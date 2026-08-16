import '../../models/floor.dart' as current;
import '../../models/space.dart' as current;
import '../../services/cache_service.dart';
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

/// [SpaceRepository] backed by the app's shared [CacheService].
///
/// Bridges the current Riverpod cache (already populated by the bulk loader)
/// into the map layer's [SpaceModel]/[FloorModel] domain. Keeps the map in
/// sync with whatever the rest of the app displays without duplicate network
/// requests.
class CacheBackedSpaceRepository implements SpaceRepository {
  final CacheService _cache;

  CacheBackedSpaceRepository({required CacheService cache}) : _cache = cache;

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async {
    return _cache.spaces
        .where((s) => s.isBuilding)
        .map(_toSpaceModel)
        .toList();
  }

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    final space = _cache.spaceByBuid(buid);
    return space == null ? null : _toSpaceModel(space);
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async {
    final floors = _cache.floorsOf(buid);
    final models = floors.map(_toFloorModel).toList()..sort();
    return models;
  }

  /// Converts the current app [current.Space] to the map layer [SpaceModel].
  SpaceModel _toSpaceModel(current.Space space) {
    return SpaceModel(
      buid: space.buid,
      name: space.name,
      latitude: space.coordinatesLat,
      longitude: space.coordinatesLon,
      description: space.description,
      bucode: space.bucode,
      address: space.address,
      url: space.url,
      isPublished: space.isPublished == null || space.isPublished == 'true',
      spaceType: space.spaceType,
    );
  }

  /// Converts the current app [current.Floor] to the map layer [FloorModel].
  FloorModel _toFloorModel(current.Floor floor) {
    return FloorModel(
      buid: floor.buid,
      floorNumber: floor.floorNumber,
      floorName: floor.floorName ?? '',
      description: floor.description ?? '',
      fuid: floor.fuid,
      isPublished: floor.isPublished == null || floor.isPublished == 'true',
      bottomLeftLat: floor.bottomLeftLat,
      bottomLeftLng: floor.bottomLeftLng,
      topRightLat: floor.topRightLat,
      topRightLng: floor.topRightLng,
    );
  }
}