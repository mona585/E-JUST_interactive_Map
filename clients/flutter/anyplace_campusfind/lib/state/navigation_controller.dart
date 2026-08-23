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
  String? _destinationPuid;
  SpaceModel? _destinationSpace;
  NavigationRouteModel? _activeRoute;
  bool _followMode = true;
  DateTime? _lastRerouteTime;

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

  // -- Arrival detection (ORIGINAL PHASE 6) --
  _ArrivalAnchor? _arrivalAnchor;
  int _arrivalConfirmationCounter = 0;

  // -- Segment tracking for cross-building navigation --
  int _currentSegmentIndex = 0;

  // -- Pause bookkeeping --
  String? _pauseReason;

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

  NavigationController({
    required NavigationRouteScope spaceProvider,
    required this._locationProvider,
    NavigationRepository? navigationRepository,
  })  : _spaceScope = spaceProvider,
        _navigationRepository =
            navigationRepository ?? AnyplaceNavigationRepository() {
    _locationProvider.addListener(_onLocationChanged);
    _spaceScope.addListener(_onSpaceProviderChanged);
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
        navigatingBuildingId: _destinationSpace?.buid,
        navigatingFloor: _currentNavigatingFloor,
        expectedNextFloor: _expectedNextFloor,
        pauseReason: _pauseReason,
        segmentIndex: _currentSegmentIndex,
        timestamp: DateTime.now(),
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
  String? get destinationPuid => _destinationPuid;
  SpaceModel? get destinationSpace => _destinationSpace;

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
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
    required String destinationFloorNumber,
  }) {
    if (_state != NavigationState.idle &&
        _state != NavigationState.routePreview) {
      return;
    }

    final route = _spaceScope.activeNavigationRoute;
    if (route == null || !route.hasRenderablePath) return;

    final wasIdle = _state == NavigationState.idle;

    _destinationPuid = destinationPuid;
    _destinationSpace = destinationSpace;
    _activeRoute = route;
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
    _resolveArrivalAnchor();

    if (wasIdle) {
      _transition(NavigationState.routePreview);
    }
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
    _exitConfirmationCounter = 0;
    _newFloorEstimateCount = 0;
    _arrivalConfirmationCounter = 0;

    final fix = _locationProvider.currentFix;
    if (fix?.source == PositionSource.wifi) {
      _transition(NavigationState.activeIndoor);
    } else {
      _transition(NavigationState.activeOutdoor);
    }
    notifyListeners();
  }

  /// Ends the session from ANY state (user action; bypasses the table).
  void endNavigation() {
    _state = NavigationState.idle;
    _previousActiveState = null;
    _destinationPuid = null;
    _destinationSpace = null;
    _activeRoute = null;
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
    notifyListeners();
  }

  /// Marks arrival at the destination.
  ///
  /// Manual hook kept test-visible; the ORIGINAL PHASE 6 evidence producer
  /// ([_checkArrival]) drives it in production through the same [_arrive]
  /// path.
  @visibleForTesting
  void markArrived() => _arrive();

  /// Test-only view of the residency-prep latch (ORIGINAL PHASE 4 —
  /// approach/cancel behavior has no other external signal).
  @visibleForTesting
  bool get buildingPreloadedForTest => _buildingPreloaded;

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
    _updateCustomRouteProgress(location);
    _checkDeviationAndReroute(location);
    _checkFloorTransition(location);
    _checkBuildingExit(location);
    checkBuildingApproach(location);
    checkEntranceProximity(location);
    _checkSegmentTransition(location);
    _checkArrival(location);
    _checkGpsLoss(location);
    notifyListeners();
  }

  void _onSpaceProviderChanged() {
    // Sync route if the scope's active route changed (e.g., reroute completed)
    final route = _spaceScope.activeNavigationRoute;
    if (route != null && route != _activeRoute && route.hasRenderablePath) {
      _activeRoute = route;
      // The destination anchor follows the adopted route (reroutes target
      // the same destination, but the endpoint coordinates may shift).
      if (_state.isSessionLive) {
        _resolveArrivalAnchor();
        notifyListeners();
      }
    }
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
    final destination = _destinationSpace;
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
      final elapsed = DateTime.now().difference(_lastRerouteTime!);
      if (elapsed.inSeconds < NavigationConfig.rerouteCooldownSeconds) return;
    }

    // Use custom route graph for deviation when outdoors and on a custom route
    if (_state == NavigationState.activeOutdoor &&
        _customRouteProgress != null &&
        !_customRouteProgress!.isOnRoute) {
      debugPrint(
        '[NavigationController] Off custom route '
        '(distance: ${_customRouteProgress!.distanceFromRoute.toStringAsFixed(1)}m) — rerouting',
      );
      _triggerReroute();
      return;
    }

    // Fallback: deviation against active route polyline
    final deviation = _computeMinDeviation(location.latLng, _activeRoute!);
    if (deviation > NavigationConfig.deviationThreshold) {
      _triggerReroute();
    }
  }

  /// Perpendicular distance from [point] to the nearest segment of [route]
  /// on the current navigating floor only.
  double _computeMinDeviation(LatLng point, NavigationRouteModel route) {
    final currentFloor = _currentNavigatingFloor;
    final points = currentFloor != null
        ? route.polylinePointsForFloor(currentFloor)
        : route.polylinePoints;
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
    if (_destinationPuid == null) return;

    final location = _locationProvider.currentLocation;
    if (location == null) return;

    final origin = _state;
    _lastRerouteTime = DateTime.now();
    if (!_transition(NavigationState.rerouting)) return;
    notifyListeners();

    // Step 1: Try custom KMZ routes first (outdoor only)
    if (origin == NavigationState.activeOutdoor) {
      final customRepo = _spaceScope.customRouteRepository;
      if (customRepo.isLoaded) {
        // Find destination from destination space
        final destSpace = _destinationSpace;
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
              snapThreshold: 100.0,
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
              if (_state.isSessionLive) {
                _activeRoute = customRoute;
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

    // Step 2: Fall back to API-based rerouting
    final currentFloor = _currentNavigatingFloor ?? '0';

    for (var attempt = 0; attempt < NavigationConfig.rerouteMaxRetries; attempt++) {
      try {
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: location.latitude,
          longitude: location.longitude,
          floorNumber: currentFloor,
          destinationPuid: _destinationPuid!,
        );
        if (route.hasRenderablePath) {
          // A user End during the await must not resurrect the session.
          if (_state.isSessionLive) {
            _activeRoute = route;
          }
          break;
        }
      } catch (e) {
        debugPrint('[NavigationController] Reroute attempt $attempt failed: $e');
        if (!_state.isSessionLive) break;
      }
      // Exponential backoff: 1s, 2s, 4s
      await Future.delayed(Duration(seconds: 1 << attempt));
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
      _spaceScope.selectFloor(targetFloor);
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
      _spaceScope.selectFloor(newFloorModel);
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
    _spaceScope.clearSelection();
  }

  // ──────────────────────────────────────────────────────────────
  // Building Entry Detection
  // ──────────────────────────────────────────────────────────────

  /// Called periodically during outdoor navigation to check if the user
  /// is approaching the destination building.
  void checkBuildingApproach(UserLocation location) {
    if (_state != NavigationState.activeOutdoor) return;

    final building = _destinationSpace;
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
    debugPrint(
      '[NavigationController] Pre-loading building data for ${building.name} (${building.buid})',
    );
    _buildingPreloaded = true;

    // Auto-select the building — this triggers floor loading
    if (_spaceScope.selectedSpace?.buid != building.buid) {
      _spaceScope.selectSpace(building);
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
    final building = _destinationSpace;
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
      _currentNavigatingFloor = preloadFloor.floorNumber;
      _spaceScope.selectFloor(preloadFloor);
    }

    _exitConfirmationCounter = 0;
    _transition(NavigationState.enteringBuilding);
    notifyListeners();

    // Indoor route refresh is deferred until corroboration completes.
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
        : 10.0; // 10m for regular segment endpoints

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
      debugPrint('[NavigationController] All segments complete — navigation finished');
      // Navigation complete
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
    final poi = _spaceScope.pois
        .where((p) => p.puid == _destinationPuid)
        .firstOrNull;
    if (poi != null) {
      _arrivalAnchor = _ArrivalAnchor(
        latitude: poi.latitude,
        longitude: poi.longitude,
        buid: poi.buid,
        floorNumber: poi.floorNumber,
      );
      return;
    }

    final route = _activeRoute;
    final last = route?.hasPoints == true ? route!.points.last : null;
    if (last != null) {
      _arrivalAnchor = _ArrivalAnchor(
        latitude: last.latitude,
        longitude: last.longitude,
        buid: last.buid.isEmpty ? null : last.buid,
        floorNumber: last.floorNumber.isEmpty ? null : last.floorNumber,
      );
      return;
    }
    _arrivalAnchor = null;
  }

  /// Arrival evidence producer: consecutive positioning ticks within the
  /// destination radius confirm arrival. Indoors, proximity alone is never
  /// proof — the fix must carry canonically confirmed identity matching the
  /// destination building and floor.
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

  /// Checks for GPS signal loss and pauses navigation.
  void _checkGpsLoss(UserLocation location) {
    if (!_state.isActivity) return;

    // If GPS accuracy is very poor (>100m), consider it lost
    if (location.accuracy > 100) {
      _pauseNavigation('GPS signal weak — waiting for better signal');
    }
  }

  /// Resumes from PAUSED once usable GPS returns.
  void _checkGpsRecovery(UserLocation location) {
    if (_state != NavigationState.paused) return;
    if (location.accuracy <= 100) {
      _resumeFromPause();
    }
  }

  @override
  void dispose() {
    _locationProvider.removeListener(_onLocationChanged);
    _spaceScope.removeListener(_onSpaceProviderChanged);
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
