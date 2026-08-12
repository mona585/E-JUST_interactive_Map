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

/// Provides the floorplan tile downloader/extractor.
final tileServiceProvider = Provider<TileService>((ref) {
  return TileService(ref.watch(apiServiceProvider));
});

/// Keeps the currently selected campus id (null until the user picks one on
/// first launch). Persistence is handled by [CacheService].
final selectedCampusIdProvider = StateProvider<String?>((ref) => null);

/// Whether the app is still fetching the initial bulk dataset on launch.
final initialLoadProvider = StateProvider<bool>((ref) => false);

/// Holds any error surfaced during the initial bulk load (null = no error).
final initialLoadErrorProvider = StateProvider<String?>((ref) => null);
