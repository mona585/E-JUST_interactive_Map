import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/repositories/cross_building_router.dart';
import 'package:anyplace_campusfind/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';

// FORENSIC REMEDIATION REGRESSION TESTS
// Finding NAV-002 (exit door = candidates.first, no scoring) — the connector-
// chain NAV-003 finding is retired with the indoor connector router (CP-8).

/// Offline navigation repository stub — the router contract under test never
/// requires live route data for the exit-scoring/entrance-selection flows.
class _FakeNavigationRepository implements NavigationRepository {
  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      [];

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      null;
}

SpaceModel _space(String buid) =>
    SpaceModel(buid: buid, name: buid, latitude: 30.0, longitude: 29.0);

PoiModel _poi(String puid, double lat,
        {String type = 'Entrance', bool entranceFlag = false}) =>
    PoiModel(
      puid: puid,
      buid: 'bExit',
      floorNumber: '0',
      name: puid,
      poisType: type,
      latitude: lat,
      longitude: 29.0,
      isBuildingEntrance: entranceFlag,
    );

CrossBuildingRouter _router(Map<String, List<PoiModel>> poisByBuid) {
  return CrossBuildingRouter(
    loadFloorsForBuilding: (buid) async => <FloorModel>[],
    loadPois: (buid, floorNumber) async => poisByBuid[buid] ?? const [],
    loadFloorNumbers: (buid) async => ['0'],
    navigationRepository: _FakeNavigationRepository(),
  );
}

CrossBuildingRouter _floorsRouter(
  Map<String, List<FloorModel>> floorsByBuid,
) {
  return CrossBuildingRouter(
    loadFloorsForBuilding: (buid) async =>
        floorsByBuid[buid] ?? const <FloorModel>[],
    loadPois: (buid, floorNumber) async => const [],
    loadFloorNumbers: (buid) async => ['0', '1', '2'],
    navigationRepository: _FakeNavigationRepository(),
  );
}

FloorModel _floor(
  String buid,
  String floorNumber, {
  required double blLat,
  required double blLng,
  required double trLat,
  required double trLng,
}) =>
    FloorModel(
      buid: buid,
      floorNumber: floorNumber,
      floorName: 'Floor $floorNumber',
      bottomLeftLat: blLat,
      bottomLeftLng: blLng,
      topRightLat: trLat,
      topRightLng: trLng,
    );

/// B7 floor boxes circa the E-JUST campus origin (30.86, 29.58), centered on
/// (30.8600, 29.5800) with ~47m half-widths. Real server bounds; the fabricated
/// epsilon/centroid fallback is never used.
final Map<String, List<FloorModel>> _b7Floors = {
  'b7': [
    _floor('b7', '0',
        blLat: 30.8595, blLng: 29.5795, trLat: 30.8605, trLng: 29.5805),
    _floor('b7', '1',
        blLat: 30.8595, blLng: 29.5795, trLat: 30.8605, trLng: 29.5805),
    _floor('b7', '2',
        blLat: 30.8595, blLng: 29.5795, trLat: 30.8605, trLng: 29.5805),
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NAV-002: exit selector returns the NEAREST ground entrance, not the '
      'first in load order', () async {
    final near = _poi('door_near', 30.0005, entranceFlag: true);
    final far = _poi('door_far', 30.0090, entranceFlag: true);
    final router = _router({
      'bExit': [far, near], // far door listed first
    });

    final picked = await router.selectExitPoiForTest(
      _space('bExit'),
      userLocation: const LatLng(30.0001, 29.0001),
    );

    expect(picked, isNotNull);
    expect(picked!.puid, 'door_near');
  });

  test('B7 FIX: point within 100m of B7 centroid but OUTSIDE B7 floor bounds '
      'must NOT be classified as inside B7', () async {
    final router = _floorsRouter(_b7Floors);

    // Centroid of the B7 box is (30.8600, 29.5800). This point is ~76m east
    // (< 100m of the old centroid-radius rule) but sits beyond trLng 29.5805.
    const farPoint = LatLng(30.8600, 29.5808);
    const centroid = LatLng(30.8600, 29.5800);
    final distMeters = (farPoint.latitude - centroid.latitude).abs() * 111320.0 +
        (farPoint.longitude - centroid.longitude).abs() * 111320.0 * 0.8586;
    expect(distMeters, lessThan(100),
        reason: 'precondition: point is within the old 100m centroid radius');

    final detected = await router.detectUserBuilding(farPoint, [_space('b7')]);
    expect(detected, isNull,
        reason:
            'a real point just outside B7 bounds must be treated as OUTSIDE, '
            'not falsely pulled into B7 by a centroid/distance heuristic');
  });

  test('B7 FIX: point genuinely INSIDE B7 floor bounds IS classified as B7',
      () async {
    final router = _floorsRouter(_b7Floors);
    const inside = LatLng(30.8600, 29.5800); // B7 box center
    final detected = await router.detectUserBuilding(inside, [_space('b7')]);
    expect(detected, isNotNull);
    expect(detected!.buid, 'b7');
  });

  test('B7 FIX: user inside a DIFFERENT building is not pulled into B7', () async {
    // B (target) building well south of B7; B7 and B are separate spaces.
    final floors = {
      ..._b7Floors,
      'bOther': [
        _floor('bOther', '0',
            blLat: 30.8500, blLng: 29.5700, trLat: 30.8520, trLng: 29.5720),
      ],
    };
    final router = _floorsRouter(floors);
    const userPos = LatLng(30.8510, 29.5710); // inside bOther, ~1km from b7
    final detected = await router.detectUserBuilding(userPos, [
      _space('bOther'),
      _space('b7'),
    ]);
    expect(detected, isNotNull);
    expect(detected!.buid, 'bOther',
        reason: 'nearest/smallest-matching building must be chosen by real '
            'bounds, never by proximity to the B7 centroid');
  });

  test('B7 FIX: building with NO reliable geometry is never reported inside',
      () async {
    // B7 floors carry no usable bounds -> BuildingContainment returns UNKNOWN,
    // which the router must treat as outside (never fabricate "inside").
    final router = _floorsRouter({
      'b7': [
        const FloorModel(buid: 'b7', floorNumber: '0'),
      ],
    });
    const point = LatLng(30.8600, 29.5800);
    final detected = await router.detectUserBuilding(point, [_space('b7')]);
    expect(detected, isNull,
        reason:
            'UNKNOWN geometry must behave like OUTSIDE for routing safety');
  });

  // ──────────────────────────────────────────────────────────────
  // ENTRANCE SELECTION SCORING (proximity-first regression)
  // ──────────────────────────────────────────────────────────────

  group('entrance selection scoring (proximity-first)', () {
    test('a closer entrance loses to NO farther entrance on angle alone', () {
      // The B7 scenario: E1–E3 cluster ~50m away vs the far entrance ~114m away.
      // Even with a PERFECT approach angle on the far one and a TERRIBLE angle
      // on the near one, the near entrance must have the lower (better) score.
      final nearScore = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 50,
        angleDiffDegrees: 180, // worst possible angular misalignment
      );
      final farScore = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 114,
        angleDiffDegrees: 0, // perfect angular alignment
      );

      // Angle max contribution = 180 * 0.1 = 18m-equivalent, far below the 64m
      // gap, so proximity wins.
      expect(nearScore, lessThan(farScore),
          reason:
              'a ~50m entrance must never lose to a ~114m one because of angle');
    });

    test('proximity is the dominant criterion', () {
      final near = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 60,
        angleDiffDegrees: 90,
      );
      final far = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 100,
        angleDiffDegrees: 0,
      );
      expect(near, lessThan(far),
          reason: 'a 40m distance advantage must outweigh any angle tie-break');
    });

    test('angle only breaks near-ties, never large gaps', () {
      // Near-tie (same distance): better angle wins (tie-breaker is useful).
      final aligned = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 80,
        angleDiffDegrees: 10,
      );
      final misaligned = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 80,
        angleDiffDegrees: 170,
      );
      expect(aligned, lessThan(misaligned),
          reason: 'at equal distance the better-facing entrance should win');

      // Not-a-tie (large gap): the closer entrance must win regardless of angle.
      final closeMisaligned = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 60,
        angleDiffDegrees: 180,
      );
      final farAligned = CrossBuildingRouter.entranceScore(
        walkingDistanceMeters: 110,
        angleDiffDegrees: 0,
      );
      expect(closeMisaligned, lessThan(farAligned),
          reason: 'a 50m distance gap must never be overridden by angle');
    });
  });
}
