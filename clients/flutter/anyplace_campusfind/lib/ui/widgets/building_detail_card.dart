import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/theme.dart';
import '../../data/models/floor_model.dart';
import '../../data/models/quick_access_item.dart';
import '../../data/models/space_model.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../../utils/poi_classification.dart';
import '../../widgets/quick_access_toggle_button.dart';

/// Card showing detailed metadata, interactive floor selector, and RadioMap status for a selected building.
class BuildingDetailCard extends StatelessWidget {
  final SpaceModel space;
  final VoidCallback onClose;
  final VoidCallback onFocus;
  final QuickAccessItem Function()? quickAccessItemBuilder;

  const BuildingDetailCard({
    super.key,
    required this.space,
    required this.onClose,
    required this.onFocus,
    this.quickAccessItemBuilder,
  });

  void _copyBuidToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: space.buid));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied buid to clipboard: ${space.buid}'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppTheme.surface,
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
          color: AppTheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(
              color: AppTheme.cardBorder,
              width: 1,
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
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.apartment,
                            color: AppTheme.primary,
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
                                  color: AppTheme.textPrimary,
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
                                        color: AppTheme.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: AppTheme.primary.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        space.bucode!,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      space.spaceType.toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textSecondary,
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
                            color: AppTheme.textSecondary,
                          ),
                          onPressed: onClose,
                          tooltip: 'Dismiss',
                          splashRadius: 20,
                        ),
                        if (quickAccessItemBuilder != null)
                          QuickAccessToggleButton(
                            itemBuilder: quickAccessItemBuilder!,
                          ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    const Divider(color: AppTheme.cardBorder, height: 1),
                    const SizedBox(height: 12),

                    // Building ID (buid) with Copy Button
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.tag,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'buid: ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              space.buid,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                                color: AppTheme.primary,
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
                                color: AppTheme.textSecondary,
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

                    // STATUS BADGES (Floorplan, POI, Navigation when a floor is selected)
                    if (selectedFloor != null) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _buildFloorplanStatusBadge(context, provider),
                          _buildPoiStatusBadge(context, provider),
                          _buildNavigationStatusBadge(context, provider),
                        ],
                      ),
                    ],

                    // POI LIST (when floor is selected and POIs are loaded)
                    if (selectedFloor != null && provider.hasPois &&
                        provider.pois.any((p) =>
                            !PoiClassification.isConnector(p) &&
                            !PoiClassification.isEntrance(p) &&
                            !PoiClassification.isDoor(p) &&
                            p.name.isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      _buildPoiListSection(context, provider),
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
                              foregroundColor: AppTheme.textPrimary,
                              side: const BorderSide(
                                color: AppTheme.cardBorder,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Consumer2<SpaceProvider, NavigationController>(
                            builder: (context, spaceProvider, navController, _) {
                              final isRouteLoading =
                                  spaceProvider.isLoadingNavigationRoute;
                              final hasRoute =
                                  spaceProvider.hasActiveNavigationRoute;
                              final isActive = navController.isActive;

                              return ElevatedButton.icon(
                                onPressed: (isRouteLoading || isActive)
                                    ? null
                                    : () {
                                        if (hasRoute) {
                                          spaceProvider.clearNavigationRoute();
                                          navController.endNavigation();
                                        } else {
                                          spaceProvider
                                              .requestRouteToBuilding(space);
                                        }
                                      },
                                icon: isRouteLoading
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        isActive
                                            ? Icons.stop_circle
                                            : hasRoute
                                                ? Icons.alt_route
                                                : Icons.directions,
                                        size: 18,
                                      ),
                                label: Text(
                                  isRouteLoading
                                      ? 'Routing...'
                                      : isActive
                                          ? 'Navigating'
                                          : hasRoute
                                              ? 'Clear Route'
                                              : 'Route Here',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? const Color(0xFFDC2626)
                                      : hasRoute
                                          ? const Color(0xFF059669)
                                          : AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppTheme.primary.withValues(alpha: 0.4),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              );
                            },
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
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selectedFloor != null
              ? AppTheme.primary.withValues(alpha: 0.3)
              : AppTheme.cardBorder,
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
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Floors',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
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
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${floors.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check,
                        size: 12,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Selected: Floor ${selectedFloor.floorNumber}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primary,
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
                      color: AppTheme.primary,
                    ),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading floors from Anyplace...',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
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
                  color: AppTheme.primary,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    errorMessage,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.primary,
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
                      color: AppTheme.primary,
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
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  'No indoor floors mapped for this building.',
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: AppTheme.textSecondary,
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
                                ? AppTheme.primary
                                : AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.cardBorder,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.primary.withValues(
                                        alpha: 0.3,
                                      ),
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
                                    : AppTheme.textSecondary,
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
                                      : AppTheme.textPrimary,
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
        bgColor = const Color(0xFF6366F1).withValues(alpha: 0.1);
        textColor = const Color(0xFF6366F1);
        icon = Icons.sync;
        label = 'Floorplan: Downloading...';
      case FloorplanStatus.ready:
        bgColor = const Color(0xFF059669).withValues(alpha: 0.1);
        textColor = const Color(0xFF059669);
        icon = Icons.map;
        final isCached = provider.isFloorplanCached;
        label = isCached ? 'Floorplan: Ready (Cached)' : 'Floorplan: Ready';
      case FloorplanStatus.unsupported:
        bgColor = const Color(0xFFF5F5F5);
        textColor = AppTheme.textSecondary;
        icon = Icons.info_outline;
        label = 'No floorplan image';
      case FloorplanStatus.error:
        bgColor = const Color(0xFFDC2626).withValues(alpha: 0.1);
        textColor = const Color(0xFFDC2626);
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
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
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

  Widget _buildPoiStatusBadge(BuildContext context, SpaceProvider provider) {
    final status = provider.poiStatus;
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case PoiStatus.loading:
        bgColor = const Color(0xFFD97706).withValues(alpha: 0.1);
        textColor = const Color(0xFFD97706);
        icon = Icons.sync;
        label = 'POIs: Loading...';
      case PoiStatus.ready:
        bgColor = const Color(0xFF059669).withValues(alpha: 0.1);
        textColor = const Color(0xFF059669);
        icon = Icons.place;
        label = 'POIs: ${provider.pois.length} loaded';
      case PoiStatus.error:
        bgColor = const Color(0xFFDC2626).withValues(alpha: 0.1);
        textColor = const Color(0xFFDC2626);
        icon = Icons.error_outline;
        label = provider.poiErrorMessage ?? 'POIs load failed';
      case PoiStatus.idle:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
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
          if (status == PoiStatus.error) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: () => provider.loadPoisForSelectedFloor(forceReload: true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: textColor,
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

  Widget _buildNavigationStatusBadge(
    BuildContext context,
    SpaceProvider provider,
  ) {
    final status = provider.navigationRouteStatus;
    final route = provider.activeNavigationRoute;
    final isPartial = route?.isPartial ?? false;
    Color bgColor;
    Color textColor;
    IconData icon;
    String label;

    // Check for partial route warning
    if (isPartial && route?.partialRouteWarning != null) {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.1);
      textColor = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_outlined;
      label = route!.partialRouteWarning!;
    } else {
      switch (status) {
        case NavigationRouteStatus.loading:
          bgColor = AppTheme.primary.withValues(alpha: 0.1);
          textColor = AppTheme.primary;
          icon = Icons.alt_route;
          label = 'Route: Calculating...';
        case NavigationRouteStatus.ready:
          bgColor = const Color(0xFF059669).withValues(alpha: 0.1);
          textColor = const Color(0xFF059669);
          icon = Icons.route;
          label = 'Route: Ready';
        case NavigationRouteStatus.unsupported:
          bgColor = const Color(0xFFF5F5F5);
          textColor = AppTheme.textSecondary;
          icon = Icons.info_outline;
          label = provider.navigationRouteErrorMessage ?? 'Route unavailable';
        case NavigationRouteStatus.error:
          bgColor = const Color(0xFFDC2626).withValues(alpha: 0.1);
          textColor = const Color(0xFFDC2626);
          icon = Icons.error_outline;
          label = provider.navigationRouteErrorMessage ?? 'Route failed';
        case NavigationRouteStatus.idle:
          return const SizedBox.shrink();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
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
        ],
      ),
    );
  }

  Widget _buildPoiListSection(BuildContext context, SpaceProvider provider) {
    final allPois = provider.pois;
    final selectedPoi = provider.selectedPoi;

    final navigablePois = allPois.where((p) =>
        !PoiClassification.isConnector(p) &&
        !PoiClassification.isEntrance(p) &&
        !PoiClassification.isDoor(p) &&
        p.name.isNotEmpty).toList();

    if (navigablePois.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.place, size: 14, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              const Text(
                'Points of Interest',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Text(
                  '${navigablePois.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: navigablePois.length,
                itemBuilder: (context, index) {
                  final poi = navigablePois[index];
                  final isSelected = selectedPoi?.puid == poi.puid;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        provider.selectPoi(poi);
                        provider.requestRouteToSelectedPoi();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppTheme.primary.withValues(alpha: 0.1)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                isSelected ? Icons.navigation : Icons.place,
                                size: 14,
                                color: isSelected
                                    ? AppTheme.primary
                                    : AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    poi.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: AppTheme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (poi.poisType.isNotEmpty)
                                    Text(
                                      poi.poisType,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: isSelected
                                  ? AppTheme.primary
                                  : AppTheme.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
