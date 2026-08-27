import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/datasources/kmz_loader.dart';
import 'package:anyplace_campusfind/data/models/custom_route_model.dart';
import 'package:anyplace_campusfind/data/models/route_progress.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_graph.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';

void main() {
  group('KmzLoader', () {
    test('parseKml extracts LineString features', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Line 1</name>
      <LineString>
        <coordinates>
          30.8591,29.5635,0
          30.8600,29.5630,0
          30.8610,29.5625,0
        </coordinates>
      </LineString>
    </Placemark>
    <Placemark>
      <name>Line 2</name>
      <LineString>
        <coordinates>
          30.8600,29.5630,0
          30.8605,29.5628,0
          30.8615,29.5620,0
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);

      expect(features.length, 2);
      expect(features[0].name, 'Line 1');
      expect(features[0].isLineString, true);
      expect(features[0].coordinates.length, 3);
      // Standard KML lon,lat → auto-detected, LatLng(lat,lon)
      expect(features[0].coordinates[0].latitude, 29.5635);
      expect(features[0].coordinates[0].longitude, 30.8591);
    });

    test('parseKml extracts Point features', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>EJUST</name>
      <Point>
        <coordinates>30.8620,29.5620,0</coordinates>
      </Point>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);

      expect(features.length, 1);
      expect(features[0].name, 'EJUST');
      expect(features[0].isPoint, true);
      expect(features[0].coordinates.length, 1);
      expect(features[0].coordinates[0].latitude, 29.5620);
      expect(features[0].coordinates[0].longitude, 30.8620);
    });

    test('parseKml handles empty coordinates', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Empty</name>
      <LineString>
        <coordinates></coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);
      expect(features.length, 0);
    });

    test('parseKml handles malformed XML gracefully', () {
      const kml = '<not valid xml';
      final features = KmzLoader.parseKml(kml);
      expect(features.length, 0);
    });

    test('parseKml handles newlines in coordinates', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Multiline</name>
      <LineString>
        <coordinates>
          30.8591,29.5635,0
          30.8600,29.5630,0
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);
      expect(features.length, 1);
      expect(features[0].coordinates.length, 2);
    });
  });

  group('CustomRoute', () {
    test('lengthMeters computes geodesic distance', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [
          const LatLng(29.5635, 30.8591),
          const LatLng(29.5630, 30.8600),
        ],
      );

      expect(route.lengthMeters, greaterThan(0));
      expect(route.lengthMeters, lessThan(500)); // Should be < 500m
    });

    test('vertexCount returns correct count', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [
          const LatLng(29.5635, 30.8591),
          const LatLng(29.5630, 30.8600),
          const LatLng(29.5625, 30.8610),
        ],
      );

      expect(route.vertexCount, 3);
    });
  });

  group('CustomRouteGraph', () {
    late CustomRouteGraph graph;
    late CustomRoute route1;
    late CustomRoute route2;

    setUp(() {
      graph = CustomRouteGraph();

      // Simulate two routes that share a junction point
      route1 = CustomRoute(
        name: 'Line 1',
        vertices: [
          const LatLng(29.5635, 30.8591),
          const LatLng(29.5630, 30.8600),
          const LatLng(29.5625, 30.8610),
        ],
      );

      route2 = CustomRoute(
        name: 'Line 2',
        vertices: [
          const LatLng(29.5630, 30.8600), // Same as route1 vertex 1
          const LatLng(29.5628, 30.8605),
          const LatLng(29.5620, 30.8615),
        ],
      );
    });

    test('build creates vertices and edges', () {
      graph.build([route1, route2]);

      expect(graph.vertexCount, greaterThan(0));
      expect(graph.edgeCount, greaterThan(0));
      expect(graph.routes.length, 2);
    });

    test('build detects junctions', () {
      graph.build([route1, route2], junctionThresholdMeters: 15.0);

      // The shared point at (29.5630, 30.8600) should be a junction
      expect(graph.junctionIndices.isNotEmpty, true);
    });

    test('snapToRoute finds nearest edge', () {
      graph.build([route1, route2]);

      // Point near route1 vertex 1
      final snap = graph.snapToRoute(
        const LatLng(29.5631, 30.8601),
        maxSnapDistance: 50.0,
      );

      expect(snap, isNotNull);
      expect(snap!.distanceMeters, lessThan(50));
    });

    test('snapToRoute returns null when too far', () {
      graph.build([route1]);

      // Point far from any route
      final snap = graph.snapToRoute(
        const LatLng(29.5000, 30.8000),
        maxSnapDistance: 50.0,
      );

      expect(snap, isNull);
    });

    test('nearestVertex finds closest vertex', () {
      graph.build([route1, route2]);

      final result = graph.nearestVertex(
        const LatLng(29.5631, 30.8601),
        maxDistance: 50.0,
      );

      expect(result, isNotNull);
      expect(result!.$2, lessThan(50));
    });

    test('shortestPath finds path between vertices', () {
      graph.build([route1, route2]);

      // Path from route1 start to route2 end
      final path = graph.shortestPath(0, graph.vertexCount - 1);

      expect(path.isNotEmpty, true);
      expect(path.first, 0);
      expect(path.last, graph.vertexCount - 1);
    });

    test('routeBetween finds path between GPS positions', () {
      graph.build([route1, route2]);

      final path = graph.routeBetween(
        const LatLng(29.5635, 30.8591), // Near route1 start
        const LatLng(29.5620, 30.8615), // Near route2 end
      );

      expect(path.length, greaterThanOrEqualTo(2));
    });

    test('routeBetween returns empty when no path', () {
      graph.build([route1]);

      final path = graph.routeBetween(
        const LatLng(29.5000, 30.8000), // Far from any route
        const LatLng(29.5001, 30.8001),
      );

      expect(path, isEmpty);
    });

    test('getEdgesForRoute returns correct edges', () {
      graph.build([route1, route2]);

      final edges0 = graph.getEdgesForRoute(0);
      final edges1 = graph.getEdgesForRoute(1);

      expect(edges0.isNotEmpty, true);
      expect(edges1.isNotEmpty, true);
      expect(edges0.length + edges1.length, graph.edgeCount);
    });
  });

  group('CustomRouteModel', () {
    test('copyWith preserves original values', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [const LatLng(29.5635, 30.8591)],
        graphStartIndex: 5,
        graphEndIndex: 10,
      );

      final copy = route.copyWith(graphStartIndex: 0);

      expect(copy.name, 'Test');
      expect(copy.vertices.length, 1);
      expect(copy.graphStartIndex, 0);
      expect(copy.graphEndIndex, 10);
    });

    test('hasPoints returns true for non-empty routes', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [const LatLng(29.5635, 30.8591)],
      );

      expect(route.hasPoints, true);
    });

    test('toString includes name and vertex count', () {
      final route = CustomRoute(
        name: 'Line 1',
        vertices: [
          const LatLng(29.5635, 30.8591),
          const LatLng(29.5630, 30.8600),
        ],
      );

      expect(route.toString(), contains('Line 1'));
      expect(route.toString(), contains('2'));
    });
  });

  group('SnapResult enhanced fields', () {
    late CustomRouteGraph graph;
    late CustomRoute route;

    setUp(() {
      graph = CustomRouteGraph();
      route = CustomRoute(
        name: 'Test',
        vertices: [
          const LatLng(29.5630, 30.8590),
          const LatLng(29.5630, 30.8600),
          const LatLng(29.5630, 30.8610),
        ],
      );
      graph.build([route]);
    });

    test('snapToRoute returns valid edgeProgress', () {
      // Point near midpoint of first edge
      final snap = graph.snapToRoute(
        const LatLng(29.5631, 30.8595),
        maxSnapDistance: 50.0,
      );

      expect(snap, isNotNull);
      expect(snap!.edgeProgress, greaterThanOrEqualTo(0.0));
      expect(snap.edgeProgress, lessThanOrEqualTo(1.0));
    });

    test('snapToRoute returns directionDot in [-1, 1]', () {
      final snap = graph.snapToRoute(
        const LatLng(29.5631, 30.8595),
        maxSnapDistance: 50.0,
      );

      expect(snap, isNotNull);
      expect(snap!.directionDot, greaterThanOrEqualTo(-1.0));
      expect(snap.directionDot, lessThanOrEqualTo(1.0));
    });
  });

  group('RouteProgress', () {
    test('progressFraction computes correctly', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [
          const LatLng(29.5630, 30.8590),
          const LatLng(29.5630, 30.8610),
        ],
      );

      final progress = RouteProgress(
        route: route,
        currentEdgeIndex: 0,
        edgeProgress: 0.5,
        snappedPosition: const LatLng(29.5630, 30.8600),
        distanceFromRoute: 5.0,
        distanceTraveled: 100.0,
        distanceRemaining: 100.0,
        totalRouteLength: 200.0,
        isOnRoute: true,
      );

      expect(progress.progressFraction, closeTo(0.5, 0.01));
      expect(progress.progressPercent, 50);
      expect(progress.isOnRoute, true);
    });

    test('progressFraction clamps to [0, 1]', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [const LatLng(29.5630, 30.8590)],
      );

      final progress = RouteProgress(
        route: route,
        currentEdgeIndex: 0,
        edgeProgress: 0.0,
        snappedPosition: const LatLng(29.5630, 30.8590),
        distanceFromRoute: 0.0,
        distanceTraveled: 300.0,
        distanceRemaining: 0.0,
        totalRouteLength: 200.0,
        isOnRoute: true,
      );

      expect(progress.progressFraction, 1.0);
      expect(progress.progressPercent, 100);
    });
  });

  group('CustomRouteRepository enhanced methods', () {
    late CustomRouteRepository repository;

    setUp(() {
      repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());
    });

    test('getRouteProgress returns progress near route', () {
      final route = repository.routes.first;
      final midVertex = route.vertices[route.vertices.length ~/ 2];
      // Offset slightly from route
      final testPoint = LatLng(
        midVertex.latitude + 0.0001,
        midVertex.longitude,
      );

      final progress = repository.getRouteProgress(
        testPoint,
        maxSnapDistance: 50.0,
        offRouteThreshold: 30.0,
      );

      expect(progress, isNotNull);
      expect(progress!.isOnRoute, true);
      expect(progress.distanceTraveled, greaterThanOrEqualTo(0));
      expect(progress.distanceRemaining, greaterThanOrEqualTo(0));
      expect(progress.totalRouteLength, greaterThan(0));
    });

    test('getRouteProgress returns null when far from route', () {
      final progress = repository.getRouteProgress(
        const LatLng(29.5, 30.8),
        maxSnapDistance: 50.0,
      );

      expect(progress, isNull);
    });

    test('createNavigationRouteFromPath creates valid route', () {
      final path = [
        const LatLng(29.5630, 30.8590),
        const LatLng(29.5630, 30.8600),
        const LatLng(29.5630, 30.8610),
      ];

      final navRoute = repository.createNavigationRouteFromPath(
        path,
        destinationBuid: 'test_buid',
      );

      expect(navRoute, isNotNull);
      expect(navRoute!.hasRenderablePath, true);
      expect(navRoute.segments.length, 1);
      expect(navRoute.segments[0].points.length, 3);
    });

    test('createNavigationRouteFromPath returns null for short path', () {
      final navRoute = repository.createNavigationRouteFromPath(
        [const LatLng(29.5630, 30.8590)],
      );

      expect(navRoute, isNull);
    });
  });

  group('Hybrid routing (OSRM + custom route connection)', () {
    late CustomRouteGraph graph;

    setUp(() {
      graph = CustomRouteGraph();
    });

    test('routeBetweenEdges connects points near edges (not vertices)', () {
      // Create a route: A---B---C
      // After KML lon,lat parsing, "29.5630,30.8590" → LatLng(30.8590, 29.5630)
      final route = CustomRoute(
        name: 'Main Road',
        vertices: [
          const LatLng(30.8590, 29.5630), // A
          const LatLng(30.8600, 29.5630), // B
          const LatLng(30.8610, 29.5630), // C
        ],
      );
      graph.build([route]);

      // Points near the midpoint of edges, not near any vertex
      final from = const LatLng(30.8595, 29.5631); // near edge A-B midpoint
      final to = const LatLng(30.8605, 29.5631);   // near edge B-C midpoint

      final path = graph.routeBetweenEdges(from, to, snapThreshold: 50.0);

      expect(path, isNotNull);
      expect(path!.length, greaterThanOrEqualTo(3)); // from, graph vertices, to
      expect(path.first, from);
      expect(path.last, to);
    });

    test('routeBetweenEdges returns null when too far from any edge', () {
      final route = CustomRoute(
        name: 'Main Road',
        vertices: [
          const LatLng(30.8590, 29.5630),
          const LatLng(30.8600, 29.5630),
        ],
      );
      graph.build([route]);

      // Point far from any route
      final from = const LatLng(30.8500, 29.5500);
      final to = const LatLng(30.8501, 29.5501);

      final path = graph.routeBetweenEdges(from, to, snapThreshold: 50.0);
      expect(path, isNull);
    });

    test('routeBetweenEdges works when from is near edge but to is at vertex', () {
      final route = CustomRoute(
        name: 'Main Road',
        vertices: [
          const LatLng(30.8590, 29.5630),
          const LatLng(30.8600, 29.5630),
          const LatLng(30.8610, 29.5630),
        ],
      );
      graph.build([route]);

      final from = const LatLng(30.8595, 29.5631); // near edge, not vertex
      final to = const LatLng(30.8610, 29.5630);     // at vertex C

      final path = graph.routeBetweenEdges(from, to, snapThreshold: 50.0);
      expect(path, isNotNull);
      expect(path!.first, from);
      expect(path.last, to);
    });

    test('routeBetweenEdges picks shortest path across junction', () {
      // Two routes forming a cross:
      // Route 1: A---J---B (horizontal)
      // Route 2: C---J---D (vertical)
      // Junction J at (30.8600, 29.5630)
      final route1 = CustomRoute(
        name: 'Horizontal',
        vertices: [
          const LatLng(30.8590, 29.5630), // A
          const LatLng(30.8600, 29.5630), // J
          const LatLng(30.8610, 29.5630), // B
        ],
      );
      final route2 = CustomRoute(
        name: 'Vertical',
        vertices: [
          const LatLng(30.8600, 29.5620), // C
          const LatLng(30.8600, 29.5630), // J (same point)
          const LatLng(30.8600, 29.5640), // D
        ],
      );
      graph.build([route1, route2], junctionThresholdMeters: 15.0);

      // From near edge A-J, to near edge J-D
      final from = const LatLng(30.8595, 29.5631);
      final to = const LatLng(30.8600, 29.5635);

      final path = graph.routeBetweenEdges(from, to, snapThreshold: 50.0);
      expect(path, isNotNull);
      expect(path!.length, greaterThanOrEqualTo(3));
    });

    test('routeBetweenEdges is bidirectional', () {
      final route = CustomRoute(
        name: 'Main Road',
        vertices: [
          const LatLng(30.8590, 29.5630),
          const LatLng(30.8600, 29.5630),
          const LatLng(30.8610, 29.5630),
        ],
      );
      graph.build([route]);

      final a = const LatLng(30.8595, 29.5631);
      final b = const LatLng(30.8605, 29.5631);

      final pathAB = graph.routeBetweenEdges(a, b, snapThreshold: 50.0);
      final pathBA = graph.routeBetweenEdges(b, a, snapThreshold: 50.0);

      expect(pathAB, isNotNull);
      expect(pathBA, isNotNull);
      expect(pathAB!.first, a);
      expect(pathAB.last, b);
      expect(pathBA!.first, b);
      expect(pathBA.last, a);
    });

    test('routeBetweenEdges respects snap threshold', () {
      final route = CustomRoute(
        name: 'Main Road',
        vertices: [
          const LatLng(30.8590, 29.5630),
          const LatLng(30.8600, 29.5630),
        ],
      );
      graph.build([route]);

      // Point ~200m away from the route
      final far = const LatLng(30.8610, 29.5650);

      // With tight threshold: should fail
      final pathTight = graph.routeBetweenEdges(
        far, const LatLng(30.8600, 29.5630),
        snapThreshold: 50.0,
      );
      expect(pathTight, isNull);

      // With generous threshold: should succeed
      final pathWide = graph.routeBetweenEdges(
        far, const LatLng(30.8600, 29.5630),
        snapThreshold: 500.0,
      );
      expect(pathWide, isNotNull);
    });

    test('existing routeBetween (vertex-based) still works', () {
      final route = CustomRoute(
        name: 'Test',
        vertices: [
          const LatLng(30.8591, 29.5635),
          const LatLng(30.8600, 29.5630),
          const LatLng(30.8610, 29.5625),
        ],
      );
      graph.build([route]);

      // Points near vertices
      final path = graph.routeBetween(
        const LatLng(30.8591, 29.5635),
        const LatLng(30.8610, 29.5625),
      );

      expect(path.length, greaterThanOrEqualTo(2));
    });

    test('findHybridRoute on repository tries direct then edge snap', () {
      final repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());

      // The test KML has routes at lat≈30.859-30.861, lon≈29.563-29.564
      // Direct graph routing: points near vertices
      final directPath = repository.findHybridRoute(
        const LatLng(30.8590, 29.5630), // at route1 start vertex
        const LatLng(30.8610, 29.5640), // at route2 end vertex
        snapThreshold: 50.0,
      );
      expect(directPath, isNotNull);
      expect(directPath!.length, greaterThanOrEqualTo(2));

      // Edge-based hybrid: points near edges but not vertices
      final hybridPath = repository.findHybridRoute(
        const LatLng(30.8595, 29.5631), // near edge, not vertex
        const LatLng(30.8608, 29.5638), // near edge, not vertex
        snapThreshold: 50.0,
      );
      expect(hybridPath, isNotNull);
      expect(hybridPath!.length, greaterThanOrEqualTo(2));
    });

    test('findHybridRoute returns null when both points too far', () {
      final repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());

      final path = repository.findHybridRoute(
        const LatLng(29.5000, 30.8000),
        const LatLng(29.5001, 30.8001),
        snapThreshold: 50.0,
      );
      expect(path, isNull);
    });

    test('custom route remains visible after hybrid routing', () {
      final repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());

      expect(repository.isLoaded, true);
      expect(repository.routes.length, 2);

      final polylines = repository.getAllRoutePolylinePoints();
      expect(polylines.length, 2);
      expect(polylines[0].length, 3);
      expect(polylines[1].length, 3);
    });

    test('OSRM-style routing still works (simulated)', () {
      final repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());

      // Simulate OSRM endpoint near custom route start
      final osrmEndpoint = const LatLng(30.8590, 29.5630);
      final destination = const LatLng(30.8610, 29.5640);

      final hybrid = repository.findHybridRoute(
        osrmEndpoint,
        destination,
        snapThreshold: 100.0,
      );

      expect(hybrid, isNotNull);
      expect(hybrid!.first, osrmEndpoint);
      expect(hybrid.last, destination);
    });
  });

  group('KmzLoader line styles (My Maps fidelity)', () {
    test('kmlColorToArgb converts aabbggrr to AARRGGBB', () {
      // ff757575 is grayscale so channels coincide; use a mixed value:
      // KML aabbggrr = '80ff0000' → pure blue at 50% alpha.
      expect(KmzLoader.kmlColorToArgb('80ff0000'), 0x800000FF);
      // Opaque red in KML ('ff0000ff') → 0xFFFF0000.
      expect(KmzLoader.kmlColorToArgb('ff0000ff'), 0xFFFF0000);
      // Malformed input yields null.
      expect(KmzLoader.kmlColorToArgb('fff'), isNull);
      expect(KmzLoader.kmlColorToArgb('zzzzzzzz'), isNull);
    });

    test('styleUrl through StyleMap resolves normal LineStyle', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Style id="line-123456-32000-nodesc-normal">
      <LineStyle>
        <color>ff123456</color>
        <width>32</width>
      </LineStyle>
    </Style>
    <Style id="line-123456-32000-nodesc-highlight">
      <LineStyle>
        <color>ff654321</color>
        <width>48</width>
      </LineStyle>
    </Style>
    <StyleMap id="line-123456-32000-nodesc">
      <Pair><key>normal</key>
        <styleUrl>#line-123456-32000-nodesc-normal</styleUrl></Pair>
      <Pair><key>highlight</key>
        <styleUrl>#line-123456-32000-nodesc-highlight</styleUrl></Pair>
    </StyleMap>
    <Placemark>
      <name>A</name>
      <styleUrl>#line-123456-32000-nodesc</styleUrl>
      <LineString><coordinates>
        30.8591,29.5635,0
        30.8600,29.5630,0
      </coordinates></LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);
      // KML writes aabbggrr: 'ff123456' → alpha ff, blue 12, green 34,
      // red 56 → Flutter ARGB 0xFF563412. The highlight variant
      // ('ff654321' → 0xFF214365) must NOT be picked.
      expect(features.single.lineColorArgb, 0xFF563412);
      expect(features.single.lineWidth, 32);
    });

    test('inline Style takes precedence over styleUrl', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Style id="shared">
      <LineStyle><color>ff111111</color></LineStyle>
    </Style>
    <Placemark>
      <name>A</name>
      <styleUrl>#shared</styleUrl>
      <Style>
        <LineStyle><color>ff222222</color><width>7</width></LineStyle>
      </Style>
      <LineString><coordinates>
        30.8591,29.5635,0
        30.8600,29.5630,0
      </coordinates></LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);
      // 'ff222222' is grayscale, so the aabbggrr swizzle is identity.
      expect(features.single.lineColorArgb, 0xFF222222);
      expect(features.single.lineWidth, 7);
    });

    test('unstyled features carry no color/width', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Bare</name>
      <LineString><coordinates>
        30.8591,29.5635,0
        30.8600,29.5630,0
      </coordinates></LineString>
    </Placemark>
  </Document>
</kml>''';

      final features = KmzLoader.parseKml(kml);
      expect(features.single.lineColorArgb, isNull);
      expect(features.single.lineWidth, isNull);
    });

    test('repository threads source style into CustomRoute', () {
      final repository = CustomRouteRepository();
      repository.loadFromBytes(_createTestKmz());

      // _createTestKmz has no styles: model must expose nulls so renderers
      // can fall back to the KML-spec defaults.
      for (final route in repository.routes) {
        expect(route.lineColorArgb, isNull);
        expect(route.lineWidth, isNull);
      }
    });
  });
}

/// Creates a minimal KMZ byte array for testing.
List<int> _createTestKmz() {
  const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <Placemark>
      <name>Line 1</name>
      <LineString>
        <coordinates>
          29.5630,30.8590,0
          29.5630,30.8600,0
          29.5630,30.8610,0
        </coordinates>
      </LineString>
    </Placemark>
    <Placemark>
      <name>Line 2</name>
      <LineString>
        <coordinates>
          29.5630,30.8600,0
          29.5635,30.8605,0
          29.5640,30.8610,0
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

  // Create a simple ZIP archive in memory
  final archive = Archive();
  archive.addFile(ArchiveFile('doc.kml', kml.length, kml.codeUnits));
  return ZipEncoder().encode(archive) ?? [];
}
