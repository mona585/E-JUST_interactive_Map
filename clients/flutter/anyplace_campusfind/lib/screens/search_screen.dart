import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/search_provider.dart';
import '../services/search_service.dart';
import '../utils/category_deriver.dart';
import '../widgets/search_result_card.dart';
import 'detail_navigation.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  EntityCategory? _selectedCategory;
  late final SearchService _searchService;

  @override
  void initState() {
    super.initState();
    _searchService = ref.read(searchServiceProvider);
    // Listen to SearchService changes (index updates from background sync)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchService.addListener(_onSearchIndexChanged);
    });
  }

  @override
  void dispose() {
    _searchService.removeListener(_onSearchIndexChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onSearchIndexChanged() {
    // Rebuild when the search index changes (new data indexed)
    setState(() {});
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final searchService = _searchService;
    final query = _controller.text;
    final results = searchService.query(query, category: _selectedCategory);
    final categories = _discoverCategories(searchService);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              controller: _controller,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search buildings, rooms, professors...',
                prefixIcon: const Icon(Icons.search, size: 22, color: AppTheme.textTertiary),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 20, color: AppTheme.textTertiary),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
                // "All" chip
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedCategory == null
                            ? AppTheme.primary.withValues(alpha: 0.1)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedCategory == null ? AppTheme.primary : AppTheme.cardBorder,
                          width: _selectedCategory == null ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        'All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _selectedCategory == null ? AppTheme.primary : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                // Category chips
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCategory = (_selectedCategory == c) ? null : c;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: (_selectedCategory == c)
                              ? c.color.withValues(alpha: 0.1)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (_selectedCategory == c) ? c.color : AppTheme.cardBorder,
                            width: (_selectedCategory == c) ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          c.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: (_selectedCategory == c) ? c.color : AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Search Results (${results.length})',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                if (searchService.isSyncing) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${searchService.syncedBuildings}/${searchService.totalBuildings}',
                    style: TextStyle(fontSize: 11, color: AppTheme.textTertiary),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off, size: 48, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          _controller.text.isNotEmpty || _selectedCategory != null
                              ? 'No results match your search'
                              : 'Start typing to search',
                          style: const TextStyle(color: AppTheme.textTertiary, fontSize: 14),
                        ),
                        if (searchService.isSyncing) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Search gets richer as data loads...',
                            style: TextStyle(color: AppTheme.textTertiary.withValues(alpha: 0.6), fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final result = results[i];
                      return SearchResultCard(
                        result: result,
                        onTap: () => openSearchResult(context, ref, result),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<EntityCategory> _discoverCategories(SearchService searchService) {
    final seen = <EntityCategory>{};
    for (final item in searchService.query('', limit: 1000)) {
      seen.add(item.category);
    }
    seen.remove(EntityCategory.other);
    seen.remove(EntityCategory.floor);
    return seen.toList();
  }
}
