import 'package:flutter/foundation.dart';

import '../models/navigation_route_model.dart';
import '../models/navigation_state.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../utils/navigation_log.dart';
import 'navigation_arrival_detector.dart';
import 'navigation_building_context_handler.dart';
import 'navigation_deviation_handler.dart';
import 'navigation_event_log.dart';
import 'navigation_floor_transition_handler.dart';
import 'navigation_gps_guard.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_progress_tracker.dart';
import 'navigation_route_scope.dart';
import 'navigation_segment_tracker.dart';
import 'navigation_state_machine.dart';

/// Session lifecycle and identity ownership, extracted from
/// [NavigationPilot].
///
/// Owns the navigation session (id + revision), the session-fencing guard
/// (INV-3 core) every async continuation must pass, the single adopt / route
/// store write-through choke, and the destination-change (retarget)
/// transaction. Per-session resets are distributed to the handlers that
/// own the respective bookkeeping.
class NavigationSessionManager {
  NavigationSessionManager({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
    required NavigationEventLog navEvent,
    required NavigationFloorTransitionHandler floor,
    required NavigationBuildingContextHandler building,
    required NavigationDeviationHandler deviation,
    required NavigationArrivalDetector arrival,
    required NavigationRouteProgressTracker progress,
    required NavigationSegmentTracker segment,
    required NavigationGpsGuard gps,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _floor = floor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _building = building,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _deviation = deviation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _arrival = arrival,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _progress = progress,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _segment = segment,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _gps = gps;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;
  final NavigationEventLog _navEvent;
  final NavigationFloorTransitionHandler _floor;
  final NavigationBuildingContextHandler _building;
  final NavigationDeviationHandler _deviation;
  final NavigationArrivalDetector _arrival;
  final NavigationRouteProgressTracker _progress;
  final NavigationSegmentTracker _segment;
  final NavigationGpsGuard _gps;

  NavigationSession? _session;

  // Route-completion bookkeeping.
  bool _routeIncomplete = false;

  NavigationSession? get session => _session;

  /// Identity of the live navigation session, or null when no session exists.
  String? get sessionId => _session?.sessionId;

  /// Destination identity lives on the session.
  String? get destinationPuid => _session?.destinationPuid;
  SpaceModel? get destinationSpace => _session?.destinationSpace;

  bool get routeIncomplete => _routeIncomplete;

  /// Session-fencing guard (MASTER PLAN PHASE 1 / INV-3 core): an async
  /// continuation may commit only while the session it captured is still
  /// the current one at the route revision it observed.
  bool isCurrent({required String sessionId, required int revision}) =>
      _session != null &&
      _session!.sessionId == sessionId &&
      _session!.routeRevision == revision;

  /// Test-only revision bump.
  void bumpRevision() {
    if (_session != null) _session!.routeRevision++;
  }

  void setRouteIncomplete(bool value) => _routeIncomplete = value;

  /// Single choke point for every session write-through. The debug-mode
  /// assertion makes any reentrant adoption loop fail fast in tests instead
  /// of silently corrupting observer order.
  bool _adoptingRoute = false;
  void adoptNavigatedRoute(NavigationRouteModel route) {
    assert(!_adoptingRoute, 'reentrant adoptNavigatedRoute detected');
    _adoptingRoute = true;
    try {
      _scope.adoptNavigatedRoute(route);
    } finally {
      _adoptingRoute = false;
    }
  }

  /// Starts route preview mode after the user taps "Route Here".
  ///
  /// The route must already be loaded in the scope provider. Calling again
  /// while previewing re-seeds the preview (e.g., destination changed).
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
  }) {
    if (_machine.state != NavigationState.idle &&
        _machine.state != NavigationState.routePreview) {
      return;
    }

    final route = _scope.activeNavigationRoute;
    if (route == null || !route.hasRenderablePath) return;

    final wasIdle = _machine.state == NavigationState.idle;

    final destinationPoi = _scope.pois
        .where((p) => p.puid == destinationPuid)
        .firstOrNull;
    _session = NavigationSession(
      destinationPuid: destinationPuid,
      destinationSpace: destinationSpace,
      destinationFloorNumber: destinationPoi?.floorNumber,
    );
    // The route itself stays where it already is — the scope store. Preview
    // seeding is NOT a controller write, so the revision starts at 0; it is
    // bumped only by committed session replacements (reroutes).
    _floor.seedNavigatingFloor(_scope.selectedFloor?.floorNumber);
    _floor.resetForPreviewSeed();
    _building.resetForPreviewSeed();
    _arrival.resetForPreviewSeed();
    _deviation.resetForPreviewSeed();
    _routeIncomplete = false;
    _arrival.resolveAnchor();

    if (wasIdle) {
      _machine.transition(NavigationState.routePreview);
    }
    _navEvent.navEvent('PREVIEW_SEED', detail: 'points=${route.points.length}');
    _navEvent.navEvent('SESSION_START', force: true);
    _port.notifyChanged();
  }

  /// Transitions from preview to active navigation when the user taps
  /// "Start Directions".
  void startActiveNavigation() {
    if (_machine.state != NavigationState.routePreview) return;

    _deviation.resetForStartActive();
    _building.resetForStartActive();
    _floor.resetForStartActive();
    _arrival.resetForStartActive();

    _machine.transition(NavigationState.activeOutdoor);
    _port.notifyChanged();
  }

  /// Ends the session from ANY state (user action; bypasses the table).
  void endNavigation() {
    final endedSessionId = _session?.sessionId;
    _machine.reset();
    _session = null;
    _scope.clearNavigationRoute();
    _floor.resetForEnd();
    _segment.resetIndex();
    _gps.resetForEnd();
    _progress.clear();
    _building.resetForEnd();
    _arrival.resetForEnd();
    _deviation.resetForEnd();
    _routeIncomplete = false;
    if (endedSessionId != null) {
      _navEvent.navEvent('TERMINATE', detail: 'sid=$endedSessionId', force: true);
      _navEvent.navEvent('SESSION_END', force: true);
    }
    _port.notifyChanged();
  }

  /// Canonical teardown (MASTER PLAN PHASE 15, INV-10).
  void terminateNavigation() {
    try {
      endNavigation();
    } catch (e) {
      navigationLog('[NAV] TERMINATE_FAULT detail=$e');
      _machine.forceIdle();
      _session = null;
      try {
        _scope.clearNavigationRoute();
      } catch (_) {}
      _port.notifyChanged();
    }
  }

  /// Explicit destination-change protocol (MASTER PLAN PHASE 4).
  Future<bool> retargetDestination(PoiModel newTarget) async {
    if (_machine.state == NavigationState.idle ||
        _machine.state == NavigationState.arrived) {
      return false;
    }
    final oldSessionId = _session?.sessionId;
    debugPrint('[NAV] RETARGET sid=$oldSessionId -> ${newTarget.puid}');

    // 1. Identity first: everything captured under the old id is now dead.
    final newSession = NavigationSession(
      destinationPuid: newTarget.puid,
      destinationSpace: _scope.selectedSpace?.buid == newTarget.buid
          ? _scope.selectedSpace
          : null,
      destinationFloorNumber: newTarget.floorNumber,
    );
    _session = newSession;

    // 2. Reset per-session bookkeeping (same set startRoutePreview resets).
    _floor.seedNavigatingFloor(_scope.selectedFloor?.floorNumber);
    _floor.resetForRetarget();
    _building.resetForRetarget();
    _arrival.resetForRetarget();
    _progress.clear();
    _deviation.resetForRetarget();
    _routeIncomplete = false;
    _port.notifyChanged();

    // 3. Content second: cascade for the new target behind request ids.
    final ok = await _scope.requestRouteForRetarget(newTarget);

    // 4. Post-await identity gate: only the newest retarget may seed.
    if (!identical(_session, newSession)) {
      debugPrint(
        '[NAV] RETARGET superseded for ${newTarget.puid} — '
        'discarding',
      );
      return false;
    }

    // 5. Anchor + state handling. The activity the user was in continues;
    // overlays restore to it via their own dynamic edges.
    if (ok) {
      _arrival.resolveAnchor();
    } else {
      // Degraded but honest: anchor directly on the requested POI so
      // arrival still targets what the user asked for.
      _arrival.anchorOn(newTarget);
      debugPrint(
        '[NAV] RETARGET route unavailable for ${newTarget.puid}; '
        'anchored on POI',
      );
    }
    if (_machine.state == NavigationState.rerouting ||
        _machine.state == NavigationState.paused) {
      final restore = _machine.previousActiveState;
      if (restore != null) _machine.transition(restore);
    }
    debugPrint(
      '[NAV] SESSION_REPLACED old=$oldSessionId '
      'new=${_session!.sessionId} dst=${newTarget.puid}',
    );
    _port.notifyChanged();
    return ok;
  }
}
