import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../data/models/quick_access_item.dart';
import '../providers/providers.dart';
import '../screens/detail_navigation.dart';
import '../utils/category_deriver.dart';
import 'quick_access_toggle_button.dart';

/// Horizontal Quick Access strip populated from the unified
/// [QuickAccessItem] store. Extracted from the former Home tab so the
/// campus dynamic content panel can mount the exact same experience.
class QuickAccessList extends ConsumerWidget {
  const QuickAccessList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    ref.watch(cacheVersionProvider);

    return FutureBuilder<List<QuickAccessItem>>(
      future: cache.getQuickAccessItems(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <QuickAccessItem>[];

        if (items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              children: [
                Icon(Icons.bookmark_border, size: 40, color: AppTheme.textTertiary.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                const Text('No saved locations yet',
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 14)),
                const SizedBox(height: 4),
                const Text('Tap the bookmark on any building or place to add it',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
              ],
            ),
          );
        }

        return SizedBox(
          height: 116,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final item = items[i];
              return QuickAccessItemCard(
                item: item,
                onTap: () => openQuickAccessItem(context, ref, item),
              );
            },
          ),
        );
      },
    );
  }
}

/// Compact Quick Access card in the style of the original Quick Access UI,
/// populated from a [QuickAccessItem] display snapshot.
class QuickAccessItemCard extends StatelessWidget {
  const QuickAccessItemCard({super.key, required this.item, required this.onTap});

  final QuickAccessItem item;
  final VoidCallback onTap;

  EntityCategory get _category {
    try {
      return EntityCategory.values.byName(item.category);
    } catch (_) {
      return EntityCategory.other;
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = _category;
    final iconColor = category.color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                    ),
                    child: Icon(category.icon, color: iconColor, size: 20),
                  ),
                  const Spacer(),
                  Text(item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            Positioned(
              top: 2,
              right: 2,
              child: Transform.scale(
                scale: 0.8,
                child: QuickAccessToggleButton(itemBuilder: () => item),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
