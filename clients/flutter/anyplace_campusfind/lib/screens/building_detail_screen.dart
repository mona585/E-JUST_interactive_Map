import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/providers.dart';
import '../utils/description_parser.dart';
import '../utils/map_focus.dart';
import 'detail_navigation.dart';

class BuildingDetailScreen extends ConsumerStatefulWidget {
  const BuildingDetailScreen({super.key, required this.space});

  final Space space;

  @override
  ConsumerState<BuildingDetailScreen> createState() =>
      _BuildingDetailScreenState();
}

class _BuildingDetailScreenState extends ConsumerState<BuildingDetailScreen> {
  String _roomQuery = '';

  List<Poi> get _matchingPois {
    final cache = ref.read(cacheServiceProvider);
    final pois = cache.poisOf(widget.space.buid);
    final query = _roomQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return pois
        .where((p) =>
            p.name.toLowerCase().contains(query) ||
            (p.description ?? '').toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheServiceProvider);
    final space = widget.space;
    final parser = DescriptionParser(space.description);
    final floors = cache.floorsOf(space.buid);
    final roomResults = _matchingPois;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Building Directory',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: AppTheme.textSecondary, size: 22),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Hero image
          _Hero(space: space, parser: parser),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room search
                TextField(
                  onChanged: (v) => setState(() => _roomQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search rooms inside this building...',
                    prefixIcon: const Icon(Icons.search, size: 22, color: AppTheme.textTertiary),
                    suffixIcon: _roomQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => setState(() => _roomQuery = ''),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 24),
                // Room results
                if (roomResults.isNotEmpty) ...[
                  for (final poi in roomResults.take(5))
                    _RoomResultTile(poi: poi, space: space),
                  const SizedBox(height: 16),
                ] else if (_roomQuery.trim().isNotEmpty) ...[
                  Text('No rooms match "${_roomQuery.trim()}".',
                      style: const TextStyle(color: AppTheme.textTertiary, fontSize: 14)),
                  const SizedBox(height: 16),
                ],
                // Floors Directory
                const Text('Floors Directory',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 12),
                if (floors.isEmpty)
                  const Text('No floor data available.',
                      style: TextStyle(color: AppTheme.textTertiary, fontSize: 14))
                else
                  for (final floor in floors)
                    _FloorTile(floor: floor, space: space),
                const SizedBox(height: 24),
                // Accessibility & Facilities
                if (parser.hasAccessibilityInfo) ...[
                  const Text('Accessibility & Facilities',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in parser.facilityTags)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check, size: 16, color: AppTheme.primary),
                              const SizedBox(width: 6),
                              Text(tag, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                // Navigate button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => navigateToBuildingOnMap(context, ref, space),
                    icon: const Icon(Icons.navigation, size: 20),
                    label: Text('Navigate to ${space.name}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.space, required this.parser});

  final Space space;
  final DescriptionParser parser;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF37474F), Color(0xFF263238)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative pattern
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.white.withValues(alpha: 0.05),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Icon(Icons.apartment,
                size: 80, color: Colors.white.withValues(alpha: 0.15)),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(space.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                if (parser.summary.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(parser.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 13)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorTile extends ConsumerWidget {
  const _FloorTile({required this.floor, required this.space});

  final dynamic floor;
  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showBuildingOnMap(context, ref, space, floor: floor),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  floor.floorName ?? 'Floor ${floor.floorNumber}',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  floor.description ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondary),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomResultTile extends ConsumerWidget {
  const _RoomResultTile({required this.poi, required this.space});

  final Poi poi;
  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.room, color: AppTheme.primary, size: 18),
        ),
        title: Text(poi.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text('Floor ${poi.floorNumber}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
        trailing: Icon(Icons.arrow_outward, size: 16, color: AppTheme.primary.withValues(alpha: 0.6)),
        onTap: () => openPoi(context, ref, poi, space: space),
      ),
    ),
    );
  }
}
