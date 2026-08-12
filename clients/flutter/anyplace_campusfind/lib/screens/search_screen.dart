import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/search_provider.dart';
import '../widgets/search_result_card.dart';
import 'detail_navigation.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
  }

  void _clearAllFilters() {
    _controller.clear();
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(searchCategoryFilterProvider.notifier).state = null;
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(searchIndexProvider);
    final query = ref.watch(searchQueryProvider);
    final category = ref.watch(searchCategoryFilterProvider);

    final categories = index.all.map((r) => r.category).toSet().toList();
    final results = index.query(query, category: category);
    final hasActiveFilter = query.isNotEmpty || category != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_location_alt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Search Directory',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: AppTheme.textSecondary, size: 22),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              controller: _controller,
              onChanged: (v) =>
                  ref.read(searchQueryProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Search professors, rooms, halls...',
                prefixIcon: const Icon(Icons.search, size: 22, color: AppTheme.textTertiary),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppTheme.textTertiary),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Filter By label + chips
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Filter By',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _FilterChipWidget(
                  label: 'Professors',
                  selected: category == null,
                  onTap: () =>
                      ref.read(searchCategoryFilterProvider.notifier).state = null,
                ),
                for (final c in categories)
                  _FilterChipWidget(
                    label: c.label,
                    selected: category == c,
                    onTap: () =>
                        ref.read(searchCategoryFilterProvider.notifier).state =
                            category == c ? null : c,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Results header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Search Results (${results.length})',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const Spacer(),
                if (hasActiveFilter)
                  GestureDetector(
                    onTap: _clearAllFilters,
                    child: const Text('Clear filters',
                        style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Results list
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(hasActiveFilter ? 'No results match your filters' : 'Start typing to search',
                            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 14)),
                        if (hasActiveFilter) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _clearAllFilters,
                            icon: const Icon(Icons.refresh, size: 18),
                            label: const Text('Clear filters'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: results.length,
                    itemBuilder: (context, i) => SearchResultCard(
                      result: results[i],
                      onTap: () => openSearchResult(context, ref, results[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipWidget extends StatelessWidget {
  const _FilterChipWidget({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
