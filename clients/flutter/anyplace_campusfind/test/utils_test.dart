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
    Poi poi(String name, [String? description, String? poisType]) => Poi(
          puid: 'p',
          buid: 'b',
          name: name,
          coordinatesLat: 0,
          coordinatesLon: 0,
          floorNumber: '0',
          description: description,
          poisType: poisType,
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

    test('derives categories from architect pois_type field', () {
      expect(CategoryDeriver.derivePoi(poi('408', null, 'Room')),
          EntityCategory.room);
      expect(CategoryDeriver.derivePoi(poi('308', null, 'Office')),
          EntityCategory.office);
      expect(CategoryDeriver.derivePoi(poi('Lift 1', null, 'Elevator')),
          EntityCategory.elevator);
      expect(CategoryDeriver.derivePoi(poi('Stairwell A', null, 'Stair')),
          EntityCategory.stairs);
      expect(CategoryDeriver.derivePoi(poi('WC 1', null, 'Toilets')),
          EntityCategory.toilets);
      expect(CategoryDeriver.derivePoi(poi('Main Door', null, 'Entrance')),
          EntityCategory.entrance);
      expect(CategoryDeriver.derivePoi(poi('LIB Central', null, 'Library')),
          EntityCategory.library);
      expect(CategoryDeriver.derivePoi(poi('Chem Lab', null, 'LAB')),
          EntityCategory.lab);
      expect(CategoryDeriver.derivePoi(poi('Kitchen', null, 'Kitchen')),
          EntityCategory.cafeteria);
      expect(CategoryDeriver.derivePoi(poi('Kiosk', null, 'Mini Market')),
          EntityCategory.cafeteria);
      // Professor titles beat the generic Office type.
      expect(
        CategoryDeriver.derivePoi(poi('Dr. Ahmed', null, 'Office')),
        EntityCategory.professor,
      );
      // Unknown architect types fall back to keyword/Other.
      expect(CategoryDeriver.derivePoi(poi('414', null, 'None')),
          EntityCategory.other);
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
        EntityCategory.library,
        EntityCategory.cafeteria,
        EntityCategory.other,
      ]);
    });

    test('discovers architect types in canonical enum order', () {
      final categories = CategoryDeriver.discoverCategories([
        poi('408', null, 'Room'),
        poi('Lift 1', null, 'Elevator'),
        poi('Wedding Hall', null, 'Cafeteria'),
        poi('Main Door', null, 'Entrance'),
      ]);
      expect(categories, [
        EntityCategory.room,
        EntityCategory.elevator,
        EntityCategory.entrance,
        EntityCategory.cafeteria,
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
