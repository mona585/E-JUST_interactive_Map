import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

void main() {
  group('AnyplaceApiClient POIs', () {
    const testBuid = 'building_b8f4e123_test';
    const testFloor = '0';

    final samplePoisJsonResponse = {
      'pois': [
        {
          'puid': 'poi_1',
          'buid': testBuid,
          'floor_number': testFloor,
          'name': 'G01 Room',
          'pois_type': 'Room',
          'coordinates_lat': '30.859418',
          'coordinates_lon': '29.562789',
        },
        {
          'puid': 'poi_2',
          'buid': testBuid,
          'floor_number': testFloor,
          'name': 'G02 Office',
          'pois_type': 'Office',
          'coordinates_lat': '30.859247',
          'coordinates_lon': '29.563119',
        },
      ]
    };

    test(
        'fetchPoisByFloor sends POST to /api/mapping/pois/floor/all and returns list of PoiModels',
        () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, ApiConfig.endpointPoisFloorAll);
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['buid'], testBuid);
        expect(body['floor_number'], testFloor);

        return http.Response(
          jsonEncode(samplePoisJsonResponse),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final pois = await apiClient.fetchPoisByFloor(testBuid, testFloor);

      expect(pois.length, equals(2));
      expect(pois[0].puid, 'poi_1');
      expect(pois[0].name, 'G01 Room');
      expect(pois[0].poisType, 'Room');
      expect(pois[1].puid, 'poi_2');
      expect(pois[1].name, 'G02 Office');
    });

    test('fetchPoisByFloor decodes GZIP compressed response properly', () async {
      final jsonText = jsonEncode(samplePoisJsonResponse);
      final gzippedBytes = gzip.encode(utf8.encode(jsonText));

      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          gzippedBytes,
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final pois = await apiClient.fetchPoisByFloor(testBuid, testFloor);

      expect(pois.length, equals(2));
      expect(pois[0].name, 'G01 Room');
    });

    test('fetchPoisByFloor returns empty list when pois array is empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'pois': []}), 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final pois = await apiClient.fetchPoisByFloor(testBuid, testFloor);

      expect(pois, isEmpty);
    });

    test('fetchPoisByFloor throws ApiException on HTTP 404', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'status': 'error', 'message': 'Space not found'}),
          404,
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);

      expect(
        () => apiClient.fetchPoisByFloor(testBuid, testFloor),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(404),
        )),
      );
    });

    test('fetchPoisByFloor throws ApiException on empty parameters', () async {
      final apiClient = AnyplaceApiClient();

      expect(
        () => apiClient.fetchPoisByFloor('', '0'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => apiClient.fetchPoisByFloor('buid_1', ''),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
