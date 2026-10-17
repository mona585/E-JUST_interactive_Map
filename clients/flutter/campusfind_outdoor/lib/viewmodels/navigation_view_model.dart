import 'package:flutter/foundation.dart';

import '../models/floor_transition_event.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/position_estimate.dart';
import '../models/position_fix.dart';
import '../models/route_progress.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import '../repositories/navigation_repository.dart';
import '../services/navigation_pilot.dart';
import '../models/navigation_state.dart';
import '../services/navigation_route_scope.dart';
import 'location_view_model.dart';

export '../services/navigation_building_context_handler.dart'
    show navigationDwellExpired;
export '../models/navigation_state.dart' show NavigationSubState;

/// Legacy top-level navigation phase.
///
/// Retained for compatibility with existing consumers; derived from the
/// canonical [NavigationState] machine via [NavigationViewModel.phase].
enum NavigationPhase { idle, preview, active }

/// Thin presentation facade over [NavigationPilot].
///
/// The pilot owns every navigation decision and all session bookkeeping;
/// this view model subscribes to positioning evidence, forwards UI commands,
/// and exposes the pilot's canonical state plus the follow-mode camera
/// preference to the widget tree.
class NavigationViewModel extends ChangeNotifier
    implements NavigationPilotPort {
  NavigationViewModel({
    required NavigationRouteScope spaceProvider,
    required LocationViewModel locationProvider,
    NavigationRepository? navigationRepository,
  }) {
    _locationProvider = locationProvider;
    _pilot = NavigationPilot(
      scope: spaceProvider,
      navigationRepository:
          navigationRepository ?? AnyplaceNavigationRepository(),
      port: this,
    );
    _locationProvider.addListener(_onLocationChanged);
  }

  late final LocationViewModel _locationProvider;
  late final NavigationPilot _pilot;

  bool _followMode = true;

  /// Test-only clock override for dwell-timeout and cooldown decisions.
  ///
  /// Widget tests run under a fake async zone where [DateTime.now()] does
  /// not advance with pumped durations; injecting a controllable clock
  /// keeps the timeout rules exercisable without changing production
  /// behavior (null override = wall clock). Forwarded to the pilot through
  /// [NavigationPilotPort.now].
  @visibleForTesting
  DateTime Function()? debugNowOverride;

  void _onLocationChanged() => _pilot.evaluateUserLocation();

  // ──────────────────────────────────────────────────────────────
  // NavigationPilotPort implementation
  // ──────────────────────────────────────────────────────────────

  @override
  PositionFix? get currentFix => _locationProvider.currentFix;

  @override
  UserLocation? get currentLocation => _locationProvider.currentLocation;

  @override
  UserLocation? get gpsLocation => _locationProvider.gpsLocation;

  @override
  PositionEstimate? get latestIndoorEstimate =>
      _locationProvider.latestIndoorEstimate;

  @override
  bool get hasGpsFix => _locationProvider.positionSource == LocationSource.gps;

  @override
  bool get isIndoorWifiActive => _locationProvider.isIndoorWifiActive;

  @override
  bool get gpsDegraded => _locationProvider.gpsDegraded;

  @override
  DateTime now() => debugNowOverride?.call() ?? DateTime.now();

  @override
  void notifyChanged() => notifyListeners();

  // ──────────────────────────────────────────────────────────────
  // Canonical state surface (delegated to the pilot)
  // ──────────────────────────────────────────────────────────────

  /// Current canonical navigation state.
  NavigationState get navigationState => _pilot.state;

  /// Immutable snapshot of the whole machine for observers that need a
  /// consistent multi-field read.
  NavigationSnapshot get snapshot => _pilot.snapshot;

  /// Legacy phase projection of the canonical state.
  NavigationPhase get phase {
    switch (_pilot.state) {
      case NavigationState.idle:
        return NavigationPhase.idle;
      case NavigationState.routePreview:
        return NavigationPhase.preview;
      default:
        return NavigationPhase.active;
    }
  }

  NavigationSubState get subState => _pilot.subState;

  bool get followMode => _followMode;

  /// A live session covers activities and overlays but not preview/idle —
  /// identical semantics to the legacy "phase == active" check.
  bool get isActive => _pilot.isActive;
  bool get isPreview => _pilot.isPreview;
  NavigationRouteModel? get activeRoute => _pilot.activeRoute;
  String? get currentNavigatingFloor => _pilot.currentNavigatingFloor;
  bool get isTransitioningFloors => _pilot.isTransitioningFloors;
  bool get isRerouting => _pilot.isRerouting;
  bool get isArrived => _pilot.isArrived;

  /// Identity of the live navigation session, or null when no session exists.
  String? get sessionId => _pilot.sessionId;

  /// Destination identity lives on the session; these getters are delegates
  /// so existing consumers stay source-compatible.
  String? get destinationPuid => _pilot.destinationPuid;
  SpaceModel? get destinationSpace => _pilot.destinationSpace;

  // Segment navigation getters
  int get currentSegmentIndex => _pilot.currentSegmentIndex;
  bool get isPaused => _pilot.isPaused;
  String? get pauseMessage => _pilot.pauseMessage;
  bool get isPartialRoute => _pilot.isPartialRoute;

  // Custom route navigation getters
  RouteProgress? get customRouteProgress => _pilot.customRouteProgress;
  bool get isOnCustomRoute => _pilot.isOnCustomRoute;

  /// The current segment being navigated, or null if not started.
  RouteSegment? get currentSegment => _pilot.currentSegment;

  /// The next segment after the current one, or null.
  RouteSegment? get nextSegment => _pilot.nextSegment;

  /// Total number of segments in the current route.
  int get totalSegments => _pilot.totalSegments;

  /// User-friendly positioning status message.
  String get positioningStatus => _pilot.positioningStatus;

  /// Position to render during a floor transition (held position), or the
  /// current location otherwise.
  UserLocation? get heldPositionDuringTransition =>
      _pilot.heldPositionDuringTransition;

  /// Floor-transition lifecycle events for the current session, oldest first.
  List<FloorTransitionEvent> get floorTransitionEvents =>
      _pilot.floorTransitionEvents;

  /// Most recent floor-transition event, or null before any transition.
  FloorTransitionEvent? get lastFloorTransitionEvent =>
      _pilot.lastFloorTransitionEvent;

  bool get rerouteFailed => _pilot.rerouteFailed;
  bool get routeIncomplete => _pilot.routeIncomplete;

  // ──────────────────────────────────────────────────────────────
  // Commands
  // ──────────────────────────────────────────────────────────────

  /// Starts route preview mode after the user taps "Route Here".
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
  }) => _pilot.startRoutePreview(
    destinationPuid: destinationPuid,
    destinationSpace: destinationSpace,
  );

  /// Transitions from preview to active navigation when the user taps
  /// "Start Directions".
  void startActiveNavigation() {
    _followMode = true;
    _pilot.startActiveNavigation();
  }

  /// Ends the session from ANY state (user action; bypasses the table).
  void endNavigation() {
    _followMode = true;
    _pilot.endNavigation();
  }

  /// Canonical teardown (MASTER PLAN PHASE 15, INV-10).
  void terminateNavigation() => _pilot.terminateNavigation();

  /// Marks arrival at the destination.
  @visibleForTesting
  void markArrived() => _pilot.markArrived();

  /// Explicit destination-change protocol (MASTER PLAN PHASE 4).
  Future<bool> retargetDestination(PoiModel newTarget) =>
      _pilot.retargetDestination(newTarget);

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
    _pilot.resetExitConfirmation();
    notifyListeners();
  }

  // ──────────────────────────────────────────────────────────────
  // Test-only surface
  // ──────────────────────────────────────────────────────────────

  /// Test-only view of the residency-prep latch (ORIGINAL PHASE 4).
  @visibleForTesting
  bool get buildingPreloadedForTest => _pilot.buildingPreloadedForTest;

  /// Test-only view of the live session (Phase 1).
  @visibleForTesting
  NavigationSession? get sessionForTest => _pilot.sessionForTest;

  /// Test-only view of the reroute cooldown stamp (Phase 1).
  @visibleForTesting
  DateTime? get lastRerouteTimeForTest => _pilot.lastRerouteTimeForTest;

  /// Test-only direct entry into the reroute flow (Phase 1).
  @visibleForTesting
  Future<void> debugTriggerReroute() => _pilot.debugTriggerReroute();

  /// Test-only revision bump (Phase 1).
  @visibleForTesting
  void debugBumpRouteRevision() => _pilot.debugBumpRouteRevision();

  /// Test-only anchor suppression (Phase 9).
  @visibleForTesting
  void debugClearArrivalAnchorForTest() =>
      _pilot.debugClearArrivalAnchorForTest();

  /// Test-only identity view of the resolved arrival anchor (Phase 13).
  @visibleForTesting
  Object? get arrivalAnchorForTest => _pilot.arrivalAnchorForTest;

  @override
  void dispose() {
    _locationProvider.removeListener(_onLocationChanged);
    super.dispose();
  }
}