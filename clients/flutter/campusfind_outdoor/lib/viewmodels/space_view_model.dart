import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/campus_asset_status.dart';
import '../models/campus_gate.dart';
import '../models/floor_model.dart';
import '../models/floorplan_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/quick_access_item.dart';
import '../models/space_model.dart';
import '../repositories/custom_route_repository.dart';
import '../repositories/navigation_repository.dart';
import '../repositories/poi_repository.dart';
import '../repositories/space_repository.dart';
import '../services/cache_service.dart';
import '../services/campus_asset_loader.dart';
import '../services/campus_route_assets.dart';
import '../services/campus_route_coordinator.dart';
import '../services/campus_search_index.dart';
import '../services/navigation_route_scope.dart';
import '../services/quick_access_service.dart';
import '../services/search_service.dart';
import '../viewmodels/location_view_model.dart';

/// Provider managing state for Anyplace buildings, floors, and POIs.
///
/// This class is the composition root + selection controller after the
/// MVVM decomposition:
///  * acquisition of spaces/floors/POIs lives in
///    [CampusAssetLoader];
///  * the bundled route/gate infrastructure lives in [CampusRoutingAssets];
///  * every navigation-route REQUEST (cascades, fencing, store) lives in
///    [CampusRouteCoordinator];
///  * the background search sync lives in [CampusSearchIndex];
///  * selection semantics + cross-tab navigation orchestration remain here.
class SpaceViewModel extends ChangeNotifier implements NavigationRouteScope {
  late final CampusAssetLoader _assetLoader;
  late final CampusRoutingAssets _assets;
  late final CampusRouteCoordinator _routeCoordinator;
  late final CampusSearchIndex _searchIndex;

  late final CacheService? _cacheService;

  /// One-time Quick Access seeding + legacy saved-POI migration.
  late final QuickAccessService? _quickAccessService = _cacheService == null
      ? null
      : QuickAccessService(_cacheService);

  // Selection state (browsing + destination context).
  SpaceModel? _selectedSpace;
  FloorModel? _selectedFloor;
  PoiModel? _selectedPoi;
  CampusGate? _selectedGate;

  LocationViewModel? _locationProvider;

  // Batch loading pause flag (user action priority)
  bool _batchPaused = false;

  // Fallback center used ONLY when the app has no GPS fix and no selection.
  //
  // SERVER MIGRATION: was the Cyprus centroid of the old UCY backend; now
  // the centroid of the six live E-JUST buildings on map.beout.ai (mean of
  // the actual /space/public payload coordinates).
  static const LatLng defaultCenter = LatLng(30.859877, 29.563241);

  SpaceViewModel({
    SpaceRepository? repository,
    PoiRepository? poiRepository,
    NavigationRepository? navigationRepository,
    this._locationProvider,
    CacheService? cacheService,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _cacheService = cacheService {
    final resolvedRepository = repository ?? AnyplaceSpaceRepository();
    final resolvedPoiRepository = poiRepository ?? AnyplacePoiRepository();
    final resolvedNavigationRepository =
        navigationRepository ?? AnyplaceNavigationRepository();

    _assetLoader = CampusAssetLoader(
      repository: resolvedRepository,
      poiRepository: resolvedPoiRepository,
      notify: notifyListeners,
      selectedSpace: () => _selectedSpace,
      selectedFloor: () => _selectedFloor,
      onSelectedSpaceRefresh: (space) => _selectedSpace = space,
      onSelectedPoiCleared: () => _selectedPoi = null,
    );

    _searchIndex = CampusSearchIndex(
      repository: resolvedRepository,
      poiRepository: resolvedPoiRepository,
      spaces: () => _assetLoader.spaces,
      isPaused: () => _batchPaused,
      onFloorsIndexed: _assetLoader.indexFloors,
    );

    _assets = CampusRoutingAssets(
      navigationRepository: resolvedNavigationRepository,
      loadFloorsForBuilding: (buid) async =>
          _assetLoader.floorsForBuilding(buid),
      loadPois: (buid, floorNumber) async =>
          _assetLoader.poisForBuildingFloor(buid, floorNumber),
      loadFloorNumbers: (buid) async => _assetLoader.floorNumbersForBuilding(buid),
      notify: notifyListeners,
    );

    _routeCoordinator = CampusRouteCoordinator(
      assets: _assets,
      notify: notifyListeners,
      cacheService: _cacheService,
      spaces: () => _assetLoader.spaces,
      floors: () => _assetLoader.floors,
      selectedPoi: () => _selectedPoi,
      currentLocation: () => _locationProvider?.currentLocation,
      setDestinationPoi: (target) {
        _selectedPoi = target;
        notifyListeners();
      },
      selectSpaceForNavigation: selectSpaceForNavigation,
      selectFloorForNavigation: selectFloorForNavigation,
      loadFloors: () => _assetLoader.loadFloorsForSelectedSpace(),
    );
  }

  /// Binds LocationViewModel for route requests that need the current fix.
  ///
  /// Selection state is never forwarded as positioning scope: selection only
  /// controls which RadioMaps load into the native engine, never which one
  /// wins positioning arbitration.
  void setLocationViewModel(LocationViewModel? locationProvider) {
    _locationProvider = locationProvider;
  }

  /// Injected liveness probe (MASTER PLAN PHASE 3, INV-4): while it returns
  /// true, the six browsing APIs suppress their legacy navigation-field
  /// resets so browsing can never destroy a live session. Wired in the
  /// composition root to `navigationController.isActive`.
  bool Function()? isNavigationSessionLive;

  /// Temporary Phase-3 retarget bridge: invoked by [navigateToPoi] when a
  /// session is live so the run ends cleanly instead of being silently
  /// destroyed by cross-tab navigation. Phase 4 replaces this with the
  /// explicit retarget protocol.
  void Function()? terminateActiveSessionForRetarget;

  bool get _sessionLive => isNavigationSessionLive?.call() ?? false;

  /// Access to the custom route repository for map rendering and queries.
  @override
  CustomRouteRepository get customRouteRepository =>
      _assets.customRouteRepository;

  /// SERVER MIGRATION: purges on-disk POI dataset caches that may still hold
  /// files from the previous backend.
  Future<void> purgeDatasetCaches() => _assetLoader.purgeDatasetCaches();

  /// Loads custom KMZ routes AND campus gates from bundled assets.
  ///
  /// Should be called once during app startup, after spaces are loaded.
  /// Safe to call multiple times (no-op if already loaded).
  Future<void> loadCustomRoutes() => _assets.load();

  // ── Spaces / floors / POIs / RadioMap / Floorplan getters ──

  List<SpaceModel> get spaces => _assetLoader.spaces;
  @override
  SpaceModel? get selectedSpace => _selectedSpace;
  bool get isLoading => _assetLoader.isLoading;
  String? get errorMessage => _assetLoader.errorMessage;
  bool get hasError => _assetLoader.errorMessage != null;
  bool get hasSelectedSpace => _selectedSpace != null;

  // Floor Getters
  @override
  List<FloorModel> get floors => _assetLoader.floors;
  @override
  FloorModel? get selectedFloor => _selectedFloor;
  bool get isLoadingFloors => _assetLoader.isLoadingFloors;
  String? get floorsErrorMessage => _assetLoader.floorsErrorMessage;
  bool get hasFloorsError => _assetLoader.floorsErrorMessage != null;
  bool get hasSelectedFloor => _selectedFloor != null;

  // RadioMap Getters
  RadioMapStatus get radioMapStatus => _assetLoader.radioMapStatus;
  bool get isLoadingRadioMap => _assetLoader.radioMapStatus == RadioMapStatus.loading;
  bool get hasActiveRadioMap => _assetLoader.radioMapStatus == RadioMapStatus.ready;
  bool get isRadioMapUnsupported =>
      _assetLoader.radioMapStatus == RadioMapStatus.unsupported;
  String? get radioMapErrorMessage => _assetLoader.radioMapErrorMessage;
  String? get activeRadioMapBuid => _assetLoader.activeRadioMapBuid;
  String? get activeRadioMapFloor => _assetLoader.activeRadioMapFloor;
  bool get isRadioMapCached => _assetLoader.isRadioMapCached;

  // Floorplan Getters
  FloorplanStatus get floorplanStatus => _assetLoader.floorplanStatus;
  @override
  FloorplanModel? get activeFloorplan => _assetLoader.activeFloorplan;
  bool get isLoadingFloorplan => _assetLoader.floorplanStatus == FloorplanStatus.loading;
  bool get hasActiveFloorplan =>
      _assetLoader.floorplanStatus == FloorplanStatus.ready &&
      _assetLoader.activeFloorplan != null;
  bool get isFloorplanUnsupported =>
      _assetLoader.floorplanStatus == FloorplanStatus.unsupported;
  String? get floorplanErrorMessage => _assetLoader.floorplanErrorMessage;
  String? get activeFloorplanImagePath => _assetLoader.activeFloorplan?.imagePath;
  bool get isFloorplanCached => _assetLoader.activeFloorplan?.isCached ?? false;

  // POI Getters
  PoiStatus get poiStatus => _assetLoader.poiStatus;
  @override
  List<PoiModel> get pois => _assetLoader.pois;
  PoiModel? get selectedPoi => _selectedPoi;
  @override
  bool get hasPois => _assetLoader.pois.isNotEmpty;
  bool get isLoadingPois => _assetLoader.poiStatus == PoiStatus.loading;
  String? get poiErrorMessage => _assetLoader.poiErrorMessage;
  bool get hasSelectedPoi => _selectedPoi != null;

  // Campus Gate Getters
  //
  // Exposes the authoritative gate list (coordinates + ids from
  // university gates.kmz) without exposing the mutable repository. The list is
  // unmodifiable, so callers can never mutate internal gate state. Disabled /
  // non-preferred gates are still returned here — "visible" is independent of
  // the routing policy that decides which gate is the automatic preferred
  // entry point.
  List<CampusGate> get campusGates => _assets.gates;
  CampusGate? get selectedGate => _selectedGate;
  bool get hasSelectedGate => _selectedGate != null;

  // Navigation Getters
  NavigationRouteStatus get navigationRouteStatus =>
      _routeCoordinator.navigationRouteStatus;
  @override
  NavigationRouteModel? get activeNavigationRoute =>
      _routeCoordinator.activeNavigationRoute;
  String? get navigationRouteErrorMessage =>
      _routeCoordinator.navigationRouteErrorMessage;
  bool get isLoadingNavigationRoute =>
      _routeCoordinator.isLoadingNavigationRoute;
  bool get hasActiveNavigationRoute =>
      _routeCoordinator.hasActiveNavigationRoute;
  bool get isNavigationRouteUnsupported =>
      _routeCoordinator.isNavigationRouteUnsupported;
  bool get isNavigationRoutePartial =>
      _routeCoordinator.isNavigationRoutePartial;
  String? get navigationRouteWarning =>
      _routeCoordinator.navigationRouteWarning;
  String? get navigationDestinationPuid =>
      _routeCoordinator.navigationDestinationPuid;

  // ── Asset acquisition ──

  /// Fetches public spaces from the Anyplace repository.
  Future<void> loadSpaces({bool forceReload = false}) =>
      _assetLoader.loadSpaces(forceReload: forceReload);

  /// Fetches floors for the currently selected space.
  Future<void> loadFloorsForSelectedSpace({bool forceReload = false}) =>
      _assetLoader.loadFloorsForSelectedSpace(forceReload: forceReload);

  /// Acquires POIs for the currently selected building and floor.
  Future<void> loadPoisForSelectedFloor({bool forceReload = false}) =>
      _assetLoader.loadPoisForSelectedFloor(forceReload: forceReload);

  /// True global wipe (app-level reset only: logout / storage clear).
  void resetAllRadiomaps() => _assetLoader.resetAllRadiomaps();

  /// Progressive background sync: fetches floors + POIs for all buildings
  /// and indexes them into [searchService].
  Future<void> loadAllFloorsAndPois(SearchService searchService) =>
      _searchIndex.loadAllFloorsAndPois(searchService);

  // ── Error clearing ──

  /// Clears the building-level error message.
  void clearError() => _assetLoader.clearError();

  /// Clears the floor-level error message.
  void clearFloorsError() => _assetLoader.clearFloorsError();

  /// Clears the radiomap-level error message.
  void clearRadioMapError() => _assetLoader.clearRadioMapError();

  /// Clears the floorplan-level error message.
  void clearFloorplanError() => _assetLoader.clearFloorplanError();

  /// Clears the POI-level error message.
  void clearPoiError() => _assetLoader.clearPoiError();

  /// Clears the navigation route-level error message.
  void clearNavigationRouteError() =>
      _routeCoordinator.clearNavigationRouteError();

  // ── Quick Access ──

  /// One-time Quick Access initialization: seeds the predefined default
  /// locations and migrates any legacy `saved_pois` into the unified format.
  ///
  /// Runs only when the Quick Access preference key has never been written.
  /// Once the key exists (even as an empty list) seeding and migration are
  /// permanently skipped, so user customizations and "Clear Quick Access" are
  /// never overwritten on later launches.
  ///
  /// Returns a per-default report describing how each requested default was
  /// resolved (real `buid` + entity name) or why it was skipped, so the audit
  /// can verify no default was ever substituted with a different location.
  Future<List<QuickAccessSeedReport>> ensureQuickAccessInitialized(
    SearchService searchService,
  ) async {
    final service = _quickAccessService;
    if (service == null) {
      debugPrint(
        '[SpaceViewModel] ensureQuickAccessInitialized: no cache service',
      );
      return const [];
    }
    return service.seedIfNeeded(
      spaces: _assetLoader.spaces,
      searchService: searchService,
    );
  }

  // ── Selection controller (INV-4 / INV-5 invariant enforcement) ──

  /// Selects a space, clears previous floor & POI selections, and automatically loads available floors.
  ///
  /// INV-4 (Phase 3): during a live navigation session the legacy
  /// navigation-field reset is suppressed; browsing state still changes.
  @override
  void selectSpace(SpaceModel space) =>
      _selectSpaceInternal(space, resetNavigationFields: true);

  /// Navigation-driven building selection (INV-5): preloads residency
  /// context for the session without ever touching route/destination fields.
  @override
  void selectSpaceForNavigation(SpaceModel space) =>
      _selectSpaceInternal(space, resetNavigationFields: false);

  void _selectSpaceInternal(
    SpaceModel space, {
    required bool resetNavigationFields,
  }) {
    if (_selectedSpace?.buid != space.buid) {
      debugPrint(
        '[SpaceViewModel] selectSpace: ${space.name} (buid: ${space.buid})',
      );
      _selectedSpace = space;
      _selectedFloor = null;
      _assetLoader.resetFloorsForSelection();
      _selectedPoi = null;
      _selectedGate = null;
      _assetLoader.resetRadioMapState();
      _assetLoader.resetFloorplanState();
      _assetLoader.resetPoiState();
      if (resetNavigationFields && !_sessionLive) {
        _routeCoordinator.resetRouteState();
      }
      _batchPaused =
          true; // Pause background batch — user action takes priority
      notifyListeners();

      // Automatically fetch floors for newly selected space
      loadFloorsForSelectedSpace();
    }
  }

  /// Clears the currently selected space, floor, RadioMap, floorplan, and POIs.
  ///
  /// INV-4 (Phase 3): navigation fields survive when a session is live.
  @override
  void clearSelection() {
    if (_selectedSpace != null || _selectedFloor != null) {
      debugPrint(
        '[SpaceViewModel] clearSelection: resetting space, floor, radiomap, floorplan, and pois',
      );
      _selectedSpace = null;
      _selectedFloor = null;
      _assetLoader.resetFloorsForSelection();
      _selectedPoi = null;
      _selectedGate = null;
      _assetLoader.bumpPoiRequestId();
      _assetLoader.resetRadioMapState();
      _assetLoader.resetFloorplanState();
      _assetLoader.resetPoiState();
      if (!_sessionLive) {
        _routeCoordinator.resetRouteState();
      }
      _batchPaused = false; // Resume background batch
      notifyListeners();
    }
  }

  /// Selects a floor for the currently selected space and triggers RadioMap, Floorplan, and POI downloads.
  ///
  /// INV-4 (Phase 3): during a live session the navigation-field reset is
  /// suppressed; the selection itself proceeds unchanged.
  @override
  void selectFloor(FloorModel floor) =>
      _selectFloorInternal(floor, resetNavigationFields: true);

  /// Navigation-driven floor selection (INV-5): connector-proximity and
  /// transition completion use this so guidance geometry is never reset.
  @override
  void selectFloorForNavigation(FloorModel floor) =>
      _selectFloorInternal(floor, resetNavigationFields: false);

  void _selectFloorInternal(
    FloorModel floor, {
    required bool resetNavigationFields,
  }) {
    if (_selectedSpace == null) {
      debugPrint('[SpaceViewModel] Cannot select floor: no space selected');
      return;
    }

    if (floor.buid != _selectedSpace!.buid) {
      debugPrint(
        '[SpaceViewModel] Mismatched buid: floor buid (${floor.buid}) != selected space buid (${_selectedSpace!.buid})',
      );
      return;
    }

    if (_selectedFloor?.floorNumber == floor.floorNumber) {
      debugPrint(
        '[SpaceViewModel] Floor ${floor.floorNumber} already selected',
      );
      return;
    }

    debugPrint(
      '[SpaceViewModel] selectFloor ACCEPTED: Floor ${floor.floorNumber} (${floor.displayName}) for ${_selectedSpace!.buid}',
    );
    _selectedFloor = floor;
    _selectedPoi = null;
    if (resetNavigationFields && !_sessionLive) {
      _routeCoordinator.resetRouteState();
    }
    notifyListeners();

    // Trigger POI acquisition for the selected floor
    loadPoisForSelectedFloor();
  }

  /// Clears the current floor selection and resets active RadioMap, Floorplan, and POIs.
  ///
  /// INV-4 (Phase 3): navigation fields survive live sessions.
  void clearFloorSelection() {
    if (_selectedFloor != null) {
      debugPrint('[SpaceViewModel] clearFloorSelection');
      _assetLoader.bumpPoiRequestId();
      _selectedFloor = null;
      _selectedPoi = null;
      _assetLoader.resetRadioMapState();
      _assetLoader.resetFloorplanState();
      _assetLoader.resetPoiState();
      if (!_sessionLive) {
        _routeCoordinator.resetRouteState();
      }
      notifyListeners();
    }
  }

  /// Selects an indoor POI for viewing details.
  void selectPoi(PoiModel? poi) {
    if (_selectedPoi?.puid != poi?.puid &&
        _routeCoordinator.navigationDestinationPuid != null &&
        _routeCoordinator.navigationDestinationPuid != poi?.puid &&
        !_sessionLive) {
      _routeCoordinator.resetRouteState();
    }
    _selectedPoi = poi;
    _selectedGate = null;
    notifyListeners();
  }

  /// Clears the selected POI.
  void clearSelectedPoi() {
    if (_selectedPoi != null) {
      _selectedPoi = null;
      if (!_sessionLive) {
        _routeCoordinator.resetRouteState();
      }
      notifyListeners();
    }
  }

  /// Selects a campus gate for viewing its details.
  ///
  /// Gates are independent of the indoor POI pipeline, so selecting one clears
  /// the indoor POI selection (only one destination detail shows at a time);
  /// building/floor state is left untouched. Navigating to a gate never
  /// changes the routing policy (preferred G2 stays the automatic entry gate).
  void selectGate(CampusGate? gate) {
    if (_selectedGate?.id == gate?.id && _selectedPoi == null) return;
    if (_selectedPoi != null) {
      _selectedPoi = null;
      if (!_sessionLive) {
        _routeCoordinator.resetRouteState();
      }
    }
    _selectedGate = gate;
    notifyListeners();
  }

  /// Clears the currently selected gate.
  void clearSelectedGate() {
    if (_selectedGate != null) {
      _selectedGate = null;
      notifyListeners();
    }
  }

  // ── Cross-tab navigation orchestration ──

  /// Orchestrates selectSpace -> selectFloor -> selectPoi from a [PoiModel].
  /// Used by cross-tab navigation (search results, recent waypoints).
  ///
  /// PHASE 3 temporary bridge: with a live session this ends the run
  /// cleanly via the injected callback instead of silently destroying it;
  /// the legacy idle path then proceeds. Phase 4 introduces the explicit
  /// retarget protocol.
  Future<bool> navigateToPoi(PoiModel targetPoi) async {
    if (_sessionLive) {
      debugPrint(
        '[SpaceViewModel] navigateToPoi during live session — clean-restart bridge',
      );
      terminateActiveSessionForRetarget?.call();
    }
    return _navigateToIdentifier(
      buid: targetPoi.buid,
      floorNumber: targetPoi.floorNumber,
      puid: targetPoi.puid,
    );
  }

  /// Navigates to a Quick Access item (building or POI).
  ///
  /// Buildings resolve their `buid` and select the space on the map. POIs
  /// navigate through the full space -> floor -> poi chain using their stored
  /// `buid`/`floorNumber`/`puid`, resolving the space and floor regardless of
  /// the currently selected building/floor. Migrated POI items lacking
  /// navigation metadata are resolved through [searchService] by puid when
  /// provided.
  Future<bool> navigateToQuickAccessItem(
    QuickAccessItem item, {
    SearchService? searchService,
  }) async {
    if (item.isBuilding) {
      return _navigateToBuilding(item.id);
    }
    if (item.isPoi) {
      var buid = item.buid;
      var floorNumber = item.floorNumber;
      if (!item.hasPoiNavigationIds && searchService != null) {
        final resolved = searchService.findPoiByPuid(item.id);
        if (resolved != null) {
          buid = resolved.buid;
          floorNumber = resolved.floorNumber;
        }
      }
      if (buid == null || floorNumber == null) {
        debugPrint(
          '[SpaceViewModel] Cannot navigate to POI ${item.id}: missing buid/floorNumber and unresolved by index',
        );
        return false;
      }
      return _navigateToIdentifier(
        buid: buid,
        floorNumber: floorNumber,
        puid: item.id,
      );
    }
    return false;
  }

  /// Shared space -> floor -> poi orchestration keyed by stable identifiers.
  /// Does not depend on the POI being present in the currently loaded list.
  Future<bool> _navigateToIdentifier({
    required String buid,
    required String floorNumber,
    required String puid,
  }) async {
    // 1. Find the SpaceModel matching the POI's buid
    final space = spaces.firstWhere(
      (s) => s.buid == buid,
      orElse: () => throw StateError('Space $buid not found'),
    );

    // 2. Select the space (clears everything, starts async floor load)
    selectSpace(space);

    // 3. Wait for floors to load
    await loadFloorsForSelectedSpace();

    // 4. Find the FloorModel
    final floor = floors.firstWhere(
      (f) => f.floorNumber == floorNumber,
      orElse: () => throw StateError('Floor $floorNumber not found'),
    );

    // 5. Select the floor (starts async POI load)
    selectFloor(floor);

    // 6. Wait for POIs to load
    await loadPoisForSelectedFloor();

    // 7. Find the POI in the loaded list and select it
    final poi = pois.firstWhere(
      (p) => p.puid == puid,
      orElse: () => throw StateError('POI $puid not found in loaded POIs'),
    );
    selectPoi(poi);
    return true;
  }

  /// Selects a building by `buid` on the map, reloading the space list first
  /// if the building is not currently known. Returns false when the building
  /// is unknown even after reloading.
  Future<bool> _navigateToBuilding(String buid) async {
    if (spaces.isEmpty) {
      await loadSpaces();
    }
    final space = spaces.where((s) => s.buid == buid).firstOrNull;
    if (space == null) {
      debugPrint(
        '[SpaceViewModel] Cannot navigate to building $buid: not found',
      );
      return false;
    }
    selectSpace(space);
    return true;
  }

  // ── Route requests (cascade + fencing + store owned by the coordinator) ──

  /// Requests a navigation route from the current position (or
  /// [originOverride] when a custom start point was chosen) to the selected
  /// POI. Uses a 3-strategy cascade identical to building routing.
  Future<void> requestRouteToSelectedPoi({LatLng? originOverride}) =>
      _routeCoordinator.requestRouteToSelectedPoi(
        originOverride: originOverride,
      );

  /// Requests a route to [targetSpace], starting from the user's current
  /// location (or [originOverride] when a custom start point was chosen).
  /// Always produces a visible route (hybrid strategy ladder).
  Future<void> requestRouteToBuilding(
    SpaceModel targetSpace, {
    LatLng? originOverride,
  }) => _routeCoordinator.requestRouteToBuilding(
    targetSpace,
    originOverride: originOverride,
  );

  /// Routes the user to a campus gate, using the gate's EXACT coordinates.
  Future<bool> requestRouteToGate(CampusGate gate) =>
      _routeCoordinator.requestRouteToGate(gate);

  /// Retarget support (MASTER PLAN PHASE 4).
  @override
  Future<bool> requestRouteForRetarget(PoiModel target) =>
      _routeCoordinator.requestRouteForRetarget(target);

  /// Session write-through (MASTER PLAN PHASE 2, INV-1/2/6).
  @override
  void adoptNavigatedRoute(NavigationRouteModel route) =>
      _routeCoordinator.adoptNavigatedRoute(route);

  /// Clears the currently displayed navigation route.
  @override
  void clearNavigationRoute() => _routeCoordinator.clearNavigationRoute();

  /// Building-exit context release (MASTER PLAN PHASE 10, INV-9).
  ///
  /// Release matrix:
  ///  * RELEASED — floorplan overlay browsing state, POI selection.
  ///  * PRESERVED FOR MAP CONTEXT — the selected building AND the last floor
  ///    selection stay so camera/bounds context and exit-detection fallbacks
  ///    remain stable after stepping outside.
  ///  * RADIOMAP — residency is NOT wiped here; Phase 11 owns the scoped
  ///    eviction policy (targeted removal, never a global native wipe).
  ///  * NEVER TOUCHED — route store, destination identity, session fields.
  @override
  void releaseIndoorContextForNavigation() {
    debugPrint(
      '[SpaceViewModel] releaseIndoorContextForNavigation (route preserved)',
    );
    _assetLoader.bumpPoiRequestId();
    _selectedPoi = null;
    _assetLoader.resetFloorplanState();
    _assetLoader.resetPoiState();
    notifyListeners();
  }
}