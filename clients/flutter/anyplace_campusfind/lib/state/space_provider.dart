import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/datasources/anyplace_api_client.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/floor_model.dart';
import '../data/models/floorplan_model.dart';
import '../data/models/navigation_route_model.dart';
import '../data/models/poi_model.dart';
import '../data/models/space_model.dart';
import '../data/repositories/floorplan_repository.dart';
import '../data/repositories/navigation_repository.dart';
import '../data/repositories/poi_repository.dart';
import '../data/repositories/radiomap_repository.dart';
import '../data/repositories/space_repository.dart';
import '../services/search_service.dart';
import 'location_provider.dart';

/// Status of RadioMap acquisition and native engine readiness for the selected floor.
enum RadioMapStatus { idle, loading, ready, unsupported, error }

/// Status of Floorplan tiles acquisition and rendering readiness.
enum FloorplanStatus { idle, loading, ready, unsupported, error }

/// Status of indoor Points of Interest (POIs) acquisition for the selected floor.
enum PoiStatus { idle, loading, ready, error }

/// Status of an Anyplace navigation route request.
enum NavigationRouteStatus { idle, loading, ready, unsupported, error }

/// Provider managing state for Anyplace buildings, floors, RadioMaps, indoor Floorplans, and POIs.
class SpaceProvider extends ChangeNotifier {
  final SpaceRepository _repository;
  final RadioMapRepository _radioMapRepository;
  final FloorplanRepository _floorplanRepository;
  final PoiRepository _poiRepository;
  final NavigationRepository _navigationRepository;
  final NativePositioningService _nativePositioningService;

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
  }) : _repository = repository ?? AnyplaceSpaceRepository(),
       _radioMapRepository = radioMapRepository ?? AnyplaceRadioMapRepository(),
       _floorplanRepository =
           floorplanRepository ?? AnyplaceFloorplanRepository(),
       _poiRepository = poiRepository ?? AnyplacePoiRepository(),
       _navigationRepository =
           navigationRepository ?? AnyplaceNavigationRepository(),
       _nativePositioningService =
           nativePositioningService ?? MethodChannelNativePositioningService();

  /// Binds LocationProvider for indoor floor position scoping.
  void setLocationProvider(LocationProvider? locationProvider) {
    _locationProvider = locationProvider;
    _syncLocationProvider();
  }

  void _syncLocationProvider() {
    _locationProvider?.setActiveIndoorFloor(
      _selectedSpace?.buid,
      _selectedFloor?.floorNumber,
    );
  }

  List<SpaceModel> get spaces => _spaces;
  SpaceModel? get selectedSpace => _selectedSpace;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  bool get hasSelectedSpace => _selectedSpace != null;

  // Floor Getters
  List<FloorModel> get floors => _floors;
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
  List<PoiModel> get pois => _pois;
  PoiModel? get selectedPoi => _selectedPoi;
  bool get hasPois => _pois.isNotEmpty;
  bool get isLoadingPois => _poiStatus == PoiStatus.loading;
  String? get poiErrorMessage => _poiErrorMessage;
  bool get hasSelectedPoi => _selectedPoi != null;

  // Navigation Getters
  NavigationRouteStatus get navigationRouteStatus => _navigationRouteStatus;
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
      final fetched = await _repository.getPublicSpaces(
        forceReload: forceReload,
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

  /// Selects a space, clears previous floor & POI selections, and automatically loads available floors.
  void selectSpace(SpaceModel space) {
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
      _resetNavigationRouteState();
      _syncLocationProvider();
      notifyListeners();

      // Automatically fetch floors for newly selected space
      loadFloorsForSelectedSpace();
    }
  }

  /// Clears the currently selected space, floor, RadioMap, floorplan, and POIs.
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
      _resetNavigationRouteState();
      _syncLocationProvider();
      notifyListeners();
    }
  }

  /// Selects a floor for the currently selected space and triggers RadioMap, Floorplan, and POI downloads.
  void selectFloor(FloorModel floor) {
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
    _resetNavigationRouteState();
    _syncLocationProvider();
    notifyListeners();

    // Trigger RadioMap, Floorplan, and POI acquisitions for the selected floor
    loadRadioMapForSelectedFloor();
    loadFloorplanForSelectedFloor();
    loadPoisForSelectedFloor();
  }

  /// Clears the current floor selection and resets active RadioMap, Floorplan, and POIs.
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
      _resetNavigationRouteState();
      _syncLocationProvider();
      notifyListeners();
    }
  }

  /// Selects an indoor POI for viewing details.
  void selectPoi(PoiModel? poi) {
    if (_selectedPoi?.puid != poi?.puid &&
        _navigationDestinationPuid != null &&
        _navigationDestinationPuid != poi?.puid) {
      _resetNavigationRouteState();
    }
    _selectedPoi = poi;
    notifyListeners();
  }

  /// Clears the selected POI.
  void clearSelectedPoi() {
    if (_selectedPoi != null) {
      _selectedPoi = null;
      _resetNavigationRouteState();
      notifyListeners();
    }
  }

  /// Orchestrates selectSpace -> selectFloor -> selectPoi from a [PoiModel].
  /// Used by cross-tab navigation (search results, recent waypoints).
  Future<bool> navigateToPoi(PoiModel targetPoi) async {
    // 1. Find the SpaceModel matching the POI's buid
    final space = _spaces.firstWhere(
      (s) => s.buid == targetPoi.buid,
      orElse: () => throw StateError('Space ${targetPoi.buid} not found'),
    );

    // 2. Select the space (clears everything, starts async floor load)
    selectSpace(space);

    // 3. Wait for floors to load
    await loadFloorsForSelectedSpace();

    // 4. Find the FloorModel
    final floor = _floors.firstWhere(
      (f) => f.floorNumber == targetPoi.floorNumber,
      orElse: () => throw StateError('Floor ${targetPoi.floorNumber} not found'),
    );

    // 5. Select the floor (starts async POI load)
    selectFloor(floor);

    // 6. Wait for POIs to load
    await loadPoisForSelectedFloor();

    // 7. Find the POI in the loaded list and select it
    final poi = _pois.firstWhere(
      (p) => p.puid == targetPoi.puid,
      orElse: () => targetPoi,
    );
    selectPoi(poi);
    return true;
  }

  /// Requests a navigation route from the current effective indoor position to the selected POI.
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

    if (locationProvider.isIndoorWifiActive &&
        locationProvider.latestIndoorEstimate?.floor != floor.floorNumber) {
      _navigationRouteStatus = NavigationRouteStatus.unsupported;
      _navigationRouteErrorMessage =
          'Your current indoor estimate does not match the selected floor.';
      notifyListeners();
      return;
    }

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = poi.puid;
    notifyListeners();

    try {
      final route = await _navigationRepository.getRouteFromCoordinates(
        latitude: currentLocation.latitude,
        longitude: currentLocation.longitude,
        floorNumber: floor.floorNumber,
        destinationPuid: poi.puid,
      );

      if (requestId != _navigationRouteRequestId ||
          _selectedPoi?.puid != poi.puid ||
          _selectedFloor?.floorNumber != floor.floorNumber) {
        return;
      }

      if (!route.hasRenderablePath) {
        _navigationRouteStatus = NavigationRouteStatus.unsupported;
        _activeNavigationRoute = null;
        _navigationRouteErrorMessage =
            'Anyplace returned an incomplete route for this POI.';
      } else {
        _navigationRouteStatus = NavigationRouteStatus.ready;
        _activeNavigationRoute = route;
        _navigationRouteErrorMessage = null;
      }
    } on ApiException catch (e) {
      if (requestId != _navigationRouteRequestId) return;

      final message = e.message.toLowerCase();
      if (message.contains('not supported') ||
          message.contains('between buildings') ||
          message.contains('starting poi') ||
          e.statusCode == 400 ||
          e.statusCode == 404) {
        _navigationRouteStatus = NavigationRouteStatus.unsupported;
      } else {
        _navigationRouteStatus = NavigationRouteStatus.error;
      }
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = e.message;
    } catch (e) {
      if (requestId != _navigationRouteRequestId) return;
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = 'Error requesting route: $e';
    } finally {
      if (requestId == _navigationRouteRequestId) {
        notifyListeners();
      }
    }
  }

  /// Clears the currently displayed navigation route.
  void clearNavigationRoute() {
    if (_navigationRouteStatus != NavigationRouteStatus.idle ||
        _activeNavigationRoute != null ||
        _navigationRouteErrorMessage != null) {
      _navigationRouteRequestId++;
      _resetNavigationRouteState();
      notifyListeners();
    }
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
      final fetchedFloors = await _repository.getFloorsByBuid(
        targetBuid,
        forceReload: forceReload,
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
      final loadedSuccessfully = await _nativePositioningService.loadRadioMap(
        radiomapContent,
        targetBuid,
        targetFloor,
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
        _radioMapErrorMessage = 'Native engine rejected RadioMap format.';
        await _nativePositioningService.clearRadioMap();
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
      await _nativePositioningService.clearRadioMap();
    } catch (e) {
      if (requestId != _radioMapRequestId) return;
      _radioMapStatus = RadioMapStatus.error;
      _radioMapErrorMessage = 'Error loading RadioMap: $e';
      debugPrint(
        '[SpaceProvider] Unexpected RadioMap error for $targetBuid / Floor $targetFloor: $e',
      );
      await _nativePositioningService.clearRadioMap();
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
        _activeFloorplan = floorplan;
        _floorplanStatus = FloorplanStatus.ready;
        _floorplanErrorMessage = null;
        debugPrint(
          '[SpaceProvider] Floorplan successfully ready for $targetBuid / Floor $targetFloor (${floorplan.imageSizeBytes} bytes)',
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
      final fetchedPois = await _poiRepository.getPoisByFloor(
        targetBuid,
        targetFloor,
        forceReload: forceReload,
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
  /// and indexes them into [searchService]. Runs throttled to avoid network spikes.
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {
    searchService.markSyncStarted(_spaces.length);

    for (int i = 0; i < _spaces.length; i++) {
      final space = _spaces[i];
      try {
        final floors = await _repository.getFloorsByBuid(space.buid);
        searchService.addFloors(space.buid, floors);

        for (final floor in floors) {
          try {
            final pois = await _poiRepository.getPoisByFloor(
              space.buid,
              floor.floorNumber,
            );
            searchService.addPois(space.buid, floor.floorNumber, pois);
          } catch (_) {
            // Skip failed floor POI fetch
          }
        }
      } catch (_) {
        // Skip failed building
      }

      searchService.markSyncProgress(i + 1);

      // Throttle: yield to event loop between buildings
      await Future.delayed(const Duration(milliseconds: 50));
    }

    searchService.markSyncComplete();
  }
}
