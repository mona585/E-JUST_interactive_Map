import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../state/navigation_controller.dart';

/// In-card instruction + segment-progress line for the navigation status bar
/// (ORIGINAL PHASE 7 — UI exposure of the Phase 3 segment model).
///
/// Renders nothing when the active route carries no segments; the text is
/// the current segment's own `instruction` verbatim — no invented guidance.
class NavigationInstructionStrip extends StatelessWidget {
  const NavigationInstructionStrip({super.key, required this.nav});

  final NavigationController nav;

  @override
  Widget build(BuildContext context) {
    final segment = nav.currentSegment;
    if (segment == null) return const SizedBox.shrink();

    final index = nav.currentSegmentIndex;
    final total = nav.totalSegments;
    final instruction = segment.instruction;

    return Padding(
      key: const ValueKey('navigation_instruction_strip'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Icon(
            Icons.directions_walk,
            size: 12,
            color: AppTheme.textTertiary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              instruction ?? 'Segment ${index + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (total > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${index + 1}/$total',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
