import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/poi_model.dart';

/// Floating detail card displayed when an indoor POI is selected.
class PoiDetailCard extends StatelessWidget {
  final PoiModel poi;
  final VoidCallback onClose;
  final VoidCallback onNavigate;
  final VoidCallback onClearRoute;
  final bool isLoadingRoute;
  final bool hasActiveRoute;
  final String? routeMessage;
  final bool isRouteUnsupported;

  const PoiDetailCard({
    super.key,
    required this.poi,
    required this.onClose,
    required this.onNavigate,
    required this.onClearRoute,
    this.isLoadingRoute = false,
    this.hasActiveRoute = false,
    this.routeMessage,
    this.isRouteUnsupported = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xF20F172A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 16,
              offset: Offset(0, 4),
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
                    color: AppTheme.accent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.place,
                    color: AppTheme.accent,
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
                              color: const Color(
                                0xFF6366F1,
                              ).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: const Color(
                                  0xFF818CF8,
                                ).withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              poi.poisType,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF818CF8),
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
            Row(
              children: [
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
                        : Icon(
                            hasActiveRoute ? Icons.alt_route : Icons.directions,
                            size: 18,
                          ),
                    label: Text(
                      isLoadingRoute
                          ? 'Loading Route...'
                          : hasActiveRoute
                          ? 'Refresh Route'
                          : 'Route Here',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryLight,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppTheme.primaryLight.withValues(
                        alpha: 0.6,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (hasActiveRoute) ...[
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: onClearRoute,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: Color(0x33FFFFFF)),
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
                ],
              ],
            ),
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
                      ? const Color(0xFF059669).withValues(alpha: 0.18)
                      : isRouteUnsupported
                      ? Colors.white10
                      : const Color(0xFFDC2626).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasActiveRoute
                        ? const Color(0xFF34D399).withValues(alpha: 0.3)
                        : isRouteUnsupported
                        ? const Color(0x33FFFFFF)
                        : const Color(0xFFF87171).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  routeMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: hasActiveRoute
                        ? const Color(0xFF6EE7B7)
                        : isRouteUnsupported
                        ? AppTheme.textSecondary
                        : const Color(0xFFFCA5A5),
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
