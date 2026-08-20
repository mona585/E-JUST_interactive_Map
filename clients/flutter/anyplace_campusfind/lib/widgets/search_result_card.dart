import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../data/models/quick_access_item.dart';
import '../providers/search_provider.dart';
import '../widgets/quick_access_toggle_button.dart';

class SearchResultCard extends ConsumerWidget {
  const SearchResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  IconData get _icon {
    switch (result.entityType) {
      case 'space':
        return Icons.business;
      case 'floor':
        return Icons.layers;
      case 'poi':
        return result.category.icon;
      default:
        return Icons.place;
    }
  }

  Color get _iconColor => result.category.color;

  String get _entityLabel {
    switch (result.entityType) {
      case 'space':
        return 'Building';
      case 'floor':
        return 'Floor';
      case 'poi':
        return result.subtitle.isNotEmpty ? result.subtitle : 'Place';
      default:
        return '';
    }
  }

  /// Builds a Quick Access item for savable entities (building or POI).
  /// Returns null for floors and other unsupported types.
  QuickAccessItem? _buildItem() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (result.entityType == 'space' && result.space != null) {
      return QuickAccessItem.fromSpace(
        result.space!,
        addedAt: now,
        category: result.category.name,
      );
    }
    if (result.entityType == 'poi' && result.poi != null) {
      return QuickAccessItem.fromPoi(
        result.poi!,
        addedAt: now,
        category: result.category.name,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = _buildItem();

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
                  color: _iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icon, color: _iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                        _entityLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textTertiary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (item != null)
                QuickAccessToggleButton(
                  itemBuilder: () => _buildItem()!,
                )
              else
                Icon(Icons.arrow_outward,
                    size: 16, color: AppTheme.primary.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}