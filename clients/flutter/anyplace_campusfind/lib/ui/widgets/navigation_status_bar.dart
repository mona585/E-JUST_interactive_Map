import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../state/navigation_controller.dart';
import '../utils/navigation_display.dart';
import 'navigation_instruction_strip.dart';

/// The navigation status bar shown during a live session
/// (ORIGINAL PHASE 7 — extracted verbatim from MapScreen so the state-aware
/// label/icon projection is testable).
///
/// Exposure only: the icon and label switch on the canonical state; the
/// Phase 5 floor-transition blackout text and the rerouting line behave
/// exactly as before. The segment instruction strip (Phase 3 model) renders
/// inside the same card when the route carries segments.
class NavigationStatusBar extends StatelessWidget {
  const NavigationStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<NavigationController>(
      builder: (context, nav, _) {
        final arrived = nav.isArrived;
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                _statusIcon(nav),
                size: 16,
                color: _statusIconColor(nav),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      navigationStatusLabel(nav),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            arrived ? FontWeight.w700 : FontWeight.w600,
                        color: arrived
                            ? const Color(0xFF059669)
                            : AppTheme.textPrimary,
                      ),
                    ),
                    NavigationInstructionStrip(nav: nav),
                    if (nav.isRerouting)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Recalculating route...',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    if (nav.isPartialRoute)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          nav.activeRoute?.partialRouteWarning ??
                              'Route incomplete — follow the available path and '
                                  'navigate manually where needed',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _statusIcon(NavigationController nav) {
    if (nav.isArrived) return Icons.check_circle;
    if (nav.isPaused) return Icons.gps_off;
    return nav.subState == NavigationSubState.indoor
        ? Icons.wifi
        : nav.subState == NavigationSubState.transitioning
            ? Icons.swap_vert
            : Icons.gps_fixed;
  }

  Color _statusIconColor(NavigationController nav) {
    if (nav.isArrived) return const Color(0xFF059669);
    if (nav.isPaused) return const Color(0xFFF59E0B);
    return nav.subState == NavigationSubState.indoor
        ? const Color(0xFF0D9488)
        : nav.subState == NavigationSubState.transitioning
            ? const Color(0xFFF59E0B)
            : AppTheme.primary;
  }
}
