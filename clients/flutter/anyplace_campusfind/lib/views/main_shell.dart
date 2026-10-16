import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart' as provider;

import '../providers/connectivity_provider.dart';
import '../viewmodels/location_view_model.dart';
import '../providers/panel_provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../viewmodels/navigation_view_model.dart';
import '../viewmodels/space_view_model.dart';
import 'map_screen.dart';
import '../widgets/arrival_banner.dart';
import '../widgets/campus_content_panel.dart';
import '../widgets/map_top_bar.dart';
import '../widgets/navigation_bottom_bar.dart';
import '../widgets/navigation_status_bar.dart';
import '../viewmodels/main_shell_view_model.dart';

/// One-line destination label for the compact navigation bar.
String? _navDestinationLabel(BuildContext context) {
  final nav = provider.Provider.of<NavigationViewModel>(context);
  final dest = nav.destinationSpace?.name;
  if (dest == null) return null;
  final floor = nav.currentNavigatingFloor;
  return floor != null ? '$dest · Floor $floor' : dest;
}

/// Map-first main shell (Phase 1 of the UI/UX redesign).
///
/// The former Home/Map bottom-tab structure is replaced by a single screen:
///
///   Search / Directions bar (top)  →  Map  →  one dynamic content area.
///
/// Notes on preserved behavior:
/// - Leaving-the-map-tab navigation termination is gone WITH the tabs: there
///   are no tabs left to leave, so that policy is intentionally a no-op.
///   Sessions still end via the explicit End controls (status bar / banner).
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  MainShellViewModel? _viewModel;
  bool _prevNavActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final spaceProvider = provider.Provider.of<SpaceViewModel>(
        context,
        listen: false,
      );
      final searchService = ref.read(searchServiceProvider);
      final cache = ref.read(cacheServiceProvider);
      _viewModel = MainShellViewModel(
        spaceProvider: spaceProvider,
        searchService: searchService,
        cacheService: cache,
      );
      _viewModel!.startDataSync();
    });
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final loc = provider.Provider.of<LocationViewModel>(context);
    final permDenied =
        loc.status == LocationStateStatus.permissionDenied ||
        loc.status == LocationStateStatus.permissionDeniedForever;
    wireCacheNotifications(ref);

    final navActive = context.select<NavigationViewModel, bool>(
      (nav) => nav.isActive,
    );

    // NAVIGATION REFINEMENT: a NEW session always starts with the compact
    // navigation bar (panel force-collapsed). Rising-edge detection keeps
    // the user's re-expanded choice stable for the rest of the session.
    if (navActive && !_prevNavActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(navPanelOpenProvider.notifier).state = false;
      });
    }
    _prevNavActive = navActive;

    final showCompactNav = navActive && !ref.watch(navPanelOpenProvider);

    return Scaffold(
      body: Column(
        key: const ValueKey('main_shell'),
        children: [
          if (permDenied)
            Material(
              color: const Color(0xFFFEE2E2),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_off,
                      size: 16,
                      color: Color(0xFFB91C1C),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.errorMessage ?? 'Location permission required',
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        if (loc.status ==
                            LocationStateStatus.permissionDeniedForever) {
                          Geolocator.openAppSettings();
                        } else {
                          loc.requestAndCenter();
                        }
                      },
                      child: Text(
                        loc.status ==
                                LocationStateStatus.permissionDeniedForever
                            ? 'Settings'
                            : 'Grant',
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!online)
            Material(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_off,
                      size: 16,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Offline — showing cached campus data',
                        style: TextStyle(
                          color: Color(0xFFE65100),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(isOnlineProvider),
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Color(0xFFE65100)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              key: const ValueKey('map_first_stack'),
              children: [
                // 1. Full-screen map canvas + its floating controls.
                const Positioned.fill(child: MapScreen()),

                // 2. Top Search / Directions bar.
                const Positioned(top: 0, left: 0, right: 0, child: MapTopBar()),

                // 3. Bottom chrome: during active navigation the dynamic
                //    panel collapses into a compact navigation bar (map gets
                //    maximum space). The user can re-expand the panel without
                //    ending navigation; ending restores the normal panel.
                if (showCompactNav)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: NavigationBottomBar(
                      subtitle: _navDestinationLabel(context),
                      onClose: () {
                        final nav = provider.Provider.of<NavigationViewModel>(
                          context,
                          listen: false,
                        );
                        final spaceProvider =
                            provider.Provider.of<SpaceViewModel>(
                              context,
                              listen: false,
                            );
                        // EXISTING termination/cleanup flows only.
                        nav.terminateNavigation();
                        spaceProvider.clearNavigationRoute();
                      },
                      onExpand: () =>
                          ref.read(navPanelOpenProvider.notifier).state = true,
                    ),
                  )
                else
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: CampusContentPanel(),
                  ),

                // 4. Navigation Status Bar + Arrival Banner during active
                //    navigation — layered ABOVE the compact bar/panel so
                //    guidance is never obscured (relocated from MapScreen).
                if (navActive)
                  Positioned(
                    left: 16,
                    right: 76,
                    bottom: 24,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ArrivalBanner(
                          onDone: () {
                            final nav =
                                provider.Provider.of<NavigationViewModel>(
                                  context,
                                  listen: false,
                                );
                            final spaceProvider =
                                provider.Provider.of<SpaceViewModel>(
                                  context,
                                  listen: false,
                                );
                            nav.terminateNavigation();
                            spaceProvider.clearNavigationRoute();
                          },
                        ),
                        const NavigationStatusBar(),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
