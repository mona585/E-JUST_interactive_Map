import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../data/models/poi_model.dart';
import '../providers/providers.dart';
import '../state/space_provider.dart';
import '../utils/category_deriver.dart';
import 'detail_navigation.dart';

class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key});

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheServiceProvider);

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
              child: const Icon(Icons.bookmark, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('Saved Places',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
      ),
      body: FutureBuilder<List<String>>(
        future: cache.getSavedPois(),
        builder: (context, snapshot) {
          final savedPuids = snapshot.data ?? const <String>[];

          if (savedPuids.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No saved places yet',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Tap the star on any place to save it here',
                      style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                ],
              ),
            );
          }

          final spaceProvider = provider.Provider.of<SpaceProvider>(context, listen: false);
          final results = savedPuids
              .map((puid) => spaceProvider.pois.where((p) => p.puid == puid).firstOrNull)
              .whereType<PoiModel>()
              .toList();

          if (results.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bookmark_border, size: 64, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text('No saved places loaded',
                      style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Select a building and floor to see saved places',
                      style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            itemCount: results.length,
            itemBuilder: (context, i) {
              final poi = results[i];
              final category = CategoryDeriver.fromPoiType(poi.poisType);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: category.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(category.icon, color: category.color, size: 22),
                  ),
                  title: Text(poi.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  subtitle: Text(poi.poisType,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
                  trailing: IconButton(
                    icon: const Icon(Icons.star, color: AppTheme.primary, size: 22),
                    onPressed: () async {
                      await cache.toggleSavedPoi(poi.puid);
                      setState(() {});
                    },
                  ),
                  onTap: () => openPoi(context, ref, poi.puid),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
