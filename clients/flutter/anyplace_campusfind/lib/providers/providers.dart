import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// Provides the shared API client. Injectable so tests can substitute a
/// mock-backed client.
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

/// Keeps the currently selected campus id (null until the user picks one on
/// first launch). Persistence is wired in during Phase 2 (CacheService).
final selectedCampusIdProvider = StateProvider<String?>((ref) => null);

/// Whether the app is still fetching the initial bulk dataset on launch.
final initialLoadProvider = StateProvider<bool>((ref) => false);

/// Holds any error surfaced during the initial bulk load (null = no error).
final initialLoadErrorProvider = StateProvider<String?>((ref) => null);
