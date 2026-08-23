import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../state/navigation_controller.dart';
import '../state/space_provider.dart';
import '../ui/screens/map_screen.dart';
import 'home_screen.dart';

const int _kMapTabIndex = 1;

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  bool _syncStarted = false;
  int _previousTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDataLoading();
    });
  }

  void _stopNavigationOnTabLeave() {
    if (!mounted) return;
    final navController =
        provider.Provider.of<NavigationController>(context, listen: false);
    final spaceProvider =
        provider.Provider.of<SpaceProvider>(context, listen: false);

    if (navController.isActive || navController.isPreview) {
      debugPrint('[MainShell] Leaving Map tab — stopping navigation');
      // PHASE 15 policy (documented product decision, v1): leaving the Map
      // tab TERMINATES the navigation session BY DESIGN. terminateNavigation
      // already clears the single store; the explicit clear below is a
      // harmless idempotent belt-and-braces. Revisit = product backlog note.
      navController.terminateNavigation();
      spaceProvider.clearNavigationRoute();
    }
  }

  Future<void> _startDataLoading() async {
    if (_syncStarted) return;
    _syncStarted = true;

    final spaceProvider = provider.Provider.of<SpaceProvider>(context, listen: false);
    final searchService = ref.read(searchServiceProvider);

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
    final index = ref.watch(shellTabProvider);
    final bulkLoad = ref.watch(bulkLoadProvider);
    wireCacheNotifications(ref);

    if (_previousTabIndex == _kMapTabIndex && index != _kMapTabIndex) {
      _stopNavigationOnTabLeave();
    }
    _previousTabIndex = index;

    return Scaffold(
      body: Column(
        key: const ValueKey('tabs'),
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
            child: _LazyIndexedStack(
              index: index,
              children: const [
                HomeScreen(),
                MapScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index.clamp(0, 1),
        onDestinationSelected: (i) =>
            ref.read(shellTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: AppTheme.textTertiary),
            selectedIcon: Icon(Icons.home, color: AppTheme.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined, color: AppTheme.textTertiary),
            selectedIcon: Icon(Icons.map, color: AppTheme.primary),
            label: 'Map',
          ),
        ],
      ),
    );
  }
}

class _LazyIndexedStack extends StatefulWidget {
  const _LazyIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<_LazyIndexedStack> {
  late final List<bool> _visited =
      List<bool>.filled(widget.children.length, false);

  @override
  Widget build(BuildContext context) {
    _visited[widget.index] = true;

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          if (_visited[i])
            Offstage(
              offstage: i != widget.index,
              child: TickerMode(
                enabled: i == widget.index,
                child: widget.children[i],
              ),
            ),
      ],
    );
  }
}
