import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/position_provider.dart';
import '../providers/providers.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'profile_screen.dart';
import 'saved_screen.dart';
import 'search_screen.dart';

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);
    final bulkLoad = ref.watch(bulkLoadProvider);
    wireCacheNotifications(ref);

    return Scaffold(
      body: Column(
        key: const ValueKey('tabs'),
        children: [
          const _PositionLifecycle(key: ValueKey('position')),
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
                SearchScreen(),
                SavedScreen(),
                ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
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
          NavigationDestination(
            icon: Icon(Icons.search_outlined, color: AppTheme.textTertiary),
            selectedIcon: Icon(Icons.search, color: AppTheme.primary),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline, color: AppTheme.textTertiary),
            selectedIcon: Icon(Icons.bookmark, color: AppTheme.primary),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, color: AppTheme.textTertiary),
            selectedIcon: Icon(Icons.person, color: AppTheme.primary),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const MainShell();
  }
}

class _PositionLifecycle extends ConsumerWidget {
  const _PositionLifecycle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);
    final notifier = ref.read(positionStateProvider.notifier);

    ref.listen(shellTabProvider, (previous, next) {
      if (next == 1) {
        notifier.start();
      } else {
        notifier.stop();
      }
    });

    if (index == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.start());
    }

    return const SizedBox.shrink();
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
