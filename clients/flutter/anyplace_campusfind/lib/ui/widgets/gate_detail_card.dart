import 'package:flutter/material.dart';

import '../../config/theme.dart';
import '../../data/models/campus_gate.dart';

/// Gate accent colour used to distinguish campus gates from buildings and
/// indoor POIs on the map. Kept local so gate branding does not touch the
/// shared theme palette.
const Color _gateAccent = Color(0xFF0E9F6E);

/// Floating detail card shown when a campus gate marker is selected.
///
/// Gates are campus-scoped entities independent of the indoor POI pipeline;
/// this card surfaces the gate's identity and a single "Navigate to Gate"
/// action. Navigation target is the gate's exact coordinates from
/// [CampusGate].
class GateDetailCard extends StatelessWidget {
  final CampusGate gate;

  /// Called when the user dismisses the card (X).
  final VoidCallback? onClose;

  /// Called when the user taps "Navigate to Gate".
  final VoidCallback? onNavigate;

  /// Whether a route request to the gate is in flight.
  final bool isLoadingRoute;

  /// Optional message shown beneath the action (e.g. a route-ready or error
  /// message), following the pattern of the POI detail card.
  final String? routeMessage;

  final bool isNavigating;

  /// Ends an in-progress navigation session.
  final VoidCallback? onEndNavigation;

  const GateDetailCard({
    super.key,
    required this.gate,
    this.onClose,
    this.onNavigate,
    this.isLoadingRoute = false,
    this.routeMessage,
    this.isNavigating = false,
    this.onEndNavigation,
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
                    color: _gateAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.meeting_room_outlined,
                      color: _gateAccent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${gate.name} (${gate.id})',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Campus Gate',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _gateAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close,
                        color: AppTheme.textSecondary),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 20,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.my_location,
                    size: 13, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${gate.latitude.toStringAsFixed(6)}, ${gate.longitude.toStringAsFixed(6)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
            ] else
              SizedBox(
                width: double.infinity,
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
                  label: Text(isLoadingRoute
                      ? 'Loading Route...'
                      : 'Navigate to Gate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gateAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _gateAccent.withValues(alpha: 0.4),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
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
                  color: const Color(0xFF0E9F6E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF0E9F6E).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  routeMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF0E9F6E),
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
