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

  /// Loads all configured campuses. Failed campuses are skipped so one bad
  /// cuid does not block the whole selector.
  Future<List<Campus>> loadConfigured() async {
    final campuses = <Campus>[];
    for (final cuid in AppConstants.configuredCampusIds) {
      try {
        final campus = await _api.fetchCampus(cuid);
        campuses.add(campus);
      } on ApiException {
        continue;
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
