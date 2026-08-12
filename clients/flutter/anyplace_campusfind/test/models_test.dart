import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/models/campus.dart';
import 'package:anyplace_campusfind/models/floor.dart';
import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/position.dart';
import 'package:anyplace_campusfind/models/route.dart';
import 'package:anyplace_campusfind/models/space.dart';

void main() {
  group('Space.fromJson', () {
    test('parses a full space payload', () {
      final space = Space.fromJson(const {
        'buid': 'building_1',
        'name': 'Main Building',
        'coordinates_lat': '30.8564',
        'coordinates_lon': '29.5945',
        'space_type': 'building',
        'description': 'West Quad | Ramps & Elevators',
        'is_published': 'true',
      });

      expect(space.buid, 'building_1');
      expect(space.coordinatesLat, 30.8564);
      expect(space.coordinatesLon, 29.5945);
      expect(space.isBuilding, isTrue);
      expect(space.description, 'West Quad | Ramps & Elevators');
    });

    test('tolerates missing optional fields', () {
      final space = Space.fromJson(const {
        'buid': 'building_2',
        'name': 'B',
        'coordinates_lat': '1',
        'coordinates_lon': '2',
        'space_type': 'building',
      });
      expect(space.description, isNull);
      expect(space.url, isNull);
    });

    test('tolerates numeric coordinates', () {
      final space = Space.fromJson(const {
        'buid': 'b',
        'name': 'B',
        'coordinates_lat': 30.5,
        'coordinates_lon': 29.5,
        'space_type': 'building',
      });
      expect(space.coordinatesLat, 30.5);
    });
  });

  group('Campus.fromJson', () {
    test('parses spaces array and restores cuid', () {
      final campus = Campus.fromJson(const {
        'cuid': 'campus_1',
        'name': 'Main Campus',
        'greeklish': 'false',
        'spaces': [
          {
            'buid': 'building_1',
            'name': 'Main Building',
            'coordinates_lat': '1',
            'coordinates_lon': '2',
            'space_type': 'building',
          },
        ],
      });
      expect(campus.cuid, 'campus_1');
      expect(campus.spaces, hasLength(1));
    });
  });

  group('Floor.fromJson', () {
    test('parses floor with explicit fuid', () {
      final floor = Floor.fromJson(const {
        'fuid': 'building_1_0',
        'buid': 'building_1',
        'floor_number': '0',
        'floor_name': 'Ground',
        'description': 'Lecture Halls',
      });
      expect(floor.fuid, 'building_1_0');
      expect(floor.floorNumber, '0');
    });

    test('derives fuid when missing', () {
      final floor = Floor.fromJson(const {
        'buid': 'building_1',
        'floor_number': '1',
      });
      expect(floor.fuid, 'building_1_1');
    });
  });

  group('Poi.fromJson', () {
    test('parses POI fields', () {
      final poi = Poi.fromJson(const {
        'puid': 'poi_1',
        'buid': 'building_1',
        'name': 'Dr. Elena Rostova',
        'description': 'Associate Professor | CS Dept',
        'coordinates_lat': '30.8564',
        'coordinates_lon': '29.5945',
        'floor_number': '0',
        'pois_type': 'None',
        'is_building_entrance': 'true',
      });
      expect(poi.puid, 'poi_1');
      expect(poi.isEntrance, isTrue);
      expect(poi.description, 'Associate Professor | CS Dept');
    });
  });

  group('RoutePoint / NavigationRoute', () {
    test('parses route points', () {
      final route = NavigationRoute.fromJson(const {
        'num_of_pois': 2,
        'pois': [
          {
            'lat': '30.856',
            'lon': '29.594',
            'puid': 'poi_1',
            'buid': 'building_1',
            'floor_number': '0',
            'pois_type': 'None',
          },
          {
            'lat': '30.857',
            'lon': '29.595',
            'puid': 'poi_2',
            'buid': 'building_1',
            'floor_number': '0',
          },
        ],
      });
      expect(route.numOfPois, 2);
      expect(route.pois, hasLength(2));
      expect(route.pois.first.lat, 30.856);
      expect(route.pois.last.poisType, isNull);
    });
  });

  group('PositionEstimate', () {
    test('parses coordinates', () {
      final pos = PositionEstimate.fromJson(const {
        'lat': '30.856',
        'long': '29.594',
      });
      expect(pos.hasFix, isTrue);
      expect(pos.lat, 30.856);
    });

    test('detects missing fix (0 0)', () {
      final pos = PositionEstimate.fromJson(const {
        'lat': '0',
        'long': '0',
      });
      expect(pos.hasFix, isFalse);
    });
  });
}
