import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/navigation_config.dart';
import '../models/navigation_route_model.dart';
import '../models/navigation_state.dart';
import '../models/position_fix.dart';
import '../models/route_progress.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import '../repositories/navigation_repository.dart';
import 'navigation_event_log.dart';
import 'navigation_engine.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_scope.dart';
import 'navigation_state_machine.dart';

/// Deviation detection and rerouting coordination extracted from
/// [NavigationPilot].
///
/// Owns the hysteresis streaks (polyline deviation and KMZ off-route), the
/// reroute cooldown/failure flags, the custom-graph-first resort, and the
/// fenced API fallback with exponential backoff. Route-store writes and
/// revision bumps go through injected session-manager callbacks so the
/// store write-through stays single-owned; the arrival anchor re-resolves
/// through the arrival detector.
class NavigationDeviationHandler {
  NavigationDeviationHandler({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
    required NavigationRepository navigationRepository,
    required NavigationEventLog navEvent,
    required NavigationSession? Function() session,
    required SpaceModel? Function() destinationSpace,
    required bool Function(String sessionId, int revision) isCurrent,
    required void Function(NavigationRouteModel) adoptRoute,
    required void Function() bumpRevision,
    required void Function(bool) setRouteIncomplete,
    required void Function() resolveArrivalAnchor,
    required String? Function() currentNavigatingFloor,
    required RouteProgress? Function() customRouteProgress,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navigationRepository = navigationRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _session = session,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _destinationSpace = destinationSpace,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
      _isCurrent = isCurrent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _adoptRoute = adoptRoute,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _bumpRevision = bumpRevision,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _setRouteIncomplete = setRouteIncomplete,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _resolveArrivalAnchor = resolveArrivalAnchor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _currentNavigatingFloor = currentNavigatingFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _customRouteProgress = customRouteProgress;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;
  final NavigationRepository _navigationRepository;
  final NavigationEventLog _navEvent;
  final NavigationSession? Function() _session;
  final SpaceModel? Function() _destinationSpace;
  final bool Function(String sessionId, int revision) _isCurrent;
  final void Function(NavigationRouteModel) _adoptRoute;
  final void Function() _bumpRevision;
  final void Function(bool) _setRouteIncomplete;
  final void Function() _resolveArrivalAnchor;
  final String? Function() _currentNavigatingFloor;
  final RouteProgress? Function() _customRouteProgress;

  int _deviationStreak = 0;
  int _kmzOffRouteStreak = 0;
  DateTime? _lastRerouteTime;
  bool _rerouteFailed = false;

  bool get rerouteFailed => _rerouteFailed;

  /// Test-only view of the reroute cooldown stamp.
  DateTime? get lastRerouteTimeForTest => _lastRerouteTime;

  /// Test-only direct entry into the reroute flow.
  Future<void> debugTriggerReroute() => triggerReroute();

  void checkDeviationAndReroute(UserLocation location) {
    final activeRoute = _scope.activeNavigationRoute;
    if (activeRoute == null) return;
    if (_machine.state == NavigationState.rerouting) return;
    if (_machine.state == NavigationState.floorTransition) return;

    // Cooldown check
    if (_lastRerouteTime != null) {
      final elapsed = _port.now().difference(_lastRerouteTime!);
      if (elapsed.inSeconds < NavigationConfig.rerouteCooldownSeconds) return;
    }

    // PHASE 6 / INV-8: decisions consume only decision-quality fixes. Below
    // the poor band, or held/stale, evidence resets the hysteresis streaks.
    final fix = _port.currentFix;
    if (fix == null ||
        fix.status != PositionFixStatus.fresh ||
        fix.accuracy > NavigationConfig.gpsPoorAccuracyMeters) {
      _deviationStreak = 0;
      _kmzOffRouteStreak = 0;
      return;
    }

    // Use custom route graph for deviation when outdoors and on a custom
    // route. KMZ off-route evidence also requires confirm-tick hysteresis.
    if (_machine.state == NavigationState.activeOutdoor &&
        _customRouteProgress() != null &&
        !_customRouteProgress()!.isOnRoute) {
      _kmzOffRouteStreak++;
      if (_kmzOffRouteStreak < NavigationConfig.rerouteDeviationConfirmTicks) {
        debugPrint(
          '[NavigationViewModel] Off custom route '
          '($_kmzOffRouteStreak/'
          '${NavigationConfig.rerouteDeviationConfirmTicks} confirm ticks)',
        );
        return;
      }
      _kmzOffRouteStreak = 0;
      debugPrint(
        '[NavigationViewModel] Off custom route '
        '(distance: ${_customRouteProgress()!.distanceFromRoute.toStringAsFixed(1)}m) — rerouting',
      );
      triggerReroute();
      return;
    }
    _kmzOffRouteStreak = 0;

    // Fallback: deviation against active route polyline with hysteresis.
    final deviation = _computeMinDeviation(location.latLng, activeRoute);
    if (deviation > NavigationConfig.deviationThreshold) {
      _deviationStreak++;
      if (_deviationStreak < NavigationConfig.rerouteDeviationConfirmTicks) {
        debugPrint(
          '[NavigationViewModel] Deviation '
          '$_deviationStreak/${NavigationConfig.rerouteDeviationConfirmTicks} '
          'confirm ticks',
        );
        return;
      }
      _deviationStreak = 0;
      triggerReroute();
    } else {
      _deviationStreak = 0;
    }
  }

  /// Perpendicular distance from [point] to the nearest segment of [route].
  double _computeMinDeviation(LatLng point, NavigationRouteModel route) =>
      NavigationEngine.routeDeviation(
        point,
        route,
        outdoor: _machine.state == NavigationState.activeOutdoor,
        currentFloor: _currentNavigatingFloor(),
      );

  Future<void> triggerReroute() async {
    if (_machine.state == NavigationState.rerouting) return;
    if (!(_machine.state == NavigationState.activeOutdoor ||
        _machine.state == NavigationState.activeIndoor ||
        _machine.state == NavigationState.enteringBuilding)) {
      return;
    }
    final session = _session();
    if (session == null || session.destinationPuid == null) return;

    final location = _port.currentLocation;
    if (location == null) return;

    final origin = _machine.state;
    // Cooldown starts only when the reroute actually begins: a rejected
    // transition must never consume it (BUG-13).
    if (!_machine.transition(NavigationState.rerouting)) return;
    _lastRerouteTime = _port.now();
    _navEvent.navEvent('REROUTE_TRIGGER', detail: 'origin=');
    _port.notifyChanged();

    // Capture identity for fencing; nothing captured here may be trusted
    // after an await without revalidation (INV-3 core).
    final sid = session.sessionId;
    final rev = session.routeRevision;
    final destinationPuid = session.destinationPuid!;

    // Step 1: Try custom KMZ routes first (outdoor only)
    if (origin == NavigationState.activeOutdoor) {
      final customRepo = _scope.customRouteRepository;
      if (customRepo.isLoaded) {
        // Find destination from destination space
        final destSpace = _destinationSpace();
        if (destSpace != null) {
          // Step 1a: Try pure custom graph routing
          var customPath = customRepo.findRoute(
            location.latLng,
            destSpace.latLng,
          );

          // Step 1b: Try hybrid routing (edge-based snap)
          if (customPath.length < 2) {
            customPath =
                customRepo.findHybridRoute(
                  location.latLng,
                  destSpace.latLng,
                  snapThreshold: NavigationConfig.rerouteKmzSnapThreshold,
                ) ??
                [];
          }

          if (customPath.length >= 2) {
            debugPrint(
              '[NavigationViewModel] Reroute using custom KMZ route: '
              '${customPath.length} points',
            );
            final customRoute = customRepo.createNavigationRouteFromPath(
              customPath,
              destinationBuid: destSpace.buid,
            );
            if (customRoute != null && customRoute.hasRenderablePath) {
              // Fenced, atomic write-through (INV-6): store + revision bump
              // + anchor re-resolution inside one observer notification.
              if (_isCurrent(sid, rev)) {
                _navEvent.navEvent('ROUTE_COMMIT', detail: 'source=reroute-kmz');
                _adoptRoute(customRoute);
                _bumpRevision();
                _resolveArrivalAnchor();
                _setRouteIncomplete(false);
              }
              if (_machine.state == NavigationState.rerouting) {
                _machine.transition(origin);
              }
              _port.notifyChanged();
              return;
            }
          }
        }
      }
    }

    // Step 2: Fall back to API-based rerouting.
    // PHASE 6 (BUG-12): outdoor sessions send a NULL floor — never a
    // fabricated '0'; indoor legs send the confirmed navigating floor.
    final String? currentFloor = origin == NavigationState.activeOutdoor
        ? null
        : _currentNavigatingFloor();
    var committed = false;

    for (
      var attempt = 0;
      attempt < NavigationConfig.rerouteMaxRetries;
      attempt++
    ) {
      try {
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: location.latitude,
          longitude: location.longitude,
          floorNumber: currentFloor,
          destinationPuid: destinationPuid,
        );
        // The captured result is dead the moment its identity stopped being
        // current — drop it silently instead of committing stale geometry.
        // A still-live session (superseded revision) returns to its
        // activity; an ended session is already idle and needs nothing.
        if (!_isCurrent(sid, rev)) {
          _navEvent.navEvent('ROUTE_DISCARDED', detail: 'reason=stale-session');
          if (_machine.state == NavigationState.rerouting) {
            _machine.transition(origin);
            _port.notifyChanged();
          }
          return;
        }
        if (route.hasRenderablePath) {
          // Fenced, atomic write-through (INV-6).
          //
          // Representation preservation: an indoor-origin reroute replaces
          // the route with fresh indoor geometry; adopting it through
          // [toSegmentedIndoor] keeps the segmented indoorRouting
          // representation (same style/projection as the rest of the
          // journey) instead of downgrading to the legacy rendering path.
          // Outdoor reroutes keep their historical representation.
          final adoptedRoute = origin == NavigationState.activeOutdoor
              ? route
              : route.toSegmentedIndoor(
                  fallbackBuildingId: _destinationSpace()?.buid,
                  instruction: 'Rerouted to your destination',
                );
          _navEvent.navEvent('ROUTE_COMMIT', detail: 'source=reroute-api attempt=');
          _adoptRoute(adoptedRoute);
          _bumpRevision();
          _resolveArrivalAnchor();
          committed = true;
          _rerouteFailed = false;
          _setRouteIncomplete(false);
          break;
        }
      } catch (e) {
        debugPrint('[NavigationViewModel] Reroute attempt $attempt failed: $e');
        if (!_isCurrent(sid, rev)) {
          if (_machine.state == NavigationState.rerouting) {
            _machine.transition(origin);
            _port.notifyChanged();
          }
          return;
        }
      }
      // Exponential backoff: 1s, 2s, 4s
      await Future.delayed(Duration(seconds: 1 << attempt));
      if (!_isCurrent(sid, rev)) {
        _navEvent.navEvent('ROUTE_DISCARDED', detail: 'reason=backoff-cancelled');
        if (_machine.state == NavigationState.rerouting) {
          _machine.transition(origin);
          _port.notifyChanged();
        }
        return;
      }
    }

    if (!committed) {
      // INV-8/INV-6 failure semantics: the valid old route persists and the
      // failure is visible (transient flag cleared on next success or End).
      _rerouteFailed = true;
      _navEvent.navEvent('REROUTE_FAILED', detail: 'keeping previous route');
      debugPrint(
        '[NavigationViewModel] Reroute failed — keeping previous '
        'route',
      );
    }

    if (_machine.state == NavigationState.rerouting) {
      // Dynamic restore edge: rerouting -> previous activity.
      _machine.transition(origin);
    }
    _port.notifyChanged();
  }

  void resetForPreviewSeed() {
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
  }

  void resetForStartActive() {
    _lastRerouteTime = null;
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
  }

  void resetForEnd() {
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
  }

  void resetForRetarget() {
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
  }
}
