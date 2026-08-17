import 'package:flutter/material.dart';
import '../data/models/poi_model.dart';

enum EntityCategory {
  professor,
  cafeteria,
  building,
  library,
  lab,
  room,
  office,
  elevator,
  stairs,
  toilets,
  entrance,
  floor,
  other;

  Color get color {
    switch (this) {
      case EntityCategory.professor:
        return const Color(0xFF7E57C2);
      case EntityCategory.cafeteria:
        return const Color(0xFFFFA000);
      case EntityCategory.building:
        return const Color(0xFF1976D2);
      case EntityCategory.library:
        return const Color(0xFF388E3C);
      case EntityCategory.lab:
        return const Color(0xFFD32F2F);
      case EntityCategory.room:
        return const Color(0xFF00838F);
      case EntityCategory.office:
        return const Color(0xFF5D4037);
      case EntityCategory.elevator:
        return const Color(0xFF757575);
      case EntityCategory.stairs:
        return const Color(0xFF9E9E9E);
      case EntityCategory.toilets:
        return const Color(0xFF0097A7);
      case EntityCategory.entrance:
        return const Color(0xFF689F38);
      case EntityCategory.floor:
        return const Color(0xFFEF6C00);
      case EntityCategory.other:
        return const Color(0xFF78909C);
    }
  }

  IconData get icon {
    switch (this) {
      case EntityCategory.professor:
        return Icons.person;
      case EntityCategory.cafeteria:
        return Icons.restaurant;
      case EntityCategory.building:
        return Icons.business;
      case EntityCategory.library:
        return Icons.menu_book;
      case EntityCategory.lab:
        return Icons.science;
      case EntityCategory.room:
        return Icons.meeting_room;
      case EntityCategory.office:
        return Icons.work;
      case EntityCategory.elevator:
        return Icons.elevator;
      case EntityCategory.stairs:
        return Icons.stairs;
      case EntityCategory.toilets:
        return Icons.wc;
      case EntityCategory.entrance:
        return Icons.door_front_door;
      case EntityCategory.floor:
        return Icons.layers;
      case EntityCategory.other:
        return Icons.help_outline;
    }
  }

  String get label {
    switch (this) {
      case EntityCategory.professor:
        return 'Professor';
      case EntityCategory.cafeteria:
        return 'Cafeteria';
      case EntityCategory.building:
        return 'Building';
      case EntityCategory.library:
        return 'Library';
      case EntityCategory.lab:
        return 'Lab';
      case EntityCategory.room:
        return 'Room';
      case EntityCategory.office:
        return 'Office';
      case EntityCategory.elevator:
        return 'Elevator';
      case EntityCategory.stairs:
        return 'Stairs';
      case EntityCategory.toilets:
        return 'Toilets';
      case EntityCategory.entrance:
        return 'Entrance';
      case EntityCategory.floor:
        return 'Floor';
      case EntityCategory.other:
        return 'Other';
    }
  }
}

class CategoryDeriver {
  static List<EntityCategory> discoverCategories(List<PoiModel> pois) {
    final seen = <EntityCategory>{};
    for (final poi in pois) {
      seen.add(fromPoiType(poi.poisType));
    }
    seen.remove(EntityCategory.other);
    return seen.toList();
  }

  static EntityCategory fromPoiType(String poisType) {
    final t = poisType.toLowerCase();
    if (t.contains('professor') || t.contains('faculty')) {
      return EntityCategory.professor;
    }
    if (t.contains('cafeteria') || t.contains('canteen') || t.contains('food')) {
      return EntityCategory.cafeteria;
    }
    if (t.contains('building') || t.contains('hall')) {
      return EntityCategory.building;
    }
    if (t.contains('library') || t.contains('book')) {
      return EntityCategory.library;
    }
    if (t.contains('lab') || t.contains('laboratory')) {
      return EntityCategory.lab;
    }
    if (t.contains('room') || t.contains('classroom')) {
      return EntityCategory.room;
    }
    if (t.contains('office')) {
      return EntityCategory.office;
    }
    if (t.contains('elevator')) {
      return EntityCategory.elevator;
    }
    if (t.contains('stairs') || t.contains('staircase')) {
      return EntityCategory.stairs;
    }
    if (t.contains('toilet') || t.contains('bathroom') || t.contains('restroom')) {
      return EntityCategory.toilets;
    }
    if (t.contains('entrance') || t.contains('door')) {
      return EntityCategory.entrance;
    }
    if (t.contains('floor')) {
      return EntityCategory.floor;
    }
    return EntityCategory.other;
  }

  static EntityCategory fromSpaceType(String spaceType) {
    final t = spaceType.toLowerCase();
    if (t.contains('library')) return EntityCategory.library;
    if (t.contains('cafeteria') || t.contains('canteen') || t.contains('food')) {
      return EntityCategory.cafeteria;
    }
    if (t.contains('lab') || t.contains('laboratory')) return EntityCategory.lab;
    if (t.contains('office')) return EntityCategory.office;
    return EntityCategory.building;
  }

  static EntityCategory fromFloorNumber(String floorNumber) {
    return EntityCategory.floor;
  }
}
