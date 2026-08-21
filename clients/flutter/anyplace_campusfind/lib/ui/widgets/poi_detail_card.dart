import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/models/poi_model.dart';
import '../../data/models/quick_access_item.dart';
import '../../widgets/quick_access_toggle_button.dart';

/// Floating detail card displayed when an indoor POI is selected.
class PoiDetailCard extends StatelessWidget {
  final PoiModel poi;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onClearRoute;
  final VoidCallback? onStartDirections;
  final VoidCallback? onEndNavigation;
  final bool isLoadingRoute;
  final bool hasActiveRoute;
  final bool isNavigating;
  final String? routeMessage;
  final bool isRouteUnsupported;
  final QuickAccessItem Function()? quickAccessItemBuilder;

  const PoiDetailCard({
    super.key,
    required this.poi,
    required this.onClose,
    required this.onNavigate,
    required this.onClearRoute,
    this.onStartDirections,
    this.onEndNavigation,
    this.isLoadingRoute = false,
    this.hasActiveRoute = false,
    this.isNavigating = false,
    this.routeMessage,
    this.isRouteUnsupported = false,
    this.quickAccessItemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.place,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        poi.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                              ),
                            ),
                            child: Text(
                              poi.poisType,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Floor ${poi.floorNumber}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
                if (quickAccessItemBuilder != null) ...[
                  const SizedBox(width: 4),
                  QuickAccessToggleButton(
                    itemBuilder: quickAccessItemBuilder!,
                  ),
                ],
              ],
            ),
            if (poi.description != null && poi.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                poi.description!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.my_location,
                  size: 13,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${poi.latitude.toStringAsFixed(6)}, ${poi.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // During active navigation — show End Navigation button
            if (isNavigating) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onEndNavigation,
                  icon: const Icon(Icons.stop_circle, size: 18),
                  label: const Text('End Navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFDC2626),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  if (hasActiveRoute) ...[
                    // Route loaded in preview — show "Start Directions"
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onStartDirections,
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: const Text('Start Directions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: onClearRoute,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textPrimary,
                        side: const BorderSide(color: AppTheme.cardBorder),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ] else ...[
                    // No route yet — show "Route Here"
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isLoadingRoute ? null : onNavigate,
                        icon: isLoadingRoute
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.directions, size: 18),
                        label: Text(
                          isLoadingRoute ? 'Loading Route...' : 'Route Here',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppTheme.primary.withValues(alpha: 0.4),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            if (routeMessage != null && routeMessage!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: hasActiveRoute
                      ? const Color(0xFF059669).withValues(alpha: 0.08)
                      : isRouteUnsupported
                      ? const Color(0xFFF5F5F5)
                      : const Color(0xFFDC2626).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasActiveRoute
                        ? const Color(0xFF059669).withValues(alpha: 0.2)
                        : isRouteUnsupported
                        ? AppTheme.cardBorder
                        : const Color(0xFFDC2626).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  routeMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActiveRoute
                        ? const Color(0xFF059669)
                        : isRouteUnsupported
                        ? AppTheme.textSecondary
                        : const Color(0xFFDC2626),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
