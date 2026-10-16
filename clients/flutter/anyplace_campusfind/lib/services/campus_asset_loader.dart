import 'package:flutter/foundation.dart';

import '../datasources/anyplace_api_client.dart';
import '../datasources/native_positioning_service.dart';
import '../models/campus_asset_status.dart';
import '../models/floor_model.dart';
import '../models/floorplan_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../repositories/floorplan_repository.dart';
import '../repositories/poi_repository.dart';
import '../repositories/radiomap_repository.dart';
import '../repositories/space_repository.dart';
import '../utils/campus_scope.dart';
import '../utils/with_retry.dart';

/// Acquires and holds all campus browsing asset state: the public space
/// (building) list, the selected building's floors, the selected floor's
/// POIs, and the RadioMap + Floorplan assets for the selected building/floor.
///
/// Extracted from [SpaceViewModel]. Owns the fetch/status/request-id state for
/// each asset pipeline (spaces, floors, POIs, RadioMap, Floorplan); the
/// view model owns selection and feeds the current selection back through
/// the [selectedSpace]/[selectedFloor] accessors for staleness checks.
///
/// [resetPoiState] also clears the view model's selected-POI via
/// [onSelectedPoiCleared] — mirroring the legacy invariant that snapping POI
/// state empties the current POI selection.
class CampusAssetLoader {
  CampusAssetLoader({
    required SpaceRepository repository,
    required RadioMapRepository radioMapRepository,
    required FloorplanRepository floorplanRepository,
    required PoiRepository poiRepository,
    required NativePositioningService nativePositioningService,
    required void Function() notify,
    required SpaceModel? Function() selectedSpace,
    required FloorModel? Function() selectedFloor,
    required void Function(SpaceModel space) onSelectedSpaceRefresh,
    required void Function() onSelectedPoiCleared,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _repository = repository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _radioMapRepository = radioMapRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _floorplanRepository = floorplanRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _poiRepository = poiRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _nativePositioningService = nativePositioningService,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _notify = notify,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedSpace = selectedSpace,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedFloor = selectedFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onSelectedSpaceRefresh = onSelectedSpaceRefresh,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onSelectedPoiCleared = onSelectedPoiCleared;

  final SpaceRepository _repository;
  final RadioMapRepository _radioMapRepository;
  final FloorplanRepository _floorplanRepository;
  final PoiRepository _poiRepository;
  final NativePositioningService _nativePositioningService;
  final void Function() _notify;
  final SpaceModel? Function() _selectedSpace;
  final FloorModel? Function() _selectedFloor;
  final void Function(SpaceModel space) _onSelectedSpaceRefresh;
  final void Function() _onSelectedPoiCleared;

  List<SpaceModel> _spaces = const [];
  bool _isLoading = false;
  String? _errorMessage;

  // Floor State
  List<FloorModel> _floors = const [];
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
  String? _poiErrorMessage;
  int _poiRequestId = 0;

  List<SpaceModel> get spaces => _spaces;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<FloorModel> get floors => _floors;
  bool get isLoadingFloors => _isLoadingFloors;
  String? get floorsErrorMessage => _floorsErrorMessage;

  PoiStatus get poiStatus => _poiStatus;
  List<PoiModel> get pois => _pois;
  String? get poiErrorMessage => _poiErrorMessage;

  RadioMapStatus get radioMapStatus => _radioMapStatus;
  String? get radioMapErrorMessage => _radioMapErrorMessage;
  String? get activeRadioMapBuid => _activeRadioMapBuid;
  String? get activeRadioMapFloor => _activeRadioMapFloor;
  bool get isRadioMapCached => _isRadioMapCached;

  FloorplanStatus get floorplanStatus => _floorplanStatus;
  FloorplanModel? get activeFloorplan => _activeFloorplan;
  String? get floorplanErrorMessage => _floorplanErrorMessage;

  /// Floors indexed for [buid] by the floor loaders and the background
  /// search sync. Used by building-containment classification.
  List<FloorModel> floorsForBuilding(String buid) =>
      _floorsByBuid[buid] ?? const <FloorModel>[];

  /// Fetches POIs for [buid]/[floorNumber] from the repository (cross-building
  /// router callback path; callers own error handling).
  Future<List<PoiModel>> poisForBuildingFloor(
    String buid,
    String floorNumber,
  ) => _poiRepository.getPoisByFloor(buid, floorNumber);

  /// Fetches the floor numbers for [buid] from the repository (cross-building
  /// router callback path; callers own error handling).
  Future<List<String>> floorNumbersForBuilding(String buid) async =>
      (await _repository.getFloorsByBuid(buid)).map((f) => f.floorNumber).toList();

  /// SERVER MIGRATION: purges all on-disk dataset caches (POIs, floorplans,
  /// radiomaps) that may still hold files from the previous backend. Safe to
  /// call repeatedly. Uses each repository's EXISTING clear-all method — no
  /// cache-system redesign. Old entries were keyed by old-server buids and
  /// could never be served again, so this only reclaims space and guarantees
  /// zero stale-data leakage.
  Future<void> purgeDatasetCaches() async {
    debugPrint(
      '[SpaceViewModel] purgeDatasetCaches: clearing POIs / '
      'floorplans / radiomaps from previous backend',
    );
    try {
      await _poiRepository.clearAll();
    } catch (e) {
      debugPrint('[SpaceViewModel] purgeDatasetCaches: pois clear failed: $e');
    }
    try {
      await _floorplanRepository.clearAll();
    } catch (e) {
      debugPrint(
        '[SpaceViewModel] purgeDatasetCaches: floorplans clear failed: $e',
      );
    }
    try {
      await _radioMapRepository.clearAllCache();
    } catch (e) {
      debugPrint(
        '[SpaceViewModel] purgeDatasetCaches: radiomaps clear failed: $e',
      );
    }
  }

  /// Fetches public spaces from the Anyplace repository.
  Future<void> loadSpaces({bool forceReload = false}) async {
    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final fetched = await withRetry(
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
      if (_selectedSpace() != null) {
        _onSelectedSpaceRefresh(
          fetched.firstWhere(
            (s) => s.buid == _selectedSpace()!.buid,
            orElse: () => _selectedSpace()!,
          ),
        );
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to load campus spaces: $e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  /// Fetches floors for the currently selected space.
  Future<void> loadFloorsForSelectedSpace({bool forceReload = false}) async {
    final targetBuid = _selectedSpace()?.buid;
    debugPrint(
      '[SpaceViewModel] loadFloorsForSelectedSpace: start for buid=$targetBuid (forceReload=$forceReload)',
    );

    if (targetBuid == null) {
      _floors = const [];
      _isLoadingFloors = false;
      return;
    }

    _isLoadingFloors = true;
    _floorsErrorMessage = null;
    _notify();

    try {
      final fetchedFloors = await withRetry(
        () => _repository.getFloorsByBuid(targetBuid, forceReload: forceReload),
        maxRetries: 1,
        label: 'loadFloors($targetBuid)',
      );

      // Verify that the building did not change while request was awaiting
      if (_selectedSpace()?.buid == targetBuid) {
        _floors = fetchedFloors;
        _floorsByBuid[targetBuid] = List<FloorModel>.unmodifiable(
          fetchedFloors,
        );
        _floorsErrorMessage = null;
        debugPrint(
          '[SpaceViewModel] loadFloorsForSelectedSpace: successfully set ${fetchedFloors.length} floors for $targetBuid',
        );
      } else {
        debugPrint(
          '[SpaceViewModel] loadFloorsForSelectedSpace: building changed while loading ($targetBuid -> ${_selectedSpace()?.buid}), ignoring result',
        );
      }
    } on ApiException catch (e) {
      debugPrint(
        '[SpaceViewModel] loadFloorsForSelectedSpace ApiException: ${e.message}',
      );
      if (_selectedSpace()?.buid == targetBuid) {
        _floorsErrorMessage = e.message;
      }
    } catch (e) {
      debugPrint(
        '[SpaceViewModel] loadFloorsForSelectedSpace unexpected error: $e',
      );
      if (_selectedSpace()?.buid == targetBuid) {
        _floorsErrorMessage = 'Failed to load floors: $e';
      }
    } finally {
      if (_selectedSpace()?.buid == targetBuid) {
        _isLoadingFloors = false;
        _notify();
      }
    }
  }

  /// Acquires the RadioMap for the currently selected building and floor,
  /// saves it to local disk cache, and loads it into the native Kotlin positioning engine.
  Future<void> loadRadioMapForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace()?.buid;
    final targetFloor = _selectedFloor()?.floorNumber;

    if (targetBuid == null || targetFloor == null) {
      resetRadioMapState();
      _notify();
      return;
    }

    final int requestId = ++_radioMapRequestId;

    _radioMapStatus = RadioMapStatus.loading;
    _radioMapErrorMessage = null;
    _isRadioMapCached = await _radioMapRepository.isRadioMapCached(
      targetBuid,
      targetFloor,
    );
    _notify();

    debugPrint(
      '[SpaceViewModel] loadRadioMap: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor (cached=$_isRadioMapCached)',
    );

    try {
      final radiomapContent = await _radioMapRepository.getRadioMap(
        targetBuid,
        targetFloor,
        forceReload: forceReload,
      );

      // Verify request is still fresh and selections haven't changed
      if (requestId != _radioMapRequestId ||
          _selectedSpace()?.buid != targetBuid ||
          _selectedFloor()?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceViewModel] Stale RadioMap request $requestId discarded (current: $_radioMapRequestId)',
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
          '[SpaceViewModel] RadioMap successfully loaded into native engine for $targetBuid / Floor $targetFloor',
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
          '[SpaceViewModel] No RadioMap available for $targetBuid / Floor $targetFloor',
        );
      } else {
        _radioMapStatus = RadioMapStatus.error;
        _radioMapErrorMessage = e.message;
        debugPrint(
          '[SpaceViewModel] RadioMap API error for $targetBuid / Floor $targetFloor: ${e.message}',
        );
      }
      // Targeted eviction: only this floor's map is affected by the failure.
      await _nativePositioningService.removeRadioMap(targetBuid, targetFloor);
    } catch (e) {
      if (requestId != _radioMapRequestId) return;
      _radioMapStatus = RadioMapStatus.error;
      _radioMapErrorMessage = 'Error loading RadioMap: $e';
      debugPrint(
        '[SpaceViewModel] Unexpected RadioMap error for $targetBuid / Floor $targetFloor: $e',
      );
      // Targeted eviction: only this floor's map is affected by the failure.
      await _nativePositioningService.removeRadioMap(targetBuid, targetFloor);
    } finally {
      if (requestId == _radioMapRequestId) {
        _notify();
      }
    }
  }

  /// Acquires the visual floorplan image for the currently selected building and floor,
  /// saves it to local disk cache, and prepares the map layer for rendering.
  Future<void> loadFloorplanForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace()?.buid;
    final currentFloor = _selectedFloor();
    final targetFloor = currentFloor?.floorNumber;

    if (targetBuid == null || targetFloor == null || currentFloor == null) {
      resetFloorplanState();
      _notify();
      return;
    }

    final int requestId = ++_floorplanRequestId;

    _floorplanStatus = FloorplanStatus.loading;
    _floorplanErrorMessage = null;
    _notify();

    debugPrint(
      '[SpaceViewModel] loadFloorplan: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor',
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
          _selectedSpace()?.buid != targetBuid ||
          _selectedFloor()?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceViewModel] Stale Floorplan request $requestId discarded (current: $_floorplanRequestId)',
        );
        return;
      }

      if (floorplan != null) {
        // If floorplan has invalid bounds (e.g. 0.0 from missing API data),
        // use the building's location as fallback center with a small offset
        // so the floor map renders on the map even when the backend does not
        // provide explicit geographic bounds.
        final hasValid = floorplan.hasValidBounds;
        final buildingLat = _selectedSpace()?.latitude ?? 0.0;
        final buildingLng = _selectedSpace()?.longitude ?? 0.0;
        final epsilon =
            0.01; // ~1.1km at equator, reasonable default floor map size when API does not provide bounds
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
          '[SpaceViewModel] Floorplan ready for $targetBuid / Floor $targetFloor '
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
          '[SpaceViewModel] No floorplan image for $targetBuid / Floor $targetFloor',
        );
      } else {
        _activeFloorplan = null;
        _floorplanStatus = FloorplanStatus.error;
        _floorplanErrorMessage = e.message;
        debugPrint(
          '[SpaceViewModel] Floorplan API error for $targetBuid / Floor $targetFloor: ${e.message}',
        );
      }
    } catch (e) {
      if (requestId != _floorplanRequestId) return;
      _activeFloorplan = null;
      _floorplanStatus = FloorplanStatus.error;
      _floorplanErrorMessage = 'Error loading floorplan: $e';
      debugPrint(
        '[SpaceViewModel] Unexpected floorplan error for $targetBuid / Floor $targetFloor: $e',
      );
    } finally {
      if (requestId == _floorplanRequestId) {
        _notify();
      }
    }
  }

  /// Acquires POIs for the currently selected building and floor,
  /// saves them to local disk cache, and prepares markers for rendering.
  Future<void> loadPoisForSelectedFloor({bool forceReload = false}) async {
    final targetBuid = _selectedSpace()?.buid;
    final targetFloor = _selectedFloor()?.floorNumber;

    if (targetBuid == null || targetFloor == null) {
      resetPoiState();
      _notify();
      return;
    }

    final int requestId = ++_poiRequestId;

    _poiStatus = PoiStatus.loading;
    _poiErrorMessage = null;
    _notify();

    debugPrint(
      '[SpaceViewModel] loadPois: start requestId=$requestId for buid=$targetBuid, floor=$targetFloor',
    );

    try {
      final fetchedPois = await withRetry(
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
          _selectedSpace()?.buid != targetBuid ||
          _selectedFloor()?.floorNumber != targetFloor) {
        debugPrint(
          '[SpaceViewModel] Stale POI request $requestId discarded (current: $_poiRequestId)',
        );
        return;
      }

      _pois = fetchedPois;
      _poiStatus = PoiStatus.ready;
      _poiErrorMessage = null;
      debugPrint(
        '[SpaceViewModel] Successfully loaded ${fetchedPois.length} POIs for $targetBuid / Floor $targetFloor',
      );
    } on ApiException catch (e) {
      if (requestId != _poiRequestId) return;
      _pois = const [];
      _poiStatus = PoiStatus.error;
      _poiErrorMessage = e.message;
      debugPrint(
        '[SpaceViewModel] POI API error for $targetBuid / Floor $targetFloor: ${e.message}',
      );
    } catch (e) {
      if (requestId != _poiRequestId) return;
      _pois = const [];
      _poiStatus = PoiStatus.error;
      _poiErrorMessage = 'Error loading POIs: $e';
      debugPrint(
        '[SpaceViewModel] Unexpected POI error for $targetBuid / Floor $targetFloor: $e',
      );
    } finally {
      if (requestId == _poiRequestId) {
        _notify();
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
  void resetRadioMapState() {
    _radioMapStatus = RadioMapStatus.idle;
    _radioMapErrorMessage = null;
    _activeRadioMapBuid = null;
    _activeRadioMapFloor = null;
    _isRadioMapCached = false;
  }

  /// True global wipe (app-level reset only: logout / storage clear).
  void resetAllRadiomaps() {
    _radioMapRequestId++;
    resetRadioMapState();
    _nativePositioningService.clearRadioMap();
    _notify();
  }

  void resetFloorplanState() {
    _floorplanStatus = FloorplanStatus.idle;
    _floorplanErrorMessage = null;
    _activeFloorplan = null;
  }

  void resetPoiState() {
    _poiStatus = PoiStatus.idle;
    _pois = const [];
    _poiErrorMessage = null;
    _onSelectedPoiCleared();
  }

  /// Invalidates in-flight RadioMap requests (used on selection changes).
  void bumpRadioMapRequestId() {
    _radioMapRequestId++;
  }

  /// Invalidates in-flight Floorplan requests (used on selection changes).
  void bumpFloorplanRequestId() {
    _floorplanRequestId++;
  }

  /// Invalidates in-flight POI requests (used on selection changes).
  void bumpPoiRequestId() {
    _poiRequestId++;
  }

  /// Registers server-real floors for [buid] into the building-containment
  /// index (background sync path).
  void indexFloors(String buid, List<FloorModel> floors) {
    _floorsByBuid[buid] = List<FloorModel>.unmodifiable(floors);
  }

  /// Clears floors + floor error for a space selection change (mirrors the
  /// legacy selection reset; the selected-floor entity is owned elsewhere).
  void resetFloorsForSelection() {
    _floors = const [];
    _floorsErrorMessage = null;
  }

  /// Clears the building-level error message.
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      _notify();
    }
  }

  /// Clears the floor-level error message.
  void clearFloorsError() {
    if (_floorsErrorMessage != null) {
      _floorsErrorMessage = null;
      _notify();
    }
  }

  /// Clears the radiomap-level error message.
  void clearRadioMapError() {
    if (_radioMapErrorMessage != null) {
      _radioMapErrorMessage = null;
      _notify();
    }
  }

  /// Clears the floorplan-level error message.
  void clearFloorplanError() {
    if (_floorplanErrorMessage != null) {
      _floorplanErrorMessage = null;
      _notify();
    }
  }

  /// Clears the POI-level error message.
  void clearPoiError() {
    if (_poiErrorMessage != null) {
      _poiErrorMessage = null;
      _notify();
    }
  }
}