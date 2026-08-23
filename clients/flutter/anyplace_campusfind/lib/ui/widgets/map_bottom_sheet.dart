import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../config/theme.dart';
import '../../data/models/quick_access_item.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../../utils/category_deriver.dart';
import '../utils/navigation_display.dart';
import '../widgets/building_detail_card.dart';
import '../widgets/poi_detail_card.dart';

/// Google Maps–style draggable bottom sheet for building/POI details on the map.
///
/// Snaps between three states:
/// - **Collapsed** (12%): drag handle + title bar
/// - **Expanded** (45%): building info + floor selector
/// - **Full** (85%): full details including status badges
///
/// Drag gesture is on the handle/header only so the body ListView scrolls freely.
class MapBottomSheet extends ConsumerStatefulWidget {
  final void Function(SpaceProvider)? onFitRouteBounds;

  const MapBottomSheet({super.key, this.onFitRouteBounds});

  @override
  ConsumerState<MapBottomSheet> createState() => _MapBottomSheetState();
}

class _MapBottomSheetState extends ConsumerState<MapBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<double>? _animation;

  static const _collapsedFraction = 0.12;
  static const _expandedFraction = 0.45;
  static const _fullFraction = 0.85;

  double _currentFraction = _collapsedFraction;
  double _dragStartY = 0;
  double _dragStartFraction = 0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animation != null) {
          setState(() {
            _currentFraction = _animation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _snapTo(double target) {
    _animation = Tween<double>(
      begin: _currentFraction,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController
      ..reset()
      ..forward();
  }

  double _snapForPosition(double fraction) {
    final distances = [
      (_collapsedFraction - fraction).abs(),
      (_expandedFraction - fraction).abs(),
      (_fullFraction - fraction).abs(),
    ];
    final minDist = distances.reduce((a, b) => a < b ? a : b);
    final idx = distances.indexOf(minDist);
    return [_collapsedFraction, _expandedFraction, _fullFraction][idx];
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragStartFraction = _currentFraction;
  }

  void _onDragUpdate(DragUpdateDetails details, double screenHeight) {
    final dy = _dragStartY - details.globalPosition.dy;
    final dfraction = dy / screenHeight;
    final newFraction = (_dragStartFraction + dfraction)
        .clamp(_collapsedFraction, _fullFraction);
    setState(() {
      _currentFraction = newFraction;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final target = _snapForPosition(_currentFraction);
    _snapTo(target);
  }

  void _onHandleTap() {
    if (_currentFraction <= _collapsedFraction + 0.05) {
      _snapTo(_expandedFraction);
    } else if (_currentFraction <= _expandedFraction + 0.15) {
      _snapTo(_fullFraction);
    } else {
      _snapTo(_collapsedFraction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final navController = provider.Provider.of<NavigationController>(context);
    final selectedSpace = spaceProvider.selectedSpace;
    final selectedPoi = spaceProvider.selectedPoi;
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 0),
      height: screenHeight * _currentFraction,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag handle + title bar — drag and tap handled here only
          GestureDetector(
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: (d) => _onDragUpdate(d, screenHeight),
            onVerticalDragEnd: _onDragEnd,
            onTap: _onHandleTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (navController.isActive)
                    _buildNavigationHeader(spaceProvider, navController)
                  else if (selectedSpace != null)
                    _buildTitleBar(
                      icon: Icons.business,
                      name: selectedSpace.name,
                      subtitle:
                          selectedSpace.bucode ?? selectedSpace.spaceType,
                    )
                  else if (selectedPoi != null)
                    _buildTitleBar(
                      icon: CategoryDeriver.fromPoiType(selectedPoi.poisType)
                          .icon,
                      name: selectedPoi.name,
                      subtitle: selectedPoi.poisType,
                    ),
                ],
              ),
            ),
          ),

          // Divider
          Container(
            height: 1,
            color: AppTheme.cardBorder.withValues(alpha: 0.5),
          ),

          // Scrollable content — ListView handles its own scrolling
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                if (selectedPoi != null)
                  PoiDetailCard(
                    poi: selectedPoi,
                    onClose: () {
                      spaceProvider.clearSelectedPoi();
                      // BUG-8 closure: ending a preview tears down the
                      // canonical way — Phase 2's endNavigation also clears
                      // the single store, so no ghost route survives.
                      if (navController.isPreview) {
                        navController.endNavigation();
                      }
                    },
                    onNavigate: () =>
                        spaceProvider.requestRouteToSelectedPoi(),
                    onClearRoute: () {
                      spaceProvider.clearNavigationRoute();
                      navController.endNavigation();
                    },
                    onStartDirections: () {
                      final target = selectedPoi;
                      // PHASE 4: "Navigate here" during an active run is the
                      // ONLY retarget entry point — a transaction, never a
                      // silent polyline swap.
                      if (navController.isActive) {
                        navController.retargetDestination(target);
                        widget.onFitRouteBounds?.call(spaceProvider);
                        return;
                      }
                      navController.startRoutePreview(
                        destinationPuid: target.puid,
                        destinationSpace: spaceProvider.selectedSpace!,
                      );
                      navController.startActiveNavigation();
                      widget.onFitRouteBounds?.call(spaceProvider);
                    },
                    onEndNavigation: () {
                      navController.endNavigation();
                      spaceProvider.clearNavigationRoute();
                    },
                    isLoadingRoute: spaceProvider.isLoadingNavigationRoute,
                    hasActiveRoute: spaceProvider.hasActiveNavigationRoute,
                    isNavigating: navController.isActive,
                    isRouteUnsupported:
                        spaceProvider.isNavigationRouteUnsupported,
                    routeMessage: spaceProvider.hasActiveNavigationRoute
                        ? 'Route ready on floor ${spaceProvider.selectedFloor?.floorNumber ?? '-'}'
                        : spaceProvider.navigationRouteErrorMessage,
                    quickAccessItemBuilder: () => QuickAccessItem.fromPoi(
                      selectedPoi,
                      addedAt: DateTime.now().millisecondsSinceEpoch,
                      category:
                          CategoryDeriver.fromPoiType(selectedPoi.poisType).name,
                    ),
                  ),
                if (selectedSpace != null)
                  BuildingDetailCard(
                    space: selectedSpace,
                    onClose: () => spaceProvider.clearSelection(),
                    onFocus: () {},
                    quickAccessItemBuilder: () => QuickAccessItem.fromSpace(
                      selectedSpace,
                      addedAt: DateTime.now().millisecondsSinceEpoch,
                      category:
                          CategoryDeriver.fromSpaceType(selectedSpace.spaceType).name,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleBar({
    required IconData icon,
    required String name,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationHeader(
    SpaceProvider spaceProvider,
    NavigationController navController,
  ) {
    final destName = navController.destinationSpace?.name ?? 'Navigating';
    final floor = navController.currentNavigatingFloor;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Positioning icon
          Icon(
            navController.subState == NavigationSubState.indoor
                ? Icons.wifi
                : navController.subState == NavigationSubState.transitioning
                    ? Icons.swap_vert
                    : Icons.gps_fixed,
            size: 18,
            color: navController.subState == NavigationSubState.indoor
                ? const Color(0xFF0D9488)
                : navController.subState == NavigationSubState.transitioning
                    ? const Color(0xFFF59E0B)
                    : AppTheme.primary,
          ),
          const SizedBox(width: 8),
          // Building name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  destName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  navigationStatusLabel(navController),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: navController.isRerouting
                        ? const Color(0xFFDC2626)
                        : AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          // Floor chip
          if (floor != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'F$floor',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ],
          // End navigation button
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              navController.endNavigation();
              spaceProvider.clearNavigationRoute();
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.stop_circle,
                size: 20,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
