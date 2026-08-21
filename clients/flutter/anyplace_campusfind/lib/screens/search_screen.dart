import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/search_provider.dart';
import '../services/search_service.dart';
import '../utils/category_deriver.dart';
import '../widgets/search_result_card.dart';
import 'detail_navigation.dart';

const int _maxBuildingOptions = 25;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  EntityCategory? _selectedCategory;
  String? _selectedBuid;
  late final SearchService _searchService;

  @override
  void initState() {
    super.initState();
    _searchService = ref.read(searchServiceProvider);
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
    setState(() {});
  }

  void _clearSearch() {
    _controller.clear();
    setState(() {});
  }

  bool get _hasActiveFilters => _selectedCategory != null || _selectedBuid != null;

  int get _activeFilterCount {
    int count = 0;
    if (_selectedCategory != null) count++;
    if (_selectedBuid != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final searchService = _searchService;
    final query = _controller.text;
    final results = searchService.query(
      query,
      category: _selectedCategory,
      buid: _selectedBuid,
    );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
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
            const Flexible(
              child: Text('Search Directory',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ),
          ],
        ), ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search rooms, POIs...',
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
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _showFilterSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: _hasActiveFilters
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hasActiveFilters ? AppTheme.primary : AppTheme.cardBorder,
                        width: _hasActiveFilters ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.tune,
                          size: 18,
                          color: _hasActiveFilters ? AppTheme.primary : AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Filters',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _hasActiveFilters ? AppTheme.primary : AppTheme.textPrimary,
                          ),
                        ),
                        if (_activeFilterCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$_activeFilterCount',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_hasActiveFilters) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedCategory = null;
                        _selectedBuid = null;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Flexible(
                  child: Text('Search Results (${results.length})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                ),
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
                          _controller.text.isNotEmpty || _hasActiveFilters
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

  static const _priorityBuid = 'building_b8f4e123-d58f-45b7-9942-4492b198c9e4_1786536183663';

  void _showFilterSheet(BuildContext context) {
    final buids = _searchService.discoverBuids();
    final categories = _searchService.discoverCategoriesFromIndex();

    final sorted = List<({String buid, String name})>.from(buids);
    final b7Index = sorted.indexWhere((b) => b.buid == _priorityBuid);
    final ({String buid, String name})? b7 = b7Index >= 0 ? sorted.removeAt(b7Index) : null;
    if (b7 != null) sorted.insert(0, b7);
    final displayBuids = sorted.take(_maxBuildingOptions).toList();

    String? pendingBuid = _selectedBuid;
    EntityCategory? pendingCategory = _selectedCategory;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textTertiary.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Filters',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                                SizedBox(height: 4),
                                Text('Narrow results by building and POI type.',
                                    style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                              ],
                            ),
                          ),
                          if (pendingBuid != null || pendingCategory != null)
                            TextButton(
                              onPressed: () {
                                setSheetState(() {
                                  pendingBuid = null;
                                  pendingCategory = null;
                                });
                              },
                              child: const Text('Reset', style: TextStyle(fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          _buildSectionHeader('Building'),
                          _buildOptionTile(
                            label: 'All buildings',
                            isSelected: pendingBuid == null,
                            onTap: () => setSheetState(() => pendingBuid = null),
                          ),
                          for (final b in displayBuids)
                            _buildOptionTile(
                              label: b.name,
                              isSelected: pendingBuid == b.buid,
                              onTap: () => setSheetState(() => pendingBuid = b.buid),
                            ),
                          if (buids.length > _maxBuildingOptions)
                            Padding(
                              padding: const EdgeInsets.only(left: 16, top: 4),
                              child: Text(
                                'Showing $_maxBuildingOptions of ${buids.length} buildings',
                                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
                              ),
                            ),
                          const SizedBox(height: 20),
                          _buildSectionHeader('POI Type'),
                          _buildOptionTile(
                            label: 'All types',
                            isSelected: pendingCategory == null,
                            onTap: () => setSheetState(() => pendingCategory = null),
                          ),
                          for (final c in categories)
                            _buildOptionTile(
                              label: c.label,
                              icon: c.icon,
                              iconColor: c.color,
                              isSelected: pendingCategory == c,
                              onTap: () => setSheetState(() => pendingCategory = c),
                            ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                _selectedBuid = pendingBuid;
                                _selectedCategory = pendingCategory;
                              });
                              Navigator.of(context).pop();
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Apply Filters',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    IconData? icon,
    Color? iconColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? AppTheme.textSecondary),
              const SizedBox(width: 12),
            ] else if (isSelected) ...[
              Icon(Icons.check_circle, size: 18, color: AppTheme.primary),
              const SizedBox(width: 12),
            ] else ...[
              const SizedBox(width: 30),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 18, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}
