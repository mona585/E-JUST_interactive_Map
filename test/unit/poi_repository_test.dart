import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/poi_cache.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';

void main() {
  late Directory tempDir;
  late PoiCache cache;

  const buid = 'building_123';
  const floor = '0';

  const samplePoi = PoiModel(
    puid: 'poi_repo_1',
    buid: buid,
    floorNumber: floor,
    name: 'Sample Room',
    poisType: 'Room',
    latitude: 30.8591,
    longitude: 29.5624,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('poi_repo_test_');
    cache = PoiCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AnyplacePoiRepository', () {
    test('cache MISS: fetches POIs from API, caches to disk, returns POI list',
        () async {
      int apiCalls = 0;

      final mockClient = MockClient((request) async {
        apiCalls++;
        expect(request.url.path, ApiConfig.endpointPoisFloorAll);
        return http.Response(
          jsonEncode({
            'pois': [samplePoi.toJson()]
          }),
          200,
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplacePoiRepository(apiClient: apiClient, cache: cache);

      expect(await repo.isPoisCached(buid, floor), isFalse);

      final pois = await repo.getPoisByFloor(buid, floor);

      expect(pois.length, equals(1));
      expect(pois[0].puid, equals('poi_repo_1'));
      expect(apiCalls, equals(1));
      expect(await repo.isPoisCached(buid, floor), isTrue);
    });

    test('cache HIT: returns POI list from disk without HTTP call', () async {
      await cache.savePois(buid, floor, [samplePoi]);

      int apiCalls = 0;
      final mockClient = MockClient((request) async {
        apiCalls++;
        return http.Response('Error', 500);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplacePoiRepository(apiClient: apiClient, cache: cache);

      final pois = await repo.getPoisByFloor(buid, floor);

      expect(pois.length, equals(1));
      expect(pois[0].puid, equals('poi_repo_1'));
      expect(apiCalls, equals(0)); // 0 network calls on cache hit
    });

    test('forceReload: bypasses cache and fetches fresh POIs from API', () async {
      await cache.savePois(buid, floor, [samplePoi]);

      int apiCalls = 0;
      final mockClient = MockClient((request) async {
        apiCalls++;
        return http.Response(
          jsonEncode({
            'pois': [samplePoi.toJson()]
          }),
          200,
        );
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplacePoiRepository(apiClient: apiClient, cache: cache);

      final pois = await repo.getPoisByFloor(buid, floor, forceReload: true);

      expect(pois.length, equals(1));
      expect(apiCalls, equals(1));
    });
  });
}
