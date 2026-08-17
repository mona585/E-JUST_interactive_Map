import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../services/cache_service.dart';

/// Provides the in-memory + persisted cache.
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService();
});

/// Monotonic counter incremented every time [CacheService] mutates its dataset.
final StateProvider<int> cacheVersionProvider = StateProvider<int>((ref) => 0);

/// Wires [CacheService.onDataChanged] to bump [cacheVersionProvider].
void wireCacheNotifications(WidgetRef ref) {
  final cache = ref.read(cacheServiceProvider);
  cache.onDataChanged ??= () {
    ref.read(cacheVersionProvider.notifier).state++;
  };
}

/// The single primary (UCY) campus is always selected.
final selectedCampusIdProvider = StateProvider<String?>((ref) {
  return AppConstants.primaryCampusCuid;
});

/// Currently active bottom-navigation tab.
final shellTabProvider = StateProvider<int>((ref) => 0);
