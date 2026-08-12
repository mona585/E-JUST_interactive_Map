import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/campus.dart';
import '../models/space.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import 'providers.dart';

/// Result of the initial bulk fetch.
class BulkLoadResult {
  const BulkLoadResult({
    required this.campuses,
    required this.spaces,
    this.error,
  });

  final List<Campus> campuses;
  final List<Space> spaces;
  final Object? error;
}

/// Fetches the full read dataset on launch:
///   campuses (campus/get is per-cuid, so we use space/public for buildings)
///   spaces/buildings
///   floors + POIs per building
///
/// Because `campus/get` requires a known `cuid` (there is no public
/// "list campuses" endpoint), the bulk load seeds the cache with all
/// published buildings from `/api/mapping/space/public`. Campus objects are
/// only fetchable once a `cuid` is known (campus selection flow).
class BulkLoader {
  BulkLoader(this._api, this._cache);

  final ApiService _api;
  final CacheService _cache;

  Future<BulkLoadResult> load() async {
    try {
      final spaces = await _api.fetchPublicSpaces();
      _cache.setSpaces(spaces);

      for (final space in spaces) {
        final floorsFuture = _api.fetchFloors(space.buid);
        final poisFuture = _api.fetchPois(space.buid);
        final floors = await floorsFuture;
        final pois = await poisFuture;
        _cache.setFloors(space.buid, floors);
        _cache.setPois(space.buid, pois);
      }

      return BulkLoadResult(campuses: _cache.campuses, spaces: spaces);
    } catch (e) {
      return BulkLoadResult(
        campuses: const [],
        spaces: _cache.spaces,
        error: e,
      );
    }
  }
}

final bulkLoaderProvider = Provider<BulkLoader>((ref) {
  return BulkLoader(
    ref.watch(apiServiceProvider),
    ref.watch(cacheServiceProvider),
  );
});

final bulkLoadProvider = FutureProvider<BulkLoadResult>((ref) async {
  final loader = ref.watch(bulkLoaderProvider);
  final result = await loader.load();
  ref.read(initialLoadErrorProvider.notifier).state =
      result.error?.toString();
  return result;
});
