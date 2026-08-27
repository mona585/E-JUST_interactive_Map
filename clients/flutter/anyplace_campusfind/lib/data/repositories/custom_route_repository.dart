import 'dart:math' show cos, sin, atan2, sqrt;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../datasources/kmz_loader.dart';
import '../models/custom_route_model.dart';
import '../models/navigation_route_model.dart';
import '../models/route_progress.dart';
import '../models/route_segment.dart';
import 'custom_route_graph.dart';

/// Repository for loading, caching, and querying custom KMZ routes.
///
/// Routes are loaded from a bundled asset KMZ file, parsed into
/// [CustomRoute] objects, and indexed in a [CustomRouteGraph] for
/// efficient spatial queries (snap-to-route, shortest path).
class CustomRouteRepository {
  /// In-memory parsed routes.
  List<CustomRoute> _routes = [];

  /// The route graph for spatial queries.
  final CustomRouteGraph _graph = CustomRouteGraph();

  /// Whether routes have been loaded and the graph is ready.
  bool _isLoaded = false;

  /// Asset path for the KMZ file.
  static const String _kmzAssetPath = 'assets/navigation/university roads.kmz';

  List<CustomRoute> get routes => List.unmodifiable(_routes);
  CustomRouteGraph get graph => _graph;
  bool get isLoaded => _isLoaded;

  /// Loads custom routes from the bundled asset KMZ file.
  ///
  /// Parses the KMZ, builds the route graph, and caches the raw bytes
  /// for subsequent loads. Safe to call multiple times (no-op if loaded).
  Future<void> loadRoutes() async {
    if (_isLoaded) return;

    try {
      // Load KMZ from assets
      final data = await rootBundle.load(_kmzAssetPath);
      final bytes = data.buffer.asUint8List();

      // Parse KMZ → KML features
      final features = KmzLoader.parseKmzBytes(bytes);

      // Convert LineString features to CustomRoute objects
      _routes = features
          .where((f) => f.isLineString && f.coordinates.length >= 2)
          .map((f) => CustomRoute(
                name: f.name,
                vertices: f.coordinates,
                lineColorArgb: f.lineColorArgb,
                lineWidth: f.lineWidth,
              ))
          .toList();

      // Build the route graph
      _graph.build(_routes);

      _isLoaded = true;

      debugPrint(
        '[CustomRouteRepository] Loaded ${_routes.length} routes '
        '(${_graph.vertexCount} vertices, ${_graph.edgeCount} edges)',
      );
    } catch (e) {
      debugPrint('[CustomRouteRepository] Failed to load routes: $e');
      _routes = [];
      _isLoaded = false;
    }
  }

  /// Loads routes from a raw KMZ byte array (for testing or manual loading).
  void loadFromBytes(List<int> kmzBytes) {
    final features = KmzLoader.parseKmzBytes(Uint8List.fromList(kmzBytes));

    _routes = features
        .where((f) => f.isLineString && f.coordinates.length >= 2)
        .map((f) => CustomRoute(
              name: f.name,
              vertices: f.coordinates,
              lineColorArgb: f.lineColorArgb,
              lineWidth: f.lineWidth,
            ))
        .toList();

    _graph.build(_routes);
    _isLoaded = true;
  }

  /// Snaps a GPS position to the nearest point on any custom route.
  ///
  /// Returns the snap result with the closest point, distance, and edge info.
  /// Returns `null` if no route is within [maxSnapDistance] meters.
  SnapResult? snapToRoute(
    LatLng position, {
    double maxSnapDistance = 50.0,
  }) {
    if (!_isLoaded) return null;
    return _graph.snapToRoute(position, maxSnapDistance: maxSnapDistance);
  }

  /// Finds the shortest path along custom routes between two GPS positions.
  ///
  /// Both positions are snapped to the nearest vertices, and Dijkstra's
  /// algorithm finds the shortest path. Returns the ordered [LatLng] points,
  /// or an empty list if no path exists.
  List<LatLng> findRoute(LatLng from, LatLng to) {
    if (!_isLoaded) return [];
    return _graph.routeBetween(from, to);
  }

  /// Hybrid route that bridges external routing (OSRM) and custom routes.
  ///
  /// First tries pure graph routing (both endpoints near vertices).
  /// If that fails, uses edge-based snapping to find connection points
  /// on the custom graph, producing a continuous path from [from] through
  /// the custom network to [to].
  ///
  /// Returns the combined path or null if neither approach works.
  List<LatLng>? findHybridRoute(
    LatLng from,
    LatLng to, {
    double snapThreshold = 100.0,
  }) {
    if (!_isLoaded) return null;

    // Step 1: Try pure graph routing (existing)
    final directPath = findRoute(from, to);
    if (directPath.length >= 2) {
      debugPrint(
        '[CustomRouteRepository] findHybridRoute: direct graph path found '
        '(${directPath.length} points)',
      );
      return directPath;
    }

    // Step 2: Try edge-based hybrid routing
    final hybridPath = _graph.routeBetweenEdges(
      from,
      to,
      snapThreshold: snapThreshold,
    );
    if (hybridPath != null && hybridPath.length >= 2) {
      debugPrint(
        '[CustomRouteRepository] findHybridRoute: hybrid path found '
        '(${hybridPath.length} points)',
      );
      return hybridPath;
    }

    debugPrint(
      '[CustomRouteRepository] findHybridRoute: no path found '
      '(from: ${from.latitude},${from.longitude}, '
      'to: ${to.latitude},${to.longitude})',
    );
    return null;
  }

  /// Checks if a GPS position is off-route (far from any custom route).
  ///
  /// Returns `true` if the nearest route edge is more than [thresholdMeters]
  /// away from [position].
  bool isOffRoute(LatLng position, {double thresholdMeters = 30.0}) {
    if (!_isLoaded) return false;
    final snap = _graph.snapToRoute(position, maxSnapDistance: thresholdMeters);
    return snap == null || snap.distanceMeters > thresholdMeters;
  }

  /// Returns all polyline points for rendering custom routes on the map.
  ///
  /// Each entry is a list of [LatLng] points for one route.
  List<List<LatLng>> getAllRoutePolylinePoints() {
    if (!_isLoaded) return [];
    return _routes
        .where((r) => r.hasPoints)
        .map((r) => r.vertices)
        .toList();
  }

  /// Computes the user's progress along the nearest custom route.
  ///
  /// Snaps [position] to the nearest edge and calculates distance traveled
  /// and remaining based on the edge's position within the route.
  /// Returns `null` if no route is within [maxSnapDistance] meters.
  RouteProgress? getRouteProgress(
    LatLng position, {
    double maxSnapDistance = 50.0,
    double offRouteThreshold = 30.0,
  }) {
    if (!_isLoaded) return null;

    final snap = _graph.snapToRoute(position, maxSnapDistance: maxSnapDistance);
    if (snap == null) return null;

    final route = _routes[snap.routeIndex];
    if (route.vertices.length < 2) return null;

    // Calculate distance traveled: sum of complete edges before current edge
    // plus partial distance on current edge
    double distanceTraveled = 0;
    final edges = _graph.getEdgesForRoute(snap.routeIndex);

    for (var i = 0; i < snap.edgeIndex; i++) {
      if (i < edges.length) {
        distanceTraveled += _haversine(edges[i].$1, edges[i].$2);
      }
    }

    // Add partial distance on current edge
    if (snap.edgeIndex < edges.length) {
      final edgeLen = _haversine(edges[snap.edgeIndex].$1, edges[snap.edgeIndex].$2);
      distanceTraveled += edgeLen * snap.edgeProgress;
    }

    final totalLength = route.lengthMeters;
    final distanceRemaining = (totalLength - distanceTraveled).clamp(0.0, totalLength);

    return RouteProgress(
      route: route,
      currentEdgeIndex: snap.edgeIndex,
      edgeProgress: snap.edgeProgress,
      snappedPosition: snap.snappedPoint,
      distanceFromRoute: snap.distanceMeters,
      distanceTraveled: distanceTraveled,
      distanceRemaining: distanceRemaining,
      totalRouteLength: totalLength,
      isOnRoute: snap.distanceMeters <= offRouteThreshold,
    );
  }

  /// Creates a [NavigationRouteModel] from a custom route path.
  ///
  /// Converts the [LatLng] path into a [NavigationRouteModel] with an
  /// outdoor walking segment, suitable for use with [NavigationController].
  NavigationRouteModel? createNavigationRouteFromPath(
    List<LatLng> path, {
    String? destinationBuid,
    String? floorNumber,
  }) {
    if (path.length < 2) return null;

    final segment = RouteSegment.outdoor(
      points: path,
      buildingId: destinationBuid ?? '',
      instruction: 'Walk along campus route',
      distance: _computePathDistance(path),
    );

    return NavigationRouteModel.fromSegments(
      segments: [segment],
      status: RouteModelStatus.ready,
    );
  }

  /// Attempts to replace the tail of an OSRM route with a custom route.
  ///
  /// Searches the ENTIRE OSRM path backward for points near the custom graph,
  /// then routes through the custom graph to the vertex nearest [destination],
  /// and appends a straight-line walk to the destination.
  List<LatLng>? spliceCustomTail(
    List<LatLng> osrmPath,
    LatLng destination, {
    double connectionThreshold = 150.0,
  }) {
    if (!_isLoaded || osrmPath.length < 2) return null;

    // Find nearest custom graph vertex to destination (allow 500m)
    final destVertex = _graph.nearestVertex(destination, maxDistance: 500.0);
    if (destVertex == null) {
      debugPrint('[CustomRouteRepository] spliceCustomTail: no vertices within 500m of destination');
      return null;
    }
    final destVertexIdx = destVertex.$1;

    debugPrint(
      '[CustomRouteRepository] spliceCustomTail: dest vertex=$destVertexIdx, '
      'dist=${destVertex.$2.toStringAsFixed(0)}m',
    );

    // Search entire OSRM path backward
    for (var i = osrmPath.length - 1; i >= 0; i--) {
      final snap = _graph.snapToRoute(
        osrmPath[i],
        maxSnapDistance: connectionThreshold,
      );
      if (snap == null) continue;

      debugPrint(
        '[CustomRouteRepository] spliceCustomTail: found connection at OSRM[$i], '
        'snap dist: ${snap.distanceMeters.toStringAsFixed(1)}m',
      );

      final fromV = _graph.edgeFromVertex(snap.edgeIndex);
      final toV = _graph.edgeToVertex(snap.edgeIndex);
      if (fromV < 0 || toV < 0) continue;

      for (final entryIdx in [fromV, toV]) {
        final path = _graph.shortestPath(entryIdx, destVertexIdx);
        if (path.isEmpty) continue;

        final combined = <LatLng>[
          ...osrmPath.sublist(0, i),
          for (final idx in path) _graph.getVertexPosition(idx),
          destination,
        ];

        debugPrint(
          '[CustomRouteRepository] spliceCustomTail: combined '
          '${osrmPath.sublist(0, i).length} OSRM + '
          '${path.length} custom + 1 walk = '
          '${combined.length} total',
        );
        return combined;
      }
    }

    debugPrint('[CustomRouteRepository] spliceCustomTail: no custom connection found');
    return null;
  }

  /// Haversine distance in meters between two [LatLng] points.
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

  static double _toRadians(double degrees) => degrees * 3.141592653589793 / 180.0;

  static double _computePathDistance(List<LatLng> points) {
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += _haversine(points[i], points[i + 1]);
    }
    return total;
  }
}
