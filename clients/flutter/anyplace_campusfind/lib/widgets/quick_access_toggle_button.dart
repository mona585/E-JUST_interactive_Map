import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../data/models/quick_access_item.dart';
import '../providers/providers.dart';

/// Unified bookmark toggle for adding/removing a location to/from Quick
/// Access. Shows the saved/bookmarked state and toggles with a single tap.
class QuickAccessToggleButton extends ConsumerWidget {
  /// Builder is used so the current saved state can be re-evaluated from the
  /// latest [QuickAccessItem] whenever the cache version changes.
  final QuickAccessItem Function() itemBuilder;

  const QuickAccessToggleButton({super.key, required this.itemBuilder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    ref.watch(cacheVersionProvider);

    return FutureBuilder<bool>(
      future: () async {
        final item = itemBuilder();
        return cache.isQuickAccessItem(item.type, item.id);
      }(),
      builder: (context, snapshot) {
        final isSaved = snapshot.data ?? false;
        return IconButton(
          onPressed: () async {
            final item = itemBuilder();
            await cache.toggleQuickAccessItem(item);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(isSaved
                      ? 'Removed from Quick Access'
                      : 'Added to Quick Access'),
                ),
              );
            }
          },
          icon: Icon(
            isSaved ? Icons.bookmark : Icons.bookmark_border,
            color: isSaved ? AppTheme.primary : AppTheme.textSecondary,
          ),
          tooltip: isSaved
              ? 'Remove from Quick Access'
              : 'Add to Quick Access',
        );
      },
    );
  }
}