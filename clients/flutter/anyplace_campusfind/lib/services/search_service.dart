import 'package:flutter/foundation.dart';

import '../data/models/floor_model.dart';
import '../data/models/poi_model.dart';
import '../data/models/space_model.dart';
import '../utils/category_deriver.dart';

/// Unified search result across spaces, floors, and POIs.
class SearchResult {
  const SearchResult({
    required this.name,
    required this.subtitle,
    required this.category,
    required this.score,
    required this.entityType,
    this.space,
    this.floor,
    this.poi,
  });

  final String name;
  final String subtitle;
  final EntityCategory category;
  final int score;
  final String entityType; // 'space', 'floor', 'poi'
  final SpaceModel? space;
  final FloorModel? floor;
  final PoiModel? poi;

  String get puid => poi?.puid ?? '';
}

/// Internal index entry wrapping a searchable entity.
class _SearchableItem {
  const _SearchableItem({
    required this.name,
    this.description,
    this.subtitle,
    this.code,
    this.address,
    required this.entityType,
    required this.category,
    this.space,
    this.floor,
    this.poi,
  });

  final String name;
  final String? description;
  final String? subtitle;
  final String? code;
  final String? address;
  final String entityType;
  final EntityCategory category;
  final SpaceModel? space;
  final FloorModel? floor;
  final PoiModel? poi;
}

/// Core search engine with progressive indexing and ranked full-text search.
class SearchService extends ChangeNotifier {
  final List<_SearchableItem> _items = [];
  bool _isSyncing = false;
  int _syncedBuildings = 0;
  int _totalBuildings = 0;

  bool get isSyncing => _isSyncing;
  int get syncedBuildings => _syncedBuildings;
  int get totalBuildings => _totalBuildings;
  int get itemCount => _items.length;

  // ---- Index methods ----

  /// Index all spaces (buildings) immediately — zero network cost.
  /// Deduplicates by buid to prevent double-indexing on retries.
  void addSpaces(List<SpaceModel> spaces) {
    final existingBuids = _items
        .where((i) => i.entityType == 'space')
        .map((i) => i.space!.buid)
        .toSet();
    for (final space in spaces) {
      if (existingBuids.contains(space.buid)) continue;
      _items.add(_SearchableItem(
        name: space.name,
        description: space.description,
        subtitle: space.spaceType,
        code: space.bucode,
        address: space.address,
        entityType: 'space',
        category: CategoryDeriver.fromSpaceType(space.spaceType),
        space: space,
      ));
    }
    notifyListeners();
  }

  /// Index floors for a building. Deduplicates by buid+floorNumber.
  void addFloors(String buid, List<FloorModel> floors) {
    final existingKeys = _items
        .where((i) => i.entityType == 'floor')
        .map((i) => '${i.floor!.buid}_${i.floor!.floorNumber}')
        .toSet();
    for (final floor in floors) {
      final key = '${buid}_${floor.floorNumber}';
      if (existingKeys.contains(key)) continue;
      _items.add(_SearchableItem(
        name: floor.displayName,
        description: floor.description.isNotEmpty ? floor.description : null,
        subtitle: 'Floor ${floor.floorNumber}',
        entityType: 'floor',
        category: EntityCategory.floor,
        floor: floor,
      ));
    }
    notifyListeners();
  }

  /// Index POIs for a specific floor. Deduplicates by puid.
  void addPois(String buid, String floorNumber, List<PoiModel> pois) {
    final existingPuids = _items
        .where((i) => i.entityType == 'poi')
        .map((i) => i.poi!.puid)
        .toSet();
    for (final poi in pois) {
      if (existingPuids.contains(poi.puid)) continue;
      _items.add(_SearchableItem(
        name: poi.name,
        description: poi.description,
        subtitle: poi.poisType,
        entityType: 'poi',
        category: CategoryDeriver.fromPoiType(poi.poisType),
        poi: poi,
      ));
    }
    notifyListeners();
  }

  void markSyncStarted(int totalBuildings) {
    _isSyncing = true;
    _totalBuildings = totalBuildings;
    _syncedBuildings = 0;
    notifyListeners();
  }

  void markSyncProgress(int synced) {
    _syncedBuildings = synced;
    notifyListeners();
  }

  void markSyncComplete() {
    _isSyncing = false;
    notifyListeners();
  }

  // ---- Query ----

  /// Searches the index with multi-field matching and relevance ranking.
  List<SearchResult> query(String rawQuery, {EntityCategory? category, int limit = 15}) {
    final q = rawQuery.toLowerCase().trim();
    final scored = <(_SearchableItem, int)>[];

    for (final item in _items) {
      final score = _scoreItem(item, q);
      if (score > 0) {
        scored.add((item, score));
      }
    }

    // Sort by score descending, then by type priority (spaces first)
    scored.sort((a, b) {
      final cmp = b.$2.compareTo(a.$2);
      if (cmp != 0) return cmp;
      return _typePriority(a.$1.entityType).compareTo(_typePriority(b.$1.entityType));
    });

    var results = scored
        .take(limit)
        .map((e) => SearchResult(
              name: e.$1.name,
              subtitle: _buildSubtitle(e.$1),
              category: e.$1.category,
              score: e.$2,
              entityType: e.$1.entityType,
              space: e.$1.space,
              floor: e.$1.floor,
              poi: e.$1.poi,
            ))
        .toList();

    if (category != null) {
      results = results.where((r) => r.category == category).toList();
    }

    return results;
  }

  /// Scores a single item against the query. Returns 0 if no match.
  int _scoreItem(_SearchableItem item, String q) {
    if (q.isEmpty) return 1; // Return all items for empty query

    int score = 0;
    final name = item.name.toLowerCase();
    final desc = item.description?.toLowerCase() ?? '';
    final code = item.code?.toLowerCase() ?? '';
    final addr = item.address?.toLowerCase() ?? '';
    final sub = item.subtitle?.toLowerCase() ?? '';

    // Name matching (highest weight)
    if (name == q) {
      score += 100;
    } else if (name.startsWith(q)) {
      score += 80;
    } else if (name.contains(q)) {
      score += 60;
    }

    // Code matching (building codes like "FST02")
    if (code.isNotEmpty) {
      if (code == q) {
        score += 70;
      } else if (code.contains(q)) {
        score += 50;
      }
    }

    // Subtitle/type matching
    if (sub.contains(q)) {
      score += 40;
    }

    // Description matching
    if (desc.contains(q)) {
      score += 30;
    }

    // Address matching
    if (addr.contains(q)) {
      score += 20;
    }

    return score;
  }

  String _buildSubtitle(_SearchableItem item) {
    final parts = <String>[];
    if (item.subtitle != null && item.subtitle!.isNotEmpty) {
      parts.add(item.subtitle!);
    }
    if (item.code != null && item.code!.isNotEmpty) {
      parts.add(item.code!);
    }
    if (item.entityType == 'poi' && item.space != null) {
      // Don't add — space isn't stored on poi items
    }
    if (item.entityType == 'floor' && item.floor != null) {
      // Show parent building context if available
    }
    return parts.isNotEmpty ? parts.join(' · ') : 'Tap for details';
  }

  int _typePriority(String entityType) {
    switch (entityType) {
      case 'space':
        return 0;
      case 'floor':
        return 1;
      case 'poi':
        return 2;
      default:
        return 3;
    }
  }
}
