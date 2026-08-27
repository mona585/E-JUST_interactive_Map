import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/panel_provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../state/navigation_controller.dart';
import '../state/space_provider.dart';
import '../ui/screens/map_screen.dart';
import '../ui/widgets/arrival_banner.dart';
import '../ui/widgets/campus_content_panel.dart';
import '../ui/widgets/map_top_bar.dart';
import '../ui/widgets/navigation_bottom_bar.dart';
import '../ui/widgets/navigation_status_bar.dart';

/// One-line destination label for the compact navigation bar.
String? _navDestinationLabel(BuildContext context) {
  final nav = provider.Provider.of<NavigationController>(context);
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
/// - `shellTabProvider` remains defined for compatibility with existing
///   cross-tab helpers (`detail_navigation.dart`); writing to it is harmless.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _syncStarted = false;
  bool _prevNavActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDataLoading();
    });
  }

  Future<void> _startDataLoading() async {
    if (_syncStarted) return;
    _syncStarted = true;

    final spaceProvider =
        provider.Provider.of<SpaceProvider>(context, listen: false);
    final searchService = ref.read(searchServiceProvider);
    final cache = ref.read(cacheServiceProvider);

    // SERVER MIGRATION (one-time, silent): if this device's local data
    // belongs to a previous backend epoch, clear old-backend Quick Access /
    // Recent Waypoints and purge the disk caches BEFORE anything reads them.
    // Quick Access then re-seeds below from the new server's real entities.
    try {
      final migrated = await cache.consumeDatasetEpochMigration();
      if (migrated) {
        await spaceProvider.purgeDatasetCaches();
      }
    } catch (e) {
      debugPrint('[MainShell] dataset migration failed (non-fatal): $e');
    }

    await spaceProvider.loadSpaces();

    if (!mounted) return;

    // Index spaces immediately
    searchService.addSpaces(spaceProvider.spaces);
    // One-time Quick Access seeding + legacy Saved migration
    await spaceProvider.ensureQuickAccessInitialized(searchService);
    // Start progressive background sync for floors + POIs
    spaceProvider.loadAllFloorsAndPois(searchService);

    // Load custom KMZ routes for outdoor navigation
    debugPrint('[MainShell] _startDataLoading: calling loadCustomRoutes');
    await spaceProvider.loadCustomRoutes();
    debugPrint('[MainShell] _startDataLoading: loadCustomRoutes completed');
  }

  @override
  Widget build(BuildContext context) {
    final bulkLoad = ref.watch(bulkLoadProvider);
    wireCacheNotifications(ref);

    final navActive = context.select<NavigationController, bool>(
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
          if (bulkLoad.hasValue && bulkLoad.value!.fromOffline)
            Material(
              color: const Color(0xFFFFF3E0),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_off, size: 16, color: Color(0xFFE65100)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Offline — showing cached campus data',
                          style: TextStyle(color: Color(0xFFE65100), fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(bulkLoadProvider),
                      child: const Text('Retry', style: TextStyle(color: Color(0xFFE65100))),
                    ),
                  ],
                ),
              ),
            ),
          if (bulkLoad.isLoading)
            const LinearProgressIndicator(minHeight: 2, color: AppTheme.primary),
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
                        final nav = provider.Provider.of<NavigationController>(
                            context,
                            listen: false);
                        final spaceProvider = provider.Provider.of<SpaceProvider>(
                            context,
                            listen: false);
                        // EXISTING termination/cleanup flows only.
                        nav.terminateNavigation();
                        spaceProvider.clearNavigationRoute();
                      },
                      onExpand: () => ref
                          .read(navPanelOpenProvider.notifier)
                          .state = true,
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
                            final nav = provider.Provider.of<NavigationController>(
                                context,
                                listen: false);
                            final spaceProvider = provider.Provider.of<SpaceProvider>(
                                context,
                                listen: false);
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
