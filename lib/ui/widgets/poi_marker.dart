import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/poi_model.dart';

/// Interactive Map Marker for displaying indoor Points of Interest (POIs).
class PoiMarker extends StatelessWidget {
  final PoiModel poi;
  final bool isSelected;
  final VoidCallback onTap;

  const PoiMarker({
    super.key,
    required this.poi,
    this.isSelected = false,
    required this.onTap,
  });

  /// Resolves an appropriate icon for the POI based on its category/type.
  IconData _getIconForType(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('elevator')) return Icons.elevator;
    if (lower.contains('stair')) return Icons.stairs;
    if (lower.contains('toilet') || lower.contains('restroom') || lower.contains('wc')) {
      return Icons.wc;
    }
    if (lower.contains('office')) return Icons.work_outline;
    if (lower.contains('room') || lower.contains('class') || lower.contains('lab')) {
      return Icons.meeting_room;
    }
    if (lower.contains('entrance') || poi.isBuildingEntrance) {
      return Icons.sensor_door;
    }
    if (lower.contains('door') || poi.isDoor) return Icons.door_front_door;
    return Icons.place;
  }

  /// Resolves an accent color for the POI marker.
  Color _getColorForType(String type) {
    if (isSelected) return AppTheme.accent;
    final lower = type.toLowerCase();
    if (lower.contains('elevator')) return const Color(0xFFF59E0B); // Amber
    if (lower.contains('stair')) return const Color(0xFF8B5CF6); // Purple
    if (lower.contains('toilet') || lower.contains('restroom')) return const Color(0xFF06B6D4); // Cyan
    if (lower.contains('office')) return const Color(0xFF3B82F6); // Blue
    if (lower.contains('entrance') || poi.isBuildingEntrance) return const Color(0xFF10B981); // Emerald
    return const Color(0xFF6366F1); // Indigo default
  }

  @override
  Widget build(BuildContext context) {
    final iconData = _getIconForType(poi.poisType);
    final accentColor = _getColorForType(poi.poisType);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : const Color(0xEE0F172A),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : accentColor,
                  width: isSelected ? 2.0 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? accentColor.withValues(alpha: 0.6)
                        : Colors.black45,
                    blurRadius: isSelected ? 6 : 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Icon(
                iconData,
                size: isSelected ? 18 : 15,
                color: isSelected ? Colors.white : accentColor,
              ),
            ),
            const SizedBox(height: 1),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xEE0F172A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                child: Text(
                  poi.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
