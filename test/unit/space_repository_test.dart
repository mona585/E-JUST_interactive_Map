import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';

void main() {
  group('AnyplaceSpaceRepository', () {
    test(
        'getPublicSpaces caches spaces in memory and returns cached on second call',
        () async {
      int requestCount = 0;
      final mockResponse = jsonEncode({
        'spaces': [
          {
            'buid': 'building_001',
            'name': 'Library',
            'coordinates_lat': '35.1444',
            'coordinates_lon': '33.4105',
          }
        ]
      });

      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(mockResponse, 200, headers: {
          'content-type': 'application/json',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceSpaceRepository(apiClient: apiClient);

      // First call -> hits API
      final list1 = await repository.getPublicSpaces();
      expect(list1.length, 1);
      expect(requestCount, 1);

      // Second call -> returns cached list without new HTTP call
      final list2 = await repository.getPublicSpaces();
      expect(list2.length, 1);
      expect(requestCount, 1);

      // Force reload -> triggers new HTTP call
      final list3 = await repository.getPublicSpaces(forceReload: true);
      expect(list3.length, 1);
      expect(requestCount, 2);
    });

    test('getSpaceByBuid returns cached space if available', () async {
      final mockResponse = jsonEncode({
        'spaces': [
          {
            'buid': 'buid_abc',
            'name': 'Cafeteria',
            'coordinates_lat': '35.12',
            'coordinates_lon': '33.12',
          }
        ]
      });

      final mockClient = MockClient((request) async {
        return http.Response(mockResponse, 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceSpaceRepository(apiClient: apiClient);

      await repository.getPublicSpaces();

      final space = await repository.getSpaceByBuid('buid_abc');
      expect(space, isNotNull);
      expect(space!.name, 'Cafeteria');
    });

    test('getFloorsByBuid caches floors per buid and returns cached on second call',
        () async {
      int floorRequestCount = 0;
      final mockFloorResponse = jsonEncode({
        'floors': [
          {
            'floor_number': '0',
            'floor_name': 'Ground Floor',
            'buid': 'buid_floor_test',
            'fuid': 'buid_floor_test_0',
            'is_published': 'true',
          },
          {
            'floor_number': '1',
            'floor_name': 'First Floor',
            'buid': 'buid_floor_test',
            'fuid': 'buid_floor_test_1',
            'is_published': 'true',
          },
        ]
      });

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/mapping/floor/all') {
          floorRequestCount++;
          return http.Response(mockFloorResponse, 200, headers: {
            'content-type': 'application/json',
          });
        }
        return http.Response('{}', 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceSpaceRepository(apiClient: apiClient);

      // First call -> hits API
      final floors1 = await repository.getFloorsByBuid('buid_floor_test');
      expect(floors1.length, 2);
      expect(floorRequestCount, 1);

      // Second call -> returns cached
      final floors2 = await repository.getFloorsByBuid('buid_floor_test');
      expect(floors2.length, 2);
      expect(floorRequestCount, 1);

      // Force reload -> hits API again
      final floors3 = await repository.getFloorsByBuid(
        'buid_floor_test',
        forceReload: true,
      );
      expect(floors3.length, 2);
      expect(floorRequestCount, 2);
    });
  });
}
