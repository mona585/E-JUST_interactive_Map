import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/constants.dart';
import '../models/poi.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../utils/category_deriver.dart';
import '../widgets/search_result_card.dart';
import 'detail_navigation.dart';

/// Home tab: greeting, search entry, dynamic quick-access cards and recent
/// waypoints.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);

    final allPois = <Poi>[
      for (final s in cache.spaces) ...cache.poisOf(s.buid),
    ];
    final categories = CategoryDeriver.discoverCategories(allPois);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Welcome back, Student',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Where are we headed today?',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          // Search entry -> Search tab
          TextField(
            readOnly: true,
            onTap: () => ref.read(shellTabProvider.notifier).state = 2,
            decoration: InputDecoration(
              hintText: 'Search buildings, professors, rooms…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (categories.isNotEmpty) ...[
            Text('Quick Access', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final category in categories)
              _QuickAccessCard(
                category: category,
                onTap: () {
                  ref.read(searchCategoryFilterProvider.notifier).state =
                      category;
                  ref.read(shellTabProvider.notifier).state = 2;
                },
              ),
          ],
          const SizedBox(height: 24),
          Text('Recent Waypoints', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const _RecentWaypointsList(),
        ],
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.category, required this.onTap});

  final EntityCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(_categoryIcon(category), color: scheme.primary),
        title: Text(category.label),
        subtitle: Text('Browse ${category.label.toLowerCase()}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  static IconData _categoryIcon(EntityCategory c) {
    switch (c) {
      case EntityCategory.professor:
        return Icons.person;
      case EntityCategory.cafeteria:
        return Icons.restaurant;
      case EntityCategory.library:
        return Icons.local_library;
      case EntityCategory.lab:
        return Icons.science;
      case EntityCategory.building:
        return Icons.apartment;
      case EntityCategory.other:
        return Icons.place;
    }
  }
}

class _RecentWaypointsList extends ConsumerWidget {
  const _RecentWaypointsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    final index = ref.watch(searchIndexProvider);

    return FutureBuilder(
      future: cache.getRecentWaypoints(),
      builder: (context, snapshot) {
        final puids = snapshot.data ?? const <String>[];
        final results = puids
            .map((puid) => index.all.where((r) => r.poi?.puid == puid).firstOrNull)
            .whereType<SearchResult>()
            .toList();

        if (results.isEmpty) {
          return Text(
            'Nothing here yet.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        }
        return Column(
          children: [
            for (final result in results)
              SearchResultCard(
                result: result,
                onTap: () => openSearchResult(context, ref, result),
              ),
          ],
        );
      },
    );
  }
}
