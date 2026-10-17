import 'package:flutter/foundation.dart';

import '../viewmodels/space_view_model.dart';
import '../services/cache_service.dart';
import '../services/search_service.dart';

/// ViewModel for the map-first shell (MVVM).
///
/// Owns the one-time startup data pipeline that previously lived inside the
/// shell widget's `State` class:
///  * the dataset-epoch migration (server wipe of old-backend caches),
///  * loading the campus spaces,
///  * indexing them into the search engine,
///  * one-time Quick Access seeding + legacy Saved-POIs migration,
///  * the progressive background floors/POIs sync,
///  * loading the custom KMZ outdoor routes + campus gates + gate policy.
///
/// The pipeline is idempotent ([startDataSync] only runs once) and otherwise
/// byte-for-byte identical to the legacy `_startDataLoading` behavior.
class MainShellViewModel extends ChangeNotifier {
  MainShellViewModel({
    required this._spaceProvider,
    SearchService? searchService,
    CacheService? cacheService,
  }) : _searchService = searchService ?? SearchService(),
       _cacheService = cacheService ?? CacheService();

  final SpaceViewModel _spaceProvider;
  final SearchService _searchService;
  final CacheService _cacheService;

  bool _syncStarted = false;

  /// Cancelled once the owning shell widget is disposed. Mirrors the legacy
  /// `if (!mounted) return;` halt in `_startDataLoading`: an async step that
  /// completes after teardown must not continue mutating providers.
  bool _cancelled = false;

  /// Marks this ViewModel cancelled. The owning widget calls this from its
  /// own `dispose()`, which runs at the exact moment the framework flips the
  /// legacy `mounted` flag (dispose precedes the `_element == null` flip).
  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  /// Whether the initial one-time data pipeline has been kick-started.
  bool get isSyncStarted => _syncStarted;

  /// The underlying space provider (view reads selection/spaces directly).
  SpaceViewModel get spaceProvider => _spaceProvider;

  /// Starts the one-time startup pipeline. Idempotent — only the first call
  /// does any work (legacy guard preserved verbatim).
  Future<void> startDataSync() async {
    if (_syncStarted || _cancelled) return;
    _syncStarted = true;

    // SERVER MIGRATION (one-time, silent): if this device's local data
    // belongs to a previous backend epoch, clear old-backend Quick Access /
    // Recent Waypoints and purge the disk caches BEFORE anything reads them.
    // Quick Access then re-seeds below from the new server's real entities.
    try {
      final migrated = await _cacheService.consumeDatasetEpochMigration();
      if (migrated) {
        await _spaceProvider.purgeDatasetCaches();
      }
    } catch (e) {
      debugPrint(
        '[MainShellViewModel] dataset migration failed (non-fatal): $e',
      );
    }

    await _spaceProvider.loadSpaces();

    // Legacy `if (!mounted) return;` halt restored: if the shell was torn
    // down while spaces were loading, stop before touching the search index /
    // Quick Access / background sync / custom routes — all of which would
    // otherwise run against a dead subtree's collaborators.
    if (_cancelled) return;

    // Index spaces immediately.
    _searchService.addSpaces(_spaceProvider.spaces);
    // One-time Quick Access seeding + legacy Saved migration.
    await _spaceProvider.ensureQuickAccessInitialized(_searchService);
    // Start progressive background sync for floors + POIs.
    _spaceProvider.loadAllFloorsAndPois(_searchService);

    // Load custom KMZ routes for outdoor navigation.
    debugPrint('[MainShellViewModel] startDataSync: calling loadCustomRoutes');
    await _spaceProvider.loadCustomRoutes();
    debugPrint(
      '[MainShellViewModel] startDataSync: loadCustomRoutes completed',
    );
  }
}
