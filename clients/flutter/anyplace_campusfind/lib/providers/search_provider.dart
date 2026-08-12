import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi.dart';
import '../models/space.dart';
import '../utils/category_deriver.dart';
import 'providers.dart';

/// A single cross-entity search result.
class SearchResult {
  const SearchResult({required this.category, this.poi, this.space});

  final EntityCategory category;
  final Poi? poi;
  final Space? space;

  bool get isPoi => poi != null;
  bool get isSpace => space != null;

  String get name => poi?.name ?? space?.name ?? '';
  String get subtitle => poi?.description ?? space?.description ?? '';
}

/// Builds a flat search index from the cached dataset, deduplicating POIs by
/// puid and adding buildings as searchable entities.
class SearchIndex {
  final List<SearchResult> _results = [];

  void rebuild(List<Space> spaces, Map<String, List<Poi>> poisByBuid) {
    _results.clear();
    for (final space in spaces) {
      _results.add(SearchResult(
        category: CategoryDeriver.deriveSpace(space),
        space: space,
      ));
      final pois = poisByBuid[space.buid] ?? const <Poi>[];
      for (final poi in pois) {
        _results.add(SearchResult(
          category: CategoryDeriver.derivePoi(poi),
          poi: poi,
        ));
      }
    }
  }

  List<SearchResult> get all => List.unmodifiable(_results);

  List<SearchResult> query(
    String rawQuery, {
    EntityCategory? category,
    int limit = 50,
  }) {
    final query = rawQuery.trim().toLowerCase();
    final matches = <SearchResult>[];
    for (final result in _results) {
      if (category != null && result.category != category) continue;
      if (query.isNotEmpty && !result.name.toLowerCase().contains(query)) {
        continue;
      }
      matches.add(result);
      if (matches.length >= limit) break;
    }
    return matches;
  }
}

/// Builds the search index whenever the cached dataset changes.
final searchIndexProvider = Provider<SearchIndex>((ref) {
  final cache = ref.watch(cacheServiceProvider);
  final index = SearchIndex();
  index.rebuild(cache.spaces, {
    for (final s in cache.spaces) s.buid: cache.poisOf(s.buid),
  });
  return index;
});

/// Search input state shared between the Home search bar and Search tab.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Currently applied category filter on the Search tab (null = All).
final searchCategoryFilterProvider = StateProvider<EntityCategory?>((ref) => null);
