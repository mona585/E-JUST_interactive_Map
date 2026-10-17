import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/campus_asset_status.dart';
import '../models/campus_gate.dart';
import '../models/floor_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import '../repositories/cross_building_router.dart';
import '../services/cache_service.dart';
import 'campus_route_assets.dart';

/// Owns every navigation-route REQUEST against the backend: the
/// POI/building/gate routing, outdoor-only composition, retargeting,
/// request-id fencing/deduplication, and the route store itself (status,
/// active route, error, destination puid).
///
/// OUTDOOR-ONLY: every request resolves to an outdoor walking route (campus
/// road graph / OSRM). No indoor routing service is ever consulted. When the
/// user's GPS fix lies inside a building footprint, the composed route starts
/// at that building's outdoor-accessible entrance
/// (see [CrossBuildingRouter.composeRoute]); it never draws an interior leg.
///
/// Extracted from [SpaceViewModel]. The coordinator holds NO selection or
/// browsing-asset state; selection semantics stay in the view model and are
/// driven here exclusively through the injected [selectSpaceForNavigation] /
/// [selectFloorForNavigation] / [setDestinationPoi] / loader callbacks. All
/// notifications fan out through [notify], wired to the view model's
/// [ChangeNotifier].
class CampusRouteCoordinator {
  CampusRouteCoordinator({
    required CampusRoutingAssets assets,
    required void Function() notify,
    CacheService? cacheService,
    required List<SpaceModel> Function() spaces,
    required List<FloorModel> Function() floors,
    required PoiModel? Function() selectedPoi,
    required UserLocation? Function() currentLocation,
    required void Function(PoiModel target) setDestinationPoi,
    required void Function(SpaceModel space) selectSpaceForNavigation,
    required void Function(FloorModel floor) selectFloorForNavigation,
    required Future<void> Function() loadFloors,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _assets = assets,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _notify = notify,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _cacheService = cacheService,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _spaces = spaces,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _floors = floors,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedPoi = selectedPoi,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _currentLocation = currentLocation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _setDestinationPoi = setDestinationPoi,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectSpaceForNavigation = selectSpaceForNavigation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectFloorForNavigation = selectFloorForNavigation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _loadFloors = loadFloors;

  final CampusRoutingAssets _assets;
  final void Function() _notify;
  final CacheService? _cacheService;
  final List<SpaceModel> Function() _spaces;
  final List<FloorModel> Function() _floors;
  final PoiModel? Function() _selectedPoi;
  final UserLocation? Function() _currentLocation;
  final void Function(PoiModel target) _setDestinationPoi;
  final void Function(SpaceModel space) _selectSpaceForNavigation;
  final void Function(FloorModel floor) _selectFloorForNavigation;
  final Future<void> Function() _loadFloors;

  // Navigation Route State
  NavigationRouteStatus _navigationRouteStatus = NavigationRouteStatus.idle;
  NavigationRouteModel? _activeNavigationRoute;
  String? _navigationRouteErrorMessage;
  String? _navigationDestinationPuid;
  int _navigationRouteRequestId = 0;

  NavigationRouteStatus get navigationRouteStatus => _navigationRouteStatus;
  NavigationRouteModel? get activeNavigationRoute => _activeNavigationRoute;
  String? get navigationRouteErrorMessage => _navigationRouteErrorMessage;
  String? get navigationDestinationPuid => _navigationDestinationPuid;
  bool get isLoadingNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.loading;
  bool get hasActiveNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.ready &&
      _activeNavigationRoute != null &&
      _activeNavigationRoute!.hasRenderablePath;
  bool get isNavigationRouteUnsupported =>
      _navigationRouteStatus == NavigationRouteStatus.unsupported;

  /// Whether the currently stored route is a navigable-with-warning PARTIAL
  /// route (D6). The model's [RouteModelStatus.partial] is the single source of
  /// truth; this getter only reflects it — it never encodes the warning in the
  /// error field.
  bool get isNavigationRoutePartial =>
      _navigationRouteStatus == NavigationRouteStatus.ready &&
      (_activeNavigationRoute?.isPartial ?? false);

  /// The partial-route warning for the currently stored route, if any (D6).
  /// Distinct from [navigationRouteErrorMessage], which is reserved for
  /// request failures.
  String? get navigationRouteWarning =>
      _activeNavigationRoute?.partialRouteWarning;

  /// Status-field reset only (selection/browsing flows and route teardown).
  void resetRouteState() {
    _navigationRouteStatus = NavigationRouteStatus.idle;
    _activeNavigationRoute = null;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
  }

  /// Idempotent teardown of the route store (used by canonical termination
  /// and the browsing clear-route action).
  void clearNavigationRoute() {
    if (_navigationRouteStatus != NavigationRouteStatus.idle ||
        _activeNavigationRoute != null ||
        _navigationRouteErrorMessage != null) {
      _navigationRouteRequestId++;
      resetRouteState();
      _notify();
    }
  }

  /// Session write-through (MASTER PLAN PHASE 2, INV-1/2/6).
  ///
  /// The single route store is replaced atomically for observers: one field
  /// assignment, status ready, error cleared, ONE notification. Browsing
  /// state (radiomap/floorplan/POIs) and destination bookkeeping are never
  /// touched here — during a live session only the navigation controller
  /// calls this.
  void adoptNavigatedRoute(NavigationRouteModel route) {
    debugPrint('[SpaceViewModel] adoptNavigatedRoute (session write-through)');
    _activeNavigationRoute = route;
    _navigationRouteStatus = NavigationRouteStatus.ready;
    _navigationRouteErrorMessage = null;
    _notify();
  }

  /// Clears the navigation route-level error message.
  void clearNavigationRouteError() {
    if (_navigationRouteErrorMessage != null) {
      _navigationRouteErrorMessage = null;
      _notify();
    }
  }

  /// Opens a new route request: bumps the fence, sets loading, and records
  /// the destination. Returns the request id for later freshness checks.
  int startRouteRequest(String? destinationPuid) {
    final requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = destinationPuid;
    _notify();
    return requestId;
  }

  /// Whether [requestId] is still the newest route request.
  bool isCurrentRouteRequest(int requestId) =>
      requestId == _navigationRouteRequestId;

  /// Requests an OUTDOOR navigation route from the current position to the
  /// selected POI.
  ///
  /// The route terminates at the destination building's outdoor-accessible
  /// entrance (or directly at the POI when its building is unknown). When the
  /// user's GPS fix lies inside a building footprint, the route starts at that
  /// building's nearest outdoor entrance (D2). A clear failure is surfaced —
  /// never a fabricated interior leg — when no honest outdoor route exists.
  Future<void> requestRouteToSelectedPoi({LatLng? originOverride}) async {
    final poi = _selectedPoi();
    final origin = originOverride ?? _currentLocation()?.latLng;

    if (poi == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage = 'Select a POI first.';
      _notify();
      return;
    }

    if (origin == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return;
    }

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = poi.puid;
    _notify();

    // Save to recent waypoints
    _cacheService?.addRecentWaypoint(poi.puid);

    final targetSpace = _spaces().where((s) => s.buid == poi.buid).firstOrNull;

    if (targetSpace != null) {
      debugPrint(
        '[SpaceViewModel] POI outdoor route: '
        '${poi.name} in ${targetSpace.name}',
      );
      try {
        final route = await _assets.crossBuildingRouter.composeRoute(
          userLocation: origin,
          targetSpace: targetSpace,
          allBuildings: _spaces(),
        );
        if (requestId != _navigationRouteRequestId ||
            _selectedPoi()?.puid != poi.puid) {
          return;
        }
        _adoptComposedRoute(route);
        return;
      } on OutdoorRouteException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        _navigationRouteStatus = NavigationRouteStatus.error;
        _activeNavigationRoute = null;
        _navigationRouteErrorMessage = e.message;
        _notify();
        return;
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint(
          '[SpaceViewModel] outdoor compose failed — direct outdoor path: $e',
        );
        // Fall through to the guaranteed outdoor planner cascade.
      }
    }

    if (requestId != _navigationRouteRequestId) return;
    final route = await _buildDirectOutdoorRoute(
      from: origin,
      to: poi.latLng,
    );
    if (requestId != _navigationRouteRequestId ||
        _selectedPoi()?.puid != poi.puid) {
      return;
    }
    _adoptComposedRoute(route);
  }

  /// Requests an OUTDOOR route to [targetSpace] from the user's current
  /// location, or from [originOverride] when a custom start point (a building
  /// the user picked) was chosen.
  ///
  /// The route terminates at the building's outdoor-accessible entrance;
  /// originating inside a footprint starts the route at that building's
  /// nearest entrance the same way. A clear failure is surfaced when no honest
  /// outdoor route exists.
  Future<void> requestRouteToBuilding(
    SpaceModel targetSpace, {
    LatLng? originOverride,
  }) async {
    final origin = originOverride ?? _currentLocation()?.latLng;

    if (origin == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return;
    }

    debugPrint(
      '[SpaceViewModel] requestRouteToBuilding: ${targetSpace.name} '
      '(buid: ${targetSpace.buid}, origin: ${origin.latitude},${origin.longitude})',
    );

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
    _notify();

    try {
      final route = await _assets.crossBuildingRouter.composeRoute(
        userLocation: origin,
        targetSpace: targetSpace,
        allBuildings: _spaces(),
      );
      if (requestId != _navigationRouteRequestId) return;
      _adoptComposedRoute(route);
      return;
    } on OutdoorRouteException catch (e) {
      if (requestId != _navigationRouteRequestId) return;
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = e.message;
      _notify();
      return;
    } catch (e) {
      if (requestId != _navigationRouteRequestId) return;
      debugPrint(
        '[SpaceViewModel] requestRouteToBuilding compose failed — '
        'direct outdoor path: $e',
      );
      // Fall through to the guaranteed outdoor planner cascade.
    }

    if (requestId != _navigationRouteRequestId) return;
    final route = await _buildDirectOutdoorRoute(
      from: origin,
      to: targetSpace.latLng,
    );
    if (requestId != _navigationRouteRequestId) return;
    _adoptComposedRoute(route);
  }

  /// Routes the user to a campus gate, using the gate's EXACT coordinates
  /// (from `university gates.kmz`) as the destination.
  ///
  /// A gate is an outdoor, campus-scoped destination — no building/floor/POI
  /// layer is involved. This reuses the existing outdoor routing cascade
  /// (custom road graph → hybrid → OSRM-to-custom → OSRM) so the route follows
  /// the campus road network wherever the gate is graph-connected.
  ///
  /// IMPORTANT (gate policy separation): the selected [gate] IS the
  /// destination and is deliberately NOT passed as a `gateEntry` to
  /// [RoutingService.buildOsrmToCustomRoute] — so the preferred automatic
  /// entry gate (G2)
  /// is never forced as an intermediate point. Routing to a gate never changes
  /// the routing policy.
  Future<bool> requestRouteToGate(CampusGate gate) async {
    final currentLocation = _currentLocation();

    if (currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return false;
    }

    final destLatLng = LatLng(gate.latitude, gate.longitude);
    final fromLatLng = currentLocation.latLng;

    debugPrint(
      '[SpaceViewModel] requestRouteToGate: ${gate.id} '
      '(destination: ${gate.latitude},${gate.longitude}, '
      'user GPS: ${currentLocation.latitude},${currentLocation.longitude})',
    );

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
    _notify();

    List<LatLng>? outdoorPath;

    // Outdoor cascade: custom → hybrid → OSRM→custom → OSRM (extracted).
    // No gateEntry is supplied — the gate IS the destination, so the preferred
    // entry gate is never forced as an intermediate point (gate policy
    // separation).
    outdoorPath = await _assets.outdoorRoutePlanner.resolveOutdoorPath(
      from: fromLatLng,
      to: destLatLng,
      gateEntry: null,
    );
    if (requestId != _navigationRouteRequestId) return false;

    if (outdoorPath.length < 2) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage =
          'Could not build a route to gate ${gate.id}.';
      debugPrint('[SpaceViewModel] requestRouteToGate: no outdoor path found');
      _notify();
      return false;
    }
    final outdoorPoints = <NavigationRoutePoint>[
      for (final pt in outdoorPath)
        NavigationRoutePoint.outdoor(
          latitude: pt.latitude,
          longitude: pt.longitude,
        ),
    ];

    final route = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: null,
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = route;
    _navigationRouteErrorMessage = null;
    _notify();

    debugPrint(
      '[SpaceViewModel] requestRouteToGate: ${route.points.length} outdoor points',
    );
    return route.hasRenderablePath;
  }

  /// Retarget support (MASTER PLAN PHASE 4).
  ///
  /// Selects the destination context exclusively through navigation-safe
  /// variants (never resetting navigation fields), then runs the initial
  /// route request — reusing its request-id machinery unchanged. Returns
  /// true when a renderable route for [target] is in the store afterwards.
  Future<bool> requestRouteForRetarget(PoiModel target) async {
    final building = _spaces().where((s) => s.buid == target.buid).firstOrNull;
    if (building == null) {
      debugPrint(
        '[SpaceViewModel] retarget: building ${target.buid} not loaded',
      );
      return false;
    }
    _selectSpaceForNavigation(building);
    await _loadFloors();
    final floors = _floors();
    final floor =
        floors.where((f) => f.floorNumber == target.floorNumber).firstOrNull ??
        floors.where((f) => f.floorNumber == '0').firstOrNull ??
        (floors.isEmpty
            ? null
            : floors.reduce(
                (a, b) => a.numericFloor <= b.numericFloor ? a : b,
              ));
    if (floor != null) {
      _selectFloorForNavigation(floor);
    }
    // Selecting the new target POI must not trip the legacy reset even when
    // idle-guard logic changes later; the session liveness guard already
    // covers it, this is belt-and-braces for the retarget window.
    _setDestinationPoi(target);

    await requestRouteToSelectedPoi();
    final ok =
        _navigationRouteStatus == NavigationRouteStatus.ready &&
        _activeNavigationRoute != null &&
        _activeNavigationRoute!.hasRenderablePath;
    debugPrint(
      '[SpaceViewModel] requestRouteForRetarget(${target.puid}) '
      '-> ${ok ? "ready" : "failed"}',
    );
    return ok;
  }

  /// Stores a freshly composed outdoor route, or records a truthful failure
  /// when it carries no renderable geometry.
  void _adoptComposedRoute(NavigationRouteModel route) {
    if (!route.hasRenderablePath) {
      _navigationRouteStatus = NavigationRouteStatus.unsupported;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage =
          'No outdoor route found to the destination.';
      _notify();
      return;
    }
    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = route;
    // D6: a partial route's warning lives on the route model, never in the
    // error field.
    _navigationRouteErrorMessage = null;
    _notify();
  }

  /// Builds an outdoor-only route straight from the preserved outdoor cascade
  /// (KMZ → hybrid → OSRM→custom → OSRM). Degrades to an explicitly-flagged
  /// approximate straight line (partial + warning) when the cascade yields no
  /// path — a visible degraded state, never a silent success.
  Future<NavigationRouteModel> _buildDirectOutdoorRoute({
    required LatLng from,
    required LatLng to,
  }) async {
    final path = await _assets.outdoorRoutePlanner.resolveOutdoorPath(
      from: from,
      to: to,
      gateEntry: _assets.preferredGate(),
    );

    if (path.length >= 2) {
      return NavigationRouteModel.hybrid(
        outdoorPoints: [
          for (final pt in path)
            NavigationRoutePoint.outdoor(
              latitude: pt.latitude,
              longitude: pt.longitude,
            ),
        ],
        indoorRoute: null,
      );
    }

    return NavigationRouteModel.hybrid(
      outdoorPoints: [
        NavigationRoutePoint.outdoor(
          latitude: from.latitude,
          longitude: from.longitude,
        ),
        NavigationRoutePoint.outdoor(
          latitude: to.latitude,
          longitude: to.longitude,
        ),
      ],
      indoorRoute: null,
      status: RouteModelStatus.partial,
      partialRouteWarning: 'Outdoor routing unavailable — following an '
          'approximate straight-line path. You may need to navigate manually '
          'for this leg.',
    );
  }
}
