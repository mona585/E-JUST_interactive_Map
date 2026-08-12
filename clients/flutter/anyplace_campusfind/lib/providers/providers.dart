import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/tile_service.dart';

/// Provides the shared API client. Injectable so tests can substitute a
/// mock-backed client.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Provides the in-memory + persisted cache (lazily initialised).
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService();
});

/// Monotonic counter incremented every time [CacheService] mutates its dataset.
/// Providers that need to rebuild when cached data changes should watch this
/// instead of [cacheServiceProvider] (whose identity never changes).
final StateProvider<int> cacheVersionProvider = StateProvider<int>((ref) => 0);

/// Wires [CacheService.onDataChanged] to bump [cacheVersionProvider].
/// Call once from MainShell.build().
void wireCacheNotifications(WidgetRef ref) {
  final cache = ref.read(cacheServiceProvider);
  cache.onDataChanged ??= () {
    ref.read(cacheVersionProvider.notifier).state++;
  };
}

/// Provides the floorplan tile downloader/extractor.
final tileServiceProvider = Provider<TileService>((ref) {
  return TileService(ref.watch(apiServiceProvider));
});

/// Keeps the currently selected campus id (null until the user picks one on
/// first launch). Persistence is handled by [CacheService].
final selectedCampusIdProvider = StateProvider<String?>((ref) => null);

/// Currently active bottom-navigation tab (0 Home, 1 Map, 2 Search).
final shellTabProvider = StateProvider<int>((ref) => 0);
