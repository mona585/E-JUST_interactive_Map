import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi.dart';
import '../models/space.dart';
import '../providers/providers.dart';
import '../utils/description_parser.dart';
import '../utils/map_focus.dart';
import 'detail_navigation.dart';
/// Building detail screen: hero placeholder, parsed building info, room
/// search, floors directory, accessibility/facilities and a Navigate button.
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
        title: const Text('Building'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Hero(space: space),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(space.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                if (parser.summary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    parser.summary,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                // Navigate to building (starts outdoor route).
                FilledButton.icon(
                  onPressed: () => navigateToBuildingOnMap(context, ref, space),
                  icon: const Icon(Icons.directions),
                  label: const Text('Navigate to Building'),
                ),
                const SizedBox(height: 24),
                Text('Rooms in this building',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => _roomQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search rooms inside ${space.name}…',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _roomQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () =>
                                setState(() => _roomQuery = ''),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                if (roomResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final poi in roomResults.take(8))
                    _RoomResultTile(poi: poi, space: space),
                ],
                const SizedBox(height: 24),
                Text('Floors Directory',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (floors.isEmpty)
                  Text(
                    'No floor data available.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  for (final floor in floors)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.layers),
                        title: Text(floor.floorName ??
                            'Floor ${floor.floorNumber}'),
                        subtitle: floor.description == null
                            ? null
                            : Text(floor.description!,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => showBuildingOnMap(
                          context,
                          ref,
                          space,
                          floor: floor,
                        ),
                      ),
                    ),
                if (parser.hasAccessibilityInfo) ...[
                  const SizedBox(height: 24),
                  Text('Accessibility & Facilities',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in parser.facilityTags)
                        Chip(avatar: const Icon(Icons.check, size: 18), label: Text(tag)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Gradient "hero" placeholder — no real building photo exists in the data.
class _Hero extends StatelessWidget {
  const _Hero({required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 160,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(Icons.apartment,
                size: 72, color: scheme.onPrimary.withValues(alpha: 0.5)),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: Text(
              space.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single room-search hit inside the building.
class _RoomResultTile extends ConsumerWidget {
  const _RoomResultTile({required this.poi, required this.space});

  final Poi poi;
  final Space space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.room),
        title: Text(poi.name),
        subtitle: Text('Floor ${poi.floorNumber}'
            '${poi.floorName != null && poi.floorName != poi.floorNumber ? ' · ${poi.floorName}' : ''}'),
        onTap: () => openPoi(context, ref, poi, space: space),
      ),
    );
  }
}
