import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/services/building_containment.dart';

/// Helpers: a small real-looking building box around (30.86, 29.58).
FloorModel _floor(
  String floor, {
  required double blLat,
  required double blLng,
  required double trLat,
  required double trLng,
}) =>
    FloorModel(
      buid: 'b7',
      floorNumber: floor,
      floorName: 'Floor $floor',
      bottomLeftLat: blLat,
      bottomLeftLng: blLng,
      topRightLat: trLat,
      topRightLng: trLng,
    );

/// A single floor with a small, plausible building box:
/// BL (30.8590, 29.5790) .. TR (30.8610, 29.5810)  (~220m x ~170m).
FloorModel _smallFloor() =>
    _floor('0', blLat: 30.8590, blLng: 29.5790, trLat: 30.8610, trLng: 29.5810);

/// A floor with NO geographic bounds (null corners — the pre-fallback state).
FloorModel _missingBoundsFloor() => const FloorModel(buid: 'b7', floorNumber: '1');

/// A floor whose bounds are all zero (server sent nothing usable).
FloorModel _zeroBoundsFloor() =>
    _floor('2', blLat: 0, blLng: 0, trLat: 0, trLng: 0);

/// An inverted / collapsed box.
FloorModel _invertedFloor() =>
    _floor('3', blLat: 30.862, blLng: 29.582, trLat: 30.860, trLng: 29.580);

/// A fabricated "epsilon" fallback rectangle: ~0.02 degrees (~2.2 km) across,
/// exactly the shape SpaceProvider fabricates when the server omits bounds.
FloorModel _epsilonFallbackFloor() =>
    _floor('4', blLat: 30.85, blLng: 29.57, trLat: 30.87, trLng: 29.59);

/// A small box used for the "within 100m of centroid but outside bounds" case:
/// BL (30.8598, 29.5798) .. TR (30.8602, 29.5802)  (~45m x ~40m), centered on
/// (30.8600, 29.5800).
FloorModel _tightFloor() =>
    _floor('0', blLat: 30.8598, blLng: 29.5798, trLat: 30.8602, trLng: 29.5802);

void main() {
  group('BuildingContainment.classify', () {
    test('point inside valid floor bounds -> inside', () {
      final point = const LatLng(30.86, 29.58); // center of _smallFloor
      final result = BuildingContainment.classify(point, [_smallFloor()]);
      expect(result.status, BuildingContainmentStatus.inside);
      expect(result.isInside, isTrue);
      expect(result.containingFloor, isNotNull);
      expect(result.containingFloor!.floorNumber, '0');
    });

    test('point outside valid floor bounds -> outside', () {
      // Far east of the box.
      final point = const LatLng(30.86, 29.5820);
      final result = BuildingContainment.classify(point, [_smallFloor()]);
      expect(result.status, BuildingContainmentStatus.outside);
      expect(result.isInside, isFalse);
    });

    test('point within 100m of centroid but outside floor bounds -> outside',
        () {
      // Centroid of _tightFloor is (30.8600, 29.5800). A point ~70m east is
      // < 100m from the centroid (old radius logic would say "inside") but
      // lies outside the tight ~45m box.
      final point = const LatLng(30.8600, 29.58063);
      final distMeters = const LatLng(30.8600, 29.5800).distanceTo(point);
      expect(distMeters, lessThan(100),
          reason: 'precondition: point is within the old 100m radius');
      final result =
          BuildingContainment.classify(point, [_tightFloor()]);
      expect(result.status, BuildingContainmentStatus.outside);
      expect(result.isInside, isFalse);
    });

    test('multi-floor: inside floor 0 -> inside', () {
      final floors = [
        _smallFloor(),
        _floor('1',
            blLat: 30.8620, blLng: 29.5820, trLat: 30.8640, trLng: 29.5840),
      ];
      final result = BuildingContainment.classify(const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.inside);
      expect(result.containingFloor!.floorNumber, '0');
    });

    test('multi-floor: outside floor 0 but inside floor 1 -> inside', () {
      final floors = [
        _smallFloor(), // floor 0 ~30.859..30.861
        _floor('1',
            blLat: 30.8620, blLng: 29.5820, trLat: 30.8640, trLng: 29.5840),
      ];
      // Inside floor 1's box only.
      final result =
          BuildingContainment.classify(const LatLng(30.863, 29.583), floors);
      expect(result.status, BuildingContainmentStatus.inside);
      expect(result.containingFloor!.floorNumber, '1');
    });

    test('multi-floor: outside all floors -> outside', () {
      final floors = [
        _smallFloor(),
        _floor('1',
            blLat: 30.8620, blLng: 29.5820, trLat: 30.8640, trLng: 29.5840),
      ];
      final result =
          BuildingContainment.classify(const LatLng(30.865, 29.585), floors);
      expect(result.status, BuildingContainmentStatus.outside);
    });

    test('invalid (zero) floor bounds are ignored', () {
      final floors = [_zeroBoundsFloor(), _smallFloor()];
      // In floor 0 (valid) -> inside; zero floor ignored.
      final result = BuildingContainment.classify(const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.inside);
      expect(result.containingFloor!.floorNumber, '0');
    });

    test('inverted floor bounds are ignored', () {
      final floors = [_invertedFloor(), _smallFloor()];
      final result = BuildingContainment.classify(const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.inside);
    });

    test('missing (null) bounds are ignored', () {
      final floors = [_missingBoundsFloor(), _smallFloor()];
      expect(BuildingContainment.hasReliableBounds(_missingBoundsFloor()), isFalse);
      final result = BuildingContainment.classify(
          const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.inside);
    });

    test('fabricated epsilon fallback rectangle is rejected', () {
      final floors = [_epsilonFallbackFloor()];
      expect(BuildingContainment.hasReliableBounds(_epsilonFallbackFloor()),
          isFalse,
          reason: 'the ~2.2km fabricated fallback must never be trusted');
      final result = BuildingContainment.classify(
          const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.unknown);
      expect(result.isInside, isFalse);
    });

    test('all floors invalid -> UNKNOWN, never INSIDE', () {
      final floors = [
        _missingBoundsFloor(),
        _zeroBoundsFloor(),
        _invertedFloor(),
        _epsilonFallbackFloor(),
      ];
      final result = BuildingContainment.classify(
          const LatLng(30.86, 29.58), floors);
      expect(result.status, BuildingContainmentStatus.unknown);
      expect(result.isInside, isFalse);
      // Convenience helper treats unknown as not-inside.
      expect(BuildingContainment.isInside(const LatLng(30.86, 29.58), floors),
          isFalse);
    });

    test('boundary point is deterministic and inclusive', () {
      // Exactly on the south-west corner -> contained (inclusive).
      final corner = const LatLng(30.8590, 29.5790);
      final result = BuildingContainment.classify(corner, [_smallFloor()]);
      expect(result.status, BuildingContainmentStatus.inside);

      // Just outside the south edge -> outside.
      final below = const LatLng(30.8589, 29.58);
      expect(
        BuildingContainment.classify(below, [_smallFloor()]).status,
        BuildingContainmentStatus.outside,
      );
    });

    test('different floor rectangles are evaluated independently', () {
      // Two disjoint well-separated floors; a point in one must NOT be
      // considered inside merely because the other floor is nearby.
      final floorA = _floor('0',
          blLat: 30.8500, blLng: 29.5600, trLat: 30.8520, trLng: 29.5620);
      final floorB = _floor('1',
          blLat: 30.8600, blLng: 29.5700, trLat: 30.8620, trLng: 29.5720);
      final floors = [floorA, floorB];
      // Inside A only.
      expect(
        BuildingContainment.classify(const LatLng(30.851, 29.561), floors)
            .containingFloor!
            .floorNumber,
        '0',
      );
      // Inside B only.
      expect(
        BuildingContainment.classify(const LatLng(30.861, 29.571), floors)
            .containingFloor!
            .floorNumber,
        '1',
      );
    });
  });

  group('BuildingContainment.hasReliableBounds', () {
    test('accepts a real small floor', () {
      expect(BuildingContainment.hasReliableBounds(_smallFloor()), isTrue);
    });
    test('rejects null bounds', () {
      expect(BuildingContainment.hasReliableBounds(_missingBoundsFloor()),
          isFalse);
    });
    test('rejects zero bounds', () {
      expect(BuildingContainment.hasReliableBounds(_zeroBoundsFloor()), isFalse);
    });
    test('rejects inverted bounds', () {
      expect(BuildingContainment.hasReliableBounds(_invertedFloor()), isFalse);
    });
    test('rejects fabricated epsilon fallback', () {
      expect(BuildingContainment.hasReliableBounds(_epsilonFallbackFloor()),
          isFalse);
    });
  });
}

extension _LatLngDistance on LatLng {
  /// Coarse degree-to-meter distance for test preconditions (E-JUST lat ~30.86).
  double distanceTo(LatLng other) {
    const mPerDeg = 111320.0;
    final dLat = (latitude - other.latitude).abs() * mPerDeg;
    final cosLat = 0.8586; // cos(30.86 deg)
    final dLng =
        (longitude - other.longitude).abs() * mPerDeg * cosLat;
    return dLng + dLat; // Manhattan-style; fine for a <100m precondition
  }
}
