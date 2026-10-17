import 'package:flutter/foundation.dart';

import '../config/constants.dart';
import '../models/quick_access_item.dart';
import '../models/space_model.dart';
import '../utils/category_deriver.dart';
import 'cache_service.dart';
import 'search_service.dart';

/// Outcome of resolving one predefined Quick Access default during seeding.
///
/// Records whether the requested default resolved to its exact verified E-JUST
/// entity in the loaded dataset, and if not, which similarly named candidates
/// were present. A resolved entry always carries the real API entity name and
/// buid; an unresolved entry is never silently substituted.
class QuickAccessSeedReport {
  const QuickAccessSeedReport.resolved({
    required this.requested,
    required this.resolvedName,
    required this.buid,
  }) : candidates = const [],
       isResolved = true;

  const QuickAccessSeedReport.unresolved({
    required this.requested,
    required this.candidates,
  }) : resolvedName = null,
       buid = null,
       isResolved = false;

  final DefaultQuickAccessLocation requested;

  /// True when the exact buid was found in the loaded dataset.
  final bool isResolved;

  /// The actual entity name in the loaded dataset (when resolved).
  final String? resolvedName;

  /// The exact buid resolved against the loaded dataset (when resolved).
  final String? buid;

  /// Similarly named entities found in the loaded dataset (when unresolved).
  final List<String> candidates;
}

/// One-time Quick Access seeding + legacy saved-POI migration.
///
/// Owns the algorithm previously embedded in the space view model: predefined
/// defaults are seeded by their VERIFIED buid from the loaded [SpaceModel]s
/// (never substituted), then legacy `saved_pois` are migrated into the unified
/// storage. Persistence and the "already initialized" guard live in
/// [CacheService].
class QuickAccessService {
  QuickAccessService(this._cacheService);

  final CacheService _cacheService;

  /// Seeds the predefined default locations and migrates any legacy
  /// `saved_pois` into the unified format.
  ///
  /// Runs only when the Quick Access preference key has never been written.
  /// Once the key exists (even as an empty list) seeding and migration are
  /// permanently skipped, so user customizations and "Clear Quick Access" are
  /// never overwritten on later launches.
  ///
  /// Returns a per-default report describing how each requested default was
  /// resolved (real `buid` + entity name) or why it was skipped, so the audit
  /// can verify no default was ever substituted with a different location.
  Future<List<QuickAccessSeedReport>> seedIfNeeded({
    required List<SpaceModel> spaces,
    required SearchService searchService,
  }) async {
    if (await _cacheService.hasQuickAccessKey()) {
      debugPrint(
        '[QuickAccessService] seedIfNeeded: already initialized',
      );
      return const [];
    }

    final items = <QuickAccessItem>[];
    var addedAt = DateTime.now().millisecondsSinceEpoch;
    final usedBuids = <String>{};
    final report = <QuickAccessSeedReport>[];

    // 1. Seed predefined defaults (in defined order) by their VERIFIED buid.
    //    A default is seeded ONLY when its exact buid exists in the loaded
    //    dataset (resolved from the live SpaceModel). When the entity is not
    //    loaded, it is reported as unresolved with the matching-name candidates
    //    found in the dataset — it is NEVER substituted with another location.
    for (final defaultLoc in AppConstants.kDefaultQuickAccessLocations) {
      final match = spaces
          .where((s) => !usedBuids.contains(s.buid) && s.buid == defaultLoc.buid)
          .firstOrNull;
      if (match == null) {
        final candidates = spaces
            .where((s) => s.name.toLowerCase().contains(defaultLoc.name.toLowerCase()))
            .map((s) => '${s.name} (buid: ${s.buid})')
            .toList();
        report.add(
          QuickAccessSeedReport.unresolved(
            requested: defaultLoc,
            candidates: candidates,
          ),
        );
        debugPrint(
          '[QuickAccessService] seedIfNeeded: default "${defaultLoc.label}" '
          'UNRESOLVED (buid ${defaultLoc.buid} not in loaded dataset). '
          'Candidate entities found: ${candidates.isEmpty ? "none" : candidates.join("; ")}',
        );
        continue;
      }
      usedBuids.add(match.buid);
      items.add(
        QuickAccessItem.fromSpace(
          match,
          addedAt: addedAt++,
          category: CategoryDeriver.fromSpaceType(match.spaceType).name,
        ),
      );
      report.add(
        QuickAccessSeedReport.resolved(
          requested: defaultLoc,
          resolvedName: match.name,
          buid: match.buid,
        ),
      );
    }

    // 2. Migrate legacy saved POIs (preserved even when unresolvable now).
    final savedPuids = await _cacheService.getSavedPois();
    for (final puid in savedPuids) {
      final resolved = searchService.findPoiByPuid(puid);
      if (resolved != null) {
        items.add(
          QuickAccessItem.fromPoi(
            resolved,
            addedAt: addedAt++,
            category: CategoryDeriver.fromPoiType(resolved.poisType).name,
          ),
        );
      } else {
        items.add(QuickAccessItem.minimalPoi(puid, addedAt: addedAt++));
      }
    }

    // 3. Persist once, then consume the legacy key.
    await _cacheService.setQuickAccessItems(items);
    if (savedPuids.isNotEmpty) {
      await _cacheService.removeSavedPoisKey();
    }
    debugPrint(
      '[QuickAccessService] seedIfNeeded: seeded ${items.length} item(s)',
    );
    return report;
  }
}