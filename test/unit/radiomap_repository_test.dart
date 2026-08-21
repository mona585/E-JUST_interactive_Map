import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/radiomap_cache.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';

void main() {
  late Directory tempDir;
  late RadioMapCache cache;

  const buid = 'building_123';
  const floor = '1';
  const sampleMap = '# NaN -110\n# X, Y, HEADING, mac1\n10.0, 20.0, 0, -85\n';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('radiomap_repo_test_');
    cache = RadioMapCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AnyplaceRadioMapRepository', () {
    test('cache MISS: fetches from API, saves to cache, returns text',
        () async {
      int apiCalls = 0;

      final mockClient = MockClient((request) async {
        apiCalls++;
        if (request.url.path == ApiConfig.endpointRadiomapSpace) {
          return http.Response('{"map_url_mean": "http://anyplace/radiomaps_frozen/$buid/$floor/indoor-radiomap-mean.txt"}', 200);
        } else {
          return http.Response(sampleMap, 200);
        }
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceRadioMapRepository(apiClient: apiClient, cache: cache);

      expect(await cache.hasRadioMap(buid, floor), isFalse);

      final result = await repository.getRadioMap(buid, floor);

      expect(result, equals(sampleMap));
      expect(apiCalls, 2); // 1 metadata + 1 raw download
      expect(await cache.hasRadioMap(buid, floor), isTrue);
    });

    test('cache HIT: returns from cache without making any HTTP call',
        () async {
      // Pre-populate cache
      await cache.saveRadioMap(buid, floor, sampleMap);

      int apiCalls = 0;
      final mockClient = MockClient((request) async {
        apiCalls++;
        return http.Response('Error', 500);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceRadioMapRepository(apiClient: apiClient, cache: cache);

      final result = await repository.getRadioMap(buid, floor);

      expect(result, equals(sampleMap));
      expect(apiCalls, 0); // No HTTP calls on cache hit
    });

    test('forceReload: bypasses cache and re-downloads', () async {
      await cache.saveRadioMap(buid, floor, 'old_cached_content');

      const updatedMap = '# NaN -110\n# X, Y, HEADING, macUpdated\n12.0, 22.0, 0, -60\n';
      int apiCalls = 0;

      final mockClient = MockClient((request) async {
        apiCalls++;
        if (request.url.path == ApiConfig.endpointRadiomapSpace) {
          return http.Response('{"map_url_mean": "http://anyplace/radiomaps_frozen/$buid/$floor/indoor-radiomap-mean.txt"}', 200);
        } else {
          return http.Response(updatedMap, 200);
        }
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repository = AnyplaceRadioMapRepository(apiClient: apiClient, cache: cache);

      final result = await repository.getRadioMap(buid, floor, forceReload: true);

      expect(result, equals(updatedMap));
      expect(apiCalls, 2);
      expect(await cache.getRadioMap(buid, floor), equals(updatedMap));
    });
  });
}
