import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';

void main() {
  group('FloorModel Unit Tests', () {
    test('parses full JSON correctly', () {
      final json = {
        'buid': 'building_abc_123',
        'floor_number': '1',
        'floor_name': 'First Floor',
        'description': 'Main Laboratory Floor',
        'fuid': 'building_abc_123_1',
        'is_published': 'true',
        'bottom_left_lat': '35.1440',
        'bottom_left_lng': '33.4100',
        'top_right_lat': '35.1450',
        'top_right_lng': '33.4110',
      };

      final floor = FloorModel.fromJson(json);

      expect(floor.buid, 'building_abc_123');
      expect(floor.floorNumber, '1');
      expect(floor.numericFloor, 1);
      expect(floor.floorName, 'First Floor');
      expect(floor.description, 'Main Laboratory Floor');
      expect(floor.fuid, 'building_abc_123_1');
      expect(floor.isPublished, isTrue);
      expect(floor.bottomLeftLat, 35.1440);
      expect(floor.bottomLeftLng, 33.4100);
      expect(floor.topRightLat, 35.1450);
      expect(floor.topRightLng, 33.4110);
      expect(floor.displayName, 'First Floor (Floor 1)');
      expect(floor.badgeLabel, 'F1');
    });

    test('handles negative basement floors and default names', () {
      final json = {
        'buid': 'building_xyz',
        'floor_number': '-1',
        'floor_name': '-1',
      };

      final floor = FloorModel.fromJson(json);

      expect(floor.floorNumber, '-1');
      expect(floor.numericFloor, -1);
      expect(floor.displayName, 'Floor -1');
      expect(floor.badgeLabel, 'B1');
      expect(floor.fuid, 'building_xyz_-1');
    });

    test('sorts floors in natural numeric order', () {
      final floors = [
        const FloorModel(buid: 'b', floorNumber: '3'),
        const FloorModel(buid: 'b', floorNumber: '-2'),
        const FloorModel(buid: 'b', floorNumber: '0'),
        const FloorModel(buid: 'b', floorNumber: '-1'),
        const FloorModel(buid: 'b', floorNumber: '1'),
        const FloorModel(buid: 'b', floorNumber: '2'),
      ];

      floors.sort();

      expect(
        floors.map((f) => f.floorNumber).toList(),
        ['-2', '-1', '0', '1', '2', '3'],
      );
    });

    test('supports value equality and hash code based on buid and floorNumber',
        () {
      const floor1 = FloorModel(
        buid: 'building_1',
        floorNumber: '0',
        floorName: 'Ground',
      );
      const floor2 = FloorModel(
        buid: 'building_1',
        floorNumber: '0',
        floorName: 'Level 0',
      );
      const floor3 = FloorModel(
        buid: 'building_1',
        floorNumber: '1',
      );
      const floorOtherBuid = FloorModel(
        buid: 'building_2',
        floorNumber: '0',
      );

      expect(floor1, equals(floor2));
      expect(floor1.hashCode, equals(floor2.hashCode));
      expect(floor1, isNot(equals(floor3)));
      expect(floor1, isNot(equals(floorOtherBuid)));
    });

    test('serializes to JSON correctly', () {
      const floor = FloorModel(
        buid: 'building_1',
        floorNumber: '2',
        floorName: 'Level 2',
        description: 'Offices',
        fuid: 'building_1_2',
        isPublished: true,
        bottomLeftLat: 35.1,
        bottomLeftLng: 33.1,
      );

      final json = floor.toJson();

      expect(json['buid'], 'building_1');
      expect(json['floor_number'], '2');
      expect(json['floor_name'], 'Level 2');
      expect(json['fuid'], 'building_1_2');
      expect(json['is_published'], 'true');
      expect(json['bottom_left_lat'], '35.1');
    });
  });
}
