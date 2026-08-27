import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../state/space_provider.dart';
import '../widgets/quick_access_list.dart';
import '../widgets/recent_waypoints_list.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);

    return Scaffold(
      appBar: _HomeAppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        children: [
          const Text('Welcome back, Student',
              style: TextStyle(fontSize: 14, color: AppTheme.textTertiary)),
          const SizedBox(height: 4),
          const Text('Where are we headed today?',
              style: TextStyle(
                  fontSize: 26, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _openSearch(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.cardBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppTheme.textTertiary, size: 22),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Search professors, rooms, halls...',
                        style: TextStyle(color: AppTheme.textTertiary, fontSize: 15)),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.tune, size: 18, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          if (spaceProvider.isLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            const Text('Quick Access',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            const SizedBox(height: 14),
            const QuickAccessList(),
            const SizedBox(height: 28),
            Row(
              children: [
                const Text('Recent Waypoints',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const Spacer(),
                TextButton(
                  onPressed: () => _openSearch(context),
                  child: const Text('See All', style: TextStyle(color: AppTheme.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const RecentWaypointsList(),
          ],
        ],
      ),
    );
  }

  static void _openSearch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
    );
  }
}

class _HomeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_location_alt, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Text('CampusFind',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ],
      ),

      actions: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.person_outline, color: AppTheme.textSecondary, size: 22),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
              );
            },
          ),
        ),
      ],
    );
  }
}
