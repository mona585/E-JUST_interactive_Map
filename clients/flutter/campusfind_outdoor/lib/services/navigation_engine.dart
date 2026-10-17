import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/navigation_route_model.dart';
import '../models/navigation_state.dart';

/// Pure navigation rules and geometry — no ChangeNotifier, no live state.
///
/// Extracted from `NavigationViewModel` so the state machine can delegate every
/// deterministic computation here while keeping orchestration, notifications
/// and location subscription in the view model.
class NavigationEngine {
  /// Projects a [NavigationState] (plus the recorded previous active state)
  /// onto the legacy [NavigationSubState] compat projection.
  static NavigationSubState projectSubState(
    NavigationState s,
    NavigationState? previousActiveState,
  ) {
    switch (s) {
      case NavigationState.activeOutdoor:
        return NavigationSubState.outdoor;
      case NavigationState.activeIndoor:
        return NavigationSubState.indoor;
      case NavigationState.enteringBuilding:
      case NavigationState.exitingBuilding:
      case NavigationState.floorTransition:
        return NavigationSubState.transitioning;
      case NavigationState.paused:
      case NavigationState.rerouting:
      case NavigationState.arrived:
        return projectSubState(
          previousActiveState ?? NavigationState.activeOutdoor,
          previousActiveState,
        );
      case NavigationState.idle:
      case NavigationState.routePreview:
        return NavigationSubState.outdoor;
    }
  }

  /// Minimum distance from [point] to the current route geometry, honoring the
  /// outdoor/indoor-flagged polyline selection used by off-route detection.
  static double routeDeviation(
    LatLng point,
    NavigationRouteModel route, {
    required bool outdoor,
    String? currentFloor,
  }) {
    List<LatLng> points;
    if (outdoor) {
      points = route.outdoorPolylinePoints;
      if (points.length < 2) {
        // Hybrid legs without outdoor-flagged geometry (legacy server
        // routes): fall through to the full polyline rather than infinity.
        points = route.polylinePoints;
      }
    } else {
      points = currentFloor != null
          ? route.polylinePointsForFloor(currentFloor)
          : route.polylinePoints;
      if (points.length < 2) {
        points = route.polylinePoints;
      }
    }
    if (points.length < 2) return double.infinity;

    double minDist = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final dist = pointToSegmentDistance(point, points[i], points[i + 1]);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  /// Haversine distance from [p] to the closest point on segment [a]-[b].
  static double pointToSegmentDistance(LatLng p, LatLng a, LatLng b) {
    final abDist = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    if (abDist < 0.001) {
      return Geolocator.distanceBetween(
        p.latitude,
        p.longitude,
        a.latitude,
        a.longitude,
      );
    }

    final apDist = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      p.latitude,
      p.longitude,
    );
    final bpDist = Geolocator.distanceBetween(
      b.latitude,
      b.longitude,
      p.latitude,
      p.longitude,
    );

    // Project p onto line ab, clamp to [0,1]
    final cosAngle =
        (apDist * apDist + abDist * abDist - bpDist * bpDist) /
        (2 * apDist * abDist);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    final ratio = (apDist * clampedCos) / abDist;
    final clampedRatio = ratio.clamp(0.0, 1.0);

    final projected = LatLng(
      a.latitude + clampedRatio * (b.latitude - a.latitude),
      a.longitude + clampedRatio * (b.longitude - a.longitude),
    );

    return Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      projected.latitude,
      projected.longitude,
    );
  }
}
