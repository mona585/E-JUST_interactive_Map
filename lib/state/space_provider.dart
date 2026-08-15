import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../data/datasources/anyplace_api_client.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/floor_model.dart';
import '../data/models/floorplan_model.dart';
import '../data/models/space_model.dart';
import '../data/repositories/floorplan_repository.dart';
import '../data/repositories/radiomap_repository.dart';
import '../data/repositories/space_repository.dart';

/// Status of RadioMap acquisition and native engine readiness for the selected floor.
enum RadioMapStatus {
  idle,
  loading,
  ready,
  unsupported,
  error,
}

/// Status of Floorplan tiles acquisition and rendering readiness.
enum FloorplanStatus {
  idle,
  loading,
  ready,
  unsupported,
  error,
}

/// Provider managing state for Anyplace buildings, floors, RadioMaps, and indoor Floorplans.
class SpaceProvider extends ChangeNotifier {
  final SpaceRepository _repository;
  final RadioMapRepository _radioMapRepository;
  final FloorplanRepository _floorplanRepository;
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

  // Default coordinate if no space selected (Cyprus / UCY area)
  static const LatLng defaultCenter = LatLng(35.1444, 33.4105);

  SpaceProvider({
    SpaceRepository? repository,
    RadioMapRepository? radioMapRepository,
    FloorplanRepository? floorplanRepository,
    NativePositioningService? nativePositioningService,
  })  : _repository = repository ?? AnyplaceSpaceRepository(),
        _radioMapRepository =
            radioMapRepository ?? AnyplaceRadioMapRepository(),
        _floorplanRepository =
            floorplanRepository ?? AnyplaceFloorplanRepository(),
        _nativePositioningService =
            nativePositioningService ?? MethodChannelNativePositioningService();

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

  /// Fetches public spaces from the Anyplace repository.
  Future<void> loadSpaces({bool forceReload = false}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched =
          await _repository.getPublicSpaces(forceReload: forceReload);
      _spaces = fetched;
      _errorMessage = null;

      // If selected space was previously set, refresh its reference from new list
      if (_selectedSpace != null) {
        final matching = _spaces.where((s) => s.buid == _selectedSpace!.buid);
        if (matching.isNotEmpty) {
          _selectedSpace = matching.first;
        }
      }
    } on ApiException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sets the currently selected building and automatically initiates loading of its floors.
  ///
  /// Any previously selected floor, RadioMap, and Floorplan are immediately reset.
  void selectSpace(SpaceModel? space) {
    if (_selectedSpace?.buid == space?.buid && _selectedSpace != null) {
      debugPrint(
        '[SpaceProvider] selectSpace: already selected ${space?.buid}',
      );
      return;
    }

    debugPrint(
      '[SpaceProvider] selectSpace: ${space?.name} (buid: ${space?.buid})',
    );

    // Cancel in-flight RadioMap and Floorplan requests
    _radioMapRequestId++;
    _floorplanRequestId++;
    _selectedSpace = space;
    _selectedFloor = null;
    _floors = const [];
    _floorsErrorMessage = null;
    _isLoadingFloors = space != null;
    _resetRadioMapState();
    _resetFloorplanState();

    notifyListeners();

    if (_selectedSpace != null) {
      loadFloorsForSelectedSpace();
    }
  }

  /// Selects a building by its building ID (`buid`).
  void selectSpaceByBuid(String buid) {
    final matching = _spaces.where((s) => s.buid == buid);
    if (matching.isNotEmpty) {
      selectSpace(matching.first);
    }
  }

  /// Selects a specific floor belonging to the current selected building
  /// and automatically initiates RadioMap and Floorplan acquisitions for that floor.
  void selectFloor(FloorModel floor) {
    if (_selectedSpace == null || floor.buid != _selectedSpace!.buid) {
      debugPrint(
        '[SpaceProvider] selectFloor REJECTED: floor.buid (${floor.buid}) does not match selected space (${_selectedSpace?.buid})',
      );
      return;
    }

    if (_selectedFloor?.floorNumber == floor.floorNumber) {
      debugPrint(
        '[SpaceProvider] selectFloor: floor ${floor.floorNumber} already selected',
      );
      return;
    }

    debugPrint(
      '[SpaceProvider] selectFloor ACCEPTED: Floor ${floor.floorNumber} (${floor.displayName}) for ${_selectedSpace!.buid}',
    );
    _selectedFloor = floor;
    notifyListeners();

    // Trigger RadioMap and Floorplan acquisitions for the selected floor
    loadRadioMapForSelectedFloor();
    loadFloorplanForSelectedFloor();
  }

  /// Clears the current floor selection and resets active RadioMap and Floorplan.
  void clearFloorSelection() {
    if (_selectedFloor != null) {
      debugPrint('[SpaceProvider] clearFloorSelection');
      _radioMapRequestId++;
      _floorplanRequestId++;
      _selectedFloor = null;
      _resetRadioMapState();
      _resetFloorplanState();
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

      // Load into native Kotlin positioning engine
      final success = await _nativePositioningService.loadRadioMap(
        radiomapContent,
        targetBuid,
        targetFloor,
      );

      if (requestId != _radioMapRequestId) return;

      if (success) {
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

  /// Clears both building and floor selections and resets active RadioMap and Floorplan.
  void clearSelection() {
    if (_selectedSpace != null || _selectedFloor != null) {
      debugPrint(
        '[SpaceProvider] clearSelection: resetting space, floor, radiomap, and floorplan',
      );
      _radioMapRequestId++;
      _floorplanRequestId++;
      _selectedSpace = null;
      _selectedFloor = null;
      _floors = const [];
      _floorsErrorMessage = null;
      _isLoadingFloors = false;
      _resetRadioMapState();
      _resetFloorplanState();
      notifyListeners();
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
}
