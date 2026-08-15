import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

void main() {
  group('AnyplaceApiClient Floorplan Image', () {
    const testBuid = 'building_test_123';
    const testFloor = '0';
    final samplePngBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D
    ]);
    final sampleBase64 = base64Encode(samplePngBytes);

    test(
        'fetchFloorplanImage sends POST to /api/floorplans64 and decodes base64 bytes',
        () async {
      final mockClient = MockClient((request) async {
        expect(
          request.url.path,
          '${ApiConfig.endpointFloorplans64}/$testBuid/$testFloor',
        );
        expect(request.method, 'POST');
        return http.Response(sampleBase64, 200, headers: {
          'content-type': 'application/octet-stream',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final bytes = await apiClient.fetchFloorplanImage(testBuid, testFloor);

      expect(bytes, equals(samplePngBytes));
    });

    test(
        'fetchFloorplanImage decodes GZIP compressed response properly',
        () async {
      final gzippedBytes = gzip.encode(utf8.encode(sampleBase64));

      final mockClient = MockClient((request) async {
        return http.Response.bytes(gzippedBytes, 200, headers: {
          'content-type': 'application/octet-stream',
        });
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final bytes = await apiClient.fetchFloorplanImage(testBuid, testFloor);

      expect(bytes, equals(samplePngBytes));
    });

    test(
        'fetchFloorplanImage cleans data:image/png;base64, prefix if present',
        () async {
      final prefixedBase64 = 'data:image/png;base64,$sampleBase64';

      final mockClient = MockClient((request) async {
        return http.Response(prefixedBase64, 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final bytes = await apiClient.fetchFloorplanImage(testBuid, testFloor);

      expect(bytes, equals(samplePngBytes));
    });

    test('fetchFloorplanImage throws ApiException on HTTP 404', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '{"status":"error","message":"Cannot find floorplan"}',
          404,
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);

      expect(
        () => apiClient.fetchFloorplanImage(testBuid, testFloor),
        throwsA(isA<ApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          equals(404),
        )),
      );
    });

    test('fetchFloorplanImage throws ApiException on empty buid or floor',
        () async {
      final apiClient = AnyplaceApiClient();

      expect(
        () => apiClient.fetchFloorplanImage('', '0'),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => apiClient.fetchFloorplanImage('buid_1', ''),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
