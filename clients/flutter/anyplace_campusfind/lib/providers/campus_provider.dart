import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/campus.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import 'providers.dart';

/// Fetches the campuses offered on first launch (by configured cuid).
class CampusLoader {
  CampusLoader(this._api, this._cache);

  final ApiService _api;
  final CacheService _cache;

  /// Loads the campuses offered on first launch.
  ///
  /// When [cuids] (default: the `CAMPUS_IDS` build-time list) are configured
  /// each cuid is fetched via `campus/get` (failed cuids are skipped so one
  /// bad id does not block the selector). When no cuids are provided, a single
  /// default campus is derived from all published buildings (`space/public`)
  /// so a zero-config build still shows the campus on first launch instead of
  /// dead-ending on an empty selector.
  Future<List<Campus>> loadConfigured({List<String>? cuids}) async {
    final campuses = <Campus>[];
    final configured = cuids ?? AppConstants.configuredCampusIds;
    if (configured.isEmpty) {
      try {
        final spaces = await _api.fetchPublicSpaces();
        if (spaces.isNotEmpty) {
          _cache.setSpaces(spaces);
          campuses.add(Campus(
            cuid: AppConstants.defaultCampusCuid,
            name: AppConstants.defaultCampusName,
            spaces: spaces,
          ));
        }
      } on ApiException {
        // Network failure — leave the list empty; the selector shows the
        // error/empty state with Retry.
      }
    } else {
      for (final cuid in configured) {
        try {
          final campus = await _api.fetchCampus(cuid);
          campuses.add(campus);
        } on ApiException {
          continue;
        }
      }
    }
    _cache.setCampuses(campuses);
    return campuses;
  }
}

final campusLoaderProvider = Provider<CampusLoader>((ref) {
  return CampusLoader(
    ref.watch(apiServiceProvider),
    ref.watch(cacheServiceProvider),
  );
});

/// Loads the campus selector options.
final configuredCampusesProvider = FutureProvider<List<Campus>>((ref) async {
  return ref.watch(campusLoaderProvider).loadConfigured();
});
