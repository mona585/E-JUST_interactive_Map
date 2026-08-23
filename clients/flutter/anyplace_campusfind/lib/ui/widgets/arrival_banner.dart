import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../state/navigation_controller.dart';

/// Arrival banner shown while the canonical machine is in ARRIVED
/// (ORIGINAL PHASE 6 arrival state, ORIGINAL PHASE 7 exposure).
///
/// Self-gating: renders nothing outside ARRIVED. ARRIVED persists until the
/// user acts — [onDone] is the only exit offered here and maps to the same
/// end-navigation path as the existing End buttons (end session + clear
/// route). No auto-dismiss, no timer.
class ArrivalBanner extends StatelessWidget {
  const ArrivalBanner({super.key, required this.onDone});

  /// Invoked when the user acknowledges the arrival (Done).
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Consumer<NavigationController>(
      builder: (context, nav, _) {
        if (!nav.isArrived) return const SizedBox.shrink();
        final destination = nav.destinationSpace?.name ?? 'destination';

        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            key: const ValueKey('arrival_banner'),
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF059669).withValues(alpha: 0.4),
              ),
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
                const Icon(
                  Icons.where_to_vote,
                  size: 18,
                  color: Color(0xFF059669),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Arrived at $destination',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onDone,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
