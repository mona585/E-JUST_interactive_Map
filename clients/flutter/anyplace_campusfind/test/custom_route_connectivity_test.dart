import 'dart:io';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';

/// Integration tests against the real KMZ asset
/// (`assets/navigation/university roads.kmz`).
///
/// The current (2519 B) KMZ encodes the E-JUST university road network as a
/// set of roads whose endpoints terminate on, or near, the body of an adjacent
/// road. Before the vertex-to-edge junction merge in [CustomRouteGraph.build]
/// this produced 13 disconnected components, so most on-campus GPS routing
/// fell back to a 2-point straight line. These tests lock in the requirement
/// that the whole network is a single connected component and that routing
/// spans previously-disconnected roads.
void main() {
  late CustomRouteRepository repository;

  setUp(() {
    repository = CustomRouteRepository();
    final file = File('assets/navigation/university roads.kmz');
    repository.loadFromBytes(file.readAsBytesSync());
  });

  int countComponents(CustomRouteRepository repo) {
    final graph = repo.graph;
    final adj = List.generate(graph.vertexCount, (_) => <int>[]);
    for (var e = 0; e < graph.edgeCount; e++) {
      adj[graph.edgeFromVertex(e)].add(graph.edgeToVertex(e));
      adj[graph.edgeToVertex(e)].add(graph.edgeFromVertex(e));
    }
    final visited = List<bool>.filled(graph.vertexCount, false);
    var comps = 0;
    for (var v = 0; v < graph.vertexCount; v++) {
      if (visited[v]) continue;
      comps++;
      final queue = Queue<int>()..add(v);
      visited[v] = true;
      while (queue.isNotEmpty) {
        final u = queue.removeFirst();
        for (final w in adj[u]) {
          if (!visited[w]) {
            visited[w] = true;
            queue.add(w);
          }
        }
      }
    }
    return comps;
  }

  test('real KMZ graph is a single fully-connected component', () {
    expect(repository.isLoaded, true);
    expect(repository.graph.vertexCount, greaterThan(0));
    expect(repository.graph.edgeCount, greaterThan(0));

    expect(countComponents(repository), 1,
        reason: 'all campus roads must form one routable network');
  });

  test('routing spans roads that were previously disconnected', () {
    // Line 12 (2 vertices) used to be an isolated component; Line 4 and
    // Line 25 belonged to the main component.
    for (final aName in ['Line 12', 'Line 4', 'Line 25']) {
      for (final bName in ['Line 4', 'Line 25', 'Line 12']) {
        if (aName == bName) continue;

        final a = repository.routes.firstWhere((r) => r.name == aName);
        final b = repository.routes.firstWhere((r) => r.name == bName);

        final path = repository.findRoute(a.vertices.first, b.vertices.last);
        expect(path.length, greaterThanOrEqualTo(2),
            reason: 'expected a path from $aName to $bName across the network');
      }
    }
  });

  test('hybrid routing connects across the campus network', () {
    final l12 = repository.routes.firstWhere((r) => r.name == 'Line 12');
    final l25 = repository.routes.firstWhere((r) => r.name == 'Line 25');

    final path = repository.findHybridRoute(
      l12.vertices.first,
      l25.vertices.last,
      snapThreshold: 100.0,
    );
    expect(path, isNotNull);
    expect(path!.length, greaterThanOrEqualTo(2));
  });

  test('snap-to-route still returns valid progress near a road', () {
    final line = repository.routes.firstWhere((r) => r.name == 'Line 10');
    final v0 = line.vertices[0];
    final v1 = line.vertices[1];

    // Midpoint of the first segment, offset ~10m perpendicularly.
    final testPoint = LatLng(
      (v0.latitude + v1.latitude) / 2,
      (v0.longitude + v1.longitude) / 2 + 0.0001,
    );

    final snap = repository.snapToRoute(testPoint, maxSnapDistance: 50.0);
    expect(snap, isNotNull);
    expect(snap!.distanceMeters, lessThan(50));
  });
}
