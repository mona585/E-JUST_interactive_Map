import '../datasources/anyplace_api_client.dart';
import '../datasources/poi_cache.dart';
import '../models/poi_model.dart';

/// Repository interface for acquiring and managing Anyplace indoor Points of Interest (POIs).
abstract class PoiRepository {
  /// Retrieves POIs for a specific building and floor.
  ///
  /// Checks local cache first; if missing or [forceReload] is true,
  /// fetches POIs from Anyplace backend and updates local disk cache.
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  });

  /// Checks if POIs for the specified building and floor are available in local cache.
  Future<bool> isPoisCached(String buid, String floor);

  /// Clears cached POIs for the specified building and floor.
  Future<void> clearPois(String buid, String floor);

  /// Clears all cached POIs.
  Future<void> clearAll();
}

/// Concrete implementation of [PoiRepository] backed by [AnyplaceApiClient] and [PoiCache].
class AnyplacePoiRepository implements PoiRepository {
  final AnyplaceApiClient _apiClient;
  final PoiCache _cache;

  AnyplacePoiRepository({
    AnyplaceApiClient? apiClient,
    PoiCache? cache,
  })  : _apiClient = apiClient ?? AnyplaceApiClient(),
        _cache = cache ?? PoiCache();

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
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

    // 1. Check local cache first unless forceReload is requested
    if (!forceReload) {
      final cached = await _cache.getPois(cleanBuid, cleanFloor);
      if (cached != null) {
        return cached;
      }
    }

    // 2. Fetch POIs from backend API
    final pois = await _apiClient.fetchPoisByFloor(cleanBuid, cleanFloor);

    // 3. Save to local cache asynchronously
    await _cache.savePois(cleanBuid, cleanFloor, pois);

    return pois;
  }

  @override
  Future<bool> isPoisCached(String buid, String floor) =>
      _cache.hasPois(buid, floor);

  @override
  Future<void> clearPois(String buid, String floor) =>
      _cache.clearPois(buid, floor);

  @override
  Future<void> clearAll() => _cache.clearAll();
}
