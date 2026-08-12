import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
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
    this.fromOffline = false,
  });

  final List<Campus> campuses;
  final List<Space> spaces;
  final Object? error;

  /// True when the dataset was restored from the local offline snapshot
  /// because the live fetch failed.
  final bool fromOffline;
}

/// Fetches the full read dataset on launch:
///   campuses + spaces/buildings
///   floors + POIs per building
///
/// When `CAMPUS_IDS` are configured at build time the dataset is scoped to
/// those campuses via `/api/mapping/campus/get` (each response carries its own
/// `spaces` list). This is required for public Anyplace servers whose
/// `/api/mapping/space/public` returns buildings from every campus globally
/// (e.g. a UCY deployment with thousands of buildings) — bulk-loading floors
/// and POIs for all of them would be impractical.
///
/// Without configured cuids the loader falls back to all published buildings
/// from `/api/mapping/space/public` so a zero-config build stays usable.
class BulkLoader {
  BulkLoader(this._api, this._cache);

  final ApiService _api;
  final CacheService _cache;

  /// Number of buildings fetched concurrently. Bounded so a campus with many
  /// buildings does not overwhelm the backend or exhaust sockets.
  static const int _concurrency = 6;

  /// Returns the campuses (empty when none configured) and the buildings that
  /// belong to them. When [AppConstants.configuredCampusIds] is non-empty the
  /// buildings come from `campus/get` responses; otherwise from `space/public`
  /// unless a runtime campus id has been selected (see [CacheService]).
  Future<(List<Campus>, List<Space>)> _loadScopedDataset() async {
    final cuids = AppConstants.configuredCampusIds;
    if (cuids.isEmpty) {
      // Fall back to runtime-selected campus id if available.
      final selectedId = await _cache.getSelectedCampusId();
      if (selectedId != null && selectedId.isNotEmpty) {
        try {
          final campus = await _api.fetchCampus(selectedId);
          return (const <Campus>[], campus.spaces);
        } on ApiException {
          // Failed to fetch selected campus; fall through to empty result.
        }
      }
      // No runtime campus id either — show empty state (no more silent global fallthrough).
      return (const <Campus>[], const <Space>[]);
    }

    final campuses = <Campus>[];
    final byBuid = <String, Space>{};
    for (final cuid in cuids) {
      try {
        final campus = await _api.fetchCampus(cuid);
        campuses.add(campus);
        for (final space in campus.spaces) {
          byBuid[space.buid] = space;
        }
      } on ApiException {
        // One bad cuid must not block data from the others.
        continue;
      }
    }
    return (campuses, byBuid.values.toList());
  }

  /// Fetches floors + POIs for every building with [._concurrency] parallel
  /// workers and stores them in the cache.
  Future<void> _loadFloorsAndPois(List<Space> spaces) async {
    final queue = List<Space>.of(spaces);
    await Future.wait(
      List.generate(_concurrency, (_) async {
        while (queue.isNotEmpty) {
          final space = queue.removeLast();
          try {
            final floors = await _api.fetchFloors(space.buid);
            final pois = await _api.fetchPois(space.buid);
            _cache.setFloors(space.buid, floors);
            _cache.setPois(space.buid, pois);
          } catch (_) {
            // A single failed building must not abort the whole load.
          }
        }
      }),
    );
  }

  Future<BulkLoadResult> load() async {
    try {
      final (campuses, spaces) = await _loadScopedDataset();
      _cache.setCampuses(campuses);
      _cache.setSpaces(spaces);

      // Fetch floors + POIs for every building with bounded concurrency so we
      // do not hammer the backend with one request per building.
      await _loadFloorsAndPois(spaces);

      // Keep a copy for offline launches (Phase 7.2).
      await _cache.saveOfflineSnapshot();

      return BulkLoadResult(campuses: campuses, spaces: spaces);
    } catch (e) {
      // Network failure: fall back to the last cached snapshot so the app can
      // still show previously fetched data (Phase 7.2).
      final restored = await _cache.loadOfflineSnapshot();
      if (restored) {
        return BulkLoadResult(
          campuses: _cache.campuses,
          spaces: _cache.spaces,
          error: null,
          fromOffline: true,
        );
      }
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
  return loader.load();
});
