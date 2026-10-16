import 'dart:collection';
import 'dart:math' show cos, sin, atan2, pi, sqrt;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/custom_route_model.dart';

/// Result of snapping a GPS position to the nearest point on the route graph.
class SnapResult {
  /// The snapped position on the route edge.
  final LatLng snappedPoint;

  /// Index of the edge (segment) in the route graph.
  final int edgeIndex;

  /// Index of the route that owns this edge.
  final int routeIndex;

  /// Perpendicular distance from the original GPS position to the snapped point.
  final double distanceMeters;

  /// Signed direction along the edge: positive = forward, negative = backward.
  /// Computed as the dot product of the GPS-to-snapped-point vector and the
  /// edge direction vector. Values near +1 mean the user is ahead of the snap
  /// point along the edge direction; near -1 means behind.
  final double directionDot;

  /// Parametric position along the edge [0.0, 1.0].
  /// 0.0 = at the from-vertex, 1.0 = at the to-vertex.
  final double edgeProgress;

  const SnapResult({
    required this.snappedPoint,
    required this.edgeIndex,
    required this.routeIndex,
    required this.distanceMeters,
    required this.directionDot,
    this.edgeProgress = 0.0,
  });
}

/// A directed edge in the route graph, connecting two vertices.
class _Edge {
  final int fromVertex;
  final int toVertex;
  final int routeIndex;
  final double lengthMeters;

  const _Edge({
    required this.fromVertex,
    required this.toVertex,
    required this.routeIndex,
    required this.lengthMeters,
  });
}

/// A vertex in the route graph with its coordinates and adjacency list.
class _Vertex {
  final LatLng position;
  final List<int> adjacentEdges;

  _Vertex({
    required this.position,
    List<int>? adjacentEdges,
  }) : adjacentEdges = adjacentEdges ?? [];
}

/// Graph data structure built from [CustomRoute] objects.
///
/// Supports:
/// - Finding the nearest edge to a GPS position (snap-to-route)
/// - Finding the nearest vertex (junction detection)
/// - Dijkstra shortest path between any two points on the graph
/// - Edge-based routing for outdoor navigation
class CustomRouteGraph {
  final List<_Vertex> _vertices = [];
  final List<_Edge> _edges = [];
  final List<CustomRoute> _routes = [];
  final List<int> _edgeRouteIndex = [];

  /// Junction vertices: indices where 3+ edges meet.
  final Set<int> _junctionIndices = {};

  UnmodifiableListView<CustomRoute> get routes =>
      UnmodifiableListView(_routes);
  int get vertexCount => _vertices.length;
  int get edgeCount => _edges.length;

  LatLng getVertexPosition(int index) => _vertices[index].position;

  /// Returns the from-vertex index of edge [index], or -1 if invalid.
  int edgeFromVertex(int index) {
    if (index < 0 || index >= _edges.length) return -1;
    return _edges[index].fromVertex;
  }

  /// Returns the to-vertex index of edge [index], or -1 if invalid.
  int edgeToVertex(int index) {
    if (index < 0 || index >= _edges.length) return -1;
    return _edges[index].toVertex;
  }
  Set<int> get junctionIndices => UnmodifiableSetView(_junctionIndices);

  /// Builds the graph from a list of [CustomRoute] objects.
  ///
  /// Junctions are detected by proximity: vertices from different routes
  /// that are within [junctionThresholdMeters] are merged into a single vertex.
  ///
  /// Beyond vertex-to-vertex merging, this also performs a convergence pass
  /// that connects a route whose endpoint terminates *on the interior* of
  /// another route's segment (a vertex-to-edge junction) back into that
  /// segment by splitting it. Campus road KMZs are typically drawn with road
  /// endpoints that touch the body of another road rather than meeting at a
  /// shared point; without this pass such roads stay in separate connected
  /// components and become unroutable. No vertex coordinate is ever moved,
  /// only graph topology is added.
  void build(
    List<CustomRoute> routes, {
    double junctionThresholdMeters = 15.0,
  }) {
    _vertices.clear();
    _edges.clear();
    _routes.clear();
    _edgeRouteIndex.clear();
    _junctionIndices.clear();

    if (routes.isEmpty) return;

    // Step 1: Collect all unique vertices with vertex-to-vertex merging and
    // record the raw per-route edges (as endpoint vertex indices).
    final vertexMap = <_VertexKey, int>{}; // key → vertex index
    final rawEdges = <({int from, int to, int route})>[];

    for (var r = 0; r < routes.length; r++) {
      final route = routes[r];
      final graphIndices = <int>[];

      for (final vert in route.vertices) {
        final key = _VertexKey(vert);

        int? existingIdx;
        for (final entry in vertexMap.entries) {
          final existing = _vertices[entry.value];
          final dist = _haversine(existing.position, vert);
          if (dist < junctionThresholdMeters) {
            existingIdx = entry.value;
            break;
          }
        }

        if (existingIdx != null) {
          graphIndices.add(existingIdx);
        } else {
          final idx = _vertices.length;
          _vertices.add(_Vertex(position: vert));
          vertexMap[key] = idx;
          graphIndices.add(idx);
        }
      }

      // Store graph indices on the route
      if (graphIndices.isNotEmpty) {
        _routes.add(route.copyWith(
          graphStartIndex: graphIndices.first,
          graphEndIndex: graphIndices.last,
        ));
      }

      // Step 2: Record edges between consecutive vertices
      for (var i = 0; i < graphIndices.length - 1; i++) {
        rawEdges.add((
          from: graphIndices[i],
          to: graphIndices[i + 1],
          route: r,
        ));
      }
    }

    // Step 2b: Convergence pass — reconnect dangling endpoints onto the
    // interior of a nearby segment within the junction threshold.
    _snapDanglingEndpointsOntoEdges(rawEdges, junctionThresholdMeters);

    // Step 3: Materialize concrete edges + adjacency + junctions.
    for (final e in rawEdges) {
      final from = e.from;
      final to = e.to;
      final edgeIdx = _edges.length;
      final dist = _haversine(_vertices[from].position, _vertices[to].position);

      _edges.add(_Edge(
        fromVertex: from,
        toVertex: to,
        routeIndex: e.route,
        lengthMeters: dist,
      ));
      _edgeRouteIndex.add(e.route);

      _vertices[from].adjacentEdges.add(edgeIdx);
      _vertices[to].adjacentEdges.add(edgeIdx);
    }

    // Step 3b: Detect junctions (vertices with 3+ adjacent edges).
    for (var i = 0; i < _vertices.length; i++) {
      if (_vertices[i].adjacentEdges.length >= 3) {
        _junctionIndices.add(i);
      }
    }

    debugPrint(
      '[CustomRouteGraph] Built: ${_vertices.length} vertices, '
      '${_edges.length} edges, ${_junctionIndices.length} junctions, '
      '${_routes.length} routes',
    );
  }

  /// Reconnects dangling endpoints into the graph.
  ///
  /// A vertex that currently has degree 0 or 1 (an unconnected route endpoint)
  /// whose perpendicular projection onto an existing segment falls within
  /// [thresholdMeters] is spliced onto that segment: the segment is split at
  /// the projection and the endpoint vertex becomes its connection point.
  /// This iterates to a fixpoint so the result is independent of the document
  /// order in which routes were added.
  ///
  /// Neither [rawEdges] endpoints nor vertex positions are modified — only
  /// the edge topology is extended (a dangling endpoint is linked onto the
  /// nearest genuine road segment).
  void _snapDanglingEndpointsOntoEdges(
    List<({int from, int to, int route})> rawEdges,
    double thresholdMeters,
  ) {
    var merged = true;
    while (merged) {
      merged = false;

      for (var v = 0; v < _vertices.length; v++) {
        final degree = rawEdges
            .where((e) => e.from == v || e.to == v)
            .length;
        // Only dangling endpoints are candidates; interior points are assumed
        // to already be routed correctly and are not moved.
        if (degree > 1) continue;

        // Find the nearest segment (not containing v) whose interior is within
        // the threshold of v.
        int bestEdge = -1;
        double bestDist = double.infinity;
        for (var e = 0; e < rawEdges.length; e++) {
          final edge = rawEdges[e];
          if (edge.from == v || edge.to == v) continue;

          final a = _vertices[edge.from].position;
          final b = _vertices[edge.to].position;
          final proj = _projectOntoEdgeWithProgress(_vertices[v].position, a, b);

          // Only split the interior; near-endpoint cases are already handled
          // by vertex-to-vertex merging.
          if (proj.t <= 0.05 || proj.t >= 0.95) continue;

          final dist = _haversine(_vertices[v].position, proj.point);
          if (dist < thresholdMeters && dist < bestDist) {
            bestDist = dist;
            bestEdge = e;
          }
        }

        if (bestEdge < 0) continue;

        // Split edge (from, to) into (from, v) and (v, to), routing the
        // dangling endpoint v through the segment it terminates on.
        final edge = rawEdges[bestEdge];
        rawEdges.removeAt(bestEdge);
        rawEdges.add((from: edge.from, to: v, route: edge.route));
        rawEdges.add((from: v, to: edge.to, route: edge.route));
        merged = true;
      }
    }
  }

  /// Finds the nearest edge to [position] and returns a [SnapResult].
  ///
  /// Returns `null` if the graph is empty.
  SnapResult? snapToRoute(LatLng position, {double maxSnapDistance = 100.0}) {
    if (_edges.isEmpty) return null;

    SnapResult? best;

    for (var i = 0; i < _edges.length; i++) {
      final edge = _edges[i];
      final a = _vertices[edge.fromVertex].position;
      final b = _vertices[edge.toVertex].position;

      final snap = _projectOntoEdgeWithProgress(position, a, b);
      final dist = _haversine(position, snap.point);

      if (dist < maxSnapDistance && (best == null || dist < best.distanceMeters)) {
        // Compute direction dot: dot product of (position→snap) and edge direction
        final edgeDirLat = b.latitude - a.latitude;
        final edgeDirLon = b.longitude - a.longitude;
        final toSnapLat = snap.point.latitude - position.latitude;
        final toSnapLon = snap.point.longitude - position.longitude;
        final edgeLen = _sqrt(edgeDirLat * edgeDirLat + edgeDirLon * edgeDirLon);
        final snapLen = _sqrt(toSnapLat * toSnapLat + toSnapLon * toSnapLon);
        double dirDot = 0.0;
        if (edgeLen > 1e-10 && snapLen > 1e-10) {
          dirDot = (edgeDirLat * toSnapLat + edgeDirLon * toSnapLon) /
              (edgeLen * snapLen);
        }

        best = SnapResult(
          snappedPoint: snap.point,
          edgeIndex: i,
          routeIndex: edge.routeIndex,
          distanceMeters: dist,
          directionDot: dirDot,
          edgeProgress: snap.t,
        );
      }
    }

    return best;
  }

  /// Finds the nearest vertex to [position].
  ///
  /// Returns the vertex index and distance, or null if graph is empty.
  (int index, double distance)? nearestVertex(
    LatLng position, {
    double maxDistance = 100.0,
  }) {
    if (_vertices.isEmpty) return null;

    int? bestIdx;
    double bestDist = double.infinity;

    for (var i = 0; i < _vertices.length; i++) {
      final dist = _haversine(position, _vertices[i].position);
      if (dist < maxDistance && dist < bestDist) {
        bestDist = dist;
        bestIdx = i;
      }
    }

    return bestIdx != null ? (bestIdx, bestDist) : null;
  }

  /// Dijkstra shortest path from vertex [fromIdx] to vertex [toIdx].
  ///
  /// Returns the ordered list of vertex indices forming the path,
  /// or an empty list if no path exists.
  List<int> shortestPath(int fromIdx, int toIdx) {
    if (fromIdx == toIdx) return [fromIdx];
    if (fromIdx >= _vertices.length || toIdx >= _vertices.length) return [];

    final dist = List<double>.filled(_vertices.length, double.infinity);
    final prev = List<int?>.filled(_vertices.length, null);
    final visited = List<bool>.filled(_vertices.length, false);

    dist[fromIdx] = 0;
    final queue = SplayTreeSet<int>((a, b) {
      final cmp = dist[a].compareTo(dist[b]);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    queue.add(fromIdx);

    while (queue.isNotEmpty) {
      final u = queue.first;
      queue.remove(u);

      if (u == toIdx) break;
      if (visited[u]) continue;
      visited[u] = true;

      for (final edgeIdx in _vertices[u].adjacentEdges) {
        final edge = _edges[edgeIdx];
        final v = edge.fromVertex == u ? edge.toVertex : edge.fromVertex;
        final alt = dist[u] + edge.lengthMeters;
        if (alt < dist[v]) {
          dist[v] = alt;
          prev[v] = u;
          queue.add(v);
        }
      }
    }

    // Reconstruct path
    if (dist[toIdx] == double.infinity) return [];

    final path = <int>[];
    int? current = toIdx;
    while (current != null) {
      path.add(current);
      current = prev[current];
    }
    return path.reversed.toList();
  }

  /// Returns the ordered [LatLng] points for a path of vertex indices.
  List<LatLng> pathToLatLngs(List<int> path) {
    return path.map((idx) => _vertices[idx].position).toList();
  }

  /// Finds the shortest path between two GPS positions on the graph.
  ///
  /// Snaps both positions to the nearest vertices, then runs Dijkstra.
  /// Returns the ordered [LatLng] points, or an empty list if no path found.
  List<LatLng> routeBetween(LatLng from, LatLng to) {
    final fromVertex = nearestVertex(from);
    final toVertex = nearestVertex(to);

    if (fromVertex == null || toVertex == null) return [];

    final path = shortestPath(fromVertex.$1, toVertex.$1);
    if (path.isEmpty) return [];

    return pathToLatLngs(path);
  }

  /// Hybrid route that snaps [from] and [to] to the nearest EDGE (not vertex),
  /// then finds the shortest path through the custom graph.
  ///
  /// This bridges the OSRM road network and custom routes: when the user's
  /// position is NOT near a graph vertex but IS near a graph edge, this method
  /// finds the connection point and produces a continuous path.
  ///
  /// Returns the full path `[from, ...graph vertices..., to]` or null if
  /// either point is beyond [snapThreshold] meters from the nearest edge.
  List<LatLng>? routeBetweenEdges(
    LatLng from,
    LatLng to, {
    double snapThreshold = 50.0,
  }) {
    if (_edges.isEmpty) return null;

    final fromSnap = snapToRoute(from, maxSnapDistance: snapThreshold);
    if (fromSnap == null) {
      debugPrint('[CustomRouteGraph] routeBetweenEdges: from not near any edge (${_haversine(from, _vertices[0].position).toStringAsFixed(0)}m to nearest)');
      return null;
    }

    final toSnap = snapToRoute(to, maxSnapDistance: snapThreshold);
    if (toSnap == null) {
      debugPrint('[CustomRouteGraph] routeBetweenEdges: to not near any edge');
      return null;
    }

    debugPrint('[CustomRouteGraph] routeBetweenEdges: '
        'from snapped to edge ${fromSnap.edgeIndex} (dist: ${fromSnap.distanceMeters.toStringAsFixed(1)}m), '
        'to snapped to edge ${toSnap.edgeIndex} (dist: ${toSnap.distanceMeters.toStringAsFixed(1)}m)');

    // Get the two vertices of the from-edge and to-edge
    final fromEdge = _edges[fromSnap.edgeIndex];
    final fromV1 = fromEdge.fromVertex;
    final fromV2 = fromEdge.toVertex;

    final toEdge = _edges[toSnap.edgeIndex];
    final toV1 = toEdge.fromVertex;
    final toV2 = toEdge.toVertex;

    // Try all 4 combinations of entry/exit vertices, pick shortest total distance
    List<int>? bestPath;
    double bestTotalDist = double.infinity;
    int bestEntry = -1;
    int bestExit = -1;

    for (final entry in {fromV1, fromV2}) {
      for (final exitV in {toV1, toV2}) {
        final path = shortestPath(entry, exitV);
        if (path.isEmpty) continue;

        // Total distance = snap distance to entry + graph path + snap distance from exit
        final fromToEntry = _haversine(from, _vertices[entry].position);
        final graphDist = _pathDistance(path);
        final exitToTo = _haversine(_vertices[exitV].position, to);
        final total = fromToEntry + graphDist + exitToTo;

        debugPrint('[CustomRouteGraph] routeBetweenEdges: '
            'entry=$entry, exit=$exitV, '
            'from→entry=${fromToEntry.toStringAsFixed(1)}m, '
            'graph=${graphDist.toStringAsFixed(1)}m, '
            'exit→to=${exitToTo.toStringAsFixed(1)}m, '
            'total=${total.toStringAsFixed(1)}m');

        if (total < bestTotalDist) {
          bestTotalDist = total;
          bestPath = path;
          bestEntry = entry;
          bestExit = exitV;
        }
      }
    }

    if (bestPath == null) {
      debugPrint('[CustomRouteGraph] routeBetweenEdges: no path found between any vertex pair');
      return null;
    }

    debugPrint('[CustomRouteGraph] routeBetweenEdges: '
        'best path via entry=$bestEntry → exit=$bestExit, '
        'total=${bestTotalDist.toStringAsFixed(1)}m, '
        '${bestPath.length} graph vertices');

    // Build full path: [from] → snap entry → ... → snap exit → [to]
    final result = <LatLng>[from];
    for (final idx in bestPath) {
      result.add(_vertices[idx].position);
    }
    result.add(to);

    return result;
  }

  /// Computes total distance along a path of vertex indices.
  double _pathDistance(List<int> path) {
    double total = 0;
    for (var i = 0; i < path.length - 1; i++) {
      total += _haversine(_vertices[path[i]].position, _vertices[path[i + 1]].position);
    }
    return total;
  }

  /// Returns route endpoint vertices (start/end of each route polyline).
  ///
  /// These are the natural connection points between the custom route network
  /// and the public road network — the vertices where campus roads meet
  /// external roads. Ideal for OSRM handoff: OSRM routes user to an endpoint,
  /// then the custom graph handles campus roads from there.
  ///
  /// Returns deduplicated list of (vertexIndex, position) pairs.
  List<(int index, LatLng position)> getRouteEndpoints() {
    final seen = <int>{};
    final endpoints = <(int, LatLng)>[];

    for (final route in _routes) {
      if (route.graphStartIndex >= 0 && !seen.contains(route.graphStartIndex)) {
        seen.add(route.graphStartIndex);
        endpoints.add((route.graphStartIndex, _vertices[route.graphStartIndex].position));
      }
      if (route.graphEndIndex >= 0 && !seen.contains(route.graphEndIndex)) {
        seen.add(route.graphEndIndex);
        endpoints.add((route.graphEndIndex, _vertices[route.graphEndIndex].position));
      }
    }
    return endpoints;
  }

  /// Returns all edges belonging to a specific route.
  List<(LatLng start, LatLng end)> getEdgesForRoute(int routeIndex) {
    final result = <(LatLng, LatLng)>[];
    for (final edge in _edges) {
      if (edge.routeIndex == routeIndex) {
        result.add((
          _vertices[edge.fromVertex].position,
          _vertices[edge.toVertex].position,
        ));
      }
    }
    return result;
  }

  // ──────────────────────────────────────────────────────────────
  // Projection utilities
  // ──────────────────────────────────────────────────────────────

  /// Projects [point] onto the line segment [a]–[b] and returns the
  /// closest point on the segment along with the parametric t value.
  static _ProjectionResult _projectOntoEdgeWithProgress(
    LatLng point, LatLng a, LatLng b,
  ) {
    final abDist = _haversine(a, b);
    if (abDist < 0.001) return _ProjectionResult(a, 0.0);

    // Approximate flat-earth projection for short distances
    final dLat = b.latitude - a.latitude;
    final dLon = b.longitude - a.longitude;
    final pLat = point.latitude - a.latitude;
    final pLon = point.longitude - a.longitude;

    final abSquared = dLat * dLat + dLon * dLon;
    final dot = pLat * dLat + pLon * dLon;
    final t = (dot / abSquared).clamp(0.0, 1.0);

    return _ProjectionResult(
      LatLng(
        a.latitude + t * dLat,
        a.longitude + t * dLon,
      ),
      t,
    );
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double guess = x / 2;
    for (var i = 0; i < 10; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }

  /// Haversine distance in meters.
  static double _haversine(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}

/// Hashable key for vertex deduplication by approximate position.
class _VertexKey {
  final int _latKey;
  final int _lonKey;

  _VertexKey(LatLng pos)
      : _latKey = (pos.latitude * 100000).round(),
        _lonKey = (pos.longitude * 100000).round();

  @override
  int get hashCode => _latKey.hashCode ^ _lonKey.hashCode;

  @override
  bool operator ==(Object other) =>
      other is _VertexKey &&
      _latKey == other._latKey &&
      _lonKey == other._lonKey;
}

/// Internal result of edge projection with parametric position.
class _ProjectionResult {
  final LatLng point;
  final double t;
  const _ProjectionResult(this.point, this.t);
}
