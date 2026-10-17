import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/navigation_config.dart';
import '../models/floor_model.dart';
import '../models/floor_transition_event.dart';
import '../models/navigation_state.dart';
import '../models/user_location.dart';
import 'navigation_event_log.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_scope.dart';
import 'navigation_state_machine.dart';

/// Floor-transition ownership extracted from [NavigationPilot].
///
/// Owns every piece of floor-transition bookkeeping (current/expected floor,
/// connector-vs-organic origin, stability accumulation, held position, event
/// history) and the detection/confirmation/timeout logic. The transaction
/// flow spans state via the machine.
class NavigationFloorTransitionHandler {
  NavigationFloorTransitionHandler({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
    required NavigationEventLog navEvent,
    required void Function() onFloorConfirmed,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onFloorConfirmed = onFloorConfirmed;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;
  final NavigationEventLog _navEvent;

  /// Confirmed floor transitions disarm the building-exit confirmation
  /// streak (building-context handler).
  final void Function() _onFloorConfirmed;

  // Floor-transition bookkeeping
  String? _currentNavigatingFloor;
  String? _expectedNextFloor;
  bool _connectorInitiatedTransition = false;
  int _newFloorEstimateCount = 0;
  DateTime? _lastFloorSwitchTime;
  DateTime? _transitionStartTime;
  final List<FloorTransitionEvent> _floorTransitionEvents = [];
  UserLocation? _lastIndoorPosition;

  String? get currentNavigatingFloor => _currentNavigatingFloor;
  String? get expectedNextFloor => _expectedNextFloor;

  /// Position to render during a floor transition (held position), or the
  /// current location otherwise.
  UserLocation? get heldPositionDuringTransition =>
      _machine.state == NavigationState.floorTransition ? _lastIndoorPosition : null;

  /// Floor-transition lifecycle events for the current session, oldest first
  /// (bounded by
  /// [NavigationConfig.floorTransitionEventHistoryLimit]).
  List<FloorTransitionEvent> get floorTransitionEvents =>
      List.unmodifiable(_floorTransitionEvents);

  /// Most recent floor-transition event, or null before any transition.
  FloorTransitionEvent? get lastFloorTransitionEvent =>
      _floorTransitionEvents.isEmpty ? null : _floorTransitionEvents.last;

  /// User-friendly positioning status message.
  String get positioningStatus {
    if (_machine.state == NavigationState.floorTransition) {
      final nextFloor = _expectedNextFloor;
      if (nextFloor != null) {
        return '${NavigationConfig.transitionBlackoutMessage} $nextFloor...';
      }
      return '${NavigationConfig.transitionBlackoutMessage}...';
    }
    final floor = _currentNavigatingFloor;
    if (_port.isIndoorWifiActive) {
      return floor != null ? 'Floor $floor' : 'Location';
    }
    if (_port.hasGpsFix) {
      return 'GPS active';
    }
    return 'Updating location\u2026';
  }

  /// Appends [event] to the bounded per-session history.
  void _recordFloorTransitionEvent(FloorTransitionEvent event) {
    _floorTransitionEvents.add(event);
    final limit = NavigationConfig.floorTransitionEventHistoryLimit;
    if (_floorTransitionEvents.length > limit) {
      _floorTransitionEvents.removeRange(
        0,
        _floorTransitionEvents.length - limit,
      );
    }
  }

  /// Best available floor identity for the user's physical position.
  String? _evidenceFloor() {
    final fix = _port.currentFix;
    if (fix != null && fix.hasScope) return fix.floor;
    final estimate = _port.latestIndoorEstimate;
    if (estimate != null && estimate.isValid) return estimate.floor;
    return null;
  }

  /// Seeds the navigating floor from the selected browsing floor when a
  /// session starts (preview seed / retarget).
  void seedNavigatingFloor(String? floorNumber) {
    _currentNavigatingFloor = floorNumber;
  }

  void checkFloorTransition(UserLocation location) {
    if (_scope.activeNavigationRoute == null) return;
    final currentFloor = _currentNavigatingFloor;
    if (currentFloor == null) return;

    // Approaching a connector (floor-change point) enters FLOOR_TRANSITION.
    if (_machine.state == NavigationState.activeIndoor) {
      final route = _scope.activeNavigationRoute!;
      final transitionIndices = route.floorTransitionIndices;
      for (final idx in transitionIndices) {
        final connectorPoint = route.points[idx];
        if (connectorPoint.floorNumber != currentFloor) continue;

        final dist = Geolocator.distanceBetween(
          location.latitude,
          location.longitude,
          connectorPoint.latitude,
          connectorPoint.longitude,
        );
        if (dist < NavigationConfig.connectorProximityThreshold) {
          // PHASE 9 / BUG-15: a connector as the LAST point has no successor.
          if (idx + 1 >= route.points.length) {
            debugPrint(
              '[NavigationViewModel] Connector is final point - '
              'no successor floor; ignoring',
            );
            continue;
          }
          // User is near a connector â€” determine next floor
          final nextFloor = route.points[idx + 1].floorNumber;
          if (nextFloor != currentFloor) {
            beginConnectorFloorTransition(nextFloor);
            break;
          }
        }
      }
    }

    // Floor-evidence confirmation runs in ACTIVE_INDOOR (organic drift) and
    // FLOOR_TRANSITION (awaiting confirmation).
    if (_machine.state != NavigationState.activeIndoor &&
        _machine.state != NavigationState.floorTransition) {
      return;
    }

    if (!_port.isIndoorWifiActive) {
      _newFloorEstimateCount = 0;
      return;
    }

    final evidenceFloor = _evidenceFloor();
    if (evidenceFloor == null || evidenceFloor == currentFloor) {
      _newFloorEstimateCount = 0;
      return;
    }

    // If we have an expected floor, verify the evidence matches it
    final expected = _expectedNextFloor;
    if (expected != null && evidenceFloor != expected) {
      _newFloorEstimateCount = 0;
      return;
    }

    _newFloorEstimateCount++;

    // DETECTED: first consistent divergent evidence tick of the current
    // accumulation run (ORIGINAL PHASE 5 â€” stage visibility).
    if (_newFloorEstimateCount == 1) {
      _navEvent.navEvent('FLOOR_EVENT', detail: 'kind=detected');
      _recordFloorTransitionEvent(
        FloorTransitionEvent(
          stage: FloorTransitionStage.detected,
          trigger: FloorTransitionTrigger.evidence,
          fromFloor: currentFloor,
          toFloor: evidenceFloor,
          timestamp: _port.now(),
        ),
      );
    }

    // Require consecutive consistent evidence before confirming
    if (_newFloorEstimateCount >= NavigationConfig.stabilityMinEstimates) {
      if (_machine.state == NavigationState.floorTransition) {
        completeFloorTransition(evidenceFloor);
      } else {
        beginOrganicFloorTransition(evidenceFloor);
      }
      _newFloorEstimateCount = 0;
    }
  }

  /// Enters FLOOR_TRANSITION because the user is near a route connector.
  void beginConnectorFloorTransition(String floorNumber) {
    if (_machine.state != NavigationState.activeIndoor) return;
    if (_currentNavigatingFloor == floorNumber) return;

    debugPrint(
      '[NavigationViewModel] Pre-loading floor $floorNumber (approaching connector)',
    );
    _expectedNextFloor = floorNumber;
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = true;
    _transitionStartTime = _port.now();

    // EXPECTED: the route anticipates a floor change (connector approached).
    _navEvent.navEvent('FLOOR_EVENT', detail: 'kind=expected');
    _recordFloorTransitionEvent(
      FloorTransitionEvent(
        stage: FloorTransitionStage.expected,
        trigger: FloorTransitionTrigger.connectorProximity,
        fromFloor: _currentNavigatingFloor,
        toFloor: floorNumber,
        timestamp: _port.now(),
      ),
    );

    // Cache last position for hold during transition
    _lastIndoorPosition = _port.currentLocation;
    _machine.transition(NavigationState.floorTransition);
    _port.notifyChanged();

    // Trigger floor load in the scope
    final floors = _scope.floors;
    final targetFloor = floors
        .where((f) => f.floorNumber == floorNumber)
        .firstOrNull;
    if (targetFloor != null &&
        _scope.selectedFloor?.floorNumber != floorNumber) {
      _scope.selectFloorForNavigation(targetFloor);
    }
  }

  /// Enters FLOOR_TRANSITION because positioning evidence drifted to another
  /// floor without a connector being approached, then completes immediately.
  void beginOrganicFloorTransition(String newFloor) {
    debugPrint(
      '[NavigationViewModel] Organic floor drift: $_currentNavigatingFloor -> $newFloor',
    );
    _expectedNextFloor = newFloor;
    _connectorInitiatedTransition = false;
    _transitionStartTime = _port.now();
    _lastIndoorPosition = _port.currentLocation;
    _machine.transition(NavigationState.floorTransition);
    _port.notifyChanged();
    completeFloorTransition(newFloor);
  }

  void completeFloorTransition(String newFloor) {
    debugPrint(
      '[NavigationViewModel] Floor transition confirmed: $_currentNavigatingFloor -> $newFloor',
    );
    final previousFloor = _currentNavigatingFloor;
    _currentNavigatingFloor = newFloor;
    _expectedNextFloor = null;
    _onFloorConfirmed();
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = _port.now();
    _transitionStartTime = null;
    _lastIndoorPosition = null;

    // Sync the scope to the new floor
    final floors = _scope.floors;
    final newFloorModel = floors
        .where((f) => f.floorNumber == newFloor)
        .firstOrNull;
    if (newFloorModel != null &&
        _scope.selectedFloor?.floorNumber != newFloor) {
      _scope.selectFloorForNavigation(newFloorModel);
    }

    // CONFIRMED: evidence-gated acceptance â€” the only stage that represents
    // physical-floor proof (ORIGINAL PHASE 5 invariant).
    _navEvent.navEvent('FLOOR_EVENT', detail: 'kind=confirmed', force: true);
    _recordFloorTransitionEvent(
      FloorTransitionEvent(
        stage: FloorTransitionStage.confirmed,
        trigger: _connectorInitiatedTransition
            ? FloorTransitionTrigger.connectorProximity
            : FloorTransitionTrigger.evidence,
        fromFloor: previousFloor,
        toFloor: newFloor,
        timestamp: _port.now(),
      ),
    );
    _connectorInitiatedTransition = false;

    if (_machine.state == NavigationState.floorTransition) {
      _machine.transition(NavigationState.activeIndoor);
    }
    _port.notifyChanged();
  }

  /// Checks if the floor transition has timed out and aborts if so.
  void checkTransitionTimeout() {
    final startTime = _transitionStartTime;
    if (startTime == null) return;

    final elapsed = _port.now().difference(startTime);
    if (elapsed.inSeconds >= NavigationConfig.transitionTimeoutSeconds) {
      debugPrint(
        '[NavigationViewModel] Floor transition timed out after ${elapsed.inSeconds}s â€” aborting',
      );
      // ABORTED: the dwell exceeded its timeout; evidence re-evaluates on
      // subsequent ticks (ORIGINAL PHASE 5 â€” stage visibility).
      _navEvent.navEvent('FLOOR_EVENT', detail: 'kind=aborted');
      _recordFloorTransitionEvent(
        FloorTransitionEvent(
          stage: FloorTransitionStage.aborted,
          trigger: FloorTransitionTrigger.timeout,
          fromFloor: _currentNavigatingFloor,
          toFloor: _expectedNextFloor,
          timestamp: _port.now(),
        ),
      );
      // Abort transition; evidence re-evaluates on subsequent ticks (WiFi
      // engagement resumes indoors, GPS-outside flows into exit detection).
      _expectedNextFloor = null;
      _connectorInitiatedTransition = false;
      _transitionStartTime = null;
      _lastIndoorPosition = null;
      _newFloorEstimateCount = 0;
      _machine.transition(NavigationState.activeIndoor);
      _port.notifyChanged();
    }
  }

  /// Consumes the post-floor-switch suppression window for the evaluation
  /// pipeline. Returns whether the pipeline should skip this tick; notifies
  /// on the suppressed path (identical semantics to the original inline
  /// check).
  bool consumePostSwitchCooldown() {
    if (_lastFloorSwitchTime != null) {
      final elapsed = _port.now().difference(_lastFloorSwitchTime!);
      if (elapsed.inSeconds < NavigationConfig.postFloorSwitchSuppressSeconds) {
        _port.notifyChanged();
        return true;
      }
      _lastFloorSwitchTime = null;
    }
    return false;
  }

  /// Route-context floor adoption for a building entrance (residency
  /// preload); the session fencing already ran on the caller side.
  void preloadEntranceFloor(FloorModel floor) {
    _currentNavigatingFloor = floor.floorNumber;
    _scope.selectFloorForNavigation(floor);
  }

  /// Route-context release on a confirmed building exit (Iâ†’O EXIT RELEASE
  /// MATRIX). Floor identity and expected-floor anticipation become
  /// stale-but-harmless and are recomputed on the next indoor leg.
  void releaseOnBuildingExit() {
    _currentNavigatingFloor = null;
    _expectedNextFloor = null;
    _connectorInitiatedTransition = false;
  }

  /// Segment-driven route-context floor bookkeeping â€” regular segment starts
  /// only (floorTransition segments are owned by the evidence-gated flow).
  void applyFromSegmentAdvance(String floorNumber) {
    _currentNavigatingFloor = floorNumber;
  }

  void resetForPreviewSeed() {
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _lastFloorSwitchTime = null;
    _lastIndoorPosition = null;
  }

  void resetForStartActive() {
    _newFloorEstimateCount = 0;
  }

  void resetForEnd() {
    _currentNavigatingFloor = null;
    _expectedNextFloor = null;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = null;
    _transitionStartTime = null;
    _lastIndoorPosition = null;
  }

  void resetForRetarget() {
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _lastFloorSwitchTime = null;
    _lastIndoorPosition = null;
  }
}
