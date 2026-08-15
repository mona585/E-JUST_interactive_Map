import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';

void main() {
  group('SpaceModel', () {
    test('parses standard Anyplace JSON correctly', () {
      final json = {
        'buid': 'building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423000957534',
        'name': 'UCY, FST02/ΘΕΕ02, New Campus, Nicosia, Cyprus',
        'coordinates_lat': '35.14442624023263',
        'coordinates_lon': '33.41047257184982',
        'bucode': 'FST02',
        'description': 'Faculty of Pure and Applied Sciences',
        'address': 'University of Cyprus, 1 University Avenue',
        'url': 'https://www.ucy.ac.cy',
        'is_published': 'true',
        'space_type': 'building',
      };

      final model = SpaceModel.fromJson(json);

      expect(model.buid, 'building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423000957534');
      expect(model.name, 'UCY, FST02/ΘΕΕ02, New Campus, Nicosia, Cyprus');
      expect(model.latitude, closeTo(35.144426, 0.0001));
      expect(model.longitude, closeTo(33.410472, 0.0001));
      expect(model.bucode, 'FST02');
      expect(model.description, 'Faculty of Pure and Applied Sciences');
      expect(model.address, 'University of Cyprus, 1 University Avenue');
      expect(model.url, 'https://www.ucy.ac.cy');
      expect(model.isPublished, isTrue);
      expect(model.spaceType, 'building');
      expect(model.latLng.latitude, closeTo(35.144426, 0.0001));
      expect(model.latLng.longitude, closeTo(33.410472, 0.0001));
    });

    test('handles numeric coordinates in JSON correctly', () {
      final json = {
        'buid': 'building_123',
        'name': 'Numeric Building',
        'coordinates_lat': 35.12345,
        'coordinates_lon': 33.54321,
      };

      final model = SpaceModel.fromJson(json);

      expect(model.buid, 'building_123');
      expect(model.name, 'Numeric Building');
      expect(model.latitude, 35.12345);
      expect(model.longitude, 33.54321);
      expect(model.bucode, isNull);
      expect(model.description, isNull);
      expect(model.isPublished, isTrue);
      expect(model.spaceType, 'building');
    });

    test('serializes to JSON correctly', () {
      const model = SpaceModel(
        buid: 'building_test',
        name: 'Test Building',
        latitude: 35.0,
        longitude: 33.0,
        bucode: 'TEST',
        description: 'Test Description',
      );

      final json = model.toJson();

      expect(json['buid'], 'building_test');
      expect(json['name'], 'Test Building');
      expect(json['coordinates_lat'], '35.0');
      expect(json['coordinates_lon'], '33.0');
      expect(json['bucode'], 'TEST');
      expect(json['description'], 'Test Description');
      expect(json['space_type'], 'building');
    });

    test('equality and hashCode work as expected', () {
      const model1 = SpaceModel(
        buid: 'buid_1',
        name: 'Building 1',
        latitude: 35.0,
        longitude: 33.0,
      );
      const model2 = SpaceModel(
        buid: 'buid_1',
        name: 'Building 1',
        latitude: 35.0,
        longitude: 33.0,
      );
      const model3 = SpaceModel(
        buid: 'buid_2',
        name: 'Building 2',
        latitude: 36.0,
        longitude: 34.0,
      );

      expect(model1, equals(model2));
      expect(model1.hashCode, equals(model2.hashCode));
      expect(model1, isNot(equals(model3)));
    });
  });
}
