import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi.dart';
import '../models/space.dart';
import '../providers/providers.dart';
import '../utils/description_parser.dart';
import '../utils/map_focus.dart';

/// Professor profile screen: parsed name/title/department, office location
/// and weekly office hours, plus a Get Directions button.
class ProfessorProfileScreen extends ConsumerWidget {
  const ProfessorProfileScreen({
    super.key,
    required this.poi,
    this.space,
  });

  final Poi poi;
  final Space? space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    final building = space ?? cache.spaceByBuid(poi.buid);
    final parser = DescriptionParser(poi.description);

    final name = parser.professorName.isNotEmpty ? parser.professorName : poi.name;
    final title = parser.professorTitle.isNotEmpty
        ? parser.professorTitle
        : 'Faculty Member';
    final department = parser.professorDepartment.isNotEmpty
        ? parser.professorDepartment
        : (poi.floorName ?? poi.floorNumber);
    final office = parser.officeLocation;
    final officeHours = parser.officeHours;

    final floor = cache.floorsOf(poi.buid).where((f) {
      return f.floorNumber == poi.floorNumber;
    }).firstOrNull;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Professor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: scheme.secondaryContainer,
                        child: Icon(Icons.person,
                            size: 36, color: scheme.onSecondaryContainer),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name,
                                style:
                                    Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 2),
                            Text(title,
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    avatar: const Icon(Icons.person_pin, size: 18),
                    label: const Text('Faculty Member'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Department
          _InfoRow(
            icon: Icons.school,
            label: 'Department',
            value: department,
          ),
          // Office location
          if (office.isNotEmpty) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.room,
              label: 'Office',
              value: office,
            ),
          ],
          if (building != null) ...[
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.apartment,
              label: 'Building',
              value: building.name,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.stairs,
              label: 'Floor',
              value: poi.floorName ?? 'Floor ${poi.floorNumber}',
            ),
          ],
          const SizedBox(height: 16),
          // Office hours
          Card(
            child: ListTile(
              leading: Icon(Icons.schedule, color: scheme.primary),
              title: const Text('Weekly Office Hours'),
              subtitle: Text(
                officeHours.isNotEmpty ? officeHours : 'Not listed',
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Get directions (route drawing is Phase 5; this focuses the map).
          FilledButton.icon(
            onPressed: () {
              if (building != null) {
                showBuildingOnMap(context, ref, building, floor: floor);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Building data unavailable')),
                );
              }
            },
            icon: const Icon(Icons.directions),
            label: Text('Get Directions to Room ${poi.name}'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      )),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}
