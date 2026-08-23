import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../config/constants.dart';
import '../data/datasources/anyplace_api_client.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/floor_model.dart';
import '../data/models/floorplan_model.dart';
import '../data/models/navigation_route_model.dart';
import '../data/models/poi_model.dart';
import '../data/models/quick_access_item.dart';
import '../data/models/space_model.dart';
import '../data/repositories/floorplan_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../data/repositories/poi_repository.dart';
import '../data/repositories/radiomap_repository.dart';
import '../data/repositories/space_repository.dart';
import '../data/repositories/cross_building_router.dart';
import '../data/repositories/custom_route_repository.dart';
import '../data/models/user_location.dart';
import '../services/search_service.dart';
import '../services/cache_service.dart';
import '../utils/category_deriver.dart';
import 'location_provider.dart';
import 'navigation_state_model.dart';

/// Status of RadioMap acquisition and native engine readiness for the selected floor.
enum RadioMapStatus { idle, loading, ready, unsupported, error }

/// Status of Floorplan tiles acquisition and rendering readiness.
enum FloorplanStatus { idle, loading, ready, unsupported, error }

/// Status of indoor Points of Interest (POIs) acquisition for the selected floor.
enum PoiStatus { idle, loading, ready, error }

/// Status of an Anyplace navigation route request.
enum NavigationRouteStatus { idle, loading, ready, unsupported, error }

/// Outcome of resolving one predefined Quick Access default during seeding.
///
/// Records whether the requested default resolved to its exact verified E-JUST
/// entity in the loaded dataset, and if not, which similarly named candidates
/// were present. A resolved entry always carries the real API entity name and
/// buid; an unresolved entry is never silently substituted.
class QuickAccessSeedReport {
  const QuickAccessSeedReport.resolved({
    required this.requested,
    required this.resolvedName,
    required this.buid,
  })  : candidates = const [],
        isResolved = true;

  const QuickAccessSeedReport.unresolved({
    required this.requested,
    required this.candidates,
  })  : resolvedName = null,
        buid = null,
        isResolved = false;

  final DefaultQuickAccessLocation requested;

  /// True when the exact buid was found in the loaded dataset.
  final bool isResolved;

  /// The actual entity name in the loaded dataset (when resolved).
  final String? resolvedName;

  /// The exact buid resolved against the loaded dataset (when resolved).
  final String? buid;

  /// Similarly named entities found in the loaded dataset (when unresolved).
  final List<String> candidates;
}

/// Provider managing state for Anyplace buildings, floors, RadioMaps, indoor Floorplans, and POIs.
class SpaceProvider extends ChangeNotifier implements NavigationRouteScope {
  final SpaceRepository _repository;
  final RadioMapRepository _radioMapRepository;
  final FloorplanRepository _floorplanRepository;
  final PoiRepository _poiRepository;
  final NavigationRepository _navigationRepository;
  final NativePositioningService _nativePositioningService;
  late final CrossBuildingRouter _crossBuildingRouter;
  final CustomRouteRepository _customRouteRepository = CustomRouteRepository();
  CacheService? _cacheService;

  List<SpaceModel> _spaces = const [];
  SpaceModel? _selectedSpace;
  bool _isLoading = false;
  String? _errorMessage;

  // Floor State
  List<FloorModel> _floors = const [];
  FloorModel? _selectedFloor;
  bool _isLoadingFloors = false;
  String? _floorsErrorMessage;

  // RadioMap State
  RadioMapStatus _radioMapStatus = RadioMapStatus.idle;
  String? _radioMapErrorMessage;
  String? _activeRadioMapBuid;
  String? _activeRadioMapFloor;
  bool _isRadioMapCached = false;
  int _radioMapRequestId = 0;

  // Floorplan State
  FloorplanStatus _floorplanStatus = FloorplanStatus.idle;
  FloorplanModel? _activeFloorplan;
  String? _floorplanErrorMessage;
  int _floorplanRequestId = 0;

  // POI State
  PoiStatus _poiStatus = PoiStatus.idle;
  List<PoiModel> _pois = const [];
  PoiModel? _selectedPoi;
  String? _poiErrorMessage;
  int _poiRequestId = 0;

  // Navigation Route State
  NavigationRouteStatus _navigationRouteStatus = NavigationRouteStatus.idle;
  NavigationRouteModel? _activeNavigationRoute;
  String? _navigationRouteErrorMessage;
  String? _navigationDestinationPuid;
  int _navigationRouteRequestId = 0;
  LocationProvider? _locationProvider;

  // Batch loading pause flag (user action priority)
  bool _batchPaused = false;

  // Default coordinate if no space selected (Cyprus / UCY area)
  static const LatLng defaultCenter = LatLng(35.1444, 33.4105);

  SpaceProvider({
    SpaceRepository? repository,
    RadioMapRepository? radioMapRepository,
    FloorplanRepository? floorplanRepository,
    PoiRepository? poiRepository,
    NavigationRepository? navigationRepository,
    NativePositioningService? nativePositioningService,
    this._locationProvider,
    CacheService? cacheService,
  }) : _repository = repository ?? AnyplaceSpaceRepository(),
       _radioMapRepository = radioMapRepository ?? AnyplaceRadioMapRepository(),
       _floorplanRepository =
           floorplanRepository ?? AnyplaceFloorplanRepository(),
       _poiRepository = poiRepository ?? AnyplacePoiRepository(),
       _navigationRepository =
           navigationRepository ?? AnyplaceNavigationRepository(),
       _nativePositioningService =
           nativePositioningService ?? MethodChannelNativePositioningService(),
       _cacheService = cacheService {
    _crossBuildingRouter = CrossBuildingRouter(
      isPositionInBuilding: (position, buildingBuid) {
        return _isPositionInBuilding(position, buildingBuid);
      },
      loadPois: (buid, floorNumber) async {
        try {
          final client = AnyplaceApiClient();
          return await client.fetchPoisByFloor(buid, floorNumber);
        } catch (e) {
          debugPrint('[SpaceProvider] loadPois callback failed for $buid/$floorNumber: $e');
          return <PoiModel>[];
        }
      },
      loadFloorNumbers: (buid) async {
        try {
          final client = AnyplaceApiClient();
          final floors = await client.fetchFloorsForBuilding(buid);
          return floors.map((f) => f.floorNumber).toList();
        } catch (e) {
          debugPrint('[SpaceProvider] loadFloorNumbers callback failed for $buid: $e');
          return <String>[];
        }
      },
      customRouteRepository: _customRouteRepository,
    );
  }

  /// Binds LocationProvider for route requests that need the current fix.
  ///
  /// Selection state is never forwarded as positioning scope: selection only
  /// controls which RadioMaps load into the native engine, never which one
  /// wins positioning arbitration.
  void setLocationProvider(LocationProvider? locationProvider) {
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
  CustomRouteRepository get customRouteRepository => _customRouteRepository;

  /// Loads custom KMZ routes from bundled assets.
  ///
  /// Should be called once during app startup, after spaces are loaded.
  /// Safe to call multiple times (no-op if already loaded).
  Future<void> loadCustomRoutes() async {
    debugPrint('[SpaceProvider] loadCustomRoutes: starting (isLoaded=${_customRouteRepository.isLoaded})');
    if (_customRouteRepository.isLoaded) return;
    await _customRouteRepository.loadRoutes();
    debugPrint('[SpaceProvider] loadCustomRoutes: loaded=${_customRouteRepository.isLoaded}, routes=${_customRouteRepository.routes.length}');
    notifyListeners();
  }

  /// Retries [fn] up to [maxRetries] times with exponential backoff.
  Future<T> _withRetry<T>(
    Future<T> Function() fn, {
    int maxRetries = 2,
    String label = '',
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        if (attempt < maxRetries) {
          final delaySec = 1 << attempt; // 1s, 2s, 4s...
          debugPrint(
            '[SpaceProvider] $label attempt ${attempt + 1} failed ($e), retrying in ${delaySec}s...',
          );
          await Future.delayed(Duration(seconds: delaySec));
        } else {
          rethrow;
        }
      }
    }
    throw StateError('unreachable');
  }

  List<SpaceModel> get spaces => _spaces;
  @override
  SpaceModel? get selectedSpace => _selectedSpace;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  bool get hasSelectedSpace => _selectedSpace != null;

  // Floor Getters
  @override
  List<FloorModel> get floors => _floors;
  @override
  FloorModel? get selectedFloor => _selectedFloor;
  bool get isLoadingFloors => _isLoadingFloors;
  String? get floorsErrorMessage => _floorsErrorMessage;
  bool get hasFloorsError => _floorsErrorMessage != null;
  bool get hasSelectedFloor => _selectedFloor != null;

  // RadioMap Getters
  RadioMapStatus get radioMapStatus => _radioMapStatus;
  bool get isLoadingRadioMap => _radioMapStatus == RadioMapStatus.loading;
  bool get hasActiveRadioMap => _radioMapStatus == RadioMapStatus.ready;
  bool get isRadioMapUnsupported =>
      _radioMapStatus == RadioMapStatus.unsupported;
  String? get radioMapErrorMessage => _radioMapErrorMessage;
  String? get activeRadioMapBuid => _activeRadioMapBuid;
  String? get activeRadioMapFloor => _activeRadioMapFloor;
  bool get isRadioMapCached => _isRadioMapCached;

  // Floorplan Getters
  FloorplanStatus get floorplanStatus => _floorplanStatus;
  @override
  FloorplanModel? get activeFloorplan => _activeFloorplan;
  bool get isLoadingFloorplan => _floorplanStatus == FloorplanStatus.loading;
  bool get hasActiveFloorplan =>
      _floorplanStatus == FloorplanStatus.ready && _activeFloorplan != null;
  bool get isFloorplanUnsupported =>
      _floorplanStatus == FloorplanStatus.unsupported;
  String? get floorplanErrorMessage => _floorplanErrorMessage;
  String? get activeFloorplanImagePath => _activeFloorplan?.imagePath;
  bool get isFloorplanCached => _activeFloorplan?.isCached ?? false;

  // POI Getters
  PoiStatus get poiStatus => _poiStatus;
  @override
  List<PoiModel> get pois => _pois;
  PoiModel? get selectedPoi => _selectedPoi;
  @override
  bool get hasPois => _pois.isNotEmpty;
  bool get isLoadingPois => _poiStatus == PoiStatus.loading;
  String? get poiErrorMessage => _poiErrorMessage;
  bool get hasSelectedPoi => _selectedPoi != null;

  // Navigation Getters
  NavigationRouteStatus get navigationRouteStatus => _navigationRouteStatus;
  @override
  NavigationRouteModel? get activeNavigationRoute => _activeNavigationRoute;
  String? get navigationRouteErrorMessage => _navigationRouteErrorMessage;
  bool get isLoadingNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.loading;
  bool get hasActiveNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.ready &&
      _activeNavigationRoute != null &&
      _activeNavigationRoute!.hasRenderablePath;
  bool get isNavigationRouteUnsupported =>
      _navigationRouteStatus == NavigationRouteStatus.unsupported;
  String? get navigationDestinationPuid => _navigationDestinationPuid;

  /// Fetches public spaces from the Anyplace repository.
  Future<void> loadSpaces({bool forceReload = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await _withRetry(
        () => _repository.getPublicSpaces(forceReload: forceReload),
        maxRetries: 2,
        label: 'loadSpaces',
      );
      _spaces = fetched;
      _errorMessage = null;

      // If selected space was previously set, refresh its reference from new list
      if (_selectedSpace != null) {
        _selectedSpace = fetched.firstWhere(
          (s) => s.buid == _selectedSpace!.buid,
          orElse: () => _selectedSpace!,
        );
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load campus spaces: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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
      SearchService searchService) async {
    final cache = _cacheService;
    if (cache == null) {
      debugPrint('[SpaceProvider] ensureQuickAccessInitialized: no cache service');
      return const [];
    }
    if (await cache.hasQuickAccessKey()) {
      debugPrint('[SpaceProvider] ensureQuickAccessInitialized: already initialized');
      return const [];
    }

    final items = <QuickAccessItem>[];
    var addedAt = DateTime.now().millisecondsSinceEpoch;
    final usedBuids = <String>{};
    final report = <QuickAccessSeedReport>[];

    // 1. Seed predefined defaults (in defined order) by their VERIFIED buid.
    //    A default is seeded ONLY when its exact buid exists in the loaded
    //    dataset (resolved from the live SpaceModel). When the entity is not
    //    loaded, it is reported as unresolved with the matching-name candidates
    //    found in the dataset — it is NEVER substituted with another location.
    for (final defaultLoc in AppConstants.kDefaultQuickAccessLocations) {
      final match = _spaces
          .where((s) =>
              !usedBuids.contains(s.buid) && s.buid == defaultLoc.buid)
          .firstOrNull;
      if (match == null) {
        final candidates = _spaces
            .where((s) => s.name
                .toLowerCase()
                .contains(defaultLoc.name.toLowerCase()))
            .map((s) => '${s.name} (buid: ${s.buid})')
            .toList();
        report.add(QuickAccessSeedReport.unresolved(
          requested: defaultLoc,
          candidates: candidates,
        ));
        debugPrint(
          '[SpaceProvider] ensureQuickAccessInitialized: default "${defaultLoc.label}" '
          'UNRESOLVED (buid ${defaultLoc.buid} not in loaded dataset). '
          'Candidate entities found: ${candidates.isEmpty ? "none" : candidates.join("; ")}',
        );
        continue;
      }
      usedBuids.add(match.buid);
      items.add(QuickAccessItem.fromSpace(
        match,
        addedAt: addedAt++,
        category: CategoryDeriver.fromSpaceType(match.spaceType).name,
      ));
      report.add(QuickAccessSeedReport.resolved(
        requested: defaultLoc,
        resolvedName: match.name,
        buid: match.buid,
      ));
    }

    // 2. Migrate legacy saved POIs (preserved even when unresolvable now).
    final savedPuids = await cache.getSavedPois();
    for (final puid in savedPuids) {
      final resolved = searchService.findPoiByPuid(puid);
      if (resolved != null) {
        items.add(QuickAccessItem.fromPoi(
          resolved,
          addedAt: addedAt++,
          category: CategoryDeriver.fromPoiType(resolved.poisType).name,
        ));
      } else {
        items.add(QuickAccessItem.minimalPoi(puid, addedAt: addedAt++));
      }
    }

    // 3. Persist once, then consume the legacy key.
    await cache.setQuickAccessItems(items);
    if (savedPuids.isNotEmpty) {
      await cache.removeSavedPoisKey();
    }
    debugPrint(
      '[SpaceProvider] ensureQuickAccessInitialized: seeded ${items.length} item(s)',
    );
    return report;
  }

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
        '[SpaceProvider] selectSpace: ${space.name} (buid: ${space.buid})',
      );
      _selectedSpace = space;
      _selectedFloor = null;
      _floors = const [];
      _floorsErrorMessage = null;
      _selectedPoi = null;
      _resetRadioMapState();
      _resetFloorplanState();
      _resetPoiState();
      if (resetNavigationFields && !_sessionLive) {
        _resetNavigationRouteState();
      }
      _batchPaused = true; // Pause background batch — user action takes priority
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
        '[SpaceProvider] clearSelection: resetting space, floor, radiomap, floorplan, and pois',
      );
      _selectedSpace = null;
      _selectedFloor = null;
      _floors = const [];
      _floorsErrorMessage = null;
      _selectedPoi = null;
      _radioMapRequestId++;
      _floorplanRequestId++;
      _poiRequestId++;
      _resetRadioMapState();
      _resetFloorplanState();
      _resetPoiState();
      if (!_sessionLive) {
        _resetNavigationRouteState();
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
      debugPrint('[SpaceProvider] Cannot select floor: no space selected');
      return;
    }

    if (floor.buid != _selectedSpace!.buid) {
      debugPrint(
        '[SpaceProvider] Mismatched buid: floor buid (${floor.buid}) != selected space buid (${_selectedSpace!.buid})',
      );
      return;
    }

    if (_selectedFloor?.floorNumber == floor.floorNumber) {
      debugPrint('[SpaceProvider] Floor ${floor.floorNumber} already selected');
      return;
    }

    debugPrint(
      '[SpaceProvider] selectFloor ACCEPTED: Floor ${floor.floorNumber} (${floor.displayName}) for ${_selectedSpace!.buid}',
    );
    _selectedFloor = floor;
    _selectedPoi = null;
    if (resetNavigationFields && !_sessionLive) {
      _resetNavigationRouteState();
    }
    notifyListeners();

    // Trigger RadioMap, Floorplan, and POI acquisitions for the selected floor
    loadRadioMapForSelectedFloor();
    loadFloorplanForSelectedFloor();
    loadPoisForSelectedFloor();
  }

  /// Clears the current floor selection and resets active RadioMap, Floorplan, and POIs.
  ///
  /// INV-4 (Phase 3): navigation fields survive live sessions.
  void clearFloorSelection() {
    if (_selectedFloor != null) {
      debugPrint('[SpaceProvider] clearFloorSelection');
      _radioMapRequestId++;
      _floorplanRequestId++;
      _poiRequestId++;
      _selectedFloor = null;
      _selectedPoi = null;
      _resetRadioMapState();
      _resetFloorplanState();
      _resetPoiState();
      if (!_sessionLive) {
        _resetNavigationRouteState();
      }
      notifyListeners();
    }
  }

  /// Selects an indoor POI for viewing details.
  void selectPoi(PoiModel? poi) {
    if (_selectedPoi?.puid != poi?.puid &&
        _navigationDestinationPuid != null &&
        _navigationDestinationPuid != poi?.puid &&
        !_sessionLive) {
      _resetNavigationRouteState();
    }
    _selectedPoi = poi;
    notifyListeners();
  }

  /// Clears the selected POI.
  void clearSelectedPoi() {
    if (_selectedPoi != null) {
      _selectedPoi = null;
      if (!_sessionLive) {
        _resetNavigationRouteState();
      }
      notifyListeners();
    }
  }

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
        '[SpaceProvider] navigateToPoi during live session — clean-restart bridge',
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
          '[SpaceProvider] Cannot navigate to POI ${item.id}: missing buid/floorNumber and unresolved by index',
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
    final space = _spaces.firstWhere(
      (s) => s.buid == buid,
      orElse: () => throw StateError('Space $buid not found'),
    );

    // 2. Select the space (clears everything, starts async floor load)
    selectSpace(space);

    // 3. Wait for floors to load
    await loadFloorsForSelectedSpace();

    // 4. Find the FloorModel
    final floor = _floors.firstWhere(
      (f) => f.floorNumber == floorNumber,
      orElse: () => throw StateError('Floor $floorNumber not found'),
    );

    // 5. Select the floor (starts async POI load)
    selectFloor(floor);

    // 6. Wait for POIs to load
    await loadPoisForSelectedFloor();

    // 7. Find the POI in the loaded list and select it
    final poi = _pois.firstWhere(
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
    if (_spaces.isEmpty) {
      await loadSpaces();
    }
    final space = _spaces.where((s) => s.buid == buid).firstOrNull;
    if (space == null) {
      debugPrint('[SpaceProvider] Cannot navigate to building $buid: not found');
      return false;
    }
    selectSpace(space);
    return true;
  }

  /// Requests a navigation route from the current position to the selected POI.
  /// Uses a 3-strategy cascade identical to building routing.
  Future<void> requestRouteToSelectedPoi() async {
    final poi = _selectedPoi;
    final floor = _selectedFloor;
    final locationProvider = _locationProvider;
    final currentLocation = locationProvider?.currentLocation;

    if (poi == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage = 'Select a POI first.';
      notifyListeners();
      return;
    }

    if (floor == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Select a floor before requesting a route.';
      notifyListeners();
      return;
    }

    if (locationProvider == null || currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      notifyListeners();
      return;
    }

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = poi.puid;
    notifyListeners();

    // Save to recent waypoints
    _cacheService?.addRecentWaypoint(poi.puid);

    // ── Cross-building / Outdoor→Indoor detection for POI navigation ──
    final userBuilding = _detectBuildingFromPolygon(currentLocation);
    final targetPoiBuilding = _spaces.where((s) => s.buid == poi.buid).firstOrNull;
    final shouldTryCrossBuilding =
        targetPoiBuilding != null &&
        (userBuilding == null || userBuilding.buid != targetPoiBuilding.buid);

    if (shouldTryCrossBuilding) {
      debugPrint(
        '[SpaceProvider] POI cross-building: user ${userBuilding != null ? "in ${userBuilding.name}" : "outside"} → ${poi.name} in ${targetPoiBuilding.name}',
      );
      try {
        final crossRoute = await _crossBuildingRouter.composeRoute(
          userLocation: currentLocation.latLng,
          targetSpace: targetPoiBuilding,
          allBuildings: _spaces,
          targetPuid: poi.puid,
        );
        if (crossRoute != null) {
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = crossRoute;
          _navigationRouteErrorMessage = crossRoute.partialRouteWarning;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[SpaceProvider] POI cross-building router failed: $e');
        // Fall through to existing cascade
      }
    }

    final destLatLng = poi.latLng;

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 1: Anyplace coordinate-based routing (works when already indoors) Ã¢â€â‚¬Ã¢â€â‚¬
    debugPrint('[SpaceProvider] Strategy 1: coordinate-based routing...');
    try {
      final route = await _navigationRepository.getRouteFromCoordinates(
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        floorNumber: floor.floorNumber,
        destinationPuid: poi.puid,
      );

      if (requestId != _navigationRouteRequestId ||
          _selectedPoi?.puid != poi.puid) {
        return;
      }

      if (route.hasRenderablePath) {
        debugPrint('[SpaceProvider] Strategy 1 succeeded');
        _navigationRouteStatus = NavigationRouteStatus.ready;
        _activeNavigationRoute = route;
        _navigationRouteErrorMessage = null;
        notifyListeners();
        return;
      }
      debugPrint('[SpaceProvider] Strategy 1 failed: no renderable path');
    } on ApiException catch (e) {
      if (requestId != _navigationRouteRequestId) return;
      final msg = e.message.toLowerCase();
      if (msg.contains('not supported') ||
          msg.contains('no route found') ||
          msg.contains('not be connected') ||
          e.statusCode == 400 ||
          e.statusCode == 404) {
        debugPrint('[SpaceProvider] Strategy 1 failed: ${e.message}');
      } else {
        debugPrint('[SpaceProvider] Strategy 1 error: ${e.message}');
        _navigationRouteStatus = NavigationRouteStatus.error;
        _activeNavigationRoute = null;
        _navigationRouteErrorMessage = e.message;
        notifyListeners();
        return;
      }
    } catch (e) {
      if (requestId != _navigationRouteRequestId) return;
      debugPrint('[SpaceProvider] Strategy 1 exception: $e');
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = 'Error requesting route: $e';
      notifyListeners();
      return;
    }

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 2: POI-to-POI routing (closest POI near user Ã¢â€ â€™ destination POI) Ã¢â€â‚¬Ã¢â€â‚¬
    if (requestId != _navigationRouteRequestId) return;

    debugPrint('[SpaceProvider] Strategy 2: POI-to-POI routing...');

    // Find closest POI to user's GPS on the currently loaded POIs
    NavigationRoutePoint? originPoi;
    if (_pois.isNotEmpty) {
      final userLatLng = currentLocation;
      var bestDist = double.infinity;
      for (final p in _pois) {
        if (p.puid == poi.puid) continue;
        final dist = Geolocator.distanceBetween(userLatLng.latitude, userLatLng.longitude, p.latitude, p.longitude);
        if (dist < bestDist) {
          bestDist = dist;
          originPoi = NavigationRoutePoint(
            latitude: p.latitude,
            longitude: p.longitude,
            puid: p.puid,
            buid: p.buid,
            floorNumber: p.floorNumber,
            poisType: p.poisType,
          );
        }
      }
    }

    if (originPoi != null) {
      debugPrint(
        '[SpaceProvider] Strategy 2: POI-to-POI ${originPoi.puid} -> ${poi.puid}',
      );
      try {
        final route = await _navigationRepository.getRouteBetweenPois(
          fromPuid: originPoi.puid,
          toPuid: poi.puid,
        );

        if (requestId != _navigationRouteRequestId ||
            _selectedPoi?.puid != poi.puid) {
          return;
        }

        if (route.hasRenderablePath) {
          debugPrint('[SpaceProvider] Strategy 2 succeeded');
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = route;
          _navigationRouteErrorMessage = null;
          notifyListeners();
          return;
        }
        debugPrint('[SpaceProvider] Strategy 2 failed: no renderable path');
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 2 failed: ${e.message}');
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 2 exception: $e');
      }
    } else {
      debugPrint('[SpaceProvider] Strategy 2 skipped: no origin POI found');
    }

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 3: OSRM outdoor walking path to POI + indoor segment (ALWAYS works) Ã¢â€â‚¬Ã¢â€â‚¬
    if (requestId != _navigationRouteRequestId) return;

    debugPrint('[SpaceProvider] Strategy 3 (hybrid): outdoor route to POI...');

    // Try custom KMZ routes first
    List<LatLng>? outdoorPath;
    if (_customRouteRepository.isLoaded) {
      // Step 1: Try pure custom graph routing
      final customPath = _customRouteRepository.findRoute(
        currentLocation.latLng,
        destLatLng,
      );
      if (customPath.length >= 2) {
        outdoorPath = customPath;
        debugPrint('[SpaceProvider] Strategy 3: using custom KMZ route (${outdoorPath.length} points)');
      } else {
      // Step 2: Try hybrid routing (edge-based snap)
        final hybridPath = _customRouteRepository.findHybridRoute(
          currentLocation.latLng,
          destLatLng,
          snapThreshold: 150.0,
        );
        if (hybridPath != null && hybridPath.length >= 2) {
          outdoorPath = hybridPath;
          debugPrint('[SpaceProvider] Strategy 3: using hybrid custom route (${outdoorPath.length} points)');
        }
      }
    }

    // Step 3: Try OSRM to nearest custom vertex + custom to destination
    if (outdoorPath == null && _customRouteRepository.isLoaded) {
      final osrmToCustomPath = await _buildOsrmToCustomRoute(
        currentLocation.latLng,
        destLatLng,
      );
      if (osrmToCustomPath != null && osrmToCustomPath.length >= 2) {
        outdoorPath = osrmToCustomPath;
        debugPrint('[SpaceProvider] Strategy 3: using OSRM->Custom route (${outdoorPath.length} points)');
      }
    }

    // Step 4: Fallback to OSRM if custom routes didn't produce a path
    if (outdoorPath == null) {
      final osrmPath = await AnyplaceApiClient.fetchOutdoorWalkingRoute(
        fromLat: currentLocation.latitude,
        fromLon: currentLocation.longitude,
        toLat: destLatLng.latitude,
        toLon: destLatLng.longitude,
      );

      if (osrmPath.length >= 2 && _customRouteRepository.isLoaded) {
        // Try OSRM + Custom tail splice
        final splicedPath = _customRouteRepository.spliceCustomTail(
          osrmPath,
          destLatLng,
          connectionThreshold: 150.0,
        );
        if (splicedPath != null) {
          outdoorPath = splicedPath;
          debugPrint('[SpaceProvider] Strategy 3: using OSRM+Custom splice (${outdoorPath.length} points)');
        } else {
          outdoorPath = osrmPath;
        }
      } else {
        outdoorPath = osrmPath;
      }
    }

    final outdoorPoints = <NavigationRoutePoint>[];
    if (outdoorPath.length >= 2) {
      for (final pt in outdoorPath) {
        outdoorPoints.add(NavigationRoutePoint.outdoor(latitude: pt.latitude,
          longitude: pt.longitude));
      }
    } else {
      // Fallback: straight line if OSRM fails
      outdoorPoints.addAll([
        NavigationRoutePoint.outdoor(latitude: currentLocation.latitude,
          longitude: currentLocation.longitude),
        NavigationRoutePoint(
          latitude: destLatLng.latitude,
          longitude: destLatLng.longitude,
          puid: poi.puid,
          buid: poi.buid,
          floorNumber: poi.floorNumber,
          poisType: poi.poisType,
        ),
      ]);
    }

    // Try to get indoor route from entrance to target POI via connectors
    NavigationRouteModel? indoorRoute;
    if (_pois.isNotEmpty) {
      // Find entrance POI nearest to the destination
      final entrancePoi = _pois.where((p) =>
          p.buid == poi.buid &&
          (p.isBuildingEntrance || p.poisType.toLowerCase().contains('entrance'))
      ).firstOrNull;

      if (entrancePoi != null && entrancePoi.puid.isNotEmpty) {
        // Attempt 1: Direct entrance→target via server API
        try {
          debugPrint(
            '[SpaceProvider] Strategy 3: indoor route ${entrancePoi.puid} → ${poi.puid}',
          );
          indoorRoute = await _navigationRepository.getRouteBetweenPois(
            fromPuid: entrancePoi.puid,
            toPuid: poi.puid,
          );
          if (indoorRoute.hasRenderablePath) {
            debugPrint('[SpaceProvider] Strategy 3: indoor route succeeded (${indoorRoute.points.length} points)');
          } else {
            debugPrint('[SpaceProvider] Strategy 3: direct indoor route no renderable path — trying connector fallback');
            indoorRoute = null;
          }
        } catch (e) {
          debugPrint('[SpaceProvider] Strategy 3: direct indoor route failed: $e');
          indoorRoute = null;
        }

        // Attempt 2: Route through intermediate connector POIs
        // Server requires edges between POIs. Room/entrance POIs often lack edges,
        // but connector POIs (pois_type == "None") have edges between them.
        if (indoorRoute == null) {
          try {
            indoorRoute = await _routeIndoorViaConnectors(
              entrancePoi: entrancePoi,
              targetPoi: poi,
            );
          } catch (e) {
            debugPrint('[SpaceProvider] Strategy 3: connector-based indoor route failed: $e');
          }
        }
      }
    }

    final hybridRoute = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: indoorRoute,
    );

    debugPrint(
      '[SpaceProvider] Strategy 3 (hybrid): ${hybridRoute.points.length} points '
      '(outdoor: ${outdoorPoints.length}, indoor: ${indoorRoute?.points.length ?? 0})',
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = hybridRoute;
    _navigationRouteErrorMessage = null;
    notifyListeners();
  }

  /// Routes from entrance to target POI through intermediate connector POIs.
  ///
  /// The server requires edges between POIs for routing. Room/entrance POIs
  /// often lack edges, but connector POIs (pois_type == "None") have edges
  /// between them in the hallway.
  Future<NavigationRouteModel?> _routeIndoorViaConnectors({
    required PoiModel entrancePoi,
    required PoiModel targetPoi,
  }) async {
    // Find all connector POIs for the target building on the same floor
    final connectors = _pois
        .where((p) =>
            p.buid == targetPoi.buid &&
            p.puid.isNotEmpty &&
            p.poisType == 'None')
        .toList();
    if (connectors.isEmpty) {
      debugPrint('[SpaceProvider] No connector POIs found for building');
      return null;
    }
    debugPrint('[SpaceProvider] Found ${connectors.length} connectors for building');

    // Find nearest connector to entrance
    PoiModel? nearestToEntrance;
    double minDistEntrance = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        entrancePoi.latitude, entrancePoi.longitude,
        c.latitude, c.longitude,
      );
      if (dist < minDistEntrance) {
        minDistEntrance = dist;
        nearestToEntrance = c;
      }
    }

    // Find nearest connector to target
    PoiModel? nearestToTarget;
    double minDistTarget = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        targetPoi.latitude, targetPoi.longitude,
        c.latitude, c.longitude,
      );
      if (dist < minDistTarget) {
        minDistTarget = dist;
        nearestToTarget = c;
      }
    }

    if (nearestToEntrance == null || nearestToTarget == null) return null;

    debugPrint(
      '[SpaceProvider] Nearest connector to entrance: ${nearestToEntrance.name} '
      '(${minDistEntrance.toStringAsFixed(0)}m)',
    );
    debugPrint(
      '[SpaceProvider] Nearest connector to target: ${nearestToTarget.name} '
      '(${minDistTarget.toStringAsFixed(0)}m)',
    );

    // If both connectors are the same, return a simple 3-point path
    if (nearestToEntrance.puid == nearestToTarget.puid) {
      debugPrint('[SpaceProvider] Same connector — straight through');
      return NavigationRouteModel.hybrid(
        outdoorPoints: [],
        indoorRoute: NavigationRouteModel(
          points: [
            _poiToRoutePoint(entrancePoi),
            _poiToRoutePoint(nearestToEntrance),
            _poiToRoutePoint(targetPoi),
          ],
        ),
      );
    }

    // Route between the two connectors via the server API
    try {
      debugPrint(
        '[SpaceProvider] Connector→connector route: ${nearestToEntrance.puid} → ${nearestToTarget.puid}',
      );
      final connectorRoute = await _navigationRepository.getRouteBetweenPois(
        fromPuid: nearestToEntrance.puid,
        toPuid: nearestToTarget.puid,
      );

      if (connectorRoute.hasRenderablePath && connectorRoute.points.length >= 2) {
        debugPrint('[SpaceProvider] Connector route succeeded (${connectorRoute.points.length} points)');
        // Build full path: entrance → connector_start + route + connector_end → target
        final fullPath = <NavigationRoutePoint>[
          NavigationRoutePoint(
            latitude: entrancePoi.latitude,
            longitude: entrancePoi.longitude,
            puid: entrancePoi.puid,
            buid: entrancePoi.buid,
            floorNumber: entrancePoi.floorNumber,
            poisType: entrancePoi.poisType,
          ),
          NavigationRoutePoint(
            latitude: nearestToEntrance.latitude,
            longitude: nearestToEntrance.longitude,
            puid: nearestToEntrance.puid,
            buid: nearestToEntrance.buid,
            floorNumber: nearestToEntrance.floorNumber,
            poisType: nearestToEntrance.poisType,
          ),
          ...connectorRoute.points,
          NavigationRoutePoint(
            latitude: nearestToTarget.latitude,
            longitude: nearestToTarget.longitude,
            puid: nearestToTarget.puid,
            buid: nearestToTarget.buid,
            floorNumber: nearestToTarget.floorNumber,
            poisType: nearestToTarget.poisType,
          ),
          NavigationRoutePoint(
            latitude: targetPoi.latitude,
            longitude: targetPoi.longitude,
            puid: targetPoi.puid,
            buid: targetPoi.buid,
            floorNumber: targetPoi.floorNumber,
            poisType: targetPoi.poisType,
          ),
        ];

        return NavigationRouteModel.hybrid(
          outdoorPoints: [],
          indoorRoute: NavigationRouteModel(
            points: fullPath,
          ),
        );
      } else {
        debugPrint('[SpaceProvider] Connector route returned ${connectorRoute.points.length} points');
      }
    } catch (e) {
      debugPrint('[SpaceProvider] Connector→connector route failed: $e');
    }

    // Last resort: straight lines through the nearest connectors
    debugPrint('[SpaceProvider] Falling back to straight-line through connectors');
    return NavigationRouteModel.hybrid(
      outdoorPoints: [],
      indoorRoute: NavigationRouteModel(
        points: [
          _poiToRoutePoint(entrancePoi),
          _poiToRoutePoint(nearestToEntrance),
          _poiToRoutePoint(nearestToTarget),
          _poiToRoutePoint(targetPoi),
        ],
      ),
    );
  }

  NavigationRoutePoint _poiToRoutePoint(PoiModel poi) {
    return NavigationRoutePoint(
      latitude: poi.latitude,
      longitude: poi.longitude,
      puid: poi.puid,
      buid: poi.buid,
      floorNumber: poi.floorNumber,
      poisType: poi.poisType,
    );
  }

  /// Builds a combined route: OSRM from user to nearest custom vertex,
  /// then custom route from there to the destination.
  Future<List<LatLng>?> _buildOsrmToCustomRoute(
    LatLng userLocation,
    LatLng destination,
  ) async {
    final customRepo = _customRouteRepository;
    if (!customRepo.isLoaded) return null;

    final destVertex = customRepo.graph.nearestVertex(
      destination,
      maxDistance: 500.0,
    );
    if (destVertex == null) {
      debugPrint('[SpaceProvider] osrm→custom: no vertex within 500m of dest');
      return null;
    }
    final destVertexIdx = destVertex.$1;

    debugPrint(
      '[SpaceProvider] osrm→custom: dest vertex=$destVertexIdx, '
      '${destVertex.$2.toStringAsFixed(0)}m from destination',
    );

    // Step 1: Get route endpoints (campus road entrances on public roads)
    final endpoints = customRepo.graph.getRouteEndpoints();
    debugPrint('[SpaceProvider] osrm→custom: ${endpoints.length} route endpoints');

    if (endpoints.isEmpty) {
      debugPrint('[SpaceProvider] osrm→custom: no route endpoints');
      return null;
    }

    // Step 2: Among endpoints connected to destVertex, find closest to user
    int? bestEntryIdx;
    double bestEntryDist = double.infinity;

    for (final (epIdx, epPos) in endpoints) {
      final path = customRepo.graph.shortestPath(epIdx, destVertexIdx);
      if (path.isEmpty) continue;

      final dist = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        epPos.latitude,
        epPos.longitude,
      );

      debugPrint(
        '[SpaceProvider] osrm→custom: endpoint $epIdx, '
        '${dist.toStringAsFixed(0)}m from user, '
        'path to dest: ${path.length} vertices',
      );

      if (dist < bestEntryDist) {
        bestEntryDist = dist;
        bestEntryIdx = epIdx;
      }
    }

    if (bestEntryIdx == null) {
      debugPrint('[SpaceProvider] osrm→custom: no endpoint connected to dest');
      return null;
    }

    final entryPos = customRepo.graph.getVertexPosition(bestEntryIdx);
    debugPrint(
      '[SpaceProvider] osrm→custom: best entry=$bestEntryIdx, '
      '${bestEntryDist.toStringAsFixed(0)}m from user',
    );

    // Step 3: OSRM from user to the campus entrance endpoint
    final osrmResult = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
      fromLat: userLocation.latitude,
      fromLon: userLocation.longitude,
      toLat: entryPos.latitude,
      toLon: entryPos.longitude,
    );

    if (osrmResult == null || osrmResult.points.length < 2) {
      debugPrint('[SpaceProvider] osrm→custom: OSRM failed');
      return null;
    }

    final osrmPath = osrmResult.points;

    // Step 4: Route through custom graph from endpoint to destination
    final customPath = customRepo.graph.shortestPath(bestEntryIdx, destVertexIdx);

    if (customPath.isEmpty) {
      debugPrint('[SpaceProvider] osrm→custom: no graph path $bestEntryIdx → $destVertexIdx');
      return [...osrmPath, destination];
    }

    final combined = <LatLng>[
      ...osrmPath,
      for (final idx in customPath) customRepo.graph.getVertexPosition(idx),
      destination,
    ];

    debugPrint(
      '[SpaceProvider] osrm→custom: ${osrmPath.length} OSRM + '
      '${customPath.length} custom = ${combined.length} total',
    );
    return combined;
  }

  /// Clears the currently displayed navigation route.
  @override
  void clearNavigationRoute() {
    if (_navigationRouteStatus != NavigationRouteStatus.idle ||
        _activeNavigationRoute != null ||
        _navigationRouteErrorMessage != null) {
      _navigationRouteRequestId++;
      _resetNavigationRouteState();
      notifyListeners();
    }
  }

  /// Building-exit context release (MASTER PLAN PHASE 3, INV-9 route-safety
  /// half; full policy lands in Phases 10–11).
  ///
  /// Clears indoor BROWSING residency — floor selection, POIs, floorplan,
  /// radiomap — without ever touching route/session/destination fields.
  /// Unlike [clearSelection] this keeps the selected building so map context
  /// and exit-detection fallbacks remain stable.
  @override
  void releaseIndoorContextForNavigation() {
    debugPrint(
      '[SpaceProvider] releaseIndoorContextForNavigation (route preserved)',
    );
    _radioMapRequestId++;
    _floorplanRequestId++;
    _poiRequestId++;
    _selectedFloor = null;
    _selectedPoi = null;
    _resetRadioMapState();
    _resetFloorplanState();
    _resetPoiState();
    notifyListeners();
  }

  /// Retarget support (MASTER PLAN PHASE 4).
  ///
  /// Selects the destination context exclusively through navigation-safe
  /// variants (never resetting navigation fields), then runs the initial
  /// route cascade — reusing its request-id machinery unchanged. Returns
  /// true when a renderable route for [target] is in the store afterwards.
  @override
  Future<bool> requestRouteForRetarget(PoiModel target) async {
    final building =
        _spaces.where((s) => s.buid == target.buid).firstOrNull;
    if (building == null) {
      debugPrint(
          '[SpaceProvider] retarget: building ${target.buid} not loaded');
      return false;
    }
    _selectSpaceInternal(building, resetNavigationFields: false);
    await loadFloorsForSelectedSpace();
    final floor = _floors
            .where((f) => f.floorNumber == target.floorNumber)
            .firstOrNull ??
        _floors.where((f) => f.floorNumber == '0').firstOrNull ??
        (_floors.isEmpty
            ? null
            : _floors.reduce((a, b) =>
                a.numericFloor <= b.numericFloor ? a : b));
    if (floor != null) {
      _selectFloorInternal(floor, resetNavigationFields: false);
    }
    // Selecting the new target POI must not trip the legacy reset even when
    // idle-guard logic changes later; the session liveness guard already
    // covers it, this is belt-and-braces for the retarget window.
    _selectedPoi = target;
    notifyListeners();

    await requestRouteToSelectedPoi();
    final ok = _navigationRouteStatus == NavigationRouteStatus.ready &&
        _activeNavigationRoute != null &&
        _activeNavigationRoute!.hasRenderablePath;
    debugPrint('[SpaceProvider] requestRouteForRetarget(${target.puid}) '
        '-> ${ok ? "ready" : "failed"}');
    return ok;
  }

  /// O→I handoff guidance refresh (MASTER PLAN PHASE 8).
  ///
  /// Narrow wrapper reusing the cascade pieces: waits (bounded) for RadioMap
  /// readiness of the confirmed scope, then anchors an indoor POI-to-POI
  /// request on the nearest known POI of that scope. The candidate is
  /// returned uncommitted — the controller owns the fenced write-through.
  @override
  Future<NavigationRouteModel?> requestIndoorRouteForSession({
    required String destinationPuid,
    required String confirmedBuid,
    required String confirmedFloor,
  }) async {
    // Radiomap readiness gate: wait up to 20 s for the confirmed scope's map
    // to be resident/ready; proceed-with-null afterwards.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final ready = _activeRadioMapBuid == confirmedBuid &&
          _activeRadioMapFloor == confirmedFloor &&
          _radioMapStatus == RadioMapStatus.ready;
      if (ready) break;
      // Unsupported scope will never become ready — stop waiting early.
      if (_activeRadioMapBuid == confirmedBuid &&
          _activeRadioMapFloor == confirmedFloor &&
          _radioMapStatus == RadioMapStatus.unsupported) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // Anchor: nearest loaded POI on the confirmed scope, else nothing usable.
    PoiModel? anchor;
    var best = double.infinity;
    for (final p in _pois) {
      if (p.buid != confirmedBuid || p.puid == destinationPuid) continue;
      final d = Geolocator.distanceBetween(
        _locationProvider?.currentLocation?.latitude ?? p.latitude,
        _locationProvider?.currentLocation?.longitude ?? p.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < best) {
        best = d;
        anchor = p;
      }
    }
    if (anchor == null) return null;

    try {
      return await _navigationRepository.getRouteBetweenPois(
        fromPuid: anchor.puid,
        toPuid: destinationPuid,
      );
    } catch (e) {
      debugPrint('[SpaceProvider] requestIndoorRouteForSession failed: $e');
      return null;
    }
  }

  /// Session write-through (MASTER PLAN PHASE 2, INV-1/2/6).
  ///
  /// The single route store is replaced atomically for observers: one field
  /// assignment, status ready, error cleared, ONE notification. Browsing
  /// state (radiomap/floorplan/POIs) and destination bookkeeping are never
  /// touched here — during a live session only the navigation controller
  /// calls this.
  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    debugPrint('[SpaceProvider] adoptNavigatedRoute (session write-through)');
    _activeNavigationRoute = route;
    _navigationRouteStatus = NavigationRouteStatus.ready;
    _navigationRouteErrorMessage = null;
    notifyListeners();
  }

  /// Requests a route from the user's current location to [targetSpace].
  ///
  /// **Always produces a visible route** using a hybrid strategy:
  /// 1. Try Anyplace coordinate-based routing (works when inside/nearby).
  /// 2. Try POI-to-POI indoor routing (entrance Ã¢â€ â€™ interior).
  /// 3. Build a GPSÃ¢â€ â€™entrance outdoor polyline and merge with any indoor path.
  /// 4. Worst case: straight line from GPS to building center.
  Future<void> requestRouteToBuilding(SpaceModel targetSpace) async {
    final locationProvider = _locationProvider;
    final currentLocation = locationProvider?.currentLocation;

    if (locationProvider == null || currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      notifyListeners();
      return;
    }

    debugPrint(
      '[SpaceProvider] requestRouteToBuilding: ${targetSpace.name} '
      '(buid: ${targetSpace.buid}, user GPS: ${currentLocation.latitude},${currentLocation.longitude})',
    );

    // ── Cross-building / Outdoor→Indoor detection ──
    // Always try cross-building router when user is NOT in the same building.
    // The router handles both: user inside another building AND user outside all buildings.
    final userBuilding = _detectBuildingFromPolygon(currentLocation);
    final shouldTryCrossBuilding =
        userBuilding == null || userBuilding.buid != targetSpace.buid;

    if (shouldTryCrossBuilding) {
      debugPrint(
        '[SpaceProvider] Cross-building check: user ${userBuilding != null ? "in ${userBuilding.name}" : "outside"} → ${targetSpace.name}',
      );
      try {
        final crossRoute = await _crossBuildingRouter.composeRoute(
          userLocation: currentLocation.latLng,
          targetSpace: targetSpace,
          allBuildings: _spaces,
        );
        if (crossRoute != null) {
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = crossRoute;
          _navigationRouteErrorMessage = crossRoute.partialRouteWarning;
          notifyListeners();
          return;
        }
      } catch (e) {
        debugPrint('[SpaceProvider] Cross-building router failed: $e');
        // Fall through to existing cascade
      }
    }

    // Make sure this building is selected and floors are loaded
    if (_selectedSpace?.buid != targetSpace.buid) {
      selectSpace(targetSpace);
      await loadFloorsForSelectedSpace();
    }

    // Find ground floor or first floor
    final groundFloor = _floors.where((f) => f.floorNumber == '0').firstOrNull ??
        (_floors.isNotEmpty ? _floors.first : null);

    final String floorNumber = groundFloor?.floorNumber ?? '0';

    debugPrint('[SpaceProvider] requestRouteToBuilding: using floor $floorNumber');

    // Select the ground floor to load POIs
    if (groundFloor != null && _selectedFloor?.floorNumber != groundFloor.floorNumber) {
      selectFloor(groundFloor);
      await loadPoisForSelectedFloor();
    }

    debugPrint('[SpaceProvider] requestRouteToBuilding: ${_pois.length} POIs loaded');

    // Find entrance POI and any other interior POI
    final entrancePoi = _pois.where((p) =>
        p.isBuildingEntrance ||
        p.poisType.toLowerCase().contains('entrance')).firstOrNull;
    final targetPoi = entrancePoi ?? (_pois.isNotEmpty ? _pois.first : null);
    final interiorPoi = _pois.where((p) => p.puid != targetPoi?.puid).firstOrNull;

    // Destination for the route = entrance if found, else the building's own coordinates
    final destLatLng = targetPoi != null
        ? targetPoi.latLng
        : targetSpace.latLng;
    final destBuid = targetPoi?.buid ?? targetSpace.buid;

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = targetPoi?.puid;
    notifyListeners();

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 1: Coordinate-based routing (indoor / near building) Ã¢â€â‚¬Ã¢â€â‚¬
    if (targetPoi != null) {
      try {
        debugPrint('[SpaceProvider] Strategy 1: coordinate-based routing...');
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
          floorNumber: floorNumber,
          destinationPuid: targetPoi.puid,
        );
        if (requestId != _navigationRouteRequestId) return;

        if (route.hasRenderablePath) {
          debugPrint('[SpaceProvider] Strategy 1 succeeded: ${route.points.length} points');
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = route;
          _navigationRouteErrorMessage = null;
          notifyListeners();
          return;
        }
        debugPrint('[SpaceProvider] Strategy 1 returned ${route.points.length} pts (need >=2)');
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 1 failed: ${e.message}');
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 1 error: $e');
      }
    }

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 2: POI-to-POI indoor route (entrance Ã¢â€ â€™ interior) Ã¢â€â‚¬Ã¢â€â‚¬
    NavigationRouteModel? indoorRoute;
    if (targetPoi != null && interiorPoi != null) {
      try {
        debugPrint(
          '[SpaceProvider] Strategy 2: POI-to-POI ${interiorPoi.puid} Ã¢â€ â€™ ${targetPoi.puid}',
        );
        indoorRoute = await _navigationRepository.getRouteBetweenPois(
          fromPuid: interiorPoi.puid,
          toPuid: targetPoi.puid,
        );
        if (requestId != _navigationRouteRequestId) return;

        if (indoorRoute.hasRenderablePath) {
          debugPrint('[SpaceProvider] Strategy 2 succeeded: ${indoorRoute.points.length} points');
        } else {
          debugPrint('[SpaceProvider] Strategy 2 returned ${indoorRoute.points.length} pts');
          indoorRoute = null;
        }
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 2 failed: ${e.message}');
        indoorRoute = null;
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceProvider] Strategy 2 error: $e');
        indoorRoute = null;
      }
    }

    // Ã¢â€â‚¬Ã¢â€â‚¬ Strategy 3: OSRM outdoor walking path + indoor route (ALWAYS produces a route) Ã¢â€â‚¬Ã¢â€â‚¬
    if (requestId != _navigationRouteRequestId) return;

    // Try custom KMZ routes first
    List<LatLng>? outdoorPath;
    if (_customRouteRepository.isLoaded) {
      // Step 1: Try pure custom graph routing
      final customPath = _customRouteRepository.findRoute(
        currentLocation.latLng,
        destLatLng,
      );
      if (customPath.length >= 2) {
        outdoorPath = customPath;
        debugPrint('[SpaceProvider] Strategy 3: using custom KMZ route (${outdoorPath.length} points)');
      } else {
        // Step 2: Try hybrid routing (edge-based snap)
        final hybridPath = _customRouteRepository.findHybridRoute(
          currentLocation.latLng,
          destLatLng,
          snapThreshold: 150.0,
        );
        if (hybridPath != null && hybridPath.length >= 2) {
          outdoorPath = hybridPath;
          debugPrint('[SpaceProvider] Strategy 3: using hybrid custom route (${outdoorPath.length} points)');
        }
      }
    }

    // Step 3: Try OSRM to nearest custom vertex + custom to destination
    if (outdoorPath == null && _customRouteRepository.isLoaded) {
      final osrmToCustomPath = await _buildOsrmToCustomRoute(
        currentLocation.latLng,
        destLatLng,
      );
      if (osrmToCustomPath != null && osrmToCustomPath.length >= 2) {
        outdoorPath = osrmToCustomPath;
        debugPrint('[SpaceProvider] Strategy 3: using OSRM->Custom route (${outdoorPath.length} points)');
      }
    }

    // Step 4: Fallback to OSRM if custom routes didn't produce a path
    if (outdoorPath == null) {
      final osrmPath = await AnyplaceApiClient.fetchOutdoorWalkingRoute(
        fromLat: currentLocation.latitude,
        fromLon: currentLocation.longitude,
        toLat: destLatLng.latitude,
        toLon: destLatLng.longitude,
      );

      if (osrmPath.length >= 2 && _customRouteRepository.isLoaded) {
        // Try OSRM + Custom tail splice
        final splicedPath = _customRouteRepository.spliceCustomTail(
          osrmPath,
          destLatLng,
          connectionThreshold: 150.0,
        );
        if (splicedPath != null) {
          outdoorPath = splicedPath;
          debugPrint('[SpaceProvider] Strategy 3: using OSRM+Custom splice (${outdoorPath.length} points)');
        } else {
          outdoorPath = osrmPath;
        }
      } else {
        outdoorPath = osrmPath;
      }
    }

    // Convert path to NavigationRoutePoints (marked as outdoor)
    final outdoorPoints = <NavigationRoutePoint>[];
    if (outdoorPath.length >= 2) {
      for (final pt in outdoorPath) {
        outdoorPoints.add(NavigationRoutePoint.outdoor(latitude: pt.latitude,
          longitude: pt.longitude));
      }
    } else {
      // Fallback: straight line if OSRM fails
      outdoorPoints.addAll([
        NavigationRoutePoint.outdoor(latitude: currentLocation.latitude,
          longitude: currentLocation.longitude),
        NavigationRoutePoint(
          latitude: destLatLng.latitude,
          longitude: destLatLng.longitude,
          puid: targetPoi?.puid ?? '__building_center__',
          buid: destBuid,
          floorNumber: floorNumber,
          poisType: targetPoi?.poisType ?? 'building',
        ),
      ]);
    }

    final hybridRoute = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: indoorRoute,
    );

    debugPrint(
      '[SpaceProvider] Strategy 3 (hybrid): ${hybridRoute.points.length} points '
      '(outdoor: ${outdoorPoints.length}, indoor: ${indoorRoute?.points.length ?? 0})',
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = hybridRoute;
    _navigationRouteErrorMessage = null;
    notifyListeners();
  }

  /// Fetches floors for the currently selected space.
  Future<void> loadFloorsForSelectedSpace({bool forceReload = false}) async {
    final targetBuid = _selectedSpace?.buid;
    debugPrint(
      '[SpaceProvider] loadFloorsForSelectedSpace: start for buid=$targetBuid (forceReload=$forceReload)',
    );

    if (targetBuid == null) {
      _floors = const [];
      _isLoadingFloors = false;
      return;
    }

    _isLoadingFloors = true;
    _floorsErrorMessage = null;
    notifyListeners();

    try {
      final fetchedFloors = await _withRetry(
        () => _repository.getFloorsByBuid(
          targetBuid,
          forceReload: forceReload,
        ),
        maxRetries: 1,
        label: 'loadFloors($targetBuid)',
      );

      // Verify that the building did not change while request was awaiting
      if (_selectedSpace?.buid == targetBuid) {
        _floors = fetchedFloors;
        _floorsErrorMessage = null;
        debugPrint(
          '[SpaceProvider] loadFloorsForSelectedSpace: successfully set ${fetchedFloors.length} floors for $targetBuid',
        );
      } else {
        debugPrint(
          '[SpaceProvider] loadFloorsForSelectedSpace: building changed while loading ($targetBuid -> ${_selectedSpace?.buid}), ignoring result',
        );
      }
    } on ApiException catch (e) {
      debugPrint(
        '[SpaceProvider] loadFloorsForSelectedSpace ApiException: ${e.message}',
      );
      if (_selectedSpace?.buid == targetBuid) {
        _floorsErrorMessage = e.message;
      }
    } catch (e) {
      debugPrint(
        '[SpaceProvider] loadFloorsForSelectedSpace unexpected error: $e',
      );
      if (_selectedSpace?.buid == targetBuid) {
        _floorsErrorMessage = 'Failed to load floors: $e';
      }
    } finally {
      if (_selectedSpace?.buid == targetBuid) {
        _isLoadingFloors = false;
        notifyListeners();
      }
    }
  }

  /// Acquires the RadioMap for the currently selected building and floor,
  /// saves it to local disk cache, and loads it into the native Kotlin positioning engine.
  Future<void> loadRadioMapForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace?.buid;
    final targetFloor = _selectedFloor?.floorNumber;

    if (targetBuid == null || targetFloor == null) {
      _resetRadioMapState();
      notifyListeners();
      return;
    }

    final int requestId = ++_radioMapRequestId;

    _radioMapStatus = RadioMapStatus.loading;
    _radioMapErrorMessage = null;
    _isRadioMapCached = await _radioMapRepository.isRadioMapCached(
      targetBuid,
      targetFloor,
    );
    notifyListeners();

    debugPrint(
      '[SpaceProvider] loadRadioMap: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor (cached=$_isRadioMapCached)',
    );

    try {
      final radiomapContent = await _radioMapRepository.getRadioMap(
        targetBuid,
        targetFloor,
        forceReload: forceReload,
      );

      // Verify request is still fresh and selections haven't changed
      if (requestId != _radioMapRequestId ||
          _selectedSpace?.buid != targetBuid ||
          _selectedFloor?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceProvider] Stale RadioMap request $requestId discarded (current: $_radioMapRequestId)',
        );
        return;
      }

      // Load radiomap into native Kotlin positioning engine
      String? loadFailureReason;
      final loadedSuccessfully = await _nativePositioningService.loadRadioMap(
        radiomapContent,
        targetBuid,
        targetFloor,
        onFailureDetail: (detail) => loadFailureReason = detail,
      );

      if (loadedSuccessfully) {
        _radioMapStatus = RadioMapStatus.ready;
        _activeRadioMapBuid = targetBuid;
        _activeRadioMapFloor = targetFloor;
        _radioMapErrorMessage = null;
        _isRadioMapCached = true;
        debugPrint(
          '[SpaceProvider] RadioMap successfully loaded into native engine for $targetBuid / Floor $targetFloor',
        );
      } else {
        _radioMapStatus = RadioMapStatus.error;
        _radioMapErrorMessage =
            loadFailureReason ?? 'Native engine rejected RadioMap format.';
        // Targeted eviction: only this floor's map is removed; other resident
        // RadioMaps keep serving positioning.
        await _nativePositioningService.removeRadioMap(targetBuid, targetFloor);
      }
    } on ApiException catch (e) {
      if (requestId != _radioMapRequestId) return;

      final msg = e.message.toLowerCase();
      if (msg.contains('not supported') ||
          msg.contains('cannot find') ||
          msg.contains('404') ||
          e.statusCode == 400 ||
          e.statusCode == 404) {
        _radioMapStatus = RadioMapStatus.unsupported;
        _radioMapErrorMessage = 'No RadioMap available for this floor.';
        debugPrint(
          '[SpaceProvider] No RadioMap available for $targetBuid / Floor $targetFloor',
        );
      } else {
        _radioMapStatus = RadioMapStatus.error;
        _radioMapErrorMessage = e.message;
        debugPrint(
          '[SpaceProvider] RadioMap API error for $targetBuid / Floor $targetFloor: ${e.message}',
        );
      }
      // Targeted eviction: only this floor's map is affected by the failure.
      await _nativePositioningService.removeRadioMap(targetBuid, targetFloor);
    } catch (e) {
      if (requestId != _radioMapRequestId) return;
      _radioMapStatus = RadioMapStatus.error;
      _radioMapErrorMessage = 'Error loading RadioMap: $e';
      debugPrint(
        '[SpaceProvider] Unexpected RadioMap error for $targetBuid / Floor $targetFloor: $e',
      );
      // Targeted eviction: only this floor's map is affected by the failure.
      await _nativePositioningService.removeRadioMap(targetBuid, targetFloor);
    } finally {
      if (requestId == _radioMapRequestId) {
        notifyListeners();
      }
    }
  }

  /// Acquires the visual floorplan image for the currently selected building and floor,
  /// saves it to local disk cache, and prepares the map layer for rendering.
  Future<void> loadFloorplanForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace?.buid;
    final currentFloor = _selectedFloor;
    final targetFloor = currentFloor?.floorNumber;

    if (targetBuid == null || targetFloor == null || currentFloor == null) {
      _resetFloorplanState();
      notifyListeners();
      return;
    }

    final int requestId = ++_floorplanRequestId;

    _floorplanStatus = FloorplanStatus.loading;
    _floorplanErrorMessage = null;
    notifyListeners();

    debugPrint(
      '[SpaceProvider] loadFloorplan: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor',
    );

    try {
      final floorplan = await _floorplanRepository.getFloorplan(
        targetBuid,
        targetFloor,
        currentFloor,
        forceReload: forceReload,
      );

      // Verify request is still fresh and selections haven't changed
      if (requestId != _floorplanRequestId ||
          _selectedSpace?.buid != targetBuid ||
          _selectedFloor?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceProvider] Stale Floorplan request $requestId discarded (current: $_floorplanRequestId)',
        );
        return;
      }

if (floorplan != null) {
      // If floorplan has invalid bounds (e.g. 0.0 from missing API data),
      // use the building's location as fallback center with a small offset
      // so the floor map renders on the map even when the backend does not
      // provide explicit geographic bounds.
      final hasValid = floorplan.hasValidBounds;
      final buildingLat = _selectedSpace?.latitude ?? 0.0;
      final buildingLng = _selectedSpace?.longitude ?? 0.0;
      final epsilon = 0.01; // ~1.1km at equator, reasonable default floor map size when API does not provide bounds
      final floorplanWithValidBounds = hasValid
          ? floorplan
          : floorplan.copyWith(
              bottomLeftLat: buildingLat - epsilon,
              bottomLeftLng: buildingLng - epsilon,
              topRightLat: buildingLat + epsilon,
              topRightLng: buildingLng + epsilon,
            );

      _activeFloorplan = floorplanWithValidBounds;
      _floorplanStatus = FloorplanStatus.ready;
      _floorplanErrorMessage = null;
      debugPrint(
        '[SpaceProvider] Floorplan ready for $targetBuid / Floor $targetFloor '
        '(${floorplan.imageSizeBytes} bytes, bounds ${hasValid ? 'from API' : 'fallback applied'}',
      );
    } else {
      _activeFloorplan = null;
      _floorplanStatus = FloorplanStatus.unsupported;
      _floorplanErrorMessage = 'No floorplan image available for this floor.';
    }
    } on ApiException catch (e) {
      if (requestId != _floorplanRequestId) return;

      final msg = e.message.toLowerCase();
      if (msg.contains('not found') ||
          msg.contains('404') ||
          e.statusCode == 404 ||
          e.statusCode == 400) {
        _activeFloorplan = null;
        _floorplanStatus = FloorplanStatus.unsupported;
        _floorplanErrorMessage = 'No floorplan image available for this floor.';
        debugPrint(
          '[SpaceProvider] No floorplan image for $targetBuid / Floor $targetFloor',
        );
      } else {
        _activeFloorplan = null;
        _floorplanStatus = FloorplanStatus.error;
        _floorplanErrorMessage = e.message;
        debugPrint(
          '[SpaceProvider] Floorplan API error for $targetBuid / Floor $targetFloor: ${e.message}',
        );
      }
    } catch (e) {
      if (requestId != _floorplanRequestId) return;
      _activeFloorplan = null;
      _floorplanStatus = FloorplanStatus.error;
      _floorplanErrorMessage = 'Error loading floorplan: $e';
      debugPrint(
        '[SpaceProvider] Unexpected floorplan error for $targetBuid / Floor $targetFloor: $e',
      );
    } finally {
      if (requestId == _floorplanRequestId) {
        notifyListeners();
      }
    }
  }

  /// Acquires POIs for the currently selected building and floor,
  /// saves them to local disk cache, and prepares markers for rendering.
  Future<void> loadPoisForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace?.buid;
    final targetFloor = _selectedFloor?.floorNumber;

    if (targetBuid == null || targetFloor == null) {
      _resetPoiState();
      notifyListeners();
      return;
    }

    final int requestId = ++_poiRequestId;

    _poiStatus = PoiStatus.loading;
    _poiErrorMessage = null;
    notifyListeners();

    debugPrint(
      '[SpaceProvider] loadPois: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor',
    );

    try {
      final fetchedPois = await _withRetry(
        () => _poiRepository.getPoisByFloor(
          targetBuid,
          targetFloor,
          forceReload: forceReload,
        ),
        maxRetries: 1,
        label: 'loadPois($targetBuid/F$targetFloor)',
      );

      // Verify request is still fresh and selections haven't changed
      if (requestId != _poiRequestId ||
          _selectedSpace?.buid != targetBuid ||
          _selectedFloor?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceProvider] Stale POI request $requestId discarded (current: $_poiRequestId)',
        );
        return;
      }

      _pois = fetchedPois;
      _poiStatus = PoiStatus.ready;
      _poiErrorMessage = null;
      debugPrint(
        '[SpaceProvider] Successfully loaded ${fetchedPois.length} POIs for $targetBuid / Floor $targetFloor',
      );
    } on ApiException catch (e) {
      if (requestId != _poiRequestId) return;
      _pois = const [];
      _poiStatus = PoiStatus.error;
      _poiErrorMessage = e.message;
      debugPrint(
        '[SpaceProvider] POI API error for $targetBuid / Floor $targetFloor: ${e.message}',
      );
    } catch (e) {
      if (requestId != _poiRequestId) return;
      _pois = const [];
      _poiStatus = PoiStatus.error;
      _poiErrorMessage = 'Error loading POIs: $e';
      debugPrint(
        '[SpaceProvider] Unexpected POI error for $targetBuid / Floor $targetFloor: $e',
      );
    } finally {
      if (requestId == _poiRequestId) {
        notifyListeners();
      }
    }
  }

  void _resetRadioMapState() {
    _radioMapStatus = RadioMapStatus.idle;
    _radioMapErrorMessage = null;
    _activeRadioMapBuid = null;
    _activeRadioMapFloor = null;
    _isRadioMapCached = false;
    _nativePositioningService.clearRadioMap();
  }

  void _resetFloorplanState() {
    _floorplanStatus = FloorplanStatus.idle;
    _floorplanErrorMessage = null;
    _activeFloorplan = null;
  }

  void _resetPoiState() {
    _poiStatus = PoiStatus.idle;
    _pois = const [];
    _selectedPoi = null;
    _poiErrorMessage = null;
  }

  void _resetNavigationRouteState() {
    _navigationRouteStatus = NavigationRouteStatus.idle;
    _activeNavigationRoute = null;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
  }

  /// Clears the building-level error message.
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  /// Clears the floor-level error message.
  void clearFloorsError() {
    if (_floorsErrorMessage != null) {
      _floorsErrorMessage = null;
      notifyListeners();
    }
  }

  /// Clears the radiomap-level error message.
  void clearRadioMapError() {
    if (_radioMapErrorMessage != null) {
      _radioMapErrorMessage = null;
      notifyListeners();
    }
  }

  /// Clears the floorplan-level error message.
  void clearFloorplanError() {
    if (_floorplanErrorMessage != null) {
      _floorplanErrorMessage = null;
      notifyListeners();
    }
  }

  /// Clears the POI-level error message.
  void clearPoiError() {
    if (_poiErrorMessage != null) {
      _poiErrorMessage = null;
      notifyListeners();
    }
  }

  /// Clears the navigation route-level error message.
  void clearNavigationRouteError() {
    if (_navigationRouteErrorMessage != null) {
      _navigationRouteErrorMessage = null;
      notifyListeners();
    }
  }

  /// Progressive background sync: fetches floors + POIs for all buildings
  /// and indexes them into [searchService]. Uses batched concurrency to avoid
  /// flooding the network or blocking the main thread.
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {
    searchService.markSyncStarted(_spaces.length);

    const int batchSize = 3;
    int processed = 0;

    for (int i = 0; i < _spaces.length; i += batchSize) {
      // Respect user-action pause
      while (_batchPaused) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final batch = _spaces.sublist(
        i,
        (i + batchSize > _spaces.length) ? _spaces.length : i + batchSize,
      );

      // Fetch floors for all buildings in this batch concurrently
      final floorResults = await Future.wait(
        batch.map((space) async {
          try {
            final floors = await _repository.getFloorsByBuid(space.buid);
            return _FloorFetchResult(space.buid, floors, null);
          } catch (e) {
            return _FloorFetchResult(space.buid, const [], e);
          }
        }),
        eagerError: false,
      );

      // Process floor results and fetch POIs per building SEQUENTIALLY
      for (final result in floorResults) {
        // Check pause between each building
        while (_batchPaused) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (result.error == null && result.floors.isNotEmpty) {
          searchService.addFloors(result.buid, result.floors);

          // Fetch POIs for each floor sequentially (not all at once)
          for (final floor in result.floors) {
            try {
              final pois = await _poiRepository.getPoisByFloor(
                result.buid,
                floor.floorNumber,
              );
              searchService.addPois(result.buid, floor.floorNumber, pois);
            } catch (e) {
              debugPrint(
                '[SpaceProvider] loadAllFloorsAndPois: POI fetch failed for '
                '${result.buid}/F${floor.floorNumber}: $e',
              );
            }
          }
        }

        processed++;
        searchService.markSyncProgress(processed);
      }

      // Yield to event loop between batches (200ms to avoid server overload)
      await Future.delayed(const Duration(milliseconds: 200));
    }

    searchService.markSyncComplete();
  }

  /// Checks if a [position] is inside a building's bounding box.
  /// Uses a simple radius check from the building centroid.
  bool _isPositionInBuilding(LatLng position, String buildingBuid) {
    final building = _spaces.firstWhere(
      (s) => s.buid == buildingBuid,
      orElse: () => const SpaceModel(
        buid: '', name: '', latitude: 0, longitude: 0,
      ),
    );
    if (building.buid.isEmpty) return false;

    // Simple distance check: if within 100m of building centroid, consider inside
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      building.latitude,
      building.longitude,
    );
    return distance < 100; // 100m radius threshold
  }

  /// Detects which building the user is inside by checking distance to all buildings.
  /// Returns the closest building if within 100m, or null if outdoors.
  SpaceModel? _detectBuildingFromPolygon(UserLocation userLocation) {
    SpaceModel? closestBuilding;
    double closestDistance = double.infinity;

    for (final building in _spaces) {
      final distance = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        building.latitude,
        building.longitude,
      );
      if (distance < 100 && distance < closestDistance) {
        closestDistance = distance;
        closestBuilding = building;
      }
    }

    return closestBuilding;
  }
}

class _FloorFetchResult {
  final String buid;
  final List<FloorModel> floors;
  final Object? error;
  _FloorFetchResult(this.buid, this.floors, this.error);
}

