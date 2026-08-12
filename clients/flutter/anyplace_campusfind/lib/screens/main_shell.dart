import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'campus_selection_screen.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'search_screen.dart';

/// Root scaffold with the 3-tab bottom navigation (Home, Map, Search).
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [HomeScreen(), MapScreen(), SearchScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(shellTabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
        ],
      ),
    );
  }
}

/// Switches between the first-launch campus selection flow and the main shell
/// based on the persisted campus selection.
class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCampus = ref.watch(selectedCampusIdProvider);

    if (selectedCampus == null) {
      return CampusSelectionScreen(
        onSelected: (cuid) =>
            ref.read(selectedCampusIdProvider.notifier).state = cuid,
      );
    }
    return const MainShell();
  }
}
