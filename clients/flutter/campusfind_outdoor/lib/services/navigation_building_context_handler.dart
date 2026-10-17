import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/navigation_config.dart';
import '../models/floor_model.dart';
import '../models/navigation_state.dart';
import '../models/poi_model.dart';
import '../models/position_fix.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import 'navigation_event_log.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_scope.dart';
import 'navigation_state_machine.dart';

/// Whether a dwell that started at [start] has exceeded [limitSeconds] as of
/// [now]. Pure decision function so the corroboration-timeout rules remain
/// unit-testable independently of the wall clock driving the live pipeline.
bool navigationDwellExpired(DateTime? start, DateTime now, int limitSeconds) {
  return start != null && now.difference(start).inSeconds >= limitSeconds;
}

/// Building-entry/exit ownership extracted from [NavigationPilot].
///
/// Owns the handoff pipeline into and out of a building: Wi-Fi belief flips,
/// the ENTERING/EXITING corroboration dwell against the machine's dwell
/// arm, entrance proximity with its preload policy, and the residency
/// pre-build. Exit/entrance reach into the floor handler through injected
/// callbacks so floor bookkeeping stays owned by that handler.
class NavigationBuildingContextHandler {
  NavigationBuildingContextHandler({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
    required NavigationEventLog navEvent,
    required SpaceModel? Function() destinationSpace,
    required NavigationSession? Function() session,
    required bool Function(String sessionId, int revision) isCurrent,
    required void Function(FloorModel floor) onPreloadFloor,
    required void Function() onReleaseIndoorForExit,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _destinationSpace = destinationSpace,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _session = session,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _isCurrent = isCurrent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onPreloadFloor = onPreloadFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onReleaseIndoorForExit = onReleaseIndoorForExit;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;
  final NavigationEventLog _navEvent;
  final SpaceModel? Function() _destinationSpace;
  final NavigationSession? Function() _session;
  final bool Function(String sessionId, int revision) _isCurrent;
  final void Function(FloorModel floor) _onPreloadFloor;
  final void Function() _onReleaseIndoorForExit;

  // Building-entry/exit bookkeeping
  bool _buildingPreloaded = false;
  int _exitConfirmationCounter = 0;
  DateTime? _entryDwellCooldownUntil;

  bool get buildingPreloaded => _buildingPreloaded;

  /// Resets the building-exit confirmation streak (used when the user
  /// re-enters follow mode).
  void resetExitConfirmation() {
    _exitConfirmationCounter = 0;
  }

  /// Evidence-based outdoor → building-entry trigger: positioning believing
  /// Wi-Fi while we are navigating outdoors means the user walked into a
  /// covered area. Destination selection can never cause this.
  void checkBeliefFlip(PositionFix? fix) {
    if (_machine.state != NavigationState.activeOutdoor) return;
    if (fix?.source != PositionSource.wifi) return;
    _navEvent.navEvent('HANDOFF_ENTER_START', detail: 'belief-flip');
    debugPrint(
      '[NavigationViewModel] WiFi belief outdoors — entering building flow',
    );
    _machine.transition(NavigationState.enteringBuilding);
  }

  /// Maintains ENTERING_BUILDING / EXITING_BUILDING dwell states: resolves
  /// them on corroborating evidence or times them out safely.
  void maintainDwell(PositionFix? fix, UserLocation location) {
    switch (_machine.state) {
      case NavigationState.enteringBuilding:
        if (fix != null &&
            fix.source == PositionSource.wifi &&
            _entryCorroborated(fix)) {
          debugPrint(
            '[NavigationViewModel] Building entry corroborated by WiFi',
          );
          _entryDwellCooldownUntil = null;
          _navEvent.navEvent(
            'HANDOFF_ENTER_CONFIRM',
            detail: 'corroborated',
            force: true,
          );
          _machine.transition(NavigationState.activeIndoor);
          return;
        }
        if (navigationDwellExpired(
          _machine.dwellStart,
          _port.now(),
          NavigationConfig.enteringCorroborationTimeoutSeconds,
        )) {
          _navEvent.navEvent('HANDOFF_ENTER_TIMEOUT', detail: 'reverting outdoors');
          debugPrint(
            '[NavigationViewModel] Entry not corroborated within '
            '${NavigationConfig.enteringCorroborationTimeoutSeconds}s — '
            'back to outdoor',
          );
          _entryDwellCooldownUntil = _port.now().add(
            const Duration(
              seconds: NavigationConfig.entryRetriggerCooldownSeconds,
            ),
          );
          _machine.transition(NavigationState.activeOutdoor);
        }
        break;
      case NavigationState.exitingBuilding:
        if (fix?.source == PositionSource.wifi) {
          debugPrint(
            '[NavigationViewModel] WiFi re-engaged during exit — staying indoors',
          );
          _machine.transition(NavigationState.activeIndoor);
          return;
        }
        if (navigationDwellExpired(
          _machine.dwellStart,
          _port.now(),
          NavigationConfig.exitingCorroborationTimeoutSeconds,
        )) {
          _navEvent.navEvent(
            'HANDOFF_EXIT_TIMEOUT',
            detail: 'exit unconfirmed — remaining outdoors',
          );
          debugPrint(
            '[NavigationViewModel] Exit not confirmed within '
            '${NavigationConfig.exitingCorroborationTimeoutSeconds}s — '
            'remaining outdoors',
          );
          _machine.transition(NavigationState.activeOutdoor);
          return;
        }
        if (location.accuracy <= NavigationConfig.exitAccuracyThreshold &&
            _isOutsideBuilding(location)) {
          _navEvent.navEvent('HANDOFF_EXIT_CONFIRM', force: true);
          debugPrint('[NavigationViewModel] Building exit confirmed');
          applyBuildingExitSideEffects();
          _machine.transition(NavigationState.activeOutdoor);
        }
        break;
      default:
        break;
    }
  }

  /// Identity rule for entry corroboration: the corroborating Wi-Fi fix must
  /// carry canonically confirmed scope matching the destination building.
  bool _entryCorroborated(PositionFix fix) {
    final destination = _destinationSpace();
    if (destination == null) return true;
    if (!fix.hasScope) return false;
    return fix.buildingId == destination.buid;
  }

  /// Accumulates outside-building GPS confirmations while indoors and enters
  /// EXITING_BUILDING once confident. Confirmation completes in
  /// [maintainDwell].
  void checkBuildingExit(UserLocation location) {
    if (_machine.state != NavigationState.activeIndoor) return;

    final gpsLocation = _port.gpsLocation;

    // Require: indoor positioning lost, GPS available with good accuracy
    if (_port.isIndoorWifiActive) {
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
      debugPrint('[NavigationViewModel] Building exit detected');
      _machine.transition(NavigationState.exitingBuilding);
    }
  }

  /// Whether [gpsLocation] is physically outside the building currently being
  /// navigated. EXIT detection deliberately tolerates missing/imperfect
  /// geometry: it checks the active floorplan's real bounds first, then falls
  /// back to the distance-from-building-center threshold.
  bool _isOutsideBuilding(UserLocation gpsLocation) {
    final floorplan = _scope.activeFloorplan;
    if (floorplan != null && floorplan.hasValidBounds) {
      // Primary: check against floorplan bounds
      return !floorplan.bounds.contains(gpsLocation.latLng);
    }

    // Fallback: distance from building center
    final building = _scope.selectedSpace;
    if (building != null) {
      final dist = Geolocator.distanceBetween(
        gpsLocation.latitude,
        gpsLocation.longitude,
        building.latitude,
        building.longitude,
      );
      return dist > NavigationConfig.exitDistanceThreshold;
    }
    return false;
  }

  /// Side effects of a confirmed building exit. Must run BEFORE the state
  /// change clears selection-dependent context.
  void applyBuildingExitSideEffects() {
    _onReleaseIndoorForExit();
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;

    // Clear indoor floor selection — return to GPS-based tracking
    _scope.releaseIndoorContextForNavigation();
  }

  /// Called periodically during outdoor navigation to check if the user
  /// is approaching the destination building.
  void checkBuildingApproach(UserLocation location) {
    if (_machine.state != NavigationState.activeOutdoor) return;

    final building = _destinationSpace();
    if (building == null) return;

    final dist = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      building.latitude,
      building.longitude,
    );

    // Cancel preparation if the user moved away again.
    if (_buildingPreloaded &&
        dist > NavigationConfig.buildingPrepCancelThreshold) {
      debugPrint(
        '[NavigationViewModel] Building approach cancelled — user moved away',
      );
      _buildingPreloaded = false;
      return;
    }
    if (_buildingPreloaded) return; // already staged

    // Stage 1: Early preparation
    if (dist < NavigationConfig.buildingPrepThreshold) {
      preLoadBuildingData(building);
    }
  }

  Future<void> preLoadBuildingData(SpaceModel building) async {
    // Fencing pattern (Phase 1): identity is captured before any effect and
    // revalidated at the completion point.
    final session = _session();
    if (session == null) return;
    final sid = session.sessionId;
    final rev = session.routeRevision;

    debugPrint(
      '[NavigationViewModel] Pre-loading building data for ${building.name} (${building.buid})',
    );
    _buildingPreloaded = true;

    // Auto-select the building — this triggers floor loading
if (_scope.selectedSpace?.buid != building.buid &&
        _isCurrent(sid, rev)) {
      _scope.selectSpaceForNavigation(building);
    }
  }

  /// Checks if the user is close enough to a building entrance to enter the
  /// ENTERING_BUILDING dwell (awaiting positioning corroboration).
  void checkEntranceProximity(UserLocation location) {
    if (_machine.state != NavigationState.activeOutdoor) return;
    if (!_buildingPreloaded) return;

    // Wait for ground floor POIs to be loaded
    if (!_scope.hasPois) return;

    // Find nearest entrance POI
    final entrancePois = _scope.pois
        .where(
          (poi) =>
              poi.isBuildingEntrance ||
              poi.poisType.toLowerCase().contains('entrance'),
        )
        .toList();
    if (entrancePois.isEmpty) {
      // Fallback: use building center proximity
      checkFallbackEntranceProximity(location);
      return;
    }

    // Find nearest entrance by distance
    PoiModel? nearest;
    double minDist = double.infinity;
    for (final poi in entrancePois) {
      final dist = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        poi.latitude,
        poi.longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        nearest = poi;
      }
    }

    // Stage 2: Building-entry dwell
    final threshold = NavigationConfig.entranceTransitionThreshold;
    if (minDist < threshold && nearest != null) {
      triggerEntranceApproach();
    }
  }

  void checkFallbackEntranceProximity(UserLocation location) {
    final building = _destinationSpace();
    if (building == null) return;

    final dist = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      building.latitude,
      building.longitude,
    );
    if (dist < NavigationConfig.entranceFallbackThreshold) {
      triggerEntranceApproach();
    }
  }

  /// Entrance reached: prepares residency context as ROUTE CONTEXT only and
  /// waits for positioning corroboration. Never claims the user is indoors.
  void triggerEntranceApproach() {
    final cooldownUntil = _entryDwellCooldownUntil;
    if (cooldownUntil != null && _port.now().isBefore(cooldownUntil)) {
      debugPrint(
        '[NavigationViewModel] Entrance dwell suppressed — re-trigger '
        'cooldown active',
      );
      return;
    }

    debugPrint(
      '[NavigationViewModel] Entrance reached — awaiting WiFi corroboration',
    );

    final floors = _scope.floors;
    FloorModel? preloadFloor;

    // Tier 1: the floor the active route actually enters the building on.
    final arrivalFloor = _routeArrivalFloor();
    if (arrivalFloor != null) {
      preloadFloor = floors
          .where((f) => f.floorNumber == arrivalFloor)
          .firstOrNull;
    }

    // Tier 2: legacy ground-floor heuristic.
    // Tier 3: deterministic lowest numeric floor (replaces server-order).
    preloadFloor ??= floors.where((f) => f.floorNumber == '0').firstOrNull;
    preloadFloor ??= floors.isEmpty
        ? null
        : floors.reduce((a, b) => a.numericFloor <= b.numericFloor ? a : b);

    if (preloadFloor != null) {
      // Fencing pattern (Phase 1): only a current session may drive
      // navigation-context floor selection.
      final session = _session();
      if (session != null && _isCurrent(session.sessionId, session.routeRevision)) {
        _onPreloadFloor(preloadFloor);
      }
    }

    _exitConfirmationCounter = 0;
    _navEvent.navEvent('HANDOFF_ENTER_START', detail: 'entrance-proximity');
    _machine.transition(NavigationState.enteringBuilding);
    _port.notifyChanged();
  }

  /// The floor on which the active route enters its destination building,
  /// or null when the route carries no indoor information.
  String? _routeArrivalFloor() {
    final route = _scope.activeNavigationRoute;
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

  void resetForPreviewSeed() {
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    _entryDwellCooldownUntil = null;
  }

  void resetForStartActive() {
    _exitConfirmationCounter = 0;
  }

  void resetForEnd() {
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    _entryDwellCooldownUntil = null;
  }

  void resetForRetarget() {
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    _entryDwellCooldownUntil = null;
  }
}
