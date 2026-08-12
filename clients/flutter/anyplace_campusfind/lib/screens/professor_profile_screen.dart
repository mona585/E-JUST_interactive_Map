import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/theme.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/providers.dart';
import '../utils/description_parser.dart';
import '../utils/map_focus.dart';

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
    final title = parser.professorTitle.isNotEmpty ? parser.professorTitle : 'Faculty Member';
    final department = parser.professorDepartment.isNotEmpty
        ? parser.professorDepartment
        : (poi.floorName ?? poi.floorNumber);
    final office = parser.officeLocation;
    final officeHours = parser.officeHours;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Professor Profile',
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
        padding: const EdgeInsets.all(20),
        children: [
          // Profile card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: const Color(0xFFF5F5F5),
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
                      const SizedBox(height: 2),
                      Text(title,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      const SizedBox(height: 2),
                      Text(department,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Available status + Save
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9C4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.circle, size: 10, color: Color(0xFFF9A825)),
                      SizedBox(width: 8),
                      Text('Available Now',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFF57F17))),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.star_border, size: 20, color: AppTheme.primary),
                    SizedBox(width: 6),
                    Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Office Location
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Office Location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.apartment, color: AppTheme.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(building?.name ?? 'Building',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            '$office · Floor ${poi.floorNumber}${parser.professorDepartment.isNotEmpty ? ' (${parser.professorDepartment})' : ''}',
                            style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Map Pin',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Weekly Office Hours
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Weekly Office Hours',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 12),
                if (officeHours.isNotEmpty) ...[
                  _OfficeHourRow(
                    day: officeHours.split(RegExp(r'\s*(?:,|\|)\s*')).first.trim(),
                    time: officeHours.contains(RegExp(r'\d+\s*(?:AM|PM)'))
                        ? officeHours.replaceAll(RegExp(r'^[^0-9]*'), '')
                        : 'See department',
                    highlighted: true,
                  ),
                  if (officeHours.contains('Friday'))
                    _OfficeHourRow(day: 'Friday', time: '10:00 AM - 11:30 AM', highlighted: false),
                ] else ...[
                  _OfficeHourRow(day: officeHours.isNotEmpty ? officeHours : 'Mon, Wed', time: '2:00 PM - 3:30 PM', highlighted: true),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Get Directions button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (building != null) {
                  navigateToPoiOnMap(context, ref, poi);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Building data unavailable')),
                  );
                }
              },
              icon: const Icon(Icons.navigation, size: 20),
              label: Text('Get Directions to Room ${poi.name}',
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
    );
  }
}

class _OfficeHourRow extends StatelessWidget {
  const _OfficeHourRow({
    required this.day,
    required this.time,
    required this.highlighted,
  });

  final String day;
  final String time;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: highlighted ? AppTheme.primary : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? AppTheme.primary : AppTheme.cardBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(day,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: highlighted ? Colors.white : AppTheme.textPrimary)),
          ),
          Text(time,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: highlighted ? Colors.white : AppTheme.textTertiary)),
        ],
      ),
    );
  }
}
