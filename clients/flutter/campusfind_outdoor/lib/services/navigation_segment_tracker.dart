import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/navigation_config.dart';
import '../models/route_segment.dart';
import '../models/user_location.dart';
import 'navigation_arrival_detector.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_scope.dart';

/// Segment tracking for cross-building/leg-aware navigation, extracted from
/// [NavigationPilot].
///
/// Owns the current segment index, the proximity-based advance rule, the
/// route-exhaustion (completed-away-from-destination) semantics, and the
/// segment getters. Floor bookkeeping for regular segment starts is pushed
/// to the floor-transition handler through an injected callback; completion
/// flags live in the session manager.
class NavigationSegmentTracker {
  NavigationSegmentTracker({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required ArrivalAnchor? Function() arrivalAnchor,
    required void Function(bool) setRouteIncomplete,
    required void Function(String floorNumber) setNavigatingFloor,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _arrivalAnchor = arrivalAnchor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _setRouteIncomplete = setRouteIncomplete,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _setNavigatingFloor = setNavigatingFloor;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final ArrivalAnchor? Function() _arrivalAnchor;
  final void Function(bool) _setRouteIncomplete;
  final void Function(String floorNumber) _setNavigatingFloor;

  int _currentSegmentIndex = 0;

  int get currentSegmentIndex => _currentSegmentIndex;

  /// The current segment being navigated, or null if not started.
  RouteSegment? get currentSegment {
    final route = _scope.activeNavigationRoute;
    if (route == null || !route.hasSegments) return null;
    if (_currentSegmentIndex >= route.segments.length) return null;
    return route.segments[_currentSegmentIndex];
  }

  /// The next segment after the current one, or null.
  RouteSegment? get nextSegment {
    final route = _scope.activeNavigationRoute;
    if (route == null || !route.hasSegments) return null;
    final nextIdx = _currentSegmentIndex + 1;
    if (nextIdx >= route.segments.length) return null;
    return route.segments[nextIdx];
  }

  /// Total number of segments in the current route.
  int get totalSegments => _scope.activeNavigationRoute?.segments.length ?? 0;

  /// Checks if the user has transitioned between route segments.
  void checkSegmentTransition(UserLocation location) {
    final route = _scope.activeNavigationRoute;
    if (route == null || !route.hasSegments) return;
    if (_currentSegmentIndex >= route.segments.length) return;

    final currentSeg = route.segments[_currentSegmentIndex];
    if (currentSeg.isEmpty) return;

    // Check proximity to segment endpoint
    final endPoint = currentSeg.endPoint;
    if (endPoint == null) return;

    final distance = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      endPoint.latitude,
      endPoint.longitude,
    );

    // Use appropriate threshold based on segment type
    final threshold = currentSeg.type == RouteSegmentType.floorTransition
        ? NavigationConfig.connectorProximityThreshold
        : NavigationConfig.segmentAdvanceThresholdMeters;

    if (distance <= threshold) {
      debugPrint(
        '[NavigationViewModel] Segment $_currentSegmentIndex complete '
        '(${currentSeg.type.name}), advancing to next',
      );
      _advanceToNextSegment();
    }
  }

  /// Advances to the next route segment.
  void _advanceToNextSegment() {
    final route = _scope.activeNavigationRoute;
    if (route == null || !route.hasSegments) return;

    final nextIdx = _currentSegmentIndex + 1;
    if (nextIdx >= route.segments.length) {
      _handleRouteExhaustion();
      return;
    }

    _currentSegmentIndex = nextIdx;
    final nextSeg = route.segments[_currentSegmentIndex];

    debugPrint(
      '[NavigationViewModel] Now on segment $_currentSegmentIndex: '
      '${nextSeg.type.name} (${nextSeg.instruction ?? "no instruction"})',
    );

    // ROUTE-CONTEXT bookkeeping for regular segment starts only. Floor
    // changes proper (floorTransition segments) are owned exclusively by the
    // evidence-gated FLOOR_TRANSITION flow and are never claimed here.
    if (nextSeg.type != RouteSegmentType.floorTransition &&
        nextSeg.floorNumber != null &&
        nextSeg.buildingId != null) {
      _setNavigatingFloor(nextSeg.floorNumber!);
    }

    _port.notifyChanged();
  }

  /// PHASE 9 / BUG-15: segment exhaustion semantics.
  void _handleRouteExhaustion() {
    debugPrint('[NavigationViewModel] All segments complete');
    final location = _port.currentLocation;
    final anchor = _arrivalAnchor();
    if (anchor != null && location != null) {
      final dist = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        anchor.latitude,
        anchor.longitude,
      );
      if (dist < NavigationConfig.arrivalProximityThresholdMeters) {
        debugPrint(
          '[NavigationViewModel] Route exhausted within arrival '
          'radius — arrival owns completion',
        );
        return;
      }
    }
    _setRouteIncomplete(true);
    debugPrint(
      '[NavigationViewModel] Route exhausted away from destination '
      '— flagged incomplete; session continues',
    );
    _port.notifyChanged();
  }

  void resetIndex() {
    _currentSegmentIndex = 0;
  }
}
