import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/models/floor_model.dart';

/// Canonical result of a building-containment query.
///
/// The three-way answer matters for routing safety: a building with NO
/// reliable geographic data must surface as [unknown], never as [inside],
/// so the caller never fabricates an indoor starting point or a fake exit.
enum BuildingContainmentStatus {
  /// The point lies within the server-real bounds of at least one floor.
  inside,

  /// The building has reliable floor bounds and the point lies outside all of
  /// them.
  outside,

  /// The building has no reliable floor bounds; the answer is not knowable
  /// from the available data.
  unknown,
}

/// Immutable outcome of [BuildingContainment.classify].
class BuildingContainmentResult {
  final BuildingContainmentStatus status;

  /// The specific floor whose bounds contained the point, when [inside].
  /// Used for deterministic "strictest match" resolution among overlapping
  /// buildings.
  final FloorModel? containingFloor;

  const BuildingContainmentResult(this.status, {this.containingFloor});

  bool get isInside => status == BuildingContainmentStatus.inside;

  bool get isOutside => status == BuildingContainmentStatus.outside;

  bool get isUnknown => status == BuildingContainmentStatus.unknown;
}

/// Canonical definition of "is this GPS point physically inside a building".
///
/// The ONLY accepted geometry is real, server-provided [FloorModel] bounding
/// boxes ([FloorModel.bottomLeftLat] ... [FloorModel.topRightLng]). This is a
/// deliberate, provable safety boundary:
///
///  * It NEVER reads [FloorplanModel] bounds. The ~1.1 km floorplan fallback
///    rectangle fabricated in SpaceProvider.loadFloorplan (the `epsilon`
///    rectangle) exists only on the FloorplanModel rendering path and is
///    therefore structurally excluded from building classification.
///  * It NEVER applies any radius/centroid heuristic. A point is inside only
///    when it is geometrically contained by a real floor bounds rectangle.
///  * It is pure and deterministic: no I/O, no randomness, no clock.
///
/// Multi-floor semantics use logical OR: the point is inside the building if
/// it is contained by ANY valid floor's bounds. Floors with missing, zero,
/// inverted or implausibly-large bounds are skipped; if no floor has reliable
/// bounds the result is [BuildingContainmentStatus.unknown].
abstract final class BuildingContainment {
  BuildingContainment._();

  /// Plausibility ceiling (metres) on a single floorplan's larger edge.
  ///
  /// This is NOT a classification radius — it is a sanity gate that rejects
  /// absurd server values and, critically, the fabricated ~2.2 km
  /// "epsilon" fallback rectangle. Real building floorplans are well below
  /// this; anything larger indicates geometry that must not be trusted.
  static const double kMaxPlausibleBuildingSpanMeters = 1500.0;

  /// Whether [floor] carries a real, usable geographic bounding box.
  ///
  /// Returns false (skip this floor) when any corner is missing, zero, the
  /// box is inverted, or the box is implausibly large.
  static bool hasReliableBounds(FloorModel floor) {
    final blLat = floor.bottomLeftLat;
    final blLng = floor.bottomLeftLng;
    final trLat = floor.topRightLat;
    final trLng = floor.topRightLng;

    // Missing geometry.
    if (blLat == null ||
        blLng == null ||
        trLat == null ||
        trLng == null) {
      return false;
    }
    // Zero / degenerate coordinates (server sent nothing usable).
    if (blLat == 0 && blLng == 0 && trLat == 0 && trLng == 0) {
      return false;
    }
    if (blLat == 0 || blLng == 0 || trLat == 0 || trLng == 0) {
      return false;
    }
    // Inverted / collapsed box.
    if (blLat >= trLat) {
      return false;
    }
    // Plausibility guard (rejects the fabricated epsilon fallback and other
    // absurd values). Not a radius — pure geometry sanity.
    if (approxSpanMeters(floor) > kMaxPlausibleBuildingSpanMeters) {
      return false;
    }
    return true;
  }

  /// Approximate length of the longer bounding-box edge in metres (coarse,
  /// deterministic). Used only for the plausibility gate and for the
  /// deterministic "strictest match" tie-break.
  static double approxSpanMeters(FloorModel floor) {
    final blLat = (floor.bottomLeftLat ?? 0.0);
    final blLng = (floor.bottomLeftLng ?? 0.0);
    final trLat = (floor.topRightLat ?? 0.0);
    final trLng = (floor.topRightLng ?? 0.0);

    const double metersPerDegreeLat = 111320.0;
    final latSpan = (trLat - blLat).abs() * metersPerDegreeLat;
    final midLat = (blLat + trLat) / 2.0;
    final lonMetersPerDegree =
        metersPerDegreeLat * math.cos(midLat * math.pi / 180.0);
    final lngSpan = (trLng - blLng).abs() * lonMetersPerDegree;
    return math.max(latSpan, lngSpan);
  }

  /// Whether [point] lies within the geographic rectangle of [floor].
  ///
  /// Boundary handling is inclusive: a point exactly on an edge/corner is
  /// considered contained — deterministic and consistent for all floors.
  static bool _boundsContains(FloorModel floor, LatLng point) {
    final blLat = floor.bottomLeftLat!;
    final blLng = floor.bottomLeftLng!;
    final trLat = floor.topRightLat!;
    final trLng = floor.topRightLng!;
    return point.latitude >= blLat &&
        point.latitude <= trLat &&
        point.longitude >= blLng &&
        point.longitude <= trLng;
  }

  /// Classifies [point] against [floors] using logical-OR floor containment.
  ///
  ///  * any valid floor contains [point]  -> [inside] (+ that [containingFloor])
  ///  * some floor has reliable bounds but none contains [point] -> [outside]
  ///  * no floor has reliable bounds -> [unknown]
  ///
  /// [floors] must already belong to the building being queried (the API takes
  /// a single building's floors, not a global list).
  static BuildingContainmentResult classify(
    LatLng point,
    List<FloorModel> floors,
  ) {
    var anyReliable = false;
    for (final floor in floors) {
      if (!hasReliableBounds(floor)) {
        continue;
      }
      anyReliable = true;
      if (_boundsContains(floor, point)) {
        return BuildingContainmentResult(
          BuildingContainmentStatus.inside,
          containingFloor: floor,
        );
      }
    }
    if (!anyReliable) {
      return const BuildingContainmentResult(BuildingContainmentStatus.unknown);
    }
    return const BuildingContainmentResult(BuildingContainmentStatus.outside);
  }

  /// Convenience boolean: is [point] inside any valid floor bounds of
  /// [floors]? Treats [BuildingContainmentStatus.unknown] as false so callers
  /// that only need a yes/no never classify an unknown building as inside.
  static bool isInside(LatLng point, List<FloorModel> floors) =>
      classify(point, floors).isInside;
}
