import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../config/constants.dart';
import '../data/datasources/anyplace_api_client.dart';
import '../data/datasources/gate_policy_config.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/floor_model.dart';
import '../data/models/campus_gate.dart';
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
import '../data/repositories/campus_gate_repository.dart';
import '../data/repositories/custom_route_repository.dart';
import '../data/models/user_location.dart';
import '../services/search_service.dart';
import '../services/cache_service.dart';
import '../services/building_containment.dart';
import '../utils/campus_scope.dart';
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
  final CampusGateRepository _campusGateRepository = CampusGateRepository();
  final GatePolicyConfigLoader _gatePolicyConfigLoader = GatePolicyConfigLoader();
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

  // Building → floors index for building-containment (route classification).
  // Additional data used ONLY by BuildingContainment; it is deliberately
  // independent of (and never overwrites) the selected-floor state above.
  // Populated for the selected building on floor load and for every building
  // during loadAllFloorsAndPois. Server-real FloorModel bounds are the sole
  // accepted geometry — the FloorplanModel "epsilon" fallback is never stored
  // here, so it can never reach building classification.
  final Map<String, List<FloorModel>> _floorsByBuid = {};

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

  // Campus Gate state
  //
  // Gates are CAMPUS-SCOPED entities (from university gates.kmz), deliberately
  // independent of the floor-scoped POI pipeline. Only the id of the currently
  // shown gate is stored on the provider; the authoritative list and
  // coordinates stay on the private CampusGateRepository.
  CampusGate? _selectedGate;

  // Navigation Route State
  NavigationRouteStatus _navigationRouteStatus = NavigationRouteStatus.idle;
  NavigationRouteModel? _activeNavigationRoute;
  String? _navigationRouteErrorMessage;
  String? _navigationDestinationPuid;
  int _navigationRouteRequestId = 0;
  LocationProvider? _locationProvider;

  // Batch loading pause flag (user action priority)
  bool _batchPaused = false;

  // Fallback center used ONLY when the app has no GPS fix and no selection.
  //
  // SERVER MIGRATION: was the Cyprus centroid of the old UCY backend; now
  // the centroid of the six live E-JUST buildings on map.beout.ai (mean of
  // the actual /space/public payload coordinates).
  static const LatLng defaultCenter = LatLng(30.859877, 29.563241);

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
      // Memory-backed building→floors index, populated by
      // loadFloorsForSelectedSpace and loadAllFloorsAndPois. Buildings whose
      // floors are not yet indexed resolve as empty → BuildingContainment
      // reports unknown → never classified as inside (safe outdoor default).
      loadFloorsForBuilding: (buid) async =>
          _floorsByBuid[buid] ?? const <FloorModel>[],
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
      campusGateRepository: _campusGateRepository,
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

  /// SERVER MIGRATION: purges all on-disk dataset caches (POIs, floorplans,
  /// radiomaps) that may still hold files from the previous backend. Safe to
  /// call repeatedly. Uses each repository's EXISTING clear-all method — no
  /// cache-system redesign. Old entries were keyed by old-server buids and
  /// could never be served again, so this only reclaims space and guarantees
  /// zero stale-data leakage.
  Future<void> purgeDatasetCaches() async {
    debugPrint('[SpaceProvider] purgeDatasetCaches: clearing POIs / '
        'floorplans / radiomaps from previous backend');
    try {
      await _poiRepository.clearAll();
    } catch (e) {
      debugPrint('[SpaceProvider] purgeDatasetCaches: pois clear failed: $e');
    }
    try {
      await _floorplanRepository.clearAll();
    } catch (e) {
      debugPrint(
          '[SpaceProvider] purgeDatasetCaches: floorplans clear failed: $e');
    }
    try {
      await _radioMapRepository.clearAllCache();
    } catch (e) {
      debugPrint(
          '[SpaceProvider] purgeDatasetCaches: radiomaps clear failed: $e');
    }
  }

  /// Loads custom KMZ routes AND campus gates from bundled assets.
  ///
  /// Should be called once during app startup, after spaces are loaded.
  /// Safe to call multiple times (no-op if already loaded).
  Future<void> loadCustomRoutes() async {
    debugPrint('[SpaceProvider] loadCustomRoutes: starting (isLoaded=${_customRouteRepository.isLoaded})');
    if (!_customRouteRepository.isLoaded) {
      await _customRouteRepository.loadRoutes();
      debugPrint('[SpaceProvider] loadCustomRoutes: routes loaded=${_customRouteRepository.isLoaded}, routes=${_customRouteRepository.routes.length}');
    }
    // Load the campus gate data (from university gates.kmz) alongside the
    // road network so the routing policy can select a preferred gate.
    if (!_campusGateRepository.isLoaded) {
      await _campusGateRepository.load();
      debugPrint('[SpaceProvider] loadCustomRoutes: gates loaded=${_campusGateRepository.isLoaded}, gates=${_campusGateRepository.gates.length}');
    }
    // Load the gate routing policy (preferred + disabled gate ids) from
    // gate_policy.json and apply it to the repository. The policy contains
    // gate IDs only — never coordinates (those come exclusively from the KMZ).
    try {
      final policy = await _gatePolicyConfigLoader.load();
      _campusGateRepository.setPreferredGatePolicy(
        preferredGateId: policy.preferredGateId,
        disabledGateIds: policy.disabledGateIds,
      );
      debugPrint(
        '[SpaceProvider] loadCustomRoutes: gate policy applied '
        'preferred=${policy.preferredGateId}, disabled=${policy.disabledGateIds}',
      );
    } catch (e) {
      debugPrint(
          '[SpaceProvider] loadCustomRoutes: gate policy load failed '
          '(non-fatal): $e');
    }
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

  // Campus Gate Getters
  //
  // Exposes the authoritative gate list (coordinates + ids from
  // university gates.kmz) without exposing the mutable repository. The list is
  // unmodifiable, so callers can never mutate internal gate state. Disabled /
  // non-preferred gates are still returned here — "visible" is independent of
  // the routing policy that decides which gate is the automatic preferred
  // entry point.
  List<CampusGate> get campusGates => _campusGateRepository.gates;
  CampusGate? get selectedGate => _selectedGate;
  bool get hasSelectedGate => _selectedGate != null;

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
      // E-JUST GLOBAL SCOPE: keep only the active campus's buildings. This
      // is the SINGLE filtering point — the panel list, map building
      // markers, search index and service scoping all consume `_spaces`,
      // so floors/POIs (loaded per in-scope buid) inherit the scope
      // structurally. See utils/campus_scope.dart.
      _spaces = CampusScope.filterSpaces(fetched);
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
      _selectedGate = null;
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
      _selectedGate = null;
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
    _selectedGate = null;
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
        _resetNavigationRouteState();
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
        // Same-building indoor geometry adopts the segmented indoorRouting
        // representation so it renders with the same intended indoor style
        // as composed cross-building journeys (geometry untouched).
        _activeNavigationRoute = route.toSegmentedIndoor(
          fallbackBuildingId: poi.buid,
          instruction: 'Head to ${poi.name}',
        );
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
          // Representation unification — see Strategy 1 commit above.
          _activeNavigationRoute = route.toSegmentedIndoor(
            fallbackBuildingId: poi.buid,
            instruction: 'Head to ${poi.name}',
          );
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

    // T5.6 / L8: if the user is ALREADY inside the destination building, do
    // NOT synthesize a spurious outdoor OSRM/custom leg. Strategy 1/2 having
    // failed means coordinate/POI routing was unavailable, so we keep the route
    // purely indoor (entrance→target geometry) instead of a false "walk
    // outside" from an indoor position.
    final bool insideDestination =
        _isPositionInBuilding(currentLocation.latLng, poi.buid);

    // ── Strategy 3 outdoor leg (skipped when already indoors) ──
    List<LatLng>? outdoorPath;
    if (!insideDestination) {
      // Try custom KMZ routes first
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
            snapThreshold: 250.0,
          );
          if (hybridPath != null && hybridPath.length >= 2) {
            outdoorPath = hybridPath;
            debugPrint('[SpaceProvider] Strategy 3: using hybrid custom route (${outdoorPath.length} points)');
          }
        }
      }

      // Step 3: Try OSRM to nearest custom vertex + custom to destination
      if (outdoorPath == null && _customRouteRepository.isLoaded) {
        final gate = _campusGateRepository.preferredGate();
        final osrmToCustomPath = await _buildOsrmToCustomRoute(
          currentLocation.latLng,
          destLatLng,
          gateEntry: gate,
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
    }

    final outdoorPoints = <NavigationRoutePoint>[];
    if (outdoorPath != null && outdoorPath.length >= 2) {
      for (final pt in outdoorPath) {
        outdoorPoints.add(NavigationRoutePoint.outdoor(latitude: pt.latitude,
          longitude: pt.longitude));
      }
    } else if (!insideDestination) {
      // Fallback: straight line if OSRM fails (only when an outdoor leg was
      // actually warranted).
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
    // When insideDestination, outdoorPoints stays empty → the hybrid route
    // below is purely indoor.

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
  ///
  /// When a preferred [CampusGate] is configured, the OSRM leg is routed to
  /// that gate and the campus road graph is entered at the gate's nearest
  /// vertex — `outside → preferred gate → campus roads → destination`.
  Future<List<LatLng>?> _buildOsrmToCustomRoute(
    LatLng userLocation,
    LatLng destination, {
    CampusGate? gateEntry,
  }) async {
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
      '${destVertex.$2.toStringAsFixed(0)}m from destination, '
      'gate=${gateEntry?.id ?? "none"}',
    );

    // Step 1: When a configured gate is provided, enter the campus road graph
    // at the graph vertex nearest the gate and drive OSRM to that exact gate.
    int? bestEntryIdx;
    if (gateEntry != null) {
      final gateVertex = customRepo.graph.nearestVertex(
        LatLng(gateEntry.latitude, gateEntry.longitude),
        maxDistance: 750.0,
      );
      if (gateVertex == null) {
        debugPrint(
          '[SpaceProvider] osrm→custom: gate ${gateEntry.id} is not near the '
          'campus road graph; falling back to endpoint logic',
        );
      } else {
        bestEntryIdx = gateVertex.$1;
        debugPrint(
          '[SpaceProvider] osrm→custom: gate ${gateEntry.id} snapped to graph '
          'vertex $bestEntryIdx (${gateVertex.$2.toStringAsFixed(0)}m from gate)',
        );
      }
    }

    // Step 1b: Route endpoints (campus road entrances on public roads)
    final endpoints = customRepo.graph.getRouteEndpoints();
    debugPrint('[SpaceProvider] osrm→custom: ${endpoints.length} route endpoints');

    if (endpoints.isEmpty && bestEntryIdx == null) {
      debugPrint('[SpaceProvider] osrm→custom: no route endpoints');
      return null;
    }

    // Step 2: OSRM target = gate location when resolved, otherwise pick a
    // route endpoint (prefer one near the user that connects to the dest;
    // fall back to the endpoint nearest the destination).
    LatLng entryPos;
    if (bestEntryIdx != null) {
      entryPos = LatLng(gateEntry!.latitude, gateEntry.longitude);
    } else {
      int? nearestToDestIdx;
      double nearestToDestDist = double.infinity;

      for (final (epIdx, epPos) in endpoints) {
        final distToDest = Geolocator.distanceBetween(
          destination.latitude,
          destination.longitude,
          epPos.latitude,
          epPos.longitude,
        );
        if (distToDest < nearestToDestDist) {
          nearestToDestDist = distToDest;
          nearestToDestIdx = epIdx;
        }
      }

      bestEntryIdx = nearestToDestIdx;
      if (bestEntryIdx == null) {
        debugPrint('[SpaceProvider] osrm→custom: no endpoints at all');
        return null;
      }
      entryPos = customRepo.graph.getVertexPosition(bestEntryIdx);

      final entryUserDist = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        entryPos.latitude,
        entryPos.longitude,
      );
      debugPrint(
        '[SpaceProvider] osrm→custom: best entry=$bestEntryIdx '
        '(${entryUserDist.toStringAsFixed(0)}m from user)',
      );
    }

    // Step 3: OSRM from user to the campus entrance (gate or endpoint)
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

    // Step 4: Route through custom graph from entry vertex to destination
    final customPath = customRepo.graph.shortestPath(bestEntryIdx, destVertexIdx);

    if (customPath.isEmpty) {
      debugPrint('[SpaceProvider] osrm→custom: no graph path $bestEntryIdx → $destVertexIdx; '
          'adding straight-line walk from entry to destination');
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
      '[SpaceProvider] releaseIndoorContextForNavigation (route preserved)',
    );
    _floorplanRequestId++;
    _poiRequestId++;
    _selectedPoi = null;
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
      final route = await _navigationRepository.getRouteBetweenPois(
        fromPuid: anchor.puid,
        toPuid: destinationPuid,
      );
      // Representation unification: a legitimately refetched indoor guidance
      // route renders through the same indoorRouting projection as composed
      // journeys instead of the legacy path.
      return route.toSegmentedIndoor(
        fallbackBuildingId: confirmedBuid,
        instruction: 'Head to your destination',
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

  /// UI/UX REDESIGN PHASE 2 — ADDITIVE custom-origin directions.
  ///
  /// Requests an indoor POI→POI route using the EXISTING repository API
  /// ([NavigationRepository.getRouteBetweenPois] — the identical call used by
  /// Strategy 2 of [requestRouteToSelectedPoi] and by the O→I handoff above).
  /// No routing logic is modified or duplicated here.
  ///
  /// Destination residency is set up through the navigation-safe selection
  /// variants (never resetting route fields), mirroring
  /// [requestRouteForRetarget]. A live session ends through the injected
  /// clean-restart bridge first — the same pattern as [navigateToPoi].
  ///
  /// Returns true when a renderable route for [target] is in the store.
  Future<bool> requestRouteBetweenPois(
    PoiModel origin,
    PoiModel target,
  ) async {
    if (_sessionLive) {
      debugPrint(
        '[SpaceProvider] requestRouteBetweenPois during live session — '
        'clean-restart bridge',
      );
      terminateActiveSessionForRetarget?.call();
    }

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = target.puid;
    notifyListeners();

    // Destination residency context (browsing state only, no field resets).
    final building = _spaces.where((s) => s.buid == target.buid).firstOrNull;
    if (building != null) {
      _selectSpaceInternal(building, resetNavigationFields: false);
      await loadFloorsForSelectedSpace();
      final floor = _floors
              .where((f) => f.floorNumber == target.floorNumber)
              .firstOrNull ??
          _floors.where((f) => f.floorNumber == '0').firstOrNull;
      if (floor != null) {
        _selectFloorInternal(floor, resetNavigationFields: false);
        await loadPoisForSelectedFloor();
      }
    }
    if (requestId != _navigationRouteRequestId) return false;

    try {
      final route = await _navigationRepository.getRouteBetweenPois(
        fromPuid: origin.puid,
        toPuid: target.puid,
      );
      if (requestId != _navigationRouteRequestId ||
          _navigationDestinationPuid != target.puid) {
        return false;
      }
      if (route.hasRenderablePath) {
        _navigationRouteStatus = NavigationRouteStatus.ready;
        _activeNavigationRoute = route.toSegmentedIndoor(
          fallbackBuildingId: target.buid,
          instruction: 'Head to ${target.name}',
        );
        _navigationRouteErrorMessage = null;
        _selectedPoi = target;
        notifyListeners();
        debugPrint('[SpaceProvider] requestRouteBetweenPois ready '
            '(${origin.puid} → ${target.puid})');
        return true;
      }
      _navigationRouteStatus = NavigationRouteStatus.unsupported;
      _navigationRouteErrorMessage =
          'No indoor route found between the selected places.';
      notifyListeners();
      return false;
    } on ApiException catch (e) {
      if (requestId != _navigationRouteRequestId) return false;
      final msg = e.message.toLowerCase();
      final unsupported = msg.contains('not supported') ||
          msg.contains('no route') ||
          msg.contains('not be connected') ||
          e.statusCode == 400 ||
          e.statusCode == 404;
      _navigationRouteStatus = unsupported
          ? NavigationRouteStatus.unsupported
          : NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      if (requestId != _navigationRouteRequestId) return false;
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = 'Error requesting route: $e';
      notifyListeners();
      return false;
    }
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
          // Representation unification — see requestRouteToSelectedPoi.
          _activeNavigationRoute = route.toSegmentedIndoor(
            fallbackBuildingId: targetSpace.buid,
            instruction: 'Enter ${targetSpace.name}',
          );
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
          snapThreshold: 250.0,
        );
        if (hybridPath != null && hybridPath.length >= 2) {
          outdoorPath = hybridPath;
          debugPrint('[SpaceProvider] Strategy 3: using hybrid custom route (${outdoorPath.length} points)');
        }
      }
    }

    // Step 3: Try OSRM to nearest custom vertex + custom to destination
    if (outdoorPath == null && _customRouteRepository.isLoaded) {
      final gate = _campusGateRepository.preferredGate();
      final osrmToCustomPath = await _buildOsrmToCustomRoute(
        currentLocation.latLng,
        destLatLng,
        gateEntry: gate,
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
  /// [_buildOsrmToCustomRoute] — so the preferred automatic entry gate (G2)
  /// is never forced as an intermediate point. Routing to a gate never changes
  /// the routing policy.
  Future<bool> requestRouteToGate(CampusGate gate) async {
    final locationProvider = _locationProvider;
    final currentLocation = locationProvider?.currentLocation;

    if (locationProvider == null || currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      notifyListeners();
      return false;
    }

    final destLatLng = LatLng(gate.latitude, gate.longitude);
    final fromLatLng = currentLocation.latLng;

    debugPrint(
      '[SpaceProvider] requestRouteToGate: ${gate.id} '
      '(destination: ${gate.latitude},${gate.longitude}, '
      'user GPS: ${currentLocation.latitude},${currentLocation.longitude})',
    );

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
    notifyListeners();

    List<LatLng>? outdoorPath;

    // Strategy 1: pure custom road-graph routing (both endpoints graph-near).
    if (_customRouteRepository.isLoaded) {
      final customPath =
          _customRouteRepository.findRoute(fromLatLng, destLatLng);
      if (customPath.length >= 2) {
        outdoorPath = customPath;
      } else {
        // Strategy 2: edge-based hybrid routing.
        final hybridPath = _customRouteRepository.findHybridRoute(
          fromLatLng,
          destLatLng,
          snapThreshold: 250.0,
        );
        if (hybridPath != null && hybridPath.length >= 2) {
          outdoorPath = hybridPath;
        }
      }
    }

    // Strategy 3: OSRM to a campus entry + custom graph to the gate.
    // No gateEntry is supplied — the gate IS the destination.
    if (outdoorPath == null && _customRouteRepository.isLoaded) {
      final osrmToCustomPath = await _buildOsrmToCustomRoute(
        fromLatLng,
        destLatLng,
        gateEntry: null,
      );
      if (osrmToCustomPath != null && osrmToCustomPath.length >= 2) {
        outdoorPath = osrmToCustomPath;
      }
    }

    // Strategy 4: OSRM fallback (with custom-tail splice when routes loaded).
    if (outdoorPath == null) {
      final osrmPath = await AnyplaceApiClient.fetchOutdoorWalkingRoute(
        fromLat: fromLatLng.latitude,
        fromLon: fromLatLng.longitude,
        toLat: destLatLng.latitude,
        toLon: destLatLng.longitude,
      );
      if (requestId != _navigationRouteRequestId) return false;
      if (osrmPath.length >= 2 && _customRouteRepository.isLoaded) {
        final splicedPath = _customRouteRepository.spliceCustomTail(
          osrmPath,
          destLatLng,
          connectionThreshold: 150.0,
        );
        outdoorPath = splicedPath ?? osrmPath;
      } else {
        outdoorPath = osrmPath;
      }
    }

    if (requestId != _navigationRouteRequestId) return false;

    if (outdoorPath.length < 2) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage =
          'Could not build a route to gate ${gate.id}.';
      debugPrint('[SpaceProvider] requestRouteToGate: no outdoor path found');
      notifyListeners();
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
    notifyListeners();

    debugPrint(
      '[SpaceProvider] requestRouteToGate: ${route.points.length} outdoor points',
    );
    return route.hasRenderablePath;
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
        _floorsByBuid[targetBuid] = List<FloorModel>.unmodifiable(fetchedFloors);
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

  // ── PHASE 11: Radiomap Lifecycle Contract ────────────────────────────
  //
  // LOAD     — on browsing selection AND on navigation preload (existing
  //            paths; request-id guarded, disk-cached).
  // RETAIN   — while its building could be re-entered later in the active
  //            session (building present in route segments OR exited < 10
  //            min ago). Enforced by NEVER calling the global native wipe
  //            from selection/exit paths; the native LRU (limit 4) manages
  //            natural pressure.
  // EVICT    — targeted `removeRadioMap(buid, floor)` when a load FAILS
  //            (existing loader behavior); session End intentionally leaves
  //            residency to LRU; explicit "clear offline data" is an app-
  //            level action and out of navigation scope.
  // GLOBAL WIPE — reserved for app-level resets (logout/storage) via
  //            [resetAllRadiomaps]; never invoked from selection APIs.
  //
  // Residency serves both browsing and navigation; neither may destroy the
  // other's requirements.

  /// Status-field reset only. The native engine's resident maps are left
  /// untouched so multi-building trips and return journeys keep sensing.
  void _resetRadioMapState() {
    _radioMapStatus = RadioMapStatus.idle;
    _radioMapErrorMessage = null;
    _activeRadioMapBuid = null;
    _activeRadioMapFloor = null;
    _isRadioMapCached = false;
  }

  /// True global wipe (app-level reset only: logout / storage clear).
  void resetAllRadiomaps() {
    _radioMapRequestId++;
    _resetRadioMapState();
    _nativePositioningService.clearRadioMap();
    notifyListeners();
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
          _floorsByBuid[result.buid] =
              List<FloorModel>.unmodifiable(result.floors);

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

  /// Checks if a [position] is inside [buildingBuid] using the canonical
  /// [BuildingContainment] service over that building's server-real floor
  /// bounds. Returns false for [BuildingContainmentStatus.unknown] (a building
  /// with no reliable geometry is never reported as inside).
  bool _isPositionInBuilding(LatLng position, String buildingBuid) {
    final floors = _floorsByBuid[buildingBuid] ?? const <FloorModel>[];
    return BuildingContainment.isInside(position, floors);
  }

  /// Detects which building the user is inside using the canonical
  /// [BuildingContainment] service over each building's server-real floor
  /// bounds. Returns null if the user is outside every building (or every
  /// building's geometry is unknown).
  ///
  /// Resolution among overlapping building rectangles is deterministic:
  /// the containing building whose matched floor bounds are the STRICTEST
  /// (smallest) wins, with a stable buid tie-break. No centroid/distance
  /// heuristic is applied.
  SpaceModel? _detectBuildingFromPolygon(UserLocation userLocation) {
    final point = userLocation.latLng;
    SpaceModel? result;
    double? bestSpan;
    String? bestBuid;

    for (final building in _spaces) {
      final floors = _floorsByBuid[building.buid] ?? const <FloorModel>[];
      final containment = BuildingContainment.classify(point, floors);
      if (!containment.isInside || containment.containingFloor == null) {
        continue;
      }
      final span = BuildingContainment.approxSpanMeters(
        containment.containingFloor!,
      );
      final better = result == null ||
          span < bestSpan! ||
          (span == bestSpan && building.buid.compareTo(bestBuid!) < 0);
      if (better) {
        result = building;
        bestSpan = span;
        bestBuid = building.buid;
      }
    }

    return result;
  }
}

class _FloorFetchResult {
  final String buid;
  final List<FloorModel> floors;
  final Object? error;
  _FloorFetchResult(this.buid, this.floors, this.error);
}

