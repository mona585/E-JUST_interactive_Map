import 'dart:async';

import '../models/floor_transition_event.dart';
import '../models/navigation_route_model.dart';
import '../models/navigation_state.dart';
import '../models/poi_model.dart';
import '../models/route_progress.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import '../repositories/navigation_repository.dart';
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
import 'navigation_session_manager.dart';
import 'navigation_state_machine.dart';

export 'navigation_pilot_port.dart' show NavigationPilotPort;

/// The navigation decision engine facade.
///
/// Composition root after the MVVM decomposition: owns the canonical session
/// lifecycle ([NavigationSessionManager]), the state machine ([NavigationStateMachine]),
/// and the evidence-driven evaluation handlers (floor transitions, building
/// handoff, deviation/reroute, segment advance, arrival, GPS loss/recovery).
/// This class wires the components, exposes the canonical state surface, and
/// runs the fixed evaluation order; every individual decision lives in the
/// extracted handler. The [NavigationPilotPort] it observes is implemented
/// by [NavigationViewModel], which remains a thin presentation facade.
class NavigationPilot {
  NavigationPilot({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationRepository navigationRepository,
  }) :
      // ignore: prefer_initializing_formals (private named formals are not allowed)
      _scope = scope,
      // ignore: prefer_initializing_formals
      _port = port,
      // ignore: prefer_initializing_formals
      _navigationRepository = navigationRepository {
    _eventLog = NavigationEventLog(
      port: _port,
      session: () => _sessionManager.session,
      currentFloor: () => _floorHandler.currentNavigatingFloor,
    );
    _machine = NavigationStateMachine(now: _port.now, navEvent: _eventLog);
    _arrivalDetector = NavigationArrivalDetector(
      scope: _scope,
      port: _port,
      machine: _machine,
      navEvent: _eventLog,
      session: () => _sessionManager.session,
    );
    _floorHandler = NavigationFloorTransitionHandler(
      scope: _scope,
      port: _port,
      machine: _machine,
      navEvent: _eventLog,
      onFloorConfirmed: () => _buildingHandler.resetExitConfirmation(),
    );
    _buildingHandler = NavigationBuildingContextHandler(
      scope: _scope,
      port: _port,
      machine: _machine,
      navEvent: _eventLog,
      destinationSpace: () => _sessionManager.destinationSpace,
      session: () => _sessionManager.session,
      isCurrent: (sessionId, revision) =>
          _sessionManager.isCurrent(sessionId: sessionId, revision: revision),
      onPreloadFloor: (floor) => _floorHandler.preloadEntranceFloor(floor),
      onReleaseIndoorForExit: () => _floorHandler.releaseOnBuildingExit(),
    );
    _progressTracker = NavigationRouteProgressTracker(
      scope: _scope,
      machine: _machine,
    );
    _deviationHandler = NavigationDeviationHandler(
      scope: _scope,
      port: _port,
      machine: _machine,
      navigationRepository: _navigationRepository,
      navEvent: _eventLog,
      session: () => _sessionManager.session,
      destinationSpace: () => _sessionManager.destinationSpace,
      isCurrent: (sessionId, revision) =>
          _sessionManager.isCurrent(sessionId: sessionId, revision: revision),
      adoptRoute: (route) => _sessionManager.adoptNavigatedRoute(route),
      bumpRevision: () => _sessionManager.bumpRevision(),
      setRouteIncomplete: (value) => _sessionManager.setRouteIncomplete(value),
      resolveArrivalAnchor: _arrivalDetector.resolveAnchor,
      currentNavigatingFloor: () => _floorHandler.currentNavigatingFloor,
      customRouteProgress: () => _progressTracker.progress,
    );
    _segmentTracker = NavigationSegmentTracker(
      scope: _scope,
      port: _port,
      arrivalAnchor: () => _arrivalDetector.anchor,
      setRouteIncomplete: (value) => _sessionManager.setRouteIncomplete(value),
      setNavigatingFloor: (floor) =>
          _floorHandler.applyFromSegmentAdvance(floor),
    );
    _gpsGuard = NavigationGpsGuard(port: _port, machine: _machine);
    _sessionManager = NavigationSessionManager(
      scope: _scope,
      port: _port,
      machine: _machine,
      navEvent: _eventLog,
      floor: _floorHandler,
      building: _buildingHandler,
      deviation: _deviationHandler,
      arrival: _arrivalDetector,
      progress: _progressTracker,
      segment: _segmentTracker,
      gps: _gpsGuard,
    );
  }

  late final NavigationRouteScope _scope;
  late final NavigationPilotPort _port;
  late final NavigationRepository _navigationRepository;

  late final NavigationEventLog _eventLog;
  late final NavigationStateMachine _machine;
  late final NavigationArrivalDetector _arrivalDetector;
  late final NavigationFloorTransitionHandler _floorHandler;
  late final NavigationBuildingContextHandler _buildingHandler;
  late final NavigationRouteProgressTracker _progressTracker;
  late final NavigationDeviationHandler _deviationHandler;
  late final NavigationSegmentTracker _segmentTracker;
  late final NavigationGpsGuard _gpsGuard;
  late final NavigationSessionManager _sessionManager;

  NavigationRouteModel? get _activeRoute => _scope.activeNavigationRoute;

  // ──────────────────────────────────────────────────────────────
  // Canonical state surface
  // ──────────────────────────────────────────────────────────────

  /// Current canonical navigation state.
  NavigationState get state => _machine.state;

  /// Immutable snapshot of the whole machine for observers that need a
  /// consistent multi-field read.
  NavigationSnapshot get snapshot => NavigationSnapshot(
    state: _machine.state,
    previousActiveState: _machine.previousActiveState,
    fix: _port.currentFix,
    navigatingBuildingId: _sessionManager.destinationSpace?.buid,
    navigatingFloor: _floorHandler.currentNavigatingFloor,
    expectedNextFloor: _floorHandler.expectedNextFloor,
    pauseReason: _gpsGuard.pauseMessage,
    segmentIndex: _segmentTracker.currentSegmentIndex,
    timestamp: _port.now(),
  );

  NavigationSubState get subState => _machine.subState;

  /// A live session covers activities and overlays but not preview/idle —
  /// identical semantics to the legacy "phase == active" check.
  bool get isActive => _machine.isActive;
  bool get isPreview => _machine.isPreview;
  NavigationRouteModel? get activeRoute => _activeRoute;
  String? get currentNavigatingFloor => _floorHandler.currentNavigatingFloor;
  bool get isTransitioningFloors => _machine.isTransitioningFloors;
  bool get isRerouting => _machine.isRerouting;
  bool get isArrived => _machine.isArrived;

  /// Identity of the live navigation session, or null when no session exists.
  String? get sessionId => _sessionManager.sessionId;

  /// Destination identity now lives on the session; these getters are
  /// delegates so existing consumers stay source-compatible.
  String? get destinationPuid => _sessionManager.destinationPuid;
  SpaceModel? get destinationSpace => _sessionManager.destinationSpace;

  // Segment navigation getters
  int get currentSegmentIndex => _segmentTracker.currentSegmentIndex;
  bool get isPaused => _gpsGuard.isPaused;
  String? get pauseMessage => _gpsGuard.pauseMessage;
  bool get isPartialRoute => _activeRoute?.isPartial ?? false;

  // Custom route navigation getters
  RouteProgress? get customRouteProgress => _progressTracker.progress;
  bool get isOnCustomRoute => _progressTracker.isOnCustomRoute;

  /// The current segment being navigated, or null if not started.
  RouteSegment? get currentSegment => _segmentTracker.currentSegment;

  /// The next segment after the current one, or null.
  RouteSegment? get nextSegment => _segmentTracker.nextSegment;

  /// Total number of segments in the current route.
  int get totalSegments => _segmentTracker.totalSegments;

  /// User-friendly positioning status message.
  String get positioningStatus => _floorHandler.positioningStatus;

  /// Position to render during a floor transition (held position), or the
  /// current location otherwise.
  UserLocation? get heldPositionDuringTransition =>
      _floorHandler.heldPositionDuringTransition;

  /// Floor-transition lifecycle events for the current session, oldest first.
  List<FloorTransitionEvent> get floorTransitionEvents =>
      _floorHandler.floorTransitionEvents;

  /// Most recent floor-transition event, or null before any transition.
  FloorTransitionEvent? get lastFloorTransitionEvent =>
      _floorHandler.lastFloorTransitionEvent;

  // ──────────────────────────────────────────────────────────────
  // Public commands
  // ──────────────────────────────────────────────────────────────

  /// Starts route preview mode after the user taps "Route Here".
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
  }) => _sessionManager.startRoutePreview(
    destinationPuid: destinationPuid,
    destinationSpace: destinationSpace,
  );

  /// Transitions from preview to active navigation when the user taps
  /// "Start Directions".
  void startActiveNavigation() => _sessionManager.startActiveNavigation();

  /// Ends the session from ANY state (user action; bypasses the table).
  void endNavigation() => _sessionManager.endNavigation();

  /// Canonical teardown (MASTER PLAN PHASE 15, INV-10).
  void terminateNavigation() => _sessionManager.terminateNavigation();

  /// Marks arrival at the destination.
  // Facade bridge: surfaced through NavigationViewModel for test access.
  void markArrived() => _arrivalDetector.markArrived();

  /// Explicit destination-change protocol (MASTER PLAN PHASE 4).
  Future<bool> retargetDestination(PoiModel newTarget) =>
      _sessionManager.retargetDestination(newTarget);

  /// Evaluation pipeline: fixed ordering over the extracted handlers. Every
  /// decision heuristic lives in the handler owning its bookkeeping; this
  /// method only orders the stages and preserves the pause/cooldown skip
  /// semantics.
  void evaluateUserLocation() {
    if (!_machine.state.isSessionLive) return;
    if (_machine.state == NavigationState.arrived) return;

    final location = _port.currentLocation;
    final fix = _port.currentFix;

    if (_machine.state == NavigationState.paused) {
      // Only GPS recovery matters while paused.
      if (location != null) _gpsGuard.checkGpsRecovery(location);
      return;
    }
    if (location == null) return;
    if (_machine.state == NavigationState.rerouting) return;

    // Hold position during floor transition instead of jumping to GPS.
    if (_machine.state == NavigationState.floorTransition) {
      _floorHandler.checkTransitionTimeout();
      if (_floorHandler.heldPositionDuringTransition != null) {
        _port.notifyChanged();
        return;
      }
    }

    // Suppress checks briefly after a floor switch (post-switch cooldown).
    if (_floorHandler.consumePostSwitchCooldown()) return;

    _buildingHandler.checkBeliefFlip(fix);
    _buildingHandler.maintainDwell(fix, location);

    // PHASE 6 ordering: the GPS-quality/pause gate runs BEFORE any deviation
    // or reroute evaluation so a garbage fix can never fire a reroute before
    // the pause check sees it (BUG-5 second half).
    _gpsGuard.checkGpsLoss(location);
    if (_machine.state == NavigationState.paused) {
      _port.notifyChanged();
      return;
    }

    _progressTracker.update(location);
    _deviationHandler.checkDeviationAndReroute(location);
    _floorHandler.checkFloorTransition(location);
    _buildingHandler.checkBuildingExit(location);
    _buildingHandler.checkBuildingApproach(location);
    _buildingHandler.checkEntranceProximity(location);
    _segmentTracker.checkSegmentTransition(location);
    _arrivalDetector.checkArrival(location);
    _port.notifyChanged();
  }

  // ──────────────────────────────────────────────────────────────
  // Test-only surface
  // ──────────────────────────────────────────────────────────────

  /// Test-only view of the residency-prep latch (ORIGINAL PHASE 4).
  bool get buildingPreloadedForTest => _buildingHandler.buildingPreloaded;

  /// Test-only view of the live session (Phase 1).
  NavigationSession? get sessionForTest => _sessionManager.session;

  /// Test-only view of the reroute cooldown stamp (Phase 1).
  DateTime? get lastRerouteTimeForTest => _deviationHandler.lastRerouteTimeForTest;

  /// Test-only direct entry into the reroute flow (Phase 1).
  Future<void> debugTriggerReroute() => _deviationHandler.debugTriggerReroute();

  /// Test-only revision bump (Phase 1).
  void debugBumpRouteRevision() => _sessionManager.bumpRevision();

  /// Test-only anchor suppression (Phase 9).
  void debugClearArrivalAnchorForTest() =>
      _arrivalDetector.clearAnchorForTest();

  /// Test-only identity view of the resolved arrival anchor (Phase 13).
  Object? get arrivalAnchorForTest => _arrivalDetector.arrivalAnchorForTest;

  /// Resets the building-exit confirmation streak (used when the user
  /// re-enters follow mode).
  void resetExitConfirmation() => _buildingHandler.resetExitConfirmation();

  bool get rerouteFailed => _deviationHandler.rerouteFailed;
  bool get routeIncomplete => _sessionManager.routeIncomplete;
}