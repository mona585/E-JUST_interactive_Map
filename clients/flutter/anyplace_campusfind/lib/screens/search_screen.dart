import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_provider.dart';
import '../widgets/filter_chips.dart';
import '../widgets/search_result_card.dart';

/// Search tab: live client-side search across buildings and POIs with
/// dynamic category filter chips.
class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(searchIndexProvider);
    final query = ref.watch(searchQueryProvider);
    final category = ref.watch(searchCategoryFilterProvider);

    final categories = index.all
        .map((r) => r.category)
        .toSet()
        .toList();
    final results = index.query(query, category: category);

    return Scaffold(
      appBar: AppBar(title: const Text('Search Directory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: false,
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            ref.read(searchQueryProvider.notifier).state = '',
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          FilterChips(
            categories: categories,
            selected: category,
            onSelected: (c) =>
                ref.read(searchCategoryFilterProvider.notifier).state = c,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: results.isEmpty
                ? const Center(child: Text('No results'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final result = results[i];
                      return SearchResultCard(
                        result: result,
                        onTap: () {
                          // Detail navigation lands in Phase 4; for now
                          // surface a snackbar with the entity.
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(result.name)),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
