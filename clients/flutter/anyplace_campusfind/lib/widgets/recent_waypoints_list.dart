import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../data/models/poi_model.dart';
import '../providers/providers.dart';
import '../state/space_provider.dart';
import '../utils/category_deriver.dart';

/// Recent Waypoints list resolved against the loaded POI set. Extracted from
/// the former Home tab so the campus dynamic content panel can mount the
/// exact same experience.
class RecentWaypointsList extends ConsumerWidget {
  const RecentWaypointsList({super.key});

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

        final spaceProvider =
            provider.Provider.of<SpaceProvider>(context, listen: false);
        final results = puids
            .map((puid) => spaceProvider.pois.where((p) => p.puid == puid).firstOrNull)
            .whereType<PoiModel>()
            .toList();

        if (results.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          children: [
            for (final poi in results)
              RecentWaypointCard(
                poi: poi,
                onTap: () async {
                  // shellTabProvider is kept for compatibility; the map-first
                  // shell always shows the map, so this is a harmless no-op.
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

class RecentWaypointCard extends StatelessWidget {
  const RecentWaypointCard({super.key, required this.poi, required this.onTap});

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
