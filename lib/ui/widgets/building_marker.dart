import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/space_model.dart';

/// A custom visual marker for a building on FlutterMap.
class BuildingMarker extends StatelessWidget {
  final SpaceModel space;
  final bool isSelected;
  final VoidCallback onTap;

  const BuildingMarker({
    super.key,
    required this.space,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = isSelected ? 48.0 : 38.0;
    final pinColor = isSelected ? AppTheme.markerSelected : AppTheme.markerColor;

    return GestureDetector(
      key: Key('marker_tap_${space.buid}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulse glow when selected
            if (isSelected)
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.markerSelected.withValues(alpha: 0.35),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.markerSelected.withValues(alpha: 0.6),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

            // Main Pin Body
            Container(
              width: isSelected ? 38.0 : 30.0,
              height: isSelected ? 38.0 : 30.0,
              decoration: BoxDecoration(
                color: pinColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: isSelected ? 2.5 : 1.8,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black45,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Icon(
                  space.spaceType.toLowerCase() == 'vessel'
                      ? Icons.directions_boat
                      : Icons.business,
                  color: Colors.white,
                  size: isSelected ? 20.0 : 16.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
