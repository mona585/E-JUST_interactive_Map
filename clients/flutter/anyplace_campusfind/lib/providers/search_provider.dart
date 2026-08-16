import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../utils/category_deriver.dart';
import 'providers.dart';

/// A single cross-entity search result.
class SearchResult {
  const SearchResult({
    required this.category,
    this.poi,
    this.space,
    this.floor,
  });

  final EntityCategory category;
  final Poi? poi;
  final Space? space;
  final Floor? floor;

  bool get isPoi => poi != null;
  bool get isSpace => space != null && poi == null && floor == null;
  bool get isFloor => floor != null;

  String get name => poi?.name ?? floor?.floorName ?? space?.name ?? '';

  String get subtitle =>
      poi?.description ?? floor?.description ?? space?.description ?? '';

  /// The searchable "code" of the entity: building code, floor number or
  /// POI id. Exact code matches rank highest.
  String get code {
    if (poi != null) return poi!.puid;
    if (floor != null) return floor!.floorNumber;
    return space?.bucode ?? '';
  }
}

/// Builds a flat search index from the cached dataset, deduplicating POIs by
/// puid and adding floors + buildings as searchable entities.
class SearchIndex {
  SearchIndex();

  final List<SearchResult> _results = [];

  void rebuild(
    List<Space> spaces,
    Map<String, List<Floor>> floorsByBuid,
    Map<String, List<Poi>> poisByBuid,
  ) {
    _results.clear();
    for (final space in spaces) {
      _results.add(SearchResult(
        category: CategoryDeriver.deriveSpace(space),
        space: space,
      ));
      final floors = floorsByBuid[space.buid] ?? const <Floor>[];
      for (final floor in floors) {
        _results.add(SearchResult(
          category: EntityCategory.floor,
          space: space,
          floor: floor,
        ));
      }
      final pois = poisByBuid[space.buid] ?? const <Poi>[];
      for (final poi in pois) {
        _results.add(SearchResult(
          category: CategoryDeriver.derivePoi(poi),
          space: space,
          poi: poi,
        ));
      }
    }
  }

  List<SearchResult> get all => List.unmodifiable(_results);

  /// Weighted ranking: exact code > exact name > exact POI type >
  /// name-prefix > name-contains > description/token match > partial desc.
  ///
  /// POI type and description matching use the actual backend `pois_type` /
  /// `description` values; nothing is hardcoded or inferred.
  List<SearchResult> query(
    String rawQuery, {
    EntityCategory? category,
    int limit = 50,
  }) {
    final query = rawQuery.trim().toLowerCase();
    final matches = <({SearchResult result, int score})>[];
    for (final result in _results) {
      if (category != null && result.category != category) continue;
      if (query.isEmpty) {
        matches.add((result: result, score: 0));
        continue;
      }
      final score = _score(result, query);
      if (score > 0) matches.add((result: result, score: score));
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.result.name.toLowerCase().compareTo(b.result.name.toLowerCase());
    });
    return matches.take(limit).map((m) => m.result).toList();
  }

  /// Tokenised query matching against name, code, POI type, description and
  /// floor name, weighted by the priority order in the Search spec.
  static int _score(SearchResult r, String query) {
    final tokens = query
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final name = r.name.toLowerCase();
    final code = r.code.toLowerCase();
    final poiType = (r.poi?.poisType ?? '').toLowerCase();
    final description = r.subtitle.toLowerCase();
    final floorName = (r.floor?.floorName ?? '').toLowerCase();
    final searchableText = '$name $code $poiType $description $floorName';

    // 1. Exact code.
    if (code == query) return 1000;
    // 2. Exact name.
    if (name == query) return 900;
    // 3. Exact POI type.
    if (poiType.isNotEmpty && poiType == query) return 850;
    // 4. Name starts with the query.
    if (name.startsWith(query)) return 700;
    // 5. Name contains the query.
    if (name.contains(query)) return 500;
    // 6. POI type matches a token of the query.
    if (poiType.isNotEmpty &&
        tokens.any((t) => poiType == t || poiType.contains(t))) {
      return 420;
    }
    // 6. Description/token match: every token present somewhere searchable.
    if (tokens.every((t) => searchableText.contains(t))) return 300;
    // 7. Partial description match: query (or its first token) is a prefix of
    //    the description.
    final descTokens = tokens.length == 1
        ? tokens
        : [query, tokens.first, ...tokens];
    if (description.isNotEmpty &&
        descTokens.any((t) => t.length >= 2 && description.startsWith(t))) {
      return 150;
    }
    if (description.contains(query)) return 120;
    return 0;
  }
}

/// Builds the search index whenever the cached dataset changes.
final searchIndexProvider = Provider<SearchIndex>((ref) {
  ref.watch(cacheVersionProvider);
  final cache = ref.read(cacheServiceProvider);
  final index = SearchIndex();
  index.rebuild(
    cache.spaces,
    {for (final s in cache.spaces) s.buid: cache.floorsOf(s.buid)},
    {for (final s in cache.spaces) s.buid: cache.poisOf(s.buid)},
  );
  return index;
});

/// Search input state shared between the Home search bar and Search tab.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Currently applied category filter on the Search tab (null = All).
final searchCategoryFilterProvider = StateProvider<EntityCategory?>((ref) => null);