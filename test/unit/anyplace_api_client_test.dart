import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

void main() {
  group('AnyplaceApiClient', () {
    test('fetchPublicSpaces parses valid spaces list response', () async {
      final mockResponse = jsonEncode({
        'spaces': [
          {
            'buid': 'building_001',
            'name': 'Library',
            'coordinates_lat': '35.1444',
            'coordinates_lon': '33.4105',
            'bucode': 'LIB',
            'space_type': 'building',
          },
          {
            'buid': 'building_002',
            'name': 'Science Center',
            'coordinates_lat': '35.1450',
            'coordinates_lon': '33.4110',
            'bucode': 'SCI',
            'space_type': 'building',
          },
        ],
      });

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/mapping/space/public');
        expect(request.method, 'POST');
        expect(request.headers['Content-Type'], 'application/json');
        return http.Response(
          mockResponse,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final spaces = await apiClient.fetchPublicSpaces();

      expect(spaces.length, 2);
      expect(spaces[0].buid, 'building_001');
      expect(spaces[0].name, 'Library');
      expect(spaces[0].latitude, 35.1444);
      expect(spaces[0].bucode, 'LIB');
      expect(spaces[1].buid, 'building_002');
    });

    test('fetchPublicSpaces throws ApiException on HTTP non-200', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);

      expect(
        () => apiClient.fetchPublicSpaces(),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('fetchSpaceDetails returns SpaceModel for valid buid', () async {
      final mockResponse = jsonEncode({
        'buid': 'building_001',
        'name': 'Library',
        'coordinates_lat': '35.1444',
        'coordinates_lon': '33.4105',
        'bucode': 'LIB',
        'space_type': 'building',
      });

      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/mapping/space/get');
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['buid'], 'building_001');
        return http.Response(
          mockResponse,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final space = await apiClient.fetchSpaceDetails('building_001');

      expect(space.buid, 'building_001');
      expect(space.name, 'Library');
      expect(space.latitude, 35.1444);
    });

    test('fetchSpaceDetails throws ApiException on empty buid', () async {
      final apiClient = AnyplaceApiClient();

      expect(
        () => apiClient.fetchSpaceDetails(''),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'fetchFloorsForBuilding sends correct request and returns sorted floors',
      () async {
        final mockResponse = jsonEncode({
          'floors': [
            {
              'floor_number': '2',
              'floor_name': 'Level 2',
              'buid': 'buid_123',
              'fuid': 'buid_123_2',
              'is_published': 'true',
            },
            {
              'floor_number': '0',
              'floor_name': 'Ground Floor',
              'buid': 'buid_123',
              'fuid': 'buid_123_0',
              'is_published': 'true',
            },
            {
              'floor_number': '1',
              'floor_name': 'Level 1',
              'buid': 'buid_123',
              'fuid': 'buid_123_1',
              'is_published': 'true',
            },
            {
              'floor_number': '-1',
              'floor_name': 'Basement',
              'buid': 'buid_123',
              'fuid': 'buid_123_-1',
              'is_published': 'true',
            },
          ],
        });

        final mockClient = MockClient((request) async {
          expect(request.url.path, '/api/mapping/floor/all');
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'], 'application/json');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['buid'], 'buid_123');
          return http.Response(
            mockResponse,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);
        final floors = await apiClient.fetchFloorsForBuilding('buid_123');

        expect(floors.length, 4);
        // Verify natural sorted order (-1, 0, 1, 2)
        expect(floors[0].floorNumber, '-1');
        expect(floors[1].floorNumber, '0');
        expect(floors[2].floorNumber, '1');
        expect(floors[3].floorNumber, '2');
        expect(floors[0].displayName, 'Basement (Floor -1)');
      },
    );

    test(
      'fetchFloorsForBuilding decompresses GZIP byte responses and populates missing buid',
      () async {
        final jsonPayload = jsonEncode({
          'floors': [
            {
              'floor_number': '0',
              'floor_name': 'Ground',
              // buid intentionally omitted to verify fallback
            },
            {'floor_number': '1', 'floor_name': 'First', 'buid': ''},
          ],
        });

        // Compress JSON using GZIP
        final gzipBytes = gzip.encode(utf8.encode(jsonPayload));

        final mockClient = MockClient((request) async {
          return http.Response.bytes(
            gzipBytes,
            200,
            headers: {'content-type': 'application/octet-stream'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);
        final floors = await apiClient.fetchFloorsForBuilding('buid_gzip_test');

        expect(floors.length, 2);
        expect(floors[0].floorNumber, '0');
        expect(floors[0].buid, 'buid_gzip_test');
        expect(floors[1].floorNumber, '1');
        expect(floors[1].buid, 'buid_gzip_test');
      },
    );

    test('fetchFloorsForBuilding handles empty floors list response', () async {
      final mockResponse = jsonEncode({'floors': []});

      final mockClient = MockClient((request) async {
        return http.Response(
          mockResponse,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final floors = await apiClient.fetchFloorsForBuilding('buid_empty');

      expect(floors, isEmpty);
    });

    test(
      'fetchNavigationRouteFromCoordinates sends POST to navigation coordinates endpoint and parses route points',
      () async {
        final mockResponse = jsonEncode({
          'num_of_pois': 2,
          'pois': [
            {
              'lat': '35.1444',
              'lon': '33.4105',
              'puid': 'poi_start',
              'buid': 'buid_123',
              'floor_number': '1',
              'pois_type': 'None',
            },
            {
              'lat': '35.1445',
              'lon': '33.4106',
              'puid': 'poi_dest',
              'buid': 'buid_123',
              'floor_number': '1',
              'pois_type': 'Room',
            },
          ],
          'status': 'success',
        });

        final mockClient = MockClient((request) async {
          expect(request.url.path, '/api/navigation/route/coordinates');
          expect(request.method, 'POST');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['coordinates_lat'], '35.1444');
          expect(body['coordinates_lon'], '33.4105');
          expect(body['floor_number'], '1');
          expect(body['pois_to'], 'poi_dest');
          return http.Response(
            mockResponse,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);
        final route = await apiClient.fetchNavigationRouteFromCoordinates(
          latitude: 35.1444,
          longitude: 33.4105,
          floorNumber: '1',
          destinationPuid: 'poi_dest',
        );

        expect(route.hasRenderablePath, isTrue);
        expect(route.points.length, 2);
        expect(route.points.first.puid, 'poi_start');
        expect(route.points.last.poisType, 'Room');
      },
    );

    test(
      'fetchNavigationRouteFromCoordinates throws ApiException on backend error payload',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'status': 'error',
              'message': 'Navigation is not supported on your floor.',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);

        expect(
          () => apiClient.fetchNavigationRouteFromCoordinates(
            latitude: 35.1444,
            longitude: 33.4105,
            floorNumber: '1',
            destinationPuid: 'poi_dest',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Navigation is not supported on your floor.'),
            ),
          ),
        );
      },
    );

    test(
      'fetchNavigationRouteFromCoordinates throws ApiException on malformed route payload',
      () async {
        final mockClient = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'pois': [
                {
                  'lat': '35.1444',
                  'lon': '33.4105',
                  'puid': 'poi_start',
                  'buid': 'buid_123',
                  'floor_number': '1',
                  'pois_type': 'None',
                },
                {
                  'lat': 'invalid',
                  'lon': '33.4106',
                  'puid': 'poi_dest',
                  'buid': 'buid_123',
                  'floor_number': '1',
                  'pois_type': 'Room',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);

        expect(
          () => apiClient.fetchNavigationRouteFromCoordinates(
            latitude: 35.1444,
            longitude: 33.4105,
            floorNumber: '1',
            destinationPuid: 'poi_dest',
          ),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Invalid response format from server'),
            ),
          ),
        );
      },
    );

    test(
      'fetchFloorsForBuilding throws ApiException on error payload',
      () async {
        final mockResponse = jsonEncode({
          'status': 'error',
          'message': 'Cannot find building floors',
        });

        final mockClient = MockClient((request) async {
          return http.Response(
            mockResponse,
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final apiClient = AnyplaceApiClient(client: mockClient);

        expect(
          () => apiClient.fetchFloorsForBuilding('buid_err'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('Cannot find building floors'),
            ),
          ),
        );
      },
    );

    test('fetchFloorsForBuilding throws ApiException on empty buid', () async {
      final apiClient = AnyplaceApiClient();

      expect(
        () => apiClient.fetchFloorsForBuilding(''),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
