import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Floating map controls (zoom, search, recenter, reload).
class MapControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenter;
  final VoidCallback onSearch;
  final VoidCallback onReload;
  final bool isLoading;
  final bool isTrackingLocation;
  final bool isLocating;

  const MapControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenter,
    required this.onSearch,
    required this.onReload,
    this.isLoading = false,
    this.isTrackingLocation = false,
    this.isLocating = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildControlButton(
          icon: Icons.search,
          tooltip: 'Browse / Search Buildings',
          onPressed: onSearch,
          highlight: true,
        ),
        const SizedBox(height: 10),
        _buildControlButton(
          icon: isLocating
              ? Icons.gps_fixed
              : (isTrackingLocation ? Icons.my_location : Icons.location_searching),
          tooltip: 'My Location / Recenter View',
          onPressed: onRecenter,
          iconColor: isTrackingLocation ? AppTheme.primary : AppTheme.textPrimary,
        ),
        const SizedBox(height: 10),
        _buildControlButton(
          icon: Icons.add,
          tooltip: 'Zoom In',
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 6),
        _buildControlButton(
          icon: Icons.remove,
          tooltip: 'Zoom Out',
          onPressed: onZoomOut,
        ),
        const SizedBox(height: 10),
        _buildControlButton(
          icon: isLoading ? Icons.hourglass_top : Icons.refresh,
          tooltip: 'Reload Buildings from Server',
          onPressed: isLoading ? null : onReload,
        ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool highlight = false,
    Color iconColor = AppTheme.textPrimary,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: highlight ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.1),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: highlight
                    ? AppTheme.primary
                    : AppTheme.cardBorder,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: highlight ? Colors.white : iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
