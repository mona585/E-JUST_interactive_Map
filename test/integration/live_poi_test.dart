import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/poi_cache.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';

void main() {
  group('Live Anyplace POIs Integration Test', () {
    late AnyplaceApiClient apiClient;
    late PoiCache cache;
    late AnyplacePoiRepository repository;
    late Directory tempDir;

    // 1. Building B7 (Floor 0)
    const b7Buid = 'building_b8f4e123-d58f-45b7-9942-4492b198c9e4_1786536183663';
    const b7FloorNum = '0';

    // 2. Building Langvann (Floor 1)
    const langvannBuid = 'building_d7687dfe-d904-41b1-8378-374dbdec35e0_1504342475011';
    const langvannFloorNum = '1';

    setUp(() async {
      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);
      final ioClient = IOClient(httpClient);

      apiClient = AnyplaceApiClient(client: ioClient, baseUrl: ApiConfig.baseUrl);
      tempDir = await Directory.systemTemp.createTemp('live_poi_test_');
      cache = PoiCache(customBaseDir: tempDir);
      repository = AnyplacePoiRepository(apiClient: apiClient, cache: cache);
    });

    tearDown(() async {
      apiClient.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'B7 (Floor 0): fetches 6 live POIs (G01..G06), verifies coordinates and disk caching',
        () async {
      final stopwatch = Stopwatch()..start();

      // 1. Fetch via repository (performs live HTTP POST /api/mapping/pois/floor/all)
      final pois = await repository.getPoisByFloor(b7Buid, b7FloorNum);
      stopwatch.stop();

      expect(pois, isNotEmpty);
      expect(pois.length, equals(6));

      final poiNames = pois.map((p) => p.name).toList();
      expect(poiNames, containsAll(['G01', 'G02', 'G03', 'G04', 'G05', 'G06']));

      // Verify POI Bounding Coordinates
      for (final poi in pois) {
        expect(poi.buid, equals(b7Buid));
        expect(poi.floorNumber, equals(b7FloorNum));
        expect(poi.latitude, greaterThan(30.8580));
        expect(poi.latitude, lessThan(30.8610));
        expect(poi.longitude, greaterThan(29.5620));
        expect(poi.longitude, lessThan(29.5640));
      }

      // 2. Verify disk cache hit (< 10ms)
      final cacheStopwatch = Stopwatch()..start();
      final cachedPois = await repository.getPoisByFloor(b7Buid, b7FloorNum);
      cacheStopwatch.stop();

      expect(cachedPois.length, equals(6));
      expect(cacheStopwatch.elapsedMilliseconds, lessThan(100));

      debugPrint(
        'B7 POIs live fetch time: ${stopwatch.elapsedMilliseconds}ms, count: ${pois.length}',
      );
    });

    test(
        'Langvann (Floor 1): fetches live POIs, verifies "pipe" POI details',
        () async {
      final pois = await repository.getPoisByFloor(langvannBuid, langvannFloorNum);

      expect(pois, isNotEmpty);
      expect(pois.length, equals(1));
      expect(pois.first.name, equals('pipe'));
      expect(pois.first.poisType, equals('Other'));
      expect(pois.first.latitude, closeTo(66.3338, 0.001));
      expect(pois.first.longitude, closeTo(14.1472, 0.001));
    });
  });
}
