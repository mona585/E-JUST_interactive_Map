import 'package:flutter/foundation.dart';

import '../datasources/anyplace_api_client.dart';
import '../models/campus_asset_status.dart';
import '../models/floor_model.dart';
import '../models/floorplan_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../repositories/poi_repository.dart';
import '../repositories/space_repository.dart';
import '../utils/campus_scope.dart';
import '../utils/with_retry.dart';

/// Acquires and holds all campus browsing asset state: the public space
/// (building) list, the selected building's floors, and the selected floor's
/// POIs.
///
/// Extracted from [SpaceViewModel]. Owns the fetch/status/request-id state for
/// each asset pipeline (spaces, floors, POIs); the view model owns selection
/// and feeds the current selection back through the [selectedSpace]/
/// [selectedFloor] accessors for staleness checks.
///
/// [resetPoiState] also clears the view model's selected-POI via
/// [onSelectedPoiCleared] — mirroring the legacy invariant that snapping POI
/// state empties the current POI selection.
class CampusAssetLoader {
  CampusAssetLoader({
    required SpaceRepository repository,
    required PoiRepository poiRepository,
    required void Function() notify,
    required SpaceModel? Function() selectedSpace,
    required FloorModel? Function() selectedFloor,
    required void Function(SpaceModel space) onSelectedSpaceRefresh,
    required void Function() onSelectedPoiCleared,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _repository = repository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _poiRepository = poiRepository,
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
  final PoiRepository _poiRepository;
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
  // accepted geometry.
  final Map<String, List<FloorModel>> _floorsByBuid = {};

  // RadioMap State (inert: the indoor positioning pipeline was removed; the
  // status surface is retained for the navigation-route scope contract).
  RadioMapStatus _radioMapStatus = RadioMapStatus.idle;
  String? _radioMapErrorMessage;
  String? _activeRadioMapBuid;
  String? _activeRadioMapFloor;
  bool _isRadioMapCached = false;

  // Floorplan State (inert: the indoor floorplan pipeline was removed; the
  // status surface is retained for the navigation-route scope contract).
  FloorplanStatus _floorplanStatus = FloorplanStatus.idle;
  FloorplanModel? _activeFloorplan;
  String? _floorplanErrorMessage;

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

  /// SERVER MIGRATION: purges on-disk POI dataset caches that may still hold
  /// files from the previous backend. Safe to call repeatedly. Uses the
  /// repository's EXISTING clear-all method. Old entries were keyed by
  /// old-server buids and could never be served again, so this only reclaims
  /// space and guarantees zero stale-data leakage.
  Future<void> purgeDatasetCaches() async {
    debugPrint(
      '[SpaceViewModel] purgeDatasetCaches: clearing POIs from previous backend',
    );
    try {
      await _poiRepository.clearAll();
    } catch (e) {
      debugPrint('[SpaceViewModel] purgeDatasetCaches: pois clear failed: $e');
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

  /// Status-field reset only.
  void resetRadioMapState() {
    _radioMapStatus = RadioMapStatus.idle;
    _radioMapErrorMessage = null;
    _activeRadioMapBuid = null;
    _activeRadioMapFloor = null;
    _isRadioMapCached = false;
  }

  /// App-level reset (logout / storage clear).
  void resetAllRadiomaps() {
    resetRadioMapState();
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
