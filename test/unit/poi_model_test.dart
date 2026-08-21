import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';

void main() {
  group('PoiModel', () {
    test('parses complete valid JSON with string types', () {
      final json = {
        'puid': 'poi_123',
        'buid': 'building_456',
        'floor_number': '0',
        'floor_name': 'Ground Floor',
        'name': 'G01 Room',
        'description': 'Main Lecture Hall',
        'pois_type': 'Room',
        'coordinates_lat': '30.859418',
        'coordinates_lon': '29.562789',
        'is_building_entrance': 'false',
        'is_door': 'true',
        'is_published': 'true',
        'image': 'https://ap.cs.ucy.ac.cy/image.png',
      };

      final poi = PoiModel.fromJson(json);

      expect(poi.puid, 'poi_123');
      expect(poi.buid, 'building_456');
      expect(poi.floorNumber, '0');
      expect(poi.floorName, 'Ground Floor');
      expect(poi.name, 'G01 Room');
      expect(poi.description, 'Main Lecture Hall');
      expect(poi.poisType, 'Room');
      expect(poi.latitude, closeTo(30.859418, 0.000001));
      expect(poi.longitude, closeTo(29.562789, 0.000001));
      expect(poi.isBuildingEntrance, isFalse);
      expect(poi.isDoor, isTrue);
      expect(poi.isPublished, isTrue);
      expect(poi.imageUrl, 'https://ap.cs.ucy.ac.cy/image.png');
      expect(poi.latLng.latitude, closeTo(30.859418, 0.000001));
    });

    test('parses numeric values gracefully', () {
      final json = {
        'puid': 'poi_numeric',
        'buid': 'buid_1',
        'floor_number': 1,
        'name': 'Office 101',
        'pois_type': 'Office',
        'coordinates_lat': 35.1444,
        'coordinates_lon': 33.4105,
        'is_building_entrance': 1,
        'is_door': 0,
      };

      final poi = PoiModel.fromJson(json);

      expect(poi.puid, 'poi_numeric');
      expect(poi.floorNumber, '1');
      expect(poi.latitude, 35.1444);
      expect(poi.longitude, 33.4105);
      expect(poi.isBuildingEntrance, isTrue);
      expect(poi.isDoor, isFalse);
    });

    test('handles missing or null optional fields safely', () {
      final json = {
        'puid': 'poi_minimal',
        'buid': 'buid_min',
        'floor_number': '0',
      };

      final poi = PoiModel.fromJson(json);

      expect(poi.puid, 'poi_minimal');
      expect(poi.name, 'POI');
      expect(poi.poisType, 'Other');
      expect(poi.latitude, 0.0);
      expect(poi.longitude, 0.0);
      expect(poi.description, isNull);
      expect(poi.floorName, isNull);
    });

    test('toJson serializes model back to Map', () {
      const poi = PoiModel(
        puid: 'poi_test',
        buid: 'buid_test',
        floorNumber: '2',
        name: 'Elevator A',
        poisType: 'Elevator',
        latitude: 30.8592,
        longitude: 29.5631,
      );

      final json = poi.toJson();

      expect(json['puid'], 'poi_test');
      expect(json['buid'], 'buid_test');
      expect(json['floor_number'], '2');
      expect(json['name'], 'Elevator A');
      expect(json['pois_type'], 'Elevator');
      expect(json['coordinates_lat'], '30.8592');
      expect(json['coordinates_lon'], '29.5631');
    });
  });
}
