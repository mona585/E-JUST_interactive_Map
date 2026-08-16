import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/map_theme.dart';
import '../models/floor_model.dart';
import '../models/space_model.dart';
import '../state/space_provider.dart';

/// Card showing detailed metadata, interactive floor selector, and RadioMap status for a selected building.
class BuildingDetailCard extends StatelessWidget {
  final SpaceModel space;
  final VoidCallback onClose;
  final VoidCallback onFocus;

  const BuildingDetailCard({
    super.key,
    required this.space,
    required this.onClose,
    required this.onFocus,
  });

  void _copyBuidToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: space.buid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied buid to clipboard: ${space.buid}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: MapTheme.surfaceLight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SpaceProvider>(
      builder: (context, provider, _) {
        final floors = provider.floors;
        final selectedFloor = provider.selectedFloor;
        final isLoadingFloors = provider.isLoadingFloors;
        final floorsError = provider.floorsErrorMessage;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: const Color(0xF01E293B), // Dark slate with subtle opacity
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: MapTheme.primaryLight.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Title, Tag & Close Button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: MapTheme.primaryLight.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.apartment,
                            color: MapTheme.primaryLight,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                space.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: MapTheme.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (space.bucode != null)
                                    Container(
                                      margin: const EdgeInsets.only(right: 6),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: MapTheme.accent
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: MapTheme.accent
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                      child: Text(
                                        space.bucode!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: MapTheme.accent,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: MapTheme.surfaceLight,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      space.spaceType.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: MapTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: MapTheme.textSecondary,
                          ),
                          onPressed: onClose,
                          tooltip: 'Dismiss',
                          splashRadius: 20,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(color: Color(0x22FFFFFF), height: 1),
                    const SizedBox(height: 12),

                    // Building ID (buid) with Copy Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tag,
                            size: 16,
                            color: MapTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'buid: ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: MapTheme.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              space.buid,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: MapTheme.primaryLight,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          InkWell(
                            onTap: () => _copyBuidToClipboard(context),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: MapTheme.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // FLOORS SECTION
                    _buildFloorsSection(
                      context: context,
                      provider: provider,
                      floors: floors,
                      selectedFloor: selectedFloor,
                      isLoading: isLoadingFloors,
                      errorMessage: floorsError,
                    ),

                    // STATUS BADGES (RadioMap & Floorplan when a floor is selected)
                    if (selectedFloor != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildRadioMapStatusBadge(context, provider),
                          _buildFloorplanStatusBadge(context, provider),
                        ],
                      ),
                    ],

                    const SizedBox(height: 12),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onFocus,
                            icon: const Icon(
                              Icons.center_focus_strong,
                              size: 18,
                            ),
                            label: const Text('Center on Map'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: MapTheme.textPrimary,
                              side: const BorderSide(
                                color: MapTheme.surfaceLight,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloorsSection({
    required BuildContext context,
    required SpaceProvider provider,
    required List<FloorModel> floors,
    required FloorModel? selectedFloor,
    required bool isLoading,
    required String? errorMessage,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedFloor != null
              ? MapTheme.primaryLight.withValues(alpha: 0.5)
              : const Color(0x22FFFFFF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Floors Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.layers,
                    size: 16,
                    color: MapTheme.primaryLight,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Floors',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: MapTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isLoading && floors.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: MapTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${floors.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: MapTheme.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
              if (selectedFloor != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: MapTheme.primaryLight.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: MapTheme.primaryLight.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check,
                        size: 12,
                        color: MapTheme.primaryLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Selected: Floor ${selectedFloor.floorNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: MapTheme.primaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          // Floors Body
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MapTheme.primaryLight,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading floors from Anyplace...',
                    style: TextStyle(
                      fontSize: 12,
                      color: MapTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (errorMessage != null)
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.redAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      provider.loadFloorsForSelectedSpace(forceReload: true),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 11,
                      color: MapTheme.primaryLight,
                    ),
                  ),
                ),
              ],
            )
          else if (floors.isEmpty)
            const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: MapTheme.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  'No indoor floors mapped for this building.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: MapTheme.textSecondary,
                  ),
                ),
              ],
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: floors.map((floor) {
                  final isSelected =
                      selectedFloor?.floorNumber == floor.floorNumber;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => provider.selectFloor(floor),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? MapTheme.primaryLight
                                : const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0x33FFFFFF),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: MapTheme.primaryLight
                                          .withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.layers_outlined,
                                size: 14,
                                color: isSelected
                                    ? Colors.white
                                    : MapTheme.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                floor.displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? Colors.white
                                      : MapTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRadioMapStatusBadge(BuildContext context, SpaceProvider provider) {
    final status = provider.radioMapStatus;
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case RadioMapStatus.loading:
        bgColor = const Color(0xFF0284C7).withValues(alpha: 0.2);
        textColor = const Color(0xFF38BDF8);
        icon = Icons.sync;
        label = 'RadioMap: Downloading...';
      case RadioMapStatus.ready:
        bgColor = const Color(0xFF059669).withValues(alpha: 0.2);
        textColor = const Color(0xFF34D399);
        icon = Icons.wifi_tethering;
        label = provider.isRadioMapCached
            ? 'RadioMap: Ready (Cached)'
            : 'RadioMap: Ready';
      case RadioMapStatus.unsupported:
        bgColor = Colors.white10;
        textColor = MapTheme.textSecondary;
        icon = Icons.info_outline;
        label = 'No RadioMap for this floor';
      case RadioMapStatus.error:
        bgColor = const Color(0xFFDC2626).withValues(alpha: 0.2);
        textColor = const Color(0xFFF87171);
        icon = Icons.error_outline;
        label = provider.radioMapErrorMessage ?? 'RadioMap load failed';
      case RadioMapStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (status == RadioMapStatus.error) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () =>
                  provider.loadRadioMapForSelectedFloor(forceReload: true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF38BDF8),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloorplanStatusBadge(
    BuildContext context,
    SpaceProvider provider,
  ) {
    final status = provider.floorplanStatus;
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case FloorplanStatus.loading:
        bgColor = const Color(0xFF6366F1).withValues(alpha: 0.2);
        textColor = const Color(0xFF818CF8);
        icon = Icons.sync;
        label = 'Floorplan: Downloading...';
      case FloorplanStatus.ready:
        bgColor = const Color(0xFF059669).withValues(alpha: 0.2);
        textColor = const Color(0xFF34D399);
        icon = Icons.map;
        final isCached = provider.isFloorplanCached;
        label = isCached ? 'Floorplan: Ready (Cached)' : 'Floorplan: Ready';
      case FloorplanStatus.unsupported:
        bgColor = Colors.white10;
        textColor = MapTheme.textSecondary;
        icon = Icons.info_outline;
        label = 'No floorplan image';
      case FloorplanStatus.error:
        bgColor = const Color(0xFFDC2626).withValues(alpha: 0.2);
        textColor = const Color(0xFFF87171);
        icon = Icons.error_outline;
        label = provider.floorplanErrorMessage ?? 'Floorplan load failed';
      case FloorplanStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (status == FloorplanStatus.error) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () =>
                  provider.loadFloorplanForSelectedFloor(forceReload: true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF818CF8),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}