import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Compact navigation bar shown in place of the dynamic content panel while
/// a navigation session is ACTIVE (Navigation Refinement).
///
/// Minimal chrome so the map gets maximum space:
///  * leading pulsing-style indicator + "Navigation active" label,
///  * trailing expand control — re-opens the full dynamic panel WITHOUT
///    ending navigation (the panel offers the minimize control to come back),
///  * trailing close control — ends navigation through the EXISTING
///    `NavigationController.terminateNavigation` flow (wired by MainShell).
///
/// Tapping anywhere on the bar body also expands the panel.
class NavigationBottomBar extends StatelessWidget {
  const NavigationBottomBar({
    super.key,
    required this.onClose,
    required this.onExpand,
    this.subtitle,
  });

  /// Ends the session via existing termination/cleanup flows.
  final VoidCallback onClose;

  /// Re-opens the dynamic panel; navigation must stay active.
  final VoidCallback onExpand;

  /// Optional one-line status (e.g. current floor / destination name).
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          child: InkWell(
            onTap: onExpand,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 6),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.navigation,
                        size: 18, color: Color(0xFF059669)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Navigation active',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.textPrimary)),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Text(subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textTertiary)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open panel',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.keyboard_arrow_up,
                        size: 22, color: AppTheme.textSecondary),
                    onPressed: onExpand,
                  ),
                  IconButton(
                    tooltip: 'End directions',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close,
                        size: 22, color: Color(0xFFDC2626)),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
