import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/search_service.dart';
import '../utils/category_deriver.dart';

export '../services/search_service.dart' show SearchResult;

/// Singleton search service shared across the app.
final searchServiceProvider = Provider<SearchService>((ref) {
  final service = SearchService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current search query text.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Active category filter (null = all).
final searchCategoryFilterProvider = StateProvider<EntityCategory?>((ref) => null);

/// Derived: executes search whenever query or category changes.
final searchResultsProvider = Provider<List<SearchResult>>((ref) {
  final service = ref.watch(searchServiceProvider);
  final query = ref.watch(searchQueryProvider);
  final category = ref.watch(searchCategoryFilterProvider);
  return service.query(query, category: category);
});
