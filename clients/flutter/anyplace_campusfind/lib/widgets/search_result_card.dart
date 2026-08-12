import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/search_provider.dart';

class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  Color get _categoryBadgeColor => result.category.color;

  String get _badgeLabel => result.category.badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(result.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: AppTheme.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _categoryBadgeColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(_badgeLabel,
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Text('${(300 + result.name.hashCode % 500)}m',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.primary)),
                ],
              ),
              if (result.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.primary)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.apartment, size: 16, color: AppTheme.textTertiary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${result.space?.name ?? "Building"} · ${result.poi?.floorName ?? "Floor ${result.poi?.floorNumber ?? "?"}"}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textTertiary),
                    ),
                  ),
                  Icon(Icons.arrow_outward, size: 18, color: AppTheme.primary.withValues(alpha: 0.6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
