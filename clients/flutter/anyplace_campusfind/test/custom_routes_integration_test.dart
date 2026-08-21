import 'dart:io';
import 'dart:math' show sin, cos, atan2, pi, sqrt;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/datasources/kmz_loader.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';

double _haversine(LatLng a, LatLng b) {
  const earthRadius = 6371000.0;
  final dLat = (b.latitude - a.latitude) * pi / 180.0;
  final dLon = (b.longitude - a.longitude) * pi / 180.0;
  final lat1 = a.latitude * pi / 180.0;
  final lat2 = b.latitude * pi / 180.0;
  final h = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
  return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
}

/// Integration tests using the actual KMZ asset from
/// assets/navigation/university roads.kmz
void main() {
  group('Real KMZ asset loading', () {
    late List<int> kmzBytes;

    setUpAll(() {
      final file = File(
        'C:/Users/mona mohamed/Downloads/anyplace for android part/'
        'anyplace_EJUST/clients/flutter/anyplace_campusfind/'
        'assets/navigation/university roads.kmz',
      );
      kmzBytes = file.readAsBytesSync();
    });

    test('KMZ file exists and has content', () {
      expect(kmzBytes.isNotEmpty, true);
      expect(kmzBytes.length, greaterThan(100));
    });

    test('KMZ parses into LineString and Point features', () {
      final features = KmzLoader.parseKmzBytes(Uint8List.fromList(kmzBytes));

      expect(features.isNotEmpty, true);

      final lineStrings = features.where((f) => f.isLineString).toList();
      final points = features.where((f) => f.isPoint).toList();

      // Should have Line 1, Line 2, and more routes + points
      expect(lineStrings.length, greaterThanOrEqualTo(2));
      expect(points.length, greaterThanOrEqualTo(1));

      // Line names
      final names = lineStrings.map((f) => f.name).toList();
      expect(names, contains('Line 1'));
      expect(names, contains('Line 2'));

      // Verify coordinates are in EJUST campus area
      // After KML lon,lat parsing: lat ~30.85-30.87, lon ~29.55-29.57
      for (final ls in lineStrings) {
        expect(ls.coordinates.length, greaterThanOrEqualTo(2));
        for (final pt in ls.coordinates) {
          expect(pt.latitude, inInclusiveRange(30.8, 30.9));
          expect(pt.longitude, inInclusiveRange(29.5, 29.6));
        }
      }
    });

    test('Line 1 has correct vertex count', () {
      final features = KmzLoader.parseKmzBytes(Uint8List.fromList(kmzBytes));
      final line1 = features.firstWhere((f) => f.name == 'Line 1');
      expect(line1.coordinates.length, 14);
    });

    test('Line 2 has correct vertex count', () {
      final features = KmzLoader.parseKmzBytes(Uint8List.fromList(kmzBytes));
      final line2 = features.firstWhere((f) => f.name == 'Line 2');
      expect(line2.coordinates.length, 25);
    });
  });

  group('CustomRouteRepository with real KMZ', () {
    late CustomRouteRepository repository;

    setUp(() {
      repository = CustomRouteRepository();
      final file = File(
        'C:/Users/mona mohamed/Downloads/anyplace for android part/'
        'anyplace_EJUST/clients/flutter/anyplace_campusfind/'
        'assets/navigation/university roads.kmz',
      );
      repository.loadFromBytes(file.readAsBytesSync());
    });

    test('routes loaded from real KMZ', () {
      expect(repository.isLoaded, true);
      expect(repository.routes.length, greaterThanOrEqualTo(2));
    });

    test('graph built with vertices and edges', () {
      expect(repository.graph.vertexCount, greaterThan(0));
      expect(repository.graph.edgeCount, greaterThan(0));
    });

    test('junction detected where routes meet', () {
      expect(repository.graph.junctionIndices.isNotEmpty, true);
    });

    test('getAllRoutePolylinePoints returns all routes', () {
      final polylines = repository.getAllRoutePolylinePoints();
      expect(polylines.length, greaterThanOrEqualTo(2));
      // Line 1 has 14 points, Line 2 has 25 points
      expect(polylines[0].length, 14);
      expect(polylines[1].length, 25);
    });
  });

  group('GPS-to-route matching (snap)', () {
    late CustomRouteRepository repository;

    setUp(() {
      repository = CustomRouteRepository();
      final file = File(
        'C:/Users/mona mohamed/Downloads/anyplace for android part/'
        'anyplace_EJUST/clients/flutter/anyplace_campusfind/'
        'assets/navigation/university roads.kmz',
      );
      repository.loadFromBytes(file.readAsBytesSync());
    });

    test('snap to route near Line 1 midpoint', () {
      final line1 = repository.routes.firstWhere((r) => r.name == 'Line 1');
      // Use a point slightly off the first segment
      final v0 = line1.vertices[0];
      final v1 = line1.vertices[1];
      final midLat = (v0.latitude + v1.latitude) / 2;
      final midLng = (v0.longitude + v1.longitude) / 2;
      // Offset by ~10m
      final testPoint = LatLng(midLat + 0.0001, midLng);

      final snap = repository.snapToRoute(testPoint, maxSnapDistance: 50.0);
      expect(snap, isNotNull);
      expect(snap!.distanceMeters, lessThan(50));
    });

    test('snap to route near Line 2', () {
      final line2 = repository.routes.firstWhere((r) => r.name == 'Line 2');
      final v5 = line2.vertices[5];
      // Offset by ~5m
      final testPoint = LatLng(v5.latitude + 0.00005, v5.longitude + 0.00005);

      final snap = repository.snapToRoute(testPoint, maxSnapDistance: 50.0);
      expect(snap, isNotNull);
      expect(snap!.distanceMeters, lessThan(50));
    });

    test('snap returns null when GPS is far from all routes', () {
      // Point 1km away from campus
      final testPoint = LatLng(29.5, 30.8);

      final snap = repository.snapToRoute(testPoint, maxSnapDistance: 50.0);
      expect(snap, isNull);
    });

    test('isOffRoute detects off-route position', () {
      // Position right on a route should NOT be off-route
      final line1 = repository.routes.firstWhere((r) => r.name == 'Line 1');
      final onRoute = line1.vertices[5];
      expect(repository.isOffRoute(onRoute, thresholdMeters: 30.0), false);

      // Position 1km away should be off-route
      expect(
        repository.isOffRoute(LatLng(29.5, 30.8), thresholdMeters: 30.0),
        true,
      );
    });
  });

  group('Routing along custom routes', () {
    late CustomRouteRepository repository;

    setUp(() {
      repository = CustomRouteRepository();
      final file = File(
        'C:/Users/mona mohamed/Downloads/anyplace for android part/'
        'anyplace_EJUST/clients/flutter/anyplace_campusfind/'
        'assets/navigation/university roads.kmz',
      );
      repository.loadFromBytes(file.readAsBytesSync());
    });

    test('findRoute along Line 1', () {
      final line1 = repository.routes.firstWhere((r) => r.name == 'Line 1');
      final start = line1.vertices.first;
      final end = line1.vertices.last;

      final path = repository.findRoute(start, end);
      expect(path.length, greaterThanOrEqualTo(2));

      // Path should start near Line 1 start and end near Line 1 end
      // (within junction merge tolerance of 15m)
      final startDist = _haversine(path.first, start);
      final endDist = _haversine(path.last, end);
      expect(startDist, lessThan(20.0)); // within merge tolerance
      expect(endDist, lessThan(20.0));
    });

    test('findRoute along Line 2', () {
      final line2 = repository.routes.firstWhere((r) => r.name == 'Line 2');
      final start = line2.vertices.first;
      final end = line2.vertices.last;

      final path = repository.findRoute(start, end);
      expect(path.length, greaterThanOrEqualTo(2));
    });

    test('findRoute cross-route via junction', () {
      final line1 = repository.routes.firstWhere((r) => r.name == 'Line 1');
      final line2 = repository.routes.firstWhere((r) => r.name == 'Line 2');

      // Start at Line 1 start, end at Line 2 end
      final path = repository.findRoute(
        line1.vertices.first,
        line2.vertices.last,
      );

      // Should find a path through the junction
      expect(path.length, greaterThanOrEqualTo(3));
    });

    test('findRoute returns empty for unreachable positions', () {
      final path = repository.findRoute(
        LatLng(29.5, 30.8), // Far away
        LatLng(29.501, 30.801),
      );
      expect(path, isEmpty);
    });
  });
}
