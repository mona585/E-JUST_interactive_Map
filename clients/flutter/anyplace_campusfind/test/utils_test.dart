import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/utils/category_deriver.dart';
import 'package:anyplace_campusfind/utils/description_parser.dart';
import 'package:anyplace_campusfind/utils/distance_calculator.dart';

void main() {
  group('DescriptionParser', () {
    test('parses professor description', () {
      final parser = DescriptionParser(
        'Dr. Elena Rostova | Associate Professor | CS Dept | '
        'Office 402, Floor 4 | Mon/Wed 2-3:30PM',
      );
      expect(parser.professorName, 'Dr. Elena Rostova');
      expect(parser.professorTitle, 'Associate Professor');
      expect(parser.professorDepartment, 'CS Dept');
      expect(parser.officeLocation, 'Office 402, Floor 4');
      expect(parser.officeHours, 'Mon/Wed 2-3:30PM');
    });

    test('parses building description and facility tags', () {
      final parser = DescriptionParser(
        'Main Campus West Quad | Opened 2021 | Ramps & Elevators | '
        'Braille Signage',
      );
      expect(parser.summary, 'Main Campus West Quad · Opened 2021');
      expect(parser.facilityTags, ['Ramps & Elevators', 'Braille Signage']);
      expect(parser.hasAccessibilityInfo, isTrue);
    });

    test('handles null and empty descriptions', () {
      expect(DescriptionParser(null).isEmpty, isTrue);
      expect(DescriptionParser('').segments, isEmpty);
      expect(DescriptionParser('   ').professorName, '');
    });
  });

  group('CategoryDeriver', () {
    Poi poi(String name, [String? description]) => Poi(
          puid: 'p',
          buid: 'b',
          name: name,
          coordinatesLat: 0,
          coordinatesLon: 0,
          floorNumber: '0',
          description: description,
        );

    test('derives categories from names and descriptions', () {
      expect(CategoryDeriver.derivePoi(poi('Prof. Ahmed')), EntityCategory.professor);
      expect(CategoryDeriver.derivePoi(poi('Dr. Sara')), EntityCategory.professor);
      expect(CategoryDeriver.derivePoi(poi('Main Cafeteria')), EntityCategory.cafeteria);
      expect(CategoryDeriver.derivePoi(poi('Dining Hall')), EntityCategory.cafeteria);
      expect(CategoryDeriver.derivePoi(poi('Central Library')), EntityCategory.library);
      expect(CategoryDeriver.derivePoi(poi('Physics Lab')), EntityCategory.lab);
      expect(CategoryDeriver.derivePoi(poi('CS Laboratory')), EntityCategory.lab);
      expect(CategoryDeriver.derivePoi(poi('Room 101')), EntityCategory.other);
      expect(
        CategoryDeriver.derivePoi(poi('Conference Room', 'Used by CS professors')),
        EntityCategory.professor,
      );
    });

    test('discovers distinct categories in canonical order', () {
      final categories = CategoryDeriver.discoverCategories([
        poi('Prof. Ahmed'),
        poi('Main Cafeteria'),
        poi('Central Library'),
        poi('Room 101'),
      ]);
      expect(categories, [
        EntityCategory.professor,
        EntityCategory.cafeteria,
        EntityCategory.library,
        EntityCategory.other,
      ]);
    });
  });

  group('DistanceCalculator', () {
    test('haversine returns ~0 for identical points', () {
      expect(DistanceCalculator.haversineMeters(30.8564, 29.5945, 30.8564, 29.5945), 0);
    });

    test('haversine approximates a known distance', () {
      // 1 degree of latitude ~= 111.19 km
      final d = DistanceCalculator.haversineMeters(0, 0, 1, 0);
      expect(d, closeTo(111194.9, 500));
    });

    test('finds nearest space', () {
      final far = _space('far', 1, 1);
      final near = _space('near', 0.0001, 0.0001);
      expect(DistanceCalculator.nearestSpace(0, 0, [far, near]), near);
    });
  });
}

Space _space(String buid, double lat, double lon) => Space(
      buid: buid,
      name: buid,
      coordinatesLat: lat,
      coordinatesLon: lon,
      spaceType: 'building',
    );
