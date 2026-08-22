import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/ui/screens/map_screen.dart';

const _buid = 'bldg_render_1';

NavigationRoutePoint _pt(
  String puid,
  String floor,
  double lat,
  double lon, {
  bool outdoor = false,
  String type = 'None',
}) {
  if (outdoor) {
    return NavigationRoutePoint.outdoor(
      latitude: lat,
      longitude: lon,
      buid: _buid,
      floorNumber: floor,
    );
  }
  return NavigationRoutePoint(
    latitude: lat,
    longitude: lon,
    puid: puid,
    buid: _buid,
    floorNumber: floor,
    poisType: type,
  );
}

Polyline? _byId(Set<Polyline> polylines, String id) {
  for (final p in polylines) {
    if (p.polylineId.value == id) return p;
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('legacy multi-floor route', () {
    final route = NavigationRouteModel(points: [
      _pt('pos', '0', 30.0000, 32.0000),
      _pt('conn_f0', '0', 30.0001, 32.0001),
      _pt('conn_f2', '2', 30.0002, 32.0002),
      _pt('dest', '2', 30.0003, 32.0003),
    ]);

    test('floor 0 renders only Floor 0 geometry', () {
      final polylines = routePolylinesForFloor(route, '0');

      final indoor = _byId(polylines, 'route_indoor');
      expect(indoor, isNotNull);
      expect(indoor!.points, hasLength(2));
      expect(
        indoor.points.every((p) => p.latitude <= 30.0001),
        isTrue,
        reason: 'no Floor 2 geometry may appear on Floor 0',
      );
      expect(polylines, hasLength(1));
    });

    test('floor 2 renders only Floor 2 geometry', () {
      final indoor = _byId(routePolylinesForFloor(route, '2'), 'route_indoor');
      expect(indoor, isNotNull);
      expect(indoor!.points, hasLength(2));
      expect(indoor.points.first.latitude, 30.0002);
      expect(indoor.points.last.latitude, 30.0003);
    });

    test('a displayed floor without geometry renders no indoor line', () {
      final polylines = routePolylinesForFloor(route, '1');
      expect(_byId(polylines, 'route_indoor'), isNull);
      expect(polylines, isEmpty);
    });

    test('null displayed floor falls back to legacy unfiltered rendering', () {
      final indoor = _byId(routePolylinesForFloor(route, null), 'route_indoor');
      expect(indoor!.points, hasLength(4));
    });

    test('styling is preserved when filtering', () {
      final indoor = _byId(routePolylinesForFloor(route, '2'), 'route_indoor')!;
      expect(indoor.width, 6);
      expect(indoor.patterns, isEmpty);
      final unfiltered = _byId(routePolylinesForFloor(route, null), 'route_indoor')!;
      expect(indoor.color, unfiltered.color);
      expect(indoor.width, unfiltered.width);
    });
  });

  group('same-floor route', () {
    final route = NavigationRouteModel(points: [
      _pt('a', '2', 30.0000, 32.0000),
      _pt('b', '2', 30.0001, 32.0001),
      _pt('c', '2', 30.0002, 32.0002),
    ]);

    test('behaves exactly as before — identical to unfiltered rendering', () {
      final filtered = _byId(routePolylinesForFloor(route, '2'), 'route_indoor')!;
      final legacy = _byId(routePolylinesForFloor(route, null), 'route_indoor')!;

      expect(filtered.points.length, legacy.points.length);
      for (var i = 0; i < legacy.points.length; i++) {
        expect(filtered.points[i], legacy.points[i]);
      }
      expect(filtered.color, legacy.color);
      expect(filtered.width, legacy.width);
    });
  });

  group('outdoor waypoints are floor-independent', () {
    final route = NavigationRouteModel.hybrid(
      outdoorPoints: [
        NavigationRoutePoint.outdoor(
          latitude: 29.9990,
          longitude: 31.9990,
          buid: _buid,
          floorNumber: '2',
        ),
        NavigationRoutePoint.outdoor(
          latitude: 29.9995,
          longitude: 31.9995,
          buid: _buid,
          floorNumber: '2',
        ),
      ],
      indoorRoute: NavigationRouteModel(points: [
        _pt('conn_f2', '2', 30.0002, 32.0002),
        _pt('dest', '2', 30.0003, 32.0003),
      ]),
    );

    test('outdoor dotted polyline renders on any displayed floor', () {
      for (final floor in ['0', '2']) {
        final outdoor = _byId(routePolylinesForFloor(route, floor), 'route_outdoor');
        expect(outdoor, isNotNull, reason: 'floor $floor');
        expect(outdoor!.points, hasLength(2));
        final patterns = outdoor.patterns;
        expect(patterns, hasLength(2));
        expect(
          identical(patterns[0], PatternItem.dot),
          isTrue,
          reason: 'existing outdoor styling preserved',
        );
      }
    });
  });

  group('segment-based route', () {
    final route = NavigationRouteModel.fromSegments(segments: [
      RouteSegment.outdoor(
        points: const [
          LatLng(29.9990, 31.9990),
          LatLng(29.9995, 31.9995),
        ],
        buildingId: _buid,
      ),
      RouteSegment.indoor(
        points: [
          const LatLng(30.0000, 32.0000),
          const LatLng(30.0001, 32.0001),
        ],
        buildingId: _buid,
        floorNumber: '0',
      ),
      RouteSegment.indoor(
        points: [
          const LatLng(30.0002, 32.0002),
          const LatLng(30.0003, 32.0003),
        ],
        buildingId: _buid,
        floorNumber: '2',
      ),
    ], status: RouteModelStatus.ready);

    test('renders only segments of the displayed floor plus unfloored ones', () {
      final onF0 = routePolylinesForFloor(route, '0');
      final idsF0 = onF0.map((p) => p.polylineId.value).toSet();
      expect(idsF0, containsAll(['route_segment_0', 'route_segment_1']));
      expect(idsF0, isNot(contains('route_segment_2')));

      final onF2 = routePolylinesForFloor(route, '2');
      final idsF2 = onF2.map((p) => p.polylineId.value).toSet();
      expect(idsF2, containsAll(['route_segment_0', 'route_segment_2']));
      expect(idsF2, isNot(contains('route_segment_1')));
    });

    test('polyline ids stay stable with original segment indices', () {
      final onF2 = routePolylinesForFloor(route, '2').toList()
        ..sort((a, b) => a.polylineId.value.compareTo(b.polylineId.value));
      expect(onF2[0].polylineId.value, 'route_segment_0');
      expect(onF2[1].polylineId.value, 'route_segment_2');
    });

    test('null floor renders all segments (legacy)', () {
      expect(routePolylinesForFloor(route, null), hasLength(3));
    });
  });
}
