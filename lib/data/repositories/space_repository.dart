import '../datasources/anyplace_api_client.dart';
import '../models/floor_model.dart';
import '../models/space_model.dart';

/// Repository interface for Space/Building and Floor data operations.
abstract class SpaceRepository {
  /// Retrieves list of public spaces.
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false});

  /// Retrieves details for a specific space by buid.
  Future<SpaceModel?> getSpaceByBuid(String buid);

  /// Retrieves list of floors for a specific building by buid.
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  });
}

/// Concrete implementation of [SpaceRepository] connecting to [AnyplaceApiClient].
class AnyplaceSpaceRepository implements SpaceRepository {
  final AnyplaceApiClient _apiClient;
  List<SpaceModel>? _cachedSpaces;
  final Map<String, List<FloorModel>> _cachedFloors = {};

  AnyplaceSpaceRepository({AnyplaceApiClient? apiClient})
      : _apiClient = apiClient ?? AnyplaceApiClient();

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async {
    if (!forceReload && _cachedSpaces != null && _cachedSpaces!.isNotEmpty) {
      return _cachedSpaces!;
    }

    final spaces = await _apiClient.fetchPublicSpaces();
    _cachedSpaces = List<SpaceModel>.unmodifiable(spaces);
    return _cachedSpaces!;
  }

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    // Check in-memory cache first
    if (_cachedSpaces != null) {
      final cached = _cachedSpaces!.where((s) => s.buid == buid);
      if (cached.isNotEmpty) {
        return cached.first;
      }
    }

    try {
      final space = await _apiClient.fetchSpaceDetails(buid);
      return space;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async {
    if (!forceReload && _cachedFloors.containsKey(buid)) {
      return _cachedFloors[buid]!;
    }

    final floors = await _apiClient.fetchFloorsForBuilding(buid);
    _cachedFloors[buid] = List<FloorModel>.unmodifiable(floors);
    return _cachedFloors[buid]!;
  }
}
