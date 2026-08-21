import '../datasources/anyplace_api_client.dart';
import '../datasources/floorplan_cache.dart';
import '../models/floor_model.dart';
import '../models/floorplan_model.dart';

/// Repository interface for acquiring and managing Anyplace geographic floorplan images.
abstract class FloorplanRepository {
  /// Retrieves the floorplan image for a specific building and floor.
  ///
  /// Checks local cache first; if missing or [forceReload] is true,
  /// downloads the Base64 image from Anyplace backend and stores it locally.
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  });

  /// Checks if a floorplan for the specified building and floor is available in local cache.
  Future<bool> isFloorplanCached(String buid, String floor);

  /// Clears the cached floorplan for the specified building and floor.
  Future<void> clearFloorplan(String buid, String floor);

  /// Clears all cached floorplans.
  Future<void> clearAll();
}

/// Concrete implementation of [FloorplanRepository] backed by [AnyplaceApiClient] and [FloorplanCache].
class AnyplaceFloorplanRepository implements FloorplanRepository {
  final AnyplaceApiClient _apiClient;
  final FloorplanCache _cache;

  AnyplaceFloorplanRepository({
    AnyplaceApiClient? apiClient,
    FloorplanCache? cache,
  })  : _apiClient = apiClient ?? AnyplaceApiClient(),
        _cache = cache ?? FloorplanCache();

  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();

    if (cleanBuid.isEmpty) {
      throw const ApiException('Building ID (buid) cannot be empty.');
    }
    if (cleanFloor.isEmpty) {
      throw const ApiException('Floor number cannot be empty.');
    }

    // 1. Check local cache first if not forceReload
    if (!forceReload) {
      final cached = await _cache.getFloorplan(cleanBuid, cleanFloor, floorMetadata);
      if (cached != null) {
        return cached;
      }
    }

    // 2. Fetch decoded image bytes from Anyplace /api/floorplans64/ endpoint
    final imageBytes = await _apiClient.fetchFloorplanImage(cleanBuid, cleanFloor);

    // 3. Save image bytes atomically to local disk cache and associate with floor bounds
    final floorplan = await _cache.saveFloorplan(
      cleanBuid,
      cleanFloor,
      imageBytes,
      floorMetadata,
    );

    return floorplan;
  }

  @override
  Future<bool> isFloorplanCached(String buid, String floor) =>
      _cache.hasFloorplan(buid, floor);

  @override
  Future<void> clearFloorplan(String buid, String floor) =>
      _cache.clearFloorplan(buid, floor);

  @override
  Future<void> clearAll() => _cache.clearAll();
}
