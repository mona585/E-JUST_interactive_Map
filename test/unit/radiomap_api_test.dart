import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

void main() {
  group('AnyplaceApiClient RadioMap', () {
    const testBuid = 'building_test_123';
    const testFloor = '1';
    const rawRadiomapSample =
        '# NaN -110\n'
        '# X, Y, HEADING, 84:c9:b2:6a:bd:ba, 04:bf:6d:db:65:f3\n'
        '66.333898, 14.147252, 0, -91.7, -79.7\n'
        '66.333882, 14.147260, 0, -94.3, -79.3\n';

    test('fetchRadioMapMetadata returns map_url_mean on success', () async {
      final mockMetadataResponse = jsonEncode({
        'map_url_mean':
            'https://ap.cs.ucy.ac.cy:44/anyplace/radiomaps_frozen/$testBuid/$testFloor/indoor-radiomap-mean.txt',
        'status': 'success',
        'message': 'Successfully served radiomap floor.',
        'status_code': 200,
      });

      final mockClient = MockClient((request) async {
        expect(request.url.path, ApiConfig.endpointRadiomapSpace);
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['buid'], testBuid);
        expect(body['floor'], testFloor);
        return http.Response(mockMetadataResponse, 200, headers: {
          'content-type': 'application/json',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final mapUrl = await apiClient.fetchRadioMapMetadata(testBuid, testFloor);

      expect(mapUrl, contains('radiomaps_frozen'));
      expect(mapUrl, contains(testBuid));
    });

    test('fetchRadioMapMetadata throws ApiException when unsupported (400)',
        () async {
      final mockResponse = jsonEncode({
        'status': 'error',
        'message': 'Area not supported yet!',
        'status_code': 400,
      });

      final mockClient = MockClient((request) async {
        return http.Response(mockResponse, 400, headers: {
          'content-type': 'application/json',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);

      expect(
        () => apiClient.fetchRadioMapMetadata(testBuid, testFloor),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('Area not supported yet!'),
        )),
      );
    });

    test('fetchRadioMapRaw sends POST to normalized endpoint and returns raw text',
        () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.path,
          '${ApiConfig.endpointRadiomapFrozen}/$testBuid/$testFloor/${ApiConfig.defaultRadiomapMeanFilename}',
        );
        expect(request.method, 'POST');
        return http.Response(rawRadiomapSample, 200, headers: {
          'content-type': 'text/plain; charset=utf-8',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final text = await apiClient.fetchRadioMapRaw(testBuid, testFloor);

      expect(text, equals(rawRadiomapSample));
      expect(text, startsWith('# NaN'));
    });

    test('fetchRadioMap coordinates metadata fetch and normalized download',
        () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (request.url.path == ApiConfig.endpointRadiomapSpace) {
          final metadataJson = jsonEncode({
            'map_url_mean':
                'https://ap.cs.ucy.ac.cy:44/anyplace/radiomaps_frozen/$testBuid/$testFloor/indoor-radiomap-mean.txt',
            'status': 'success',
          });
          return http.Response(metadataJson, 200, headers: {
            'content-type': 'application/json',
          });
        } else if (request.url.path ==
            '${ApiConfig.endpointRadiomapFrozen}/$testBuid/$testFloor/${ApiConfig.defaultRadiomapMeanFilename}') {
          return http.Response(rawRadiomapSample, 200);
        }
        return http.Response('Not Found', 404);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final text = await apiClient.fetchRadioMap(testBuid, testFloor);

      expect(requestCount, 2);
      expect(text, equals(rawRadiomapSample));
    });

    test('fetchRadioMap throws ApiException on empty buid or floor', () async {
      final apiClient = AnyplaceApiClient();

      expect(
        () => apiClient.fetchRadioMap('', '1'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => apiClient.fetchRadioMap('buid_1', ''),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
