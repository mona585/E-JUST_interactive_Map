import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../config/theme.dart';
import '../../screens/profile_screen.dart';
import '../../screens/search_overlay.dart';
import '../../state/location_provider.dart';
import '../../state/space_provider.dart';

/// Top Search / Directions bar of the map-first shell.
///
/// Opens the From/To [SearchOverlay] (Phase 2). The overlay is independent
/// from the bottom dynamic content area.
class MapTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const MapTopBar({super.key});

  static const _searchHint = 'Search buildings, rooms, services…';

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final locationProvider = provider.Provider.of<LocationProvider>(context);

    final hasSpacesError =
        spaceProvider.hasError && spaceProvider.spaces.isEmpty;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const SearchOverlay()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
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
                          const Icon(Icons.search,
                              color: AppTheme.textTertiary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(_searchHint,
                                style: const TextStyle(
                                    color: AppTheme.textTertiary,
                                    fontSize: 14)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (locationProvider.isIndoorWifiActive) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi,
                            size: 13, color: Color(0xFF0D9488)),
                        Text(
                          ' ${locationProvider.latestIndoorEstimate?.matchedAps ?? 0}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D9488),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.cardBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.person_outline,
                        color: AppTheme.textSecondary, size: 22),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => const ProfileScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
            // Compact spaces status line — replaces the former "Anyplace"
            // header chip (loading spinner / retry affordance preserved).
            if (spaceProvider.isLoading || hasSpacesError)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: GestureDetector(
                  onTap: hasSpacesError && !spaceProvider.isLoading
                      ? () => spaceProvider.loadSpaces(forceReload: true)
                      : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (spaceProvider.isLoading)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        )
                      else
                        const Icon(Icons.error_outline,
                            size: 13, color: Color(0xFFDC2626)),
                      const SizedBox(width: 6),
                      Text(
                        spaceProvider.isLoading
                            ? 'Loading campus spaces…'
                            : 'No connection — tap to retry',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: hasSpacesError
                              ? const Color(0xFFDC2626)
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
