import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/navigation_config.dart';
import '../data/models/floor_model.dart';
import '../data/models/floor_transition_event.dart';
import '../data/models/navigation_route_model.dart';
import '../data/models/position_fix.dart';
import '../data/models/poi_model.dart';
import '../data/models/route_progress.dart';
import '../data/models/route_segment.dart';
import '../data/models/space_model.dart';
import '../data/models/user_location.dart';
import '../data/repositories/navigation_repository.dart';
import 'location_provider.dart';
import 'navigation_state_model.dart';

/// Legacy top-level navigation phase.
///
/// Retained for compatibility with existing consumers; derived from the
/// canonical [NavigationState] machine via [NavigationController.phase].
enum NavigationPhase { idle, preview, active }

/// Legacy sub-state during active navigation.
///
/// Retained for compatibility with existing consumers; derived from the
/// canonical [NavigationState] machine via [NavigationController.subState].
enum NavigationSubState { outdoor, indoor, transitioning }

/// Manages the navigation lifecycle as an explicit state machine
/// (ORIGINAL PHASE 2 — Navigation State Machine).
///
/// The canonical state is one of [NavigationState]; all transitions pass
/// through [_transition], which enforces [kAllowedNavigationTransitions] plus
/// two dynamic edges (paused/rerouting restoring to their previous activity,
/// and user-initiated End from any state). Physical position and building/
/// floor identity come exclusively from [PositionFix]; the controller's
/// floor/building fields are route-context bookkeeping only.
///
/// This controller coordinates between [NavigationRouteScope] (building/floor/
/// route state), [LocationProvider] (canonical position fixes), and the map
/// camera consumers.
class NavigationController extends ChangeNotifier {
  final NavigationRouteScope _spaceScope;
  final LocationProvider _locationProvider;
  final NavigationRepository _navigationRepository;

  NavigationState _state = NavigationState.idle;

  /// Activity to restore after paused/rerouting/arrived overlays.
  NavigationState? _previousActiveState;

  // -- Route context --
  NavigationSession? _session;
  bool _followMode = true;
  DateTime? _lastRerouteTime;

  /// Delegating view of the SINGLE route store (MASTER PLAN PHASE 2,
  /// INV-1/INV-2). There is no second cache: evaluation and rendering read
  /// the same object by construction. Commits go through
  /// [NavigationRouteScope.adoptNavigatedRoute] with a revision increment.
  NavigationRouteModel? get _activeRoute => _spaceScope.activeNavigationRoute;

  // -- Floor-transition bookkeeping --
  String? _currentNavigatingFloor;
  String? _expectedNextFloor;

  /// Whether [_expectedNextFloor] originated from the connector-proximity
  /// path (route expectation) rather than an organic-drift completion.
  bool _connectorInitiatedTransition = false;

  int _exitConfirmationCounter = 0;
  int _newFloorEstimateCount = 0;
  DateTime? _lastFloorSwitchTime;
  DateTime? _transitionStartTime;

  /// Bounded per-session history of floor-transition lifecycle events
  /// (ORIGINAL PHASE 5 — first-class transition events).
  final List<FloorTransitionEvent> _floorTransitionEvents = [];

  // -- Position hold during transition --
  UserLocation? _lastIndoorPosition;

  // -- Building entry detection --
  bool _buildingPreloaded = false;

  // -- Arrival detection (ORIGINAL PHASE 6; Phase 13 anchor stability) --
  _ArrivalAnchor? _arrivalAnchor;
  int _arrivalConfirmationCounter = 0;
  String? _anchorSessionId;
  int _anchorRevision = -1;

  // -- Segment tracking for cross-building navigation --
  int _currentSegmentIndex = 0;

  // -- Pause bookkeeping --
  String? _pauseReason;

  // -- PHASE 6: reroute hysteresis + failure visibility --
  /// Consecutive off-route (polyline deviation) confirm ticks.
  int _deviationStreak = 0;

  /// Consecutive KMZ off-route confirm ticks.
  int _kmzOffRouteStreak = 0;

  /// Transient failure flag: the last reroute attempt could not produce a
  /// valid route. Cleared on the next successful commit, End, preview seed
  /// or retarget. Surfaced in the status bar.
  bool _rerouteFailed = false;

  bool get rerouteFailed => _rerouteFailed;

  // -- PHASE 8: O→I handoff guidance refresh --
  /// Once-per-session latch: indoor guidance content ensured.
  bool _indoorGuidanceEnsured = false;

  /// Transient hint flag: the handoff could not produce indoor geometry.
  bool _indoorGuidanceFailed = false;

  bool get indoorGuidanceUnavailable => _indoorGuidanceFailed;

  // -- PHASE 9: route-exhaustion visibility --
  /// Transient flag: segments ended away from the destination anchor.
  bool _routeIncomplete = false;

  bool get routeIncomplete => _routeIncomplete;

  // -- Custom route tracking --
  RouteProgress? _customRouteProgress;

  /// Start time of the current ENTERING_BUILDING / EXITING_BUILDING dwell.
  DateTime? _dwellStart;

  /// Until this instant the PROXIMITY path may not re-trigger
  /// ENTERING_BUILDING after a timed-out dwell. Evidence-driven belief flips
  /// ignore it. (ORIGINAL PHASE 4.)
  DateTime? _entryDwellCooldownUntil;

  /// Test-only clock override for dwell-timeout and cooldown decisions.
  /// Widget tests run under a fake async zone where [DateTime.now()] does
  /// not advance with pumped durations; injecting a controllable clock
  /// keeps the timeout rules exercisable without changing production
  /// behavior (null override = wall clock).
  @visibleForTesting
  DateTime Function()? debugNowOverride;

  DateTime _now() => debugNowOverride?.call() ?? DateTime.now();

  /// Session-fencing guard (MASTER PLAN PHASE 1 / INV-3 core): an async
  /// continuation may commit only while the session it captured is still
  /// the current one at the route revision it observed.
  bool _isCurrent({required String sessionId, required int revision}) =>
      _session != null &&
      _session!.sessionId == sessionId &&
      _session!.routeRevision == revision;

  NavigationController({
    required NavigationRouteScope spaceProvider,
    required this._locationProvider,
    NavigationRepository? navigationRepository,
  })  : _spaceScope = spaceProvider,
        _navigationRepository =
            navigationRepository ?? AnyplaceNavigationRepository() {
    _locationProvider.addListener(_onLocationChanged);
  }

  // ──────────────────────────────────────────────────────────────
  // Canonical state surface
  // ──────────────────────────────────────────────────────────────

  /// Current canonical navigation state.
  NavigationState get navigationState => _state;

  /// Immutable snapshot of the whole machine for observers that need a
  /// consistent multi-field read.
  NavigationSnapshot get snapshot => NavigationSnapshot(
        state: _state,
        previousActiveState: _previousActiveState,
        fix: _locationProvider.currentFix,
        navigatingBuildingId: destinationSpace?.buid,
        navigatingFloor: _currentNavigatingFloor,
        expectedNextFloor: _expectedNextFloor,
        pauseReason: _pauseReason,
        segmentIndex: _currentSegmentIndex,
        timestamp: _now(),
      );

  /// Enforces the allowed-edge table and records overlay bookkeeping.
  ///
  /// Illegal edges are rejected with a debug print — never thrown — so a bad
  /// detection heuristic cannot crash a live session. Returns whether the
  /// transition happened.
  bool _transition(NavigationState to) {
    final from = _state;
    if (from == to) return false;

    final dynamicRestore =
        (from == NavigationState.paused || from == NavigationState.rerouting) &&
            to == _previousActiveState;
    if (!dynamicRestore && !isAllowedNavigationTransition(from, to)) {
      debugPrint('[NavigationController] Rejected transition $from -> $to');
      return false;
    }

    _state = to;

    switch (to) {
      case NavigationState.paused:
      case NavigationState.rerouting:
      case NavigationState.arrived:
        if (from.isActivity) _previousActiveState = from;
        break;
      default:
        _previousActiveState = null;
    }

    if (to == NavigationState.enteringBuilding ||
        to == NavigationState.exitingBuilding) {
      _dwellStart = _now();
    } else {
      _dwellStart = null;
    }
    return true;
  }

  // ──────────────────────────────────────────────────────────────
  // Compatibility projections (legacy getters)
  // ──────────────────────────────────────────────────────────────

  NavigationPhase get phase {
    switch (_state) {
      case NavigationState.idle:
        return NavigationPhase.idle;
      case NavigationState.routePreview:
        return NavigationPhase.preview;
      default:
        return NavigationPhase.active;
    }
  }

  NavigationSubState get subState => _projectSubState(_state);

  NavigationSubState _projectSubState(NavigationState s) {
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
        return _projectSubState(
            _previousActiveState ?? NavigationState.activeOutdoor);
      case NavigationState.idle:
      case NavigationState.routePreview:
        return NavigationSubState.outdoor;
    }
  }

  bool get followMode => _followMode;

  /// A live session covers activities and overlays but not preview/idle —
  /// identical semantics to the legacy "phase == active" check.
  bool get isActive => _state.isSessionLive;
  bool get isPreview => _state == NavigationState.routePreview;
  NavigationRouteModel? get activeRoute => _activeRoute;
  String? get currentNavigatingFloor => _currentNavigatingFloor;
  bool get isTransitioningFloors =>
      _state == NavigationState.floorTransition;
  bool get isRerouting => _state == NavigationState.rerouting;
  bool get isArrived => _state == NavigationState.arrived;

  /// Identity of the live navigation session, or null when no session exists.
  String? get sessionId => _session?.sessionId;

  /// Destination identity now lives on the session (Phase 1); these getters
  /// are delegates so existing consumers stay source-compatible.
  String? get destinationPuid => _session?.destinationPuid;
  SpaceModel? get destinationSpace => _session?.destinationSpace;

  // Segment navigation getters
  int get currentSegmentIndex => _currentSegmentIndex;
  bool get isPaused => _state == NavigationState.paused;
  String? get pauseMessage => _pauseReason;
  bool get isPartialRoute => _activeRoute?.isPartial ?? false;

  // Custom route navigation getters
  RouteProgress? get customRouteProgress => _customRouteProgress;
  bool get isOnCustomRoute => _customRouteProgress?.isOnRoute ?? false;

  /// The current segment being navigated, or null if not started.
  RouteSegment? get currentSegment {
    if (_activeRoute == null || !_activeRoute!.hasSegments) return null;
    if (_currentSegmentIndex >= _activeRoute!.segments.length) return null;
    return _activeRoute!.segments[_currentSegmentIndex];
  }

  /// The next segment after the current one, or null.
  RouteSegment? get nextSegment {
    if (_activeRoute == null || !_activeRoute!.hasSegments) return null;
    final nextIdx = _currentSegmentIndex + 1;
    if (nextIdx >= _activeRoute!.segments.length) return null;
    return _activeRoute!.segments[nextIdx];
  }

  /// Total number of segments in the current route.
  int get totalSegments => _activeRoute?.segments.length ?? 0;

  /// User-friendly positioning status message.
  String get positioningStatus {
    if (_state == NavigationState.floorTransition) {
      final nextFloor = _expectedNextFloor;
      if (nextFloor != null) {
        return '${NavigationConfig.transitionBlackoutMessage} $nextFloor...';
      }
      return '${NavigationConfig.transitionBlackoutMessage}...';
    }
    final floor = _currentNavigatingFloor;
    switch (_locationProvider.positionSource) {
      case LocationSource.indoorWifi:
        return floor != null ? 'Indoor \u2022 Floor $floor' : 'Indoor location';
      case LocationSource.gps:
        return 'GPS active';
      case LocationSource.none:
        return 'Updating location\u2026';
    }
  }

  /// Position to render during a floor transition (held position), or the
  /// current location otherwise.
  UserLocation? get heldPositionDuringTransition =>
      _state == NavigationState.floorTransition ? _lastIndoorPosition : null;

  /// Floor-transition lifecycle events for the current session, oldest first
  /// (ORIGINAL PHASE 5 — bounded by
  /// [NavigationConfig.floorTransitionEventHistoryLimit]).
  List<FloorTransitionEvent> get floorTransitionEvents =>
      List.unmodifiable(_floorTransitionEvents);

  /// Most recent floor-transition event, or null before any transition.
  FloorTransitionEvent? get lastFloorTransitionEvent =>
      _floorTransitionEvents.isEmpty ? null : _floorTransitionEvents.last;

  /// Appends [event] to the bounded per-session history.
  void _recordFloorTransitionEvent(FloorTransitionEvent event) {
    _floorTransitionEvents.add(event);
    final limit = NavigationConfig.floorTransitionEventHistoryLimit;
    if (_floorTransitionEvents.length > limit) {
      _floorTransitionEvents.removeRange(
          0, _floorTransitionEvents.length - limit);
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────

  /// Starts route preview mode after the user taps "Route Here".
  ///
  /// The route must already be loaded in the scope provider. Calling again
  /// while previewing re-seeds the preview (e.g., destination changed).
  ///
  /// Creates the [NavigationSession] for this run. The caller-supplied
  /// destination floor parameter was unused and has been removed (BUG-15c);
  /// the session's destination floor is derived from the destination POI
  /// when it is resolvable in the scope.
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
  }) {
    if (_state != NavigationState.idle &&
        _state != NavigationState.routePreview) {
      return;
    }

    final route = _spaceScope.activeNavigationRoute;
    if (route == null || !route.hasRenderablePath) return;

    final wasIdle = _state == NavigationState.idle;

    final destinationPoi =
        _spaceScope.pois.where((p) => p.puid == destinationPuid).firstOrNull;
    _session = NavigationSession(
      destinationPuid: destinationPuid,
      destinationSpace: destinationSpace,
      destinationFloorNumber: destinationPoi?.floorNumber,
    );
    // The route itself stays where it already is — the scope store. Preview
    // seeding is NOT a controller write, so the revision starts at 0; it is
    // bumped only by committed session replacements (reroutes).
    _currentNavigatingFloor = _spaceScope.selectedFloor?.floorNumber;
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _lastFloorSwitchTime = null;
    _lastIndoorPosition = null;
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    _entryDwellCooldownUntil = null;
    _arrivalConfirmationCounter = 0;
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
    _indoorGuidanceEnsured = false;
    _indoorGuidanceFailed = false;
    _routeIncomplete = false;
    _resolveArrivalAnchor();

    if (wasIdle) {
      _transition(NavigationState.routePreview);
    }
    debugPrint('[NAV] SESSION_START sid=${_session!.sessionId} '
        'dst=$destinationPuid rev=${_session!.routeRevision}');
    notifyListeners();
  }

  /// Transitions from preview to active navigation when the user taps
  /// "Start Directions".
  ///
  /// The initial activity is chosen purely from positioning evidence — never
  /// from the destination's building or floor.
  void startActiveNavigation() {
    if (_state != NavigationState.routePreview) return;

    _followMode = true;
    _lastRerouteTime = null;
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
    _exitConfirmationCounter = 0;
    _newFloorEstimateCount = 0;
    _arrivalConfirmationCounter = 0;

    final fix = _locationProvider.currentFix;
    if (fix?.source == PositionSource.wifi) {
      _transition(NavigationState.activeIndoor);
      _ensureIndoorGuidance();
    } else {
      _transition(NavigationState.activeOutdoor);
    }
    notifyListeners();
  }

  /// PHASE 8 (BUG-7 closure): after the handoff confirms ACTIVE_INDOOR,
  /// guidance geometry becomes genuinely indoor — fetch/refresh the indoor
  /// route for the destination once per session.
  ///
  /// Contract:
  ///  * fenced by session identity + revision (Phase 1 mechanics),
  ///  * latched per session; the latch resets on retarget/End/new preview,
  ///  * RadioMap readiness for the confirmed scope is gated inside the
  ///    scope wrapper (20 s cap), then a candidate is fetched via existing
  ///    guarded machinery,
  ///  * success commits through [adoptNavigatedRoute] + revision bump,
  ///  * failure keeps the old route, sets the visible hint flag, and leaves
  ///    the latch OPEN so the next floor confirmation retries.
  Future<void> _ensureIndoorGuidance() async {
    if (_indoorGuidanceEnsured) return;
    final session = _session;
    if (session == null || !_state.isSessionLive) return;
    if (_state != NavigationState.activeIndoor) return;
    final destPuid = session.destinationPuid;
    if (destPuid == null) return;

    // Already carrying usable indoor guidance ending at the destination?
    final route = _activeRoute;
    final confirmedFloor = _currentNavigatingFloor;
    if (route != null &&
        route.hasIndoorSegment &&
        route.points.isNotEmpty &&
        route.points.last.puid == destPuid &&
        confirmedFloor != null &&
        route.points.last.floorNumber == confirmedFloor) {
      _indoorGuidanceEnsured = true;
      debugPrint('[NAV] INDOOR_GUIDANCE_ALREADY_USABLE sid='
          '${session.sessionId}');
      return;
    }

    final sid = session.sessionId;
    final rev = session.routeRevision;

    final indoorRoute = await _spaceScope.requestIndoorRouteForSession(
      destinationPuid: destPuid,
      confirmedBuid: destinationSpace?.buid ?? '',
      confirmedFloor: confirmedFloor ?? '',
    );

    // Fenced commit: only the newest identity may write.
    if (!_isCurrent(sessionId: sid, revision: rev)) {
      debugPrint('[NAV] INDOOR_GUIDANCE discarded (stale session/revision)');
      return;
    }
    if (indoorRoute != null && indoorRoute.hasRenderablePath) {
      _spaceScope.adoptNavigatedRoute(indoorRoute);
      _session!.routeRevision++;
      _resolveArrivalAnchor();
      _routeIncomplete = false;
      _indoorGuidanceEnsured = true;
      _indoorGuidanceFailed = false;
      debugPrint('[NAV] INDOOR_GUIDANCE_COMMITTED sid=$sid '
          'rev=${_session!.routeRevision}');
    } else {
      _indoorGuidanceFailed = true;
      debugPrint('[NAV] INDOOR_GUIDANCE_UNAVAILABLE sid=$sid — keeping '
          'general path; will retry on next floor confirmation');
    }
    notifyListeners();
  }

  /// Ends the session from ANY state (user action; bypasses the table).
  void endNavigation() {
    final endedSessionId = _session?.sessionId;
    _state = NavigationState.idle;
    _previousActiveState = null;
    _session = null;
    // INV-10 groundwork: teardown owns the store clear as well. Caller-side
    // clears remain harmless until Phase 15 removes them.
    _spaceScope.clearNavigationRoute();
    _currentNavigatingFloor = null;
    _expectedNextFloor = null;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _followMode = true;
    _exitConfirmationCounter = 0;
    _resetSegmentTracking();
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = null;
    _transitionStartTime = null;
    _lastIndoorPosition = null;
    _customRouteProgress = null;
    _buildingPreloaded = false;
    _dwellStart = null;
    _entryDwellCooldownUntil = null;
    _arrivalAnchor = null;
    _arrivalConfirmationCounter = 0;
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
    _indoorGuidanceEnsured = false;
    _indoorGuidanceFailed = false;
    _routeIncomplete = false;
    if (endedSessionId != null) {
      debugPrint('[NAV] SESSION_END sid=$endedSessionId');
    }
    notifyListeners();
  }

  /// Marks arrival at the destination.
  ///
  /// Manual hook kept test-visible; the ORIGINAL PHASE 6 evidence producer
  /// ([_checkArrival]) drives it in production through the same [_arrive]
  /// path.
  @visibleForTesting
  void markArrived() => _arrive();

  /// Explicit destination-change protocol (MASTER PLAN PHASE 4).
  ///
  /// Destination changes are transactions: a NEW session identity is
  /// installed FIRST, then the content (route) follows through the cascade.
  /// Every in-flight artifact of the old run fails its Phase-1 identity
  /// fence and is discarded — an old-destination route can never appear
  /// after a retarget.
  ///
  /// Legal from any live activity/overlay and from preview; refused when
  /// arrived (start a fresh journey instead). Returns true when the new
  /// route committed; on failure the NEW session remains (the user's intent
  /// stands) with arrival anchored on the POI itself.
  Future<bool> retargetDestination(PoiModel newTarget) async {
    if (_state == NavigationState.idle ||
        _state == NavigationState.arrived) {
      return false;
    }
    final oldSessionId = _session?.sessionId;
    debugPrint('[NAV] RETARGET sid=$oldSessionId -> ${newTarget.puid}');

    // 1. Identity first: everything captured under the old id is now dead.
    final newSession = NavigationSession(
      destinationPuid: newTarget.puid,
      destinationSpace: _spaceScope.selectedSpace?.buid == newTarget.buid
          ? _spaceScope.selectedSpace
          : null,
      destinationFloorNumber: newTarget.floorNumber,
    );
    _session = newSession;

    // 2. Reset per-session bookkeeping (same set startRoutePreview resets).
    _currentNavigatingFloor = _spaceScope.selectedFloor?.floorNumber;
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = false;
    _floorTransitionEvents.clear();
    _lastFloorSwitchTime = null;
    _lastIndoorPosition = null;
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    _entryDwellCooldownUntil = null;
    _arrivalConfirmationCounter = 0;
    _arrivalAnchor = null;
    _customRouteProgress = null;
    _deviationStreak = 0;
    _kmzOffRouteStreak = 0;
    _rerouteFailed = false;
    _indoorGuidanceEnsured = false;
    _indoorGuidanceFailed = false;
    _routeIncomplete = false;
    notifyListeners();

    // 3. Content second: cascade for the new target behind request ids.
    final ok = await _spaceScope.requestRouteForRetarget(newTarget);

    // 4. Post-await identity gate: only the newest retarget may seed.
    if (!identical(_session, newSession)) {
      debugPrint('[NAV] RETARGET superseded for ${newTarget.puid} — '
          'discarding');
      return false;
    }

    // 5. Anchor + state handling. The activity the user was in continues;
    // overlays restore to it via their own dynamic edges.
    if (ok) {
      _resolveArrivalAnchor();
    } else {
      // Degraded but honest: anchor directly on the requested POI so
      // arrival still targets what the user asked for.
      _arrivalAnchor = _ArrivalAnchor(
        latitude: newTarget.latitude,
        longitude: newTarget.longitude,
        buid: newTarget.buid,
        floorNumber: newTarget.floorNumber,
      );
      debugPrint('[NAV] RETARGET route unavailable for ${newTarget.puid}; '
          'anchored on POI');
    }
    if (_state == NavigationState.rerouting ||
        _state == NavigationState.paused) {
      final restore = _previousActiveState;
      if (restore != null) _transition(restore);
    }
    debugPrint('[NAV] SESSION_REPLACED old=$oldSessionId '
        'new=${_session!.sessionId} dst=${newTarget.puid}');
    notifyListeners();
    return ok;
  }

  /// Test-only view of the residency-prep latch (ORIGINAL PHASE 4 —
  /// approach/cancel behavior has no other external signal).
  @visibleForTesting
  bool get buildingPreloadedForTest => _buildingPreloaded;

  /// Test-only view of the live session (Phase 1).
  @visibleForTesting
  NavigationSession? get sessionForTest => _session;

  /// Test-only view of the reroute cooldown stamp (Phase 1 — cooldown must
  /// only be consumed by a reroute that actually began).
  @visibleForTesting
  DateTime? get lastRerouteTimeForTest => _lastRerouteTime;

  /// Test-only direct entry into the reroute flow (Phase 1 — lets tests
  /// exercise guard/fencing branches unreachable through the tick order).
  @visibleForTesting
  Future<void> debugTriggerReroute() => _triggerReroute();

  /// Test-only revision bump (Phase 1 — simulates a committed replacement
  /// landing while an older async result is still in flight).
  @visibleForTesting
  void debugBumpRouteRevision() {
    if (_session != null) _session!.routeRevision++;
  }

  /// Test-only anchor suppression (Phase 9 — drives the exhaustion branch
  /// where no destination anchor is resolvable).
  @visibleForTesting
  void debugClearArrivalAnchorForTest() {
    _arrivalAnchor = null;
  }

  /// Test-only identity view of the resolved arrival anchor (Phase 13).
  @visibleForTesting
  Object? get arrivalAnchorForTest => _arrivalAnchor;

  /// Temporarily disables follow mode (e.g., user panned the map).
  void exitFollowMode() {
    if (!_followMode) return;
    _followMode = false;
    notifyListeners();
  }

  /// Re-enables follow mode (e.g., user tapped re-center button).
  void resumeFollowMode() {
    if (_followMode) return;
    _followMode = true;
    _exitConfirmationCounter = 0;
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────
  // Internal: Location Updates
  // ──────────────────────────────────────────────────────────────

  void _onLocationChanged() {
    if (!_state.isSessionLive) return;
    if (_state == NavigationState.arrived) return;

    final location = _locationProvider.currentLocation;
    final fix = _locationProvider.currentFix;

    if (_state == NavigationState.paused) {
      // Only GPS recovery matters while paused.
      if (location != null) _checkGpsRecovery(location);
      return;
    }
    if (location == null) return;
    if (_state == NavigationState.rerouting) return;

    // Hold position during floor transition instead of jumping to GPS.
    if (_state == NavigationState.floorTransition) {
      _checkTransitionTimeout();
      if (_lastIndoorPosition != null) {
        notifyListeners();
        return;
      }
    }

    // Suppress checks briefly after a floor switch (post-switch cooldown).
    if (_lastFloorSwitchTime != null) {
      final elapsed = _now().difference(_lastFloorSwitchTime!);
      if (elapsed.inSeconds < NavigationConfig.postFloorSwitchSuppressSeconds) {
        notifyListeners();
        return;
      }
      _lastFloorSwitchTime = null;
    }

    _evaluateBeliefFlip(fix);
    _maintainDwell(fix, location);

    // PHASE 6 ordering: the GPS-quality/pause gate runs BEFORE any deviation
    // or reroute evaluation so a garbage fix can never fire a reroute before
    // the pause check sees it (BUG-5 second half).
    _checkGpsLoss(location);
    if (_state == NavigationState.paused) {
      notifyListeners();
      return;
    }

    _updateCustomRouteProgress(location);
    _checkDeviationAndReroute(location);
    _checkFloorTransition(location);
    _checkBuildingExit(location);
    checkBuildingApproach(location);
    checkEntranceProximity(location);
    _checkSegmentTransition(location);
    _checkArrival(location);
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────
  // Belief flips & corroboration dwell
  // ──────────────────────────────────────────────────────────────

  /// Evidence-based outdoor → building-entry trigger: positioning believing
  /// Wi-Fi while we are navigating outdoors means the user walked into a
  /// covered area. Destination selection can never cause this.
  void _evaluateBeliefFlip(PositionFix? fix) {
    if (_state != NavigationState.activeOutdoor) return;
    if (fix?.source != PositionSource.wifi) return;
    debugPrint(
        '[NavigationController] WiFi belief outdoors — entering building flow');
    _transition(NavigationState.enteringBuilding);
  }

  /// Maintains ENTERING_BUILDING / EXITING_BUILDING dwell states: resolves
  /// them on corroborating evidence or times them out safely.
  ///
  /// Entry corroboration is identity-aware: a believed-Wi-Fi fix only
  /// confirms when its canonically confirmed scope matches the destination
  /// building. Unconfirmed-scope Wi-Fi keeps dwelling until the arbiter's
  /// scope streak lands or the timeout reverts outdoors.
  /// Exit corroboration requires one more qualifying GPS tick; silence for
  /// longer than [NavigationConfig.exitingCorroborationTimeoutSeconds]
  /// reverts indoors rather than fabricating an exit.
  void _maintainDwell(PositionFix? fix, UserLocation location) {
    switch (_state) {
      case NavigationState.enteringBuilding:
        if (fix != null &&
            fix.source == PositionSource.wifi &&
            _entryCorroborated(fix)) {
          debugPrint(
              '[NavigationController] Building entry corroborated by WiFi');
          _entryDwellCooldownUntil = null;
          _transition(NavigationState.activeIndoor);
          // PHASE 8: handoff completeness — refresh guidance content.
          _ensureIndoorGuidance();
          return;
        }
        if (navigationDwellExpired(_dwellStart, _now(),
            NavigationConfig.enteringCorroborationTimeoutSeconds)) {
          debugPrint(
              '[NavigationController] Entry not corroborated within '
              '${NavigationConfig.enteringCorroborationTimeoutSeconds}s — '
              'back to outdoor');
          _entryDwellCooldownUntil =
              _now().add(const Duration(
                  seconds: NavigationConfig.entryRetriggerCooldownSeconds));
          _transition(NavigationState.activeOutdoor);
        }
        break;
      case NavigationState.exitingBuilding:
        if (fix?.source == PositionSource.wifi) {
          debugPrint(
              '[NavigationController] WiFi re-engaged during exit — staying indoors');
          _transition(NavigationState.activeIndoor);
          return;
        }
        if (navigationDwellExpired(_dwellStart, _now(),
            NavigationConfig.exitingCorroborationTimeoutSeconds)) {
          debugPrint(
              '[NavigationController] Exit not confirmed within '
              '${NavigationConfig.exitingCorroborationTimeoutSeconds}s — '
              'staying indoors');
          _transition(NavigationState.activeIndoor);
          return;
        }
        if (location.accuracy <= NavigationConfig.exitAccuracyThreshold &&
            _isOutsideBuilding(location)) {
          debugPrint('[NavigationController] Building exit confirmed');
          _applyBuildingExitSideEffects();
          _transition(NavigationState.activeOutdoor);
        }
        break;
      default:
        break;
    }
  }

  /// Identity rule for entry corroboration: the corroborating Wi-Fi fix must
  /// carry canonically confirmed scope matching the destination building.
  ///
  /// The confirmed pair comes solely from the Phase 1 arbiter
  /// ([PositionFix.hasScope]); selection context can never fill it. With no
  /// known destination the source check alone remains authoritative.
  bool _entryCorroborated(PositionFix fix) {
    final destination = destinationSpace;
    if (destination == null) return true;
    if (!fix.hasScope) return false;
    return fix.buildingId == destination.buid;
  }

  // ──────────────────────────────────────────────────────────────
  // Custom Route Progress Tracking
  // ──────────────────────────────────────────────────────────────

  /// Updates progress along the nearest custom route based on current GPS.
  ///
  /// Only active during outdoor navigation when custom routes are loaded.
  void _updateCustomRouteProgress(UserLocation location) {
    if (_state != NavigationState.activeOutdoor) {
      _customRouteProgress = null;
      return;
    }

    final customRepo = _spaceScope.customRouteRepository;
    if (!customRepo.isLoaded) {
      _customRouteProgress = null;
      return;
    }

    _customRouteProgress = customRepo.getRouteProgress(
      location.latLng,
      maxSnapDistance: NavigationConfig.customRouteSnapThreshold,
      offRouteThreshold: NavigationConfig.customRouteOnThreshold,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Deviation Detection & Rerouting
  // ──────────────────────────────────────────────────────────────

  void _checkDeviationAndReroute(UserLocation location) {
    if (_activeRoute == null) return;
    if (_state == NavigationState.rerouting) return;
    if (_state == NavigationState.floorTransition) return;

    // Cooldown check
    if (_lastRerouteTime != null) {
      final elapsed = _now().difference(_lastRerouteTime!);
      if (elapsed.inSeconds < NavigationConfig.rerouteCooldownSeconds) return;
    }

    // PHASE 6 / INV-8: decisions consume only decision-quality fixes. Below
    // the poor band, or held/stale, evidence resets the hysteresis streaks.
    final fix = _locationProvider.currentFix;
    if (fix == null ||
        fix.status != PositionFixStatus.fresh ||
        fix.accuracy > NavigationConfig.gpsPoorAccuracyMeters) {
      _deviationStreak = 0;
      _kmzOffRouteStreak = 0;
      return;
    }

    // Use custom route graph for deviation when outdoors and on a custom
    // route. KMZ off-route evidence also requires confirm-tick hysteresis.
    if (_state == NavigationState.activeOutdoor &&
        _customRouteProgress != null &&
        !_customRouteProgress!.isOnRoute) {
      _kmzOffRouteStreak++;
      if (_kmzOffRouteStreak <
          NavigationConfig.rerouteDeviationConfirmTicks) {
        debugPrint('[NavigationController] Off custom route '
            '($_kmzOffRouteStreak/'
            '${NavigationConfig.rerouteDeviationConfirmTicks} confirm ticks)');
        return;
      }
      _kmzOffRouteStreak = 0;
      debugPrint(
        '[NavigationController] Off custom route '
        '(distance: ${_customRouteProgress!.distanceFromRoute.toStringAsFixed(1)}m) — rerouting',
      );
      _triggerReroute();
      return;
    }
    _kmzOffRouteStreak = 0;

    // Fallback: deviation against active route polyline with hysteresis.
    final deviation = _computeMinDeviation(location.latLng, _activeRoute!);
    if (deviation > NavigationConfig.deviationThreshold) {
      _deviationStreak++;
      if (_deviationStreak < NavigationConfig.rerouteDeviationConfirmTicks) {
        debugPrint('[NavigationController] Deviation '
            '$_deviationStreak/${NavigationConfig.rerouteDeviationConfirmTicks} '
            'confirm ticks');
        return;
      }
      _deviationStreak = 0;
      _triggerReroute();
    } else {
      _deviationStreak = 0;
    }
  }

  /// Perpendicular distance from [point] to the nearest segment of [route].
  ///
  /// PHASE 7 / INV-7: outdoors, deviation is computed over the route's
  /// OUTDOOR geometry explicitly — floor bookkeeping is irrelevant and the
  /// old empty-floor-filter → infinity path can no longer occur. Indoors,
  /// the floor-filtered subset is used as before.
  double _computeMinDeviation(LatLng point, NavigationRouteModel route) {
    List<LatLng> points;
    if (_state == NavigationState.activeOutdoor) {
      points = route.outdoorPolylinePoints;
      if (points.length < 2) {
        // Hybrid legs without outdoor-flagged geometry (legacy server
        // routes): fall through to the full polyline rather than infinity.
        points = route.polylinePoints;
      }
    } else {
      final currentFloor = _currentNavigatingFloor;
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
      final dist = _pointToSegmentDistance(point, points[i], points[i + 1]);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  /// Haversine distance from [p] to the closest point on segment [a]–[b].
  double _pointToSegmentDistance(LatLng p, LatLng a, LatLng b) {
    final abDist = Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    if (abDist < 0.001) return Geolocator.distanceBetween(p.latitude, p.longitude, a.latitude, a.longitude);

    final apDist = Geolocator.distanceBetween(a.latitude, a.longitude, p.latitude, p.longitude);
    final bpDist = Geolocator.distanceBetween(b.latitude, b.longitude, p.latitude, p.longitude);

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

    return Geolocator.distanceBetween(p.latitude, p.longitude, projected.latitude, projected.longitude);
  }

  Future<void> _triggerReroute() async {
    if (_state == NavigationState.rerouting) return;
    if (!(_state == NavigationState.activeOutdoor ||
        _state == NavigationState.activeIndoor ||
        _state == NavigationState.enteringBuilding)) {
      return;
    }
    final session = _session;
    if (session == null || session.destinationPuid == null) return;

    final location = _locationProvider.currentLocation;
    if (location == null) return;

    final origin = _state;
    // Cooldown starts only when the reroute actually begins: a rejected
    // transition must never consume it (BUG-13).
    if (!_transition(NavigationState.rerouting)) return;
    _lastRerouteTime = _now();
    notifyListeners();

    // Capture identity for fencing; nothing captured here may be trusted
    // after an await without revalidation (INV-3 core).
    final sid = session.sessionId;
    final rev = session.routeRevision;
    final destinationPuid = session.destinationPuid!;

    // Step 1: Try custom KMZ routes first (outdoor only)
    if (origin == NavigationState.activeOutdoor) {
      final customRepo = _spaceScope.customRouteRepository;
      if (customRepo.isLoaded) {
        // Find destination from destination space
        final destSpace = _session?.destinationSpace;
        if (destSpace != null) {
          // Step 1a: Try pure custom graph routing
          var customPath = customRepo.findRoute(
            location.latLng,
            destSpace.latLng,
          );

          // Step 1b: Try hybrid routing (edge-based snap)
          if (customPath.length < 2) {
            customPath = customRepo.findHybridRoute(
              location.latLng,
              destSpace.latLng,
              snapThreshold: NavigationConfig.rerouteKmzSnapThreshold,
            ) ?? [];
          }

          if (customPath.length >= 2) {
            debugPrint(
              '[NavigationController] Reroute using custom KMZ route: '
              '${customPath.length} points',
            );
            final customRoute = customRepo.createNavigationRouteFromPath(
              customPath,
              destinationBuid: destSpace.buid,
            );
            if (customRoute != null && customRoute.hasRenderablePath) {
              // Fenced, atomic write-through (INV-6): store + revision bump
              // + anchor re-resolution inside one observer notification.
              if (_isCurrent(sessionId: sid, revision: rev)) {
                _spaceScope.adoptNavigatedRoute(customRoute);
                _session!.routeRevision++;
                _resolveArrivalAnchor();
                _routeIncomplete = false;
              }
              if (_state == NavigationState.rerouting) {
                _transition(origin);
              }
              notifyListeners();
              return;
            }
          }
        }
      }
    }

    // Step 2: Fall back to API-based rerouting.
    // PHASE 6 (BUG-12): outdoor sessions send a NULL floor — never a
    // fabricated '0'; indoor legs send the confirmed navigating floor.
    final String? currentFloor =
        origin == NavigationState.activeOutdoor ? null : _currentNavigatingFloor;
    var committed = false;

    for (var attempt = 0; attempt < NavigationConfig.rerouteMaxRetries; attempt++) {
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
        if (!_isCurrent(sessionId: sid, revision: rev)) {
          debugPrint('[NavigationController] Reroute result discarded '
              '(stale session/revision)');
          if (_state == NavigationState.rerouting) {
            _transition(origin);
            notifyListeners();
          }
          return;
        }
        if (route.hasRenderablePath) {
          // Fenced, atomic write-through (INV-6).
          _spaceScope.adoptNavigatedRoute(route);
          _session!.routeRevision++;
          _resolveArrivalAnchor();
          committed = true;
          _rerouteFailed = false;
          _routeIncomplete = false;
          break;
        }
      } catch (e) {
        debugPrint('[NavigationController] Reroute attempt $attempt failed: $e');
        if (!_isCurrent(sessionId: sid, revision: rev)) {
          if (_state == NavigationState.rerouting) {
            _transition(origin);
            notifyListeners();
          }
          return;
        }
      }
      // Exponential backoff: 1s, 2s, 4s
      await Future.delayed(Duration(seconds: 1 << attempt));
      if (!_isCurrent(sessionId: sid, revision: rev)) {
        debugPrint('[NavigationController] Reroute cancelled during backoff '
            '(stale session/revision)');
        if (_state == NavigationState.rerouting) {
          _transition(origin);
          notifyListeners();
        }
        return;
      }
    }

    if (!committed) {
      // INV-8/INV-6 failure semantics: the valid old route persists and the
      // failure is visible (transient flag cleared on next success or End).
      _rerouteFailed = true;
      debugPrint('[NavigationController] Reroute failed — keeping previous '
          'route');
    }

    if (_state == NavigationState.rerouting) {
      // Dynamic restore edge: rerouting -> previous activity.
      _transition(origin);
    }
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────
  // Floor Transition Detection
  // ──────────────────────────────────────────────────────────────

  /// Best available floor identity for the user's physical position.
  ///
  /// Prefers canonically confirmed [PositionFix] scope; falls back to the raw
  /// latest indoor estimate when the arbiter has not yet confirmed scope.
  String? _evidenceFloor() {
    final fix = _locationProvider.currentFix;
    if (fix != null && fix.hasScope) return fix.floor;
    final estimate = _locationProvider.latestIndoorEstimate;
    if (estimate != null && estimate.isValid) return estimate.floor;
    return null;
  }

  void _checkFloorTransition(UserLocation location) {
    if (_activeRoute == null) return;
    final currentFloor = _currentNavigatingFloor;
    if (currentFloor == null) return;

    // Approaching a connector (floor-change point) enters FLOOR_TRANSITION.
    if (_state == NavigationState.activeIndoor) {
      final transitionIndices = _activeRoute!.floorTransitionIndices;
      for (final idx in transitionIndices) {
        final connectorPoint = _activeRoute!.points[idx];
        if (connectorPoint.floorNumber != currentFloor) continue;

        final dist = Geolocator.distanceBetween(location.latitude, location.longitude, connectorPoint.latitude, connectorPoint.longitude);
        if (dist < NavigationConfig.connectorProximityThreshold) {
          // PHASE 9 / BUG-15: a connector as the LAST point has no successor.
          if (idx + 1 >= _activeRoute!.points.length) {
            debugPrint('[NavigationController] Connector is final point - '
                'no successor floor; ignoring');
            continue;
          }
          // User is near a connector — determine next floor
          final nextFloor = _activeRoute!.points[idx + 1].floorNumber;
          if (nextFloor != currentFloor) {
            _beginConnectorFloorTransition(nextFloor);
            break;
          }
        }
      }
    }

    // Floor-evidence confirmation runs in ACTIVE_INDOOR (organic drift) and
    // FLOOR_TRANSITION (awaiting confirmation).
    if (_state != NavigationState.activeIndoor &&
        _state != NavigationState.floorTransition) {
      return;
    }

    if (!_locationProvider.isIndoorWifiActive) {
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
    // accumulation run (ORIGINAL PHASE 5 — stage visibility).
    if (_newFloorEstimateCount == 1) {
      _recordFloorTransitionEvent(FloorTransitionEvent(
        stage: FloorTransitionStage.detected,
        trigger: FloorTransitionTrigger.evidence,
        fromFloor: currentFloor,
        toFloor: evidenceFloor,
        timestamp: _now(),
      ));
    }

    // Require consecutive consistent evidence before confirming
    if (_newFloorEstimateCount >= NavigationConfig.stabilityMinEstimates) {
      if (_state == NavigationState.floorTransition) {
        _completeFloorTransition(evidenceFloor);
      } else {
        _beginOrganicFloorTransition(evidenceFloor);
      }
      _newFloorEstimateCount = 0;
    }
  }

  /// Enters FLOOR_TRANSITION because the user is near a route connector.
  void _beginConnectorFloorTransition(String floorNumber) {
    if (_state != NavigationState.activeIndoor) return;
    if (_currentNavigatingFloor == floorNumber) return;

    debugPrint(
      '[NavigationController] Pre-loading floor $floorNumber (approaching connector)',
    );
    _expectedNextFloor = floorNumber;
    _newFloorEstimateCount = 0;
    _connectorInitiatedTransition = true;
    _transitionStartTime = _now();

    // EXPECTED: the route anticipates a floor change (connector approached).
    _recordFloorTransitionEvent(FloorTransitionEvent(
      stage: FloorTransitionStage.expected,
      trigger: FloorTransitionTrigger.connectorProximity,
      fromFloor: _currentNavigatingFloor,
      toFloor: floorNumber,
      timestamp: _now(),
    ));

    // Cache last position for hold during transition
    _lastIndoorPosition = _locationProvider.currentLocation;
    _transition(NavigationState.floorTransition);
    notifyListeners();

    // Trigger floor load in the scope
    final floors = _spaceScope.floors;
    final targetFloor = floors.where((f) => f.floorNumber == floorNumber).firstOrNull;
    if (targetFloor != null && _spaceScope.selectedFloor?.floorNumber != floorNumber) {
      _spaceScope.selectFloorForNavigation(targetFloor);
    }
  }

  /// Enters FLOOR_TRANSITION because positioning evidence drifted to another
  /// floor without a connector being approached, then completes immediately.
  void _beginOrganicFloorTransition(String newFloor) {
    debugPrint(
      '[NavigationController] Organic floor drift: $_currentNavigatingFloor -> $newFloor',
    );
    _expectedNextFloor = newFloor;
    _connectorInitiatedTransition = false;
    _transitionStartTime = _now();
    _lastIndoorPosition = _locationProvider.currentLocation;
    _transition(NavigationState.floorTransition);
    notifyListeners();
    _completeFloorTransition(newFloor);
  }

  void _completeFloorTransition(String newFloor) {
    debugPrint(
      '[NavigationController] Floor transition confirmed: $_currentNavigatingFloor -> $newFloor',
    );
    final previousFloor = _currentNavigatingFloor;
    _currentNavigatingFloor = newFloor;
    _expectedNextFloor = null;
    _exitConfirmationCounter = 0;
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = _now();
    _transitionStartTime = null;
    _lastIndoorPosition = null;

    // Sync the scope to the new floor
    final floors = _spaceScope.floors;
    final newFloorModel = floors.where((f) => f.floorNumber == newFloor).firstOrNull;
    if (newFloorModel != null && _spaceScope.selectedFloor?.floorNumber != newFloor) {
      _spaceScope.selectFloorForNavigation(newFloorModel);
    }

    // CONFIRMED: evidence-gated acceptance — the only stage that represents
    // physical-floor proof (ORIGINAL PHASE 5 invariant).
    _recordFloorTransitionEvent(FloorTransitionEvent(
      stage: FloorTransitionStage.confirmed,
      trigger: _connectorInitiatedTransition
          ? FloorTransitionTrigger.connectorProximity
          : FloorTransitionTrigger.evidence,
      fromFloor: previousFloor,
      toFloor: newFloor,
      timestamp: _now(),
    ));
    _connectorInitiatedTransition = false;

    if (_state == NavigationState.floorTransition) {
      _transition(NavigationState.activeIndoor);
    }
    // PHASE 8: a floor confirmation is also the retry point when indoor
    // guidance was unavailable during entry.
    _ensureIndoorGuidance();
    notifyListeners();
  }

  /// Checks if the floor transition has timed out and aborts if so.
  void _checkTransitionTimeout() {
    final startTime = _transitionStartTime;
    if (startTime == null) return;

    final elapsed = _now().difference(startTime);
    if (elapsed.inSeconds >= NavigationConfig.transitionTimeoutSeconds) {
      debugPrint(
        '[NavigationController] Floor transition timed out after ${elapsed.inSeconds}s — aborting',
      );
      // ABORTED: the dwell exceeded its timeout; evidence re-evaluates on
      // subsequent ticks (ORIGINAL PHASE 5 — stage visibility).
      _recordFloorTransitionEvent(FloorTransitionEvent(
        stage: FloorTransitionStage.aborted,
        trigger: FloorTransitionTrigger.timeout,
        fromFloor: _currentNavigatingFloor,
        toFloor: _expectedNextFloor,
        timestamp: _now(),
      ));
      // Abort transition; evidence re-evaluates on subsequent ticks (WiFi
      // engagement resumes indoors, GPS-outside flows into exit detection).
      _expectedNextFloor = null;
      _connectorInitiatedTransition = false;
      _transitionStartTime = null;
      _lastIndoorPosition = null;
      _newFloorEstimateCount = 0;
      _transition(NavigationState.activeIndoor);
      notifyListeners();
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Building Exit Detection
  // ──────────────────────────────────────────────────────────────

  /// Accumulates outside-building GPS confirmations while indoors and enters
  /// EXITING_BUILDING once confident. Confirmation completes in
  /// [_maintainDwell].
  void _checkBuildingExit(UserLocation location) {
    if (_state != NavigationState.activeIndoor) return;

    final source = _locationProvider.positionSource;
    final gpsLocation = _locationProvider.gpsLocation;

    // Require: indoor positioning lost, GPS available with good accuracy
    if (source == LocationSource.indoorWifi) {
      _exitConfirmationCounter = 0;
      return;
    }
    if (gpsLocation == null) {
      _exitConfirmationCounter = 0;
      return;
    }
    if (gpsLocation.accuracy > NavigationConfig.exitAccuracyThreshold) {
      _exitConfirmationCounter = 0;
      return;
    }

    // Check if GPS position is outside the building
    final isOutside = _isOutsideBuilding(gpsLocation);
    if (!isOutside) {
      _exitConfirmationCounter = 0;
      return;
    }

    _exitConfirmationCounter++;
    if (_exitConfirmationCounter >= NavigationConfig.exitConfirmationCount) {
      debugPrint('[NavigationController] Building exit detected');
      _transition(NavigationState.exitingBuilding);
    }
  }

  bool _isOutsideBuilding(UserLocation gpsLocation) {
    final floorplan = _spaceScope.activeFloorplan;
    if (floorplan != null && floorplan.hasValidBounds) {
      // Primary: check against floorplan bounds
      return !floorplan.bounds.contains(gpsLocation.latLng);
    }

    // Fallback: distance from building center
    final building = _spaceScope.selectedSpace;
    if (building != null) {
      final dist = Geolocator.distanceBetween(gpsLocation.latitude, gpsLocation.longitude, building.latitude, building.longitude);
      return dist > NavigationConfig.exitDistanceThreshold;
    }

    return false;
  }

  /// Side effects of a confirmed building exit. Must run BEFORE the state
  /// change clears selection-dependent context.
  void _applyBuildingExitSideEffects() {
    _currentNavigatingFloor = null;
    _expectedNextFloor = null;
    _connectorInitiatedTransition = false;
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;

    // Clear indoor floor selection — return to GPS-based tracking
    _spaceScope.releaseIndoorContextForNavigation();
  }

  // ──────────────────────────────────────────────────────────────
  // Building Entry Detection
  // ──────────────────────────────────────────────────────────────

  /// Called periodically during outdoor navigation to check if the user
  /// is approaching the destination building.
  void checkBuildingApproach(UserLocation location) {
    if (_state != NavigationState.activeOutdoor) return;

    final building = destinationSpace;
    if (building == null) return;

    final dist = Geolocator.distanceBetween(location.latitude, location.longitude, building.latitude, building.longitude);

    // Cancel preparation if the user moved away again.
    if (_buildingPreloaded &&
        dist > NavigationConfig.buildingPrepCancelThreshold) {
      debugPrint(
          '[NavigationController] Building approach cancelled — user moved away');
      _buildingPreloaded = false;
      return;
    }
    if (_buildingPreloaded) return; // already staged

    // Stage 1: Early preparation
    if (dist < NavigationConfig.buildingPrepThreshold) {
      _preLoadBuildingData(building);
    }
  }

  Future<void> _preLoadBuildingData(SpaceModel building) async {
    // Fencing pattern (Phase 1): identity is captured before any effect and
    // revalidated at the completion point.
    final session = _session;
    if (session == null) return;
    final sid = session.sessionId;
    final rev = session.routeRevision;

    debugPrint(
      '[NavigationController] Pre-loading building data for ${building.name} (${building.buid})',
    );
    _buildingPreloaded = true;

    // Auto-select the building — this triggers floor loading
    if (_spaceScope.selectedSpace?.buid != building.buid &&
        _isCurrent(sessionId: sid, revision: rev)) {
      _spaceScope.selectSpaceForNavigation(building);
    }
  }

  /// Checks if the user is close enough to a building entrance to enter the
  /// ENTERING_BUILDING dwell (awaiting positioning corroboration).
  void checkEntranceProximity(UserLocation location) {
    if (_state != NavigationState.activeOutdoor) return;
    if (!_buildingPreloaded) return;

    // Wait for ground floor POIs to be loaded
    if (!_spaceScope.hasPois) return;

    // Find nearest entrance POI
    final entrancePois = _spaceScope.pois
        .where((poi) =>
            poi.isBuildingEntrance ||
            poi.poisType.toLowerCase().contains('entrance'))
        .toList();
    if (entrancePois.isEmpty) {
      // Fallback: use building center proximity
      _checkFallbackEntranceProximity(location);
      return;
    }

    // Find nearest entrance by distance
    PoiModel? nearest;
    double minDist = double.infinity;
    for (final poi in entrancePois) {
      final dist = Geolocator.distanceBetween(location.latitude, location.longitude, poi.latitude, poi.longitude);
      if (dist < minDist) {
        minDist = dist;
        nearest = poi;
      }
    }

    // Stage 2: Building-entry dwell
    final threshold = NavigationConfig.entranceTransitionThreshold;
    if (minDist < threshold && nearest != null) {
      _triggerEntranceApproach();
    }
  }

  void _checkFallbackEntranceProximity(UserLocation location) {
    final building = destinationSpace;
    if (building == null) return;

    final dist = Geolocator.distanceBetween(location.latitude, location.longitude, building.latitude, building.longitude);
    if (dist < NavigationConfig.entranceFallbackThreshold) {
      _triggerEntranceApproach();
    }
  }

  /// Entrance reached: prepares residency context as ROUTE CONTEXT only and
  /// waits for positioning corroboration. Never claims the user is indoors.
  ///
  /// Preload floor choice (route context ONLY — never entry evidence):
  /// route-derived arrival floor → literal '0' → numerically lowest floor.
  /// A derived floor absent from the scope's floor list falls through.
  void _triggerEntranceApproach() {
    final cooldownUntil = _entryDwellCooldownUntil;
    if (cooldownUntil != null && _now().isBefore(cooldownUntil)) {
      debugPrint(
          '[NavigationController] Entrance dwell suppressed — re-trigger '
          'cooldown active');
      return;
    }

    debugPrint(
        '[NavigationController] Entrance reached — awaiting WiFi corroboration');

    final floors = _spaceScope.floors;
    FloorModel? preloadFloor;

    // Tier 1: the floor the active route actually enters the building on.
    final arrivalFloor = _routeArrivalFloor();
    if (arrivalFloor != null) {
      preloadFloor =
          floors.where((f) => f.floorNumber == arrivalFloor).firstOrNull;
    }

    // Tier 2: legacy ground-floor heuristic.
    // Tier 3: deterministic lowest numeric floor (replaces server-order).
    preloadFloor ??= floors.where((f) => f.floorNumber == '0').firstOrNull;
    preloadFloor ??= floors.isEmpty ? null : floors.reduce(
        (a, b) => a.numericFloor <= b.numericFloor ? a : b);

    if (preloadFloor != null) {
      // Fencing pattern (Phase 1): only a current session may drive
      // navigation-context floor selection.
      final session = _session;
      if (session != null &&
          _isCurrent(
              sessionId: session.sessionId,
              revision: session.routeRevision)) {
        _currentNavigatingFloor = preloadFloor.floorNumber;
        _spaceScope.selectFloorForNavigation(preloadFloor);
      }
    }

    _exitConfirmationCounter = 0;
    _transition(NavigationState.enteringBuilding);
    notifyListeners();

        // PHASE 8: indoor route refresh happens when corroboration completes —
    // see _ensureIndoorGuidance(), invoked from the ACTIVE_INDOOR entry
    // points.
  }

  /// The floor on which the active route enters its destination building,
  /// or null when the route carries no indoor information.
  ///
  /// ROUTE CONTEXT only. This value preloads floorplan/RadioMap residency
  /// and seeds bookkeeping; it must never be treated as positioning
  /// evidence of the user's physical floor.
  String? _routeArrivalFloor() {
    final route = _activeRoute;
    if (route == null) return null;

    if (route.hasSegments) {
      for (final seg in route.segments) {
        if (seg.type != RouteSegmentType.outdoorWalking &&
            seg.floorNumber != null &&
            seg.floorNumber!.isNotEmpty) {
          return seg.floorNumber;
        }
      }
    }

    for (final p in route.points) {
      if (!p.isOutdoor && p.floorNumber.isNotEmpty) {
        return p.floorNumber;
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Segment transition detection (cross-building navigation)
  // ──────────────────────────────────────────────────────────────

  /// Checks if the user has transitioned between route segments.
  void _checkSegmentTransition(UserLocation location) {
    if (_activeRoute == null || !_activeRoute!.hasSegments) return;
    if (_currentSegmentIndex >= _activeRoute!.segments.length) return;

    final currentSeg = _activeRoute!.segments[_currentSegmentIndex];
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
        '[NavigationController] Segment $_currentSegmentIndex complete '
        '(${currentSeg.type.name}), advancing to next',
      );
      _advanceToNextSegment();
    }
  }

  /// Advances to the next route segment.
  void _advanceToNextSegment() {
    if (_activeRoute == null || !_activeRoute!.hasSegments) return;

    final nextIdx = _currentSegmentIndex + 1;
    if (nextIdx >= _activeRoute!.segments.length) {
      _handleRouteExhaustion();
      return;
    }

    _currentSegmentIndex = nextIdx;
    final nextSeg = _activeRoute!.segments[_currentSegmentIndex];

    debugPrint(
      '[NavigationController] Now on segment $_currentSegmentIndex: '
      '${nextSeg.type.name} (${nextSeg.instruction ?? "no instruction"})',
    );

    // ROUTE-CONTEXT bookkeeping for regular segment starts only. Floor
    // changes proper (floorTransition segments) are owned exclusively by the
    // evidence-gated FLOOR_TRANSITION flow and are never claimed here.
    if (nextSeg.type != RouteSegmentType.floorTransition &&
        nextSeg.floorNumber != null &&
        nextSeg.buildingId != null) {
      _currentNavigatingFloor = nextSeg.floorNumber;
    }

    notifyListeners();
  }

  /// Pauses navigation (e.g., during GPS loss). Valid from any activity.
  void _pauseNavigation(String message) {
    if (_state == NavigationState.paused) return;
    _pauseReason = message;
    debugPrint('[NavigationController] Paused: $message');
    _transition(NavigationState.paused);
    notifyListeners();
  }

  /// Resumes navigation after GPS restore, returning to the interrupted
  /// activity.
  void _resumeFromPause() {
    if (_state != NavigationState.paused) return;
    final target = _previousActiveState;
    _pauseReason = null;
    debugPrint('[NavigationController] Resumed');
    if (target != null) {
      _transition(target);
    } else {
      _transition(NavigationState.idle);
    }
    notifyListeners();
  }

  /// PHASE 9 / BUG-15: segment exhaustion semantics.
  ///
  /// When the final segment completes NEAR the arrival anchor, arrival owns
  /// completion (normal path). Away from it the geometry can no longer guide:
  /// flag it visibly, keep the session alive, and leave rerouting available.
  void _handleRouteExhaustion() {
    debugPrint('[NavigationController] All segments complete');
    final location = _locationProvider.currentLocation;
    final anchor = _arrivalAnchor;
    if (anchor != null && location != null) {
      final dist = Geolocator.distanceBetween(location.latitude,
          location.longitude, anchor.latitude, anchor.longitude);
      if (dist < NavigationConfig.arrivalProximityThresholdMeters) {
        debugPrint('[NavigationController] Route exhausted within arrival '
            'radius — arrival owns completion');
        return;
      }
    }
    _routeIncomplete = true;
    debugPrint('[NavigationController] Route exhausted away from destination '
            '— flagged incomplete; session continues');
    notifyListeners();
  }

  /// Resets segment tracking when navigation stops.
  void _resetSegmentTracking() {
    _currentSegmentIndex = 0;
    _pauseReason = null;
  }

  // ──────────────────────────────────────────────────────────────
  // Arrival Detection (ORIGINAL PHASE 6)
  // ──────────────────────────────────────────────────────────────

  /// Resolves the arrival anchor for the current session: the destination
  /// POI when resolvable in the scope, otherwise the route's final point
  /// (always present and data-driven).
  void _resolveArrivalAnchor() {
    // PHASE 13: the anchor is stable per (sessionId, revision). Unrelated
    // POI-list churn cannot move it; only committed replacements re-resolve.
    final session = _session;
    if (session == null) {
      _arrivalAnchor = null;
      return;
    }
    if (_anchorSessionId == session.sessionId &&
        _anchorRevision == session.routeRevision &&
        _arrivalAnchor != null) {
      return;
    }

    final poi = _spaceScope.pois
        .where((p) => p.puid == destinationPuid)
        .firstOrNull;
    if (poi != null) {
      _arrivalAnchor = _ArrivalAnchor(
        latitude: poi.latitude,
        longitude: poi.longitude,
        buid: poi.buid,
        floorNumber: poi.floorNumber,
      );
    } else {
      final route = _activeRoute;
      final last = route?.hasPoints == true ? route!.points.last : null;
      if (last != null) {
        _arrivalAnchor = _ArrivalAnchor(
          latitude: last.latitude,
          longitude: last.longitude,
          buid: last.buid.isEmpty ? null : last.buid,
          floorNumber: last.floorNumber.isEmpty ? null : last.floorNumber,
        );
      } else {
        _arrivalAnchor = null;
      }
    }
    _anchorSessionId = session.sessionId;
    _anchorRevision = session.routeRevision;
  }

  /// PHASE 13 / INV-8: arrival is evidence, never coincidence.
  ///
  /// Indoors, proximity must additionally carry confirmed building+floor
  /// identity. Outdoors, BOTH confirming ticks must be decision-quality
  /// (fresh, good-band accuracy) — a poor/stale/held tick resets the
  /// counter exactly like an indoor identity mismatch does.
  ///
  /// Post-arrived policy (product choice): the machine STAYS in ARRIVED —
  /// the banner's Done terminates the session; there is NO auto-cleanup
  /// timer.
  void _checkArrival(UserLocation location) {
    if (_state != NavigationState.activeOutdoor &&
        _state != NavigationState.activeIndoor) {
      return;
    }
    final anchor = _arrivalAnchor;
    if (anchor == null) return;

    if (_state == NavigationState.activeIndoor) {
      final fix = _locationProvider.currentFix;
      final identityMatches = fix != null &&
          fix.hasScope &&
          fix.buildingId == anchor.buid &&
          fix.floor == anchor.floorNumber;
      if (!identityMatches) {
        _arrivalConfirmationCounter = 0;
        return;
      }
    } else {
      // Outdoor evidence-quality gate (Phase 5 flags).
      final fix = _locationProvider.currentFix;
      final qualifies = fix != null &&
          fix.source == PositionSource.gps &&
          fix.status == PositionFixStatus.fresh &&
          fix.accuracy <= NavigationConfig.gpsGoodAccuracyMeters;
      if (!qualifies) {
        _arrivalConfirmationCounter = 0;
        return;
      }
    }

    final dist = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      anchor.latitude,
      anchor.longitude,
    );
    if (dist >= NavigationConfig.arrivalProximityThresholdMeters) {
      _arrivalConfirmationCounter = 0;
      return;
    }

    _arrivalConfirmationCounter++;
    if (_arrivalConfirmationCounter >=
        NavigationConfig.arrivalConfirmationCount) {
      debugPrint('[NavigationController] Arrival confirmed at destination');
      _arrive();
    }
  }

  /// Shared arrival path for the evidence producer and the manual hook.
  void _arrive() {
    if (!_state.isActivity) return;
    _transition(NavigationState.arrived);
    notifyListeners();
  }

  /// PHASE 5: GPS quality is judged by the LocationProvider ingestion gate.
  /// PAUSED is entered once the degraded streak (poor/invalid/held fixes)
  /// reaches [NavigationConfig.gpsPausePoorTicks]; a single bad tick can
  /// never pause (INV-8 hysteresis).
  void _checkGpsLoss(UserLocation location) {
    if (!_state.isActivity) return;
    if (_locationProvider.gpsDegraded) {
      _pauseNavigation('GPS signal weak — waiting for better signal');
    }
  }

  /// Resumes from PAUSED once good-band GPS returns and the degraded streak
  /// has cleared.
  void _checkGpsRecovery(UserLocation location) {
    if (_state != NavigationState.paused) return;
    if (!_locationProvider.gpsDegraded &&
        location.accuracy <= NavigationConfig.gpsGoodAccuracyMeters) {
      _resumeFromPause();
    }
  }

  @override
  void dispose() {
    _locationProvider.removeListener(_onLocationChanged);
    super.dispose();
  }
}

/// Whether a dwell that started at [start] has exceeded [limitSeconds] as of
/// [now]. Pure decision function so the corroboration-timeout rules remain
/// unit-testable independently of the wall clock driving the live pipeline.
bool navigationDwellExpired(DateTime? start, DateTime now, int limitSeconds) {
  return start != null && now.difference(start).inSeconds >= limitSeconds;
}

/// Destination point the arrival detector measures against
/// (ORIGINAL PHASE 6).
///
/// Resolved once per session from the destination POI when available, else
/// from the route's final point. Identity fields gate indoor arrival:
/// proximity only confirms when confirmed positioning identity matches.
class _ArrivalAnchor {
  const _ArrivalAnchor({
    required this.latitude,
    required this.longitude,
    this.buid,
    this.floorNumber,
  });

  final double latitude;
  final double longitude;
  final String? buid;
  final String? floorNumber;
}
