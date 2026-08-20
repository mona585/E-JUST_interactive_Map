import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../data/models/poi_model.dart';
import '../data/models/space_model.dart';
import '../providers/providers.dart';
import '../state/space_provider.dart';
import '../utils/category_deriver.dart';

/// EJUST campus center coordinates.
const double _kCampusLat = 30.8603;
const double _kCampusLng = 29.5626;

/// Radius in meters to consider a building as part of the campus.
/// EJUST campus is ~200 feddan (~840k m²) ≈ 517m radius for a circle.
/// Using 800m to comfortably cover the irregular campus shape.
const double _kCampusRadiusMeters = 800;

/// A predefined campus location for Quick Access.
class _QuickAccessLocation {
  final String name;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _QuickAccessLocation({
    required this.name,
    required this.icon,
    required this.color,
    required this.subtitle,
  });
}

/// Static list of Quick Access locations.
/// At runtime, each is matched against loaded buildings by name (case-insensitive contains),
/// but only buildings within the campus radius are considered.
const List<_QuickAccessLocation> _quickAccessLocations = [
  _QuickAccessLocation(
    name: 'Library',
    icon: Icons.menu_book,
    color: Color(0xFF388E3C),
    subtitle: 'Study Spaces',
  ),
  _QuickAccessLocation(
    name: 'Bank',
    icon: Icons.account_balance,
    color: Color(0xFF1565C0),
    subtitle: 'Banking',
  ),
  _QuickAccessLocation(
    name: 'Cafeteria',
    icon: Icons.restaurant,
    color: Color(0xFFD32F2F),
    subtitle: 'Dining',
  ),
  _QuickAccessLocation(
    name: 'Student Affairs',
    icon: Icons.school,
    color: Color(0xFF7E57C2),
    subtitle: 'Student Services',
  ),
  _QuickAccessLocation(
    name: 'Stationery',
    icon: Icons.store,
    color: Color(0xFFEF6C00),
    subtitle: 'Supplies',
  ),
  _QuickAccessLocation(
    name: 'Food',
    icon: Icons.fastfood,
    color: Color(0xFFFFA000),
    subtitle: 'Dining',
  ),
];

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final allBuildings = spaceProvider.spaces;

    // Filter to only campus buildings (within radius of campus center).
    // This ensures new buildings added to campus auto-appear,
    // while buildings from other Anyplace instances worldwide are excluded.
    final campusBuildings = allBuildings.where((s) {
      final dist = Geolocator.distanceBetween(
        _kCampusLat, _kCampusLng, s.latitude, s.longitude,
      );
      return dist <= _kCampusRadiusMeters;
    }).toList();

    // Match predefined locations against campus buildings by name.
    // Uses contains (case-insensitive) so "Blue hall Cafeteria" matches "Cafeteria",
    // "National Bank branch" matches "Bank", "Stationery shop" matches "Stationery", etc.
    final matchedLocations = <(_QuickAccessLocation, SpaceModel)>[];
    final usedBuildings = <String>{};
    for (final loc in _quickAccessLocations) {
      final match = campusBuildings.where((s) =>
          !usedBuildings.contains(s.buid) &&
          s.name.toLowerCase().contains(loc.name.toLowerCase())).firstOrNull;
      if (match != null) {
        matchedLocations.add((loc, match));
        usedBuildings.add(match.buid);
      }
    }

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
            if (matchedLocations.isNotEmpty)
              SizedBox(
                height: 116,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: matchedLocations.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final (loc, space) = matchedLocations[i];
                    return _QuickAccessLocationCard(
                      location: loc,
                      buildingName: space.name,
                      onTap: () {
                        ref.read(shellTabProvider.notifier).state = 1;
                        provider.Provider.of<SpaceProvider>(context, listen: false)
                            .selectSpace(space);
                      },
                    );
                  },
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

class _HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 22),
            onPressed: () => ref.read(shellTabProvider.notifier).state = 4,
          ),
        ),
      ],
    );
  }
}

class _QuickAccessLocationCard extends StatelessWidget {
  const _QuickAccessLocationCard({
    required this.location,
    required this.buildingName,
    required this.onTap,
  });

  final _QuickAccessLocation location;
  final String buildingName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: location.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: location.color.withValues(alpha: 0.3)),
                ),
                child: Icon(location.icon, color: location.color, size: 20),
              ),
              const Spacer(),
              Text(buildingName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
              const SizedBox(height: 2),
              Text(location.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
            ],
          ),
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
    ref.watch(cacheVersionProvider);

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
