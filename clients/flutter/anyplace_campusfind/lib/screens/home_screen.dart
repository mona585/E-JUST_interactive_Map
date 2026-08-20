import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../data/models/poi_model.dart';
import '../providers/providers.dart';
import '../state/space_provider.dart';
import '../utils/category_deriver.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final allPois = spaceProvider.pois;
    final categories = CategoryDeriver.discoverCategories(allPois);

    return Scaffold(
      appBar: _HomeAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          const Text('Welcome back, Student',
              style: TextStyle(fontSize: 14, color: AppTheme.textTertiary)),
          const SizedBox(height: 4),
          const Text('Where are we headed today?',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => ref.read(shellTabProvider.notifier).state = 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppTheme.textTertiary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Search professors, rooms, halls...',
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 15)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, size: 18, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (spaceProvider.isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Text('Quick Access',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 14),
            if (categories.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _QuickAccessCard(
                    category: categories[i],
                    onTap: () {
                      ref.read(shellTabProvider.notifier).state = 2;
                    },
                  ),
                ),
              ),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text('Recent Waypoints',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: () => ref.read(shellTabProvider.notifier).state = 2,
                  child: const Text('See All', style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const _RecentWaypointsList(),
          ],
        ],
      ),
    );
  }
}

class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
          const Text('CampusFind',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ],
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({required this.category, required this.onTap});

  final EntityCategory category;
  final VoidCallback onTap;

  Color get _categoryColor => category.color;

  String get _subtitle {
    switch (category) {
      case EntityCategory.professor:
        return 'Offices & Hours';
      case EntityCategory.cafeteria:
        return 'Menus & Crow...';
      case EntityCategory.building:
        return 'Halls & Classro...';
      case EntityCategory.library:
        return 'Study Spaces';
      case EntityCategory.lab:
        return 'Lab Schedules';
      case EntityCategory.room:
        return 'Classrooms';
      case EntityCategory.office:
        return 'Faculty';
      case EntityCategory.elevator:
        return 'Vertical';
      case EntityCategory.stairs:
        return 'Vertical';
      case EntityCategory.toilets:
        return 'Facilities';
      case EntityCategory.entrance:
        return 'Access';
      case EntityCategory.floor:
        return 'Levels';
      case EntityCategory.other:
        return 'Browse all';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _categoryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _categoryColor.withValues(alpha: 0.3)),
              ),
              child: Icon(category.icon, color: _categoryColor, size: 22),
            ),
            const Spacer(),
            Text(category.label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 2),
            Text(_subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
          ],
        ),
      ),
    );
  }
}

class _RecentWaypointsList extends ConsumerWidget {
  const _RecentWaypointsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);

    return FutureBuilder(
      future: cache.getRecentWaypoints(),
      builder: (context, snapshot) {
        final puids = snapshot.data ?? const <String>[];

        if (puids.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              children: [
                Icon(Icons.history, size: 40, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                const Text('No recent waypoints yet',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 14)),
              ],
            ),
          );
        }

        final spaceProvider = provider.Provider.of<SpaceProvider>(context, listen: false);
        final results = puids
            .map((puid) => spaceProvider.pois.where((p) => p.puid == puid).firstOrNull)
            .whereType<PoiModel>()
            .toList();

        return Column(
          children: [
            for (final poi in results)
              _RecentWaypointCard(
                poi: poi,
                onTap: () async {
                  ref.read(shellTabProvider.notifier).state = 1;
                  await spaceProvider.navigateToPoi(poi);
                },
              ),
          ],
        );
      },
    );
  }
}

class _RecentWaypointCard extends StatelessWidget {
  const _RecentWaypointCard({required this.poi, required this.onTap});

  final PoiModel poi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = CategoryDeriver.fromPoiType(poi.poisType);
    final iconColor = category.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(category.icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(poi.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(poi.poisType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_outward, size: 16, color: AppTheme.primary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}
