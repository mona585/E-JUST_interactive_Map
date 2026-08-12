import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../models/poi.dart';
import '../models/space.dart';

/// POI/entity categories.
///
/// Categories are driven primarily by the architect-defined `pois_type` field
/// of each POI (Room, Office, Stair, Elevator, Toilets, Entrance, Library,
/// LAB, Kitchen, ...) and fall back to name/description keyword scanning so a
/// zero-config backend still yields sensible groups.
///
/// The set of categories present is discovered dynamically from backend data,
/// not hardcoded — new categories appear automatically as data changes.
enum EntityCategory {
  professor('Professors', Icons.person, AppTheme.primary, 'PROF'),
  room('Rooms', Icons.meeting_room, Color(0xFF5C6BC0), 'ROOM'),
  office('Offices', Icons.business, Color(0xFF546E7A), 'OFC'),
  elevator('Elevators', Icons.elevator, Color(0xFF00897B), 'ELEV'),
  stairs('Stairs', Icons.stairs, Color(0xFF8D6E63), 'STRS'),
  toilets('Toilets', Icons.wc, Color(0xFF00838F), 'WC'),
  entrance('Entrances', Icons.door_front_door, Color(0xFF2E7D32), 'ENTR'),
  library('Library', Icons.local_library, Color(0xFF7B1FA2), 'LIB'),
  cafeteria('Cafeterias', Icons.restaurant, Color(0xFFFFA000), 'CAFE'),
  lab('Labs', Icons.science, Color(0xFFEF6C00), 'LAB'),
  building('Buildings', Icons.apartment, Color(0xFF1976D2), 'BLDG'),
  other('Other', Icons.place, Color(0xFF757575), 'OTHER');

  const EntityCategory(this.label, this.icon, this.color, this.badge);

  final String label;
  final IconData icon;
  final Color color;
  final String badge;
}

/// Derives a category for a POI based on its architect-defined `pois_type`
/// first, then name/description keywords.
class CategoryDeriver {
  static EntityCategory derivePoi(Poi poi) {
    final name = poi.name.toLowerCase();
    final description = (poi.description ?? '').toLowerCase();
    final text = '$name $description';

    // Professor signals (titles) take priority over the generic "Office" type.
    if (poi.name.contains('Prof.') ||
        poi.name.contains('Dr.') ||
        text.contains('professor')) {
      return EntityCategory.professor;
    }

    // Architect-defined type is authoritative when present.
    final type = (poi.poisType ?? '').toLowerCase().trim();
    if (type.isNotEmpty) {
      final byType = _fromPoisType(type);
      if (byType != null) return byType;
    }

    // Keyword fallback for backends that do not populate pois_type.
    if (text.contains('cafeteria') ||
        text.contains('dining') ||
        text.contains('restaurant')) {
      return EntityCategory.cafeteria;
    }
    if (text.contains('library')) return EntityCategory.library;
    if (text.contains('lab') || text.contains('laboratory')) {
      return EntityCategory.lab;
    }
    return EntityCategory.other;
  }

  static EntityCategory deriveSpace(Space space) {
    if (space.spaceType == 'building') return EntityCategory.building;
    return EntityCategory.other;
  }

  /// Maps an architect `pois_type` value to a category, or null when unknown
  /// (callers then fall back to keyword scanning / Other).
  static EntityCategory? _fromPoisType(String type) {
    if (type.contains('prof')) return EntityCategory.professor;
    if (type.contains('room')) return EntityCategory.room;
    if (type.contains('office')) return EntityCategory.office;
    if (type.contains('elevator') || type.contains('lift')) {
      return EntityCategory.elevator;
    }
    if (type.contains('stair')) return EntityCategory.stairs;
    if (type.contains('toilet')) return EntityCategory.toilets;
    if (type.contains('entrance')) return EntityCategory.entrance;
    if (type.contains('library')) return EntityCategory.library;
    if (type.contains('lab')) return EntityCategory.lab;
    if (type.contains('kitchen') ||
        type.contains('cafeteria') ||
        type.contains('dining') ||
        type.contains('restaurant') ||
        type.contains('mini market') ||
        type.contains('food')) {
      return EntityCategory.cafeteria;
    }
    return null;
  }

  /// The distinct categories present in the given POIs, in canonical order.
  static List<EntityCategory> discoverCategories(List<Poi> pois) {
    final seen = <EntityCategory>{};
    for (final poi in pois) {
      seen.add(derivePoi(poi));
    }
    return EntityCategory.values
        .where((c) => seen.contains(c))
        .toList();
  }
}