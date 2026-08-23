import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';

const _lng = 29.5828;

LatLng _p(double lat) => LatLng(lat, _lng);

RouteSegment _outdoor(List<double> lats) => RouteSegment.outdoor(
      points: [for (final lat in lats) _p(lat)],
      buildingId: 'b2',
    );

void main() {
  group('NavigationRouteModel.fromSegments projection', () {
    test('derives flat points in order with per-segment scope flags', () {
      final exitSeg = RouteSegment.exit(
        points: [_p(30.8610), _p(30.8620), _p(30.8630)],
        buildingId: 'b1',
        floorNumber: '2',
        connectorPoiId: 'conn-exit',
      );
      final outdoorSeg = _outdoor([30.8640, 30.8650]);
      final entranceSeg = RouteSegment.entrance(
        points: [_p(30.8660), _p(30.8665)],
        buildingId: 'b2',
        floorNumber: '0',
        connectorPoiId: 'conn-entr',
      );

      final route = NavigationRouteModel.fromSegments(
        segments: [exitSeg, outdoorSeg, entranceSeg],
        status: RouteModelStatus.ready,
      );

      expect(route.hasSegments, isTrue);
      expect(route.points.length, 7);
      expect(
        route.points.map((p) => p.poisType).toList(),
        [
          'exitTransition', 'exitTransition', 'exitTransition',
          // PHASE 7 FLIP: outdoor-derived points are identity-free markers.
          'outdoor', 'outdoor',
          'entranceTransition', 'entranceTransition',
        ],
      );
      expect(route.points.where((p) => p.isOutdoor).length, 2);
      expect(route.points[0].floorNumber, '2');
      expect(route.points[3].floorNumber, '');
      expect(route.points[3].buid, '',
          reason: 'PHASE 7 / INV-7: outdoor points carry no building id');
      expect(route.points.last.latitude, 30.8665);
      expect(route.polylinePoints.length, 7);
    });

    test('synthetic puids are globally unique even when connector ids repeat',
        () {
      final a = RouteSegment.indoor(
        points: [_p(30.8600), _p(30.8601)],
        buildingId: 'b1',
        floorNumber: '1',
        connectorPoiId: 'same-connector',
      );
      final b = RouteSegment.indoor(
        points: [_p(30.8602), _p(30.8603)],
        buildingId: 'b1',
        floorNumber: '3',
        connectorPoiId: 'same-connector',
      );
      final route = NavigationRouteModel.fromSegments(
        segments: [a, b],
        status: RouteModelStatus.ready,
      );

      final puids = route.points.map((p) => p.puid).toSet();
      expect(puids.length, route.points.length,
          reason: 'every generated point must have a distinct identity');
      expect(puids.contains('__segment__'), isFalse);
      expect(route.points.first.puid, 'indoorRouting_0');
      expect(route.points.last.puid, 'indoorRouting_3');
    });

    test('empty segments contribute no points but stay listed', () {
      final emptyOutdoor = _outdoor([]);
      final indoor = RouteSegment.indoor(
        points: [_p(30.8600), _p(30.8601)],
        buildingId: 'b1',
        floorNumber: '1',
      );
      final route = NavigationRouteModel.fromSegments(
        segments: [emptyOutdoor, indoor],
        status: RouteModelStatus.ready,
      );

      expect(route.segments.length, 2);
      expect(route.hasSegments, isTrue);
      expect(route.points.length, 2);
    });

    test('status and partial warning round-trip; legacy ctor defaults hold',
        () {
      final partial = NavigationRouteModel.fromSegments(
        segments: [_outdoor([30.8600, 30.8601])],
        status: RouteModelStatus.partial,
        partialRouteWarning: 'missing leg',
      );
      expect(partial.isPartial, isTrue);
      expect(partial.partialRouteWarning, 'missing leg');

      final plain = NavigationRouteModel(points: [
        NavigationRoutePoint.outdoor(latitude: 30.86, longitude: 29.58),
        NavigationRoutePoint.outdoor(latitude: 30.87, longitude: 29.58),
      ]);
      expect(plain.isPartial, isFalse);
      expect(plain.hasSegments, isFalse);
      expect(plain.hasRenderablePath, isTrue);
    });

    test('floor-transition boundaries emerge in the derived points', () {
      final ft = RouteSegment.floorTransition(
        points: [_p(30.8651), _p(30.8652)],
        buildingId: 'b2',
        floorNumber: '0',
        connectorPoiId: 'lift-1',
      );
      final upstairs = RouteSegment.indoor(
        points: [_p(30.8653)],
        buildingId: 'b2',
        floorNumber: '3',
      );
      final route = NavigationRouteModel.fromSegments(
        segments: [_outdoor([30.8640, 30.8650]), ft, upstairs],
        status: RouteModelStatus.ready,
      );

      // Floors along the projection: '', '', '0', '0', '3'.
      // PHASE 7 FLIP: empty floors mark entrance boundaries and never count
      // as transitions — only the '0' -> '3' change between two non-empty
      // floors is a floor transition.
      expect(route.hasFloorTransitions, isTrue);
      expect(route.floorTransitionIndices, [3]);
    });

    test('legacy points-only routes keep their render accessors', () {
      final route = NavigationRouteModel(points: [
        NavigationRoutePoint.outdoor(latitude: 30.86, longitude: 29.58),
        NavigationRoutePoint.outdoor(latitude: 30.87, longitude: 29.58),
        NavigationRoutePoint(
          latitude: 30.88,
          longitude: 29.58,
          puid: 'room-1',
          buid: 'b',
          floorNumber: '1',
          poisType: 'None',
        ),
        NavigationRoutePoint(
          latitude: 30.89,
          longitude: 29.58,
          puid: 'room-2',
          buid: 'b',
          floorNumber: '1',
          poisType: 'None',
        ),
      ]);

      expect(route.hasSegments, isFalse);
      expect(route.hasOutdoorSegment, isTrue);
      expect(route.outdoorPolylinePoints.length, 2);
      expect(route.hasIndoorSegment, isTrue);
      expect(route.indoorPolylinePoints.length, 2);
      expect(route.polylinePointsForFloor('1').length, 2);
    });
  });
}
