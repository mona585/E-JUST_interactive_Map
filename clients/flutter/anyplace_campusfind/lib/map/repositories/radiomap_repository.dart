import '../data/anyplace_api_client.dart';
import '../data/radiomap_cache.dart';

/// Repository interface for acquiring and managing RadioMap data.
abstract class RadioMapRepository {
  /// Retrieves the RadioMap text for a specific building and floor.
  ///
  /// Checks local cache first; if missing or [forceReload] is true,
  /// downloads from the Anyplace backend and updates local cache.
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  });

  /// Checks if a radiomap for the specified building and floor is available in local cache.
  Future<bool> isRadioMapCached(String buid, String floor);

  /// Clears the cached radiomap for the specified building and floor.
  Future<void> clearRadioMap(String buid, String floor);

  /// Clears all cached radiomaps.
  Future<void> clearAllCache();
}

/// Concrete implementation of [RadioMapRepository] backed by [AnyplaceApiClient] and [RadioMapCache].
class AnyplaceRadioMapRepository implements RadioMapRepository {
  final AnyplaceApiClient _apiClient;
  final RadioMapCache _cache;

  AnyplaceRadioMapRepository({
    AnyplaceApiClient? apiClient,
    RadioMapCache? cache,
  })  : _apiClient = apiClient ?? AnyplaceApiClient(),
        _cache = cache ?? RadioMapCache();

  @override
  Future<String> getRadioMap(
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

    // 1. Check local disk cache first if not forceReload
    if (!forceReload) {
      final cachedContent = await _cache.getRadioMap(cleanBuid, cleanFloor);
      if (cachedContent != null && cachedContent.trim().isNotEmpty) {
        return cachedContent;
      }
    }

    // 2. Fetch from Anyplace backend (metadata + normalized raw radiomap download)
    final downloadedContent =
        await _apiClient.fetchRadioMap(cleanBuid, cleanFloor);

    // 3. Persist downloaded radiomap to local disk cache
    await _cache.saveRadioMap(cleanBuid, cleanFloor, downloadedContent);

    return downloadedContent;
  }

  @override
  Future<bool> isRadioMapCached(String buid, String floor) =>
      _cache.hasRadioMap(buid, floor);

  @override
  Future<void> clearRadioMap(String buid, String floor) =>
      _cache.clearRadioMap(buid, floor);

  @override
  Future<void> clearAllCache() => _cache.clearAll();
}