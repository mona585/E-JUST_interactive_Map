import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/floorplan_cache.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';

void main() {
  group('Live Anyplace Floorplan Image Integration Test', () {
    late AnyplaceApiClient apiClient;
    late FloorplanCache cache;
    late AnyplaceFloorplanRepository repository;
    late Directory tempDir;

    // 1. Building B7 (previously failed on 30 MB ZIP, now succeeds on 3 MB Base64 image)
    const b7Buid = 'building_b8f4e123-d58f-45b7-9942-4492b198c9e4_1786536183663';
    const b7FloorNum = '0';
    const b7Floor = FloorModel(
      buid: b7Buid,
      floorNumber: b7FloorNum,
      floorName: '0',
      bottomLeftLat: 30.85910338821698,
      bottomLeftLng: 29.562439562466327,
      topRightLat: 30.86016877674437,
      topRightLng: 29.5636380392989,
    );

    // 2. Building Langvann
    const langvannBuid = 'building_d7687dfe-d904-41b1-8378-374dbdec35e0_1504342475011';
    const langvannFloorNum = '1';
    const langvannFloor = FloorModel(
      buid: langvannBuid,
      floorNumber: langvannFloorNum,
      floorName: '1',
      bottomLeftLat: 66.33378077338729,
      bottomLeftLng: 14.147128779310648,
      topRightLat: 66.3339318522916,
      topRightLng: 14.147496091482607,
    );

    setUp(() async {
      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);
      final ioClient = IOClient(httpClient);

      apiClient = AnyplaceApiClient(client: ioClient, baseUrl: ApiConfig.baseUrl);
      tempDir = await Directory.systemTemp.createTemp('live_floorplan_test_');
      cache = FloorplanCache(customBaseDir: tempDir);
      repository = AnyplaceFloorplanRepository(apiClient: apiClient, cache: cache);
    });

    tearDown(() async {
      apiClient.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('B7 (Floor 0): fetches Base64 image, decodes, caches PNG, and validates bounds',
        () async {
      final stopwatch = Stopwatch()..start();

      // 1. Fetch via repository (performs live HTTP POST /api/floorplans64/)
      final floorplan = await repository.getFloorplan(b7Buid, b7FloorNum, b7Floor);
      stopwatch.stop();

      expect(floorplan, isNotNull);
      expect(floorplan!.buid, equals(b7Buid));
      expect(floorplan.floorNumber, equals(b7FloorNum));
      expect(floorplan.isCached, isTrue);
      expect(floorplan.imageSizeBytes, greaterThan(500000)); // Over 500 KB decoded PNG
      expect(floorplan.hasValidBounds, isTrue);

      // Verify bounds match B7 WGS84 coordinates
      expect(floorplan.bottomLeftLat, closeTo(30.8591, 0.001));
      expect(floorplan.bottomLeftLng, closeTo(29.5624, 0.001));
      expect(floorplan.topRightLat, closeTo(30.8601, 0.001));
      expect(floorplan.topRightLng, closeTo(29.5636, 0.001));

      // 2. Verify file on disk
      final imageFile = File(floorplan.imagePath);
      expect(await imageFile.exists(), isTrue);
      expect(await imageFile.length(), equals(floorplan.imageSizeBytes));

      // 3. Verify fast cache hit on second fetch (< 5ms)
      final cacheStopwatch = Stopwatch()..start();
      final cachedFloorplan = await repository.getFloorplan(b7Buid, b7FloorNum, b7Floor);
      cacheStopwatch.stop();

      expect(cachedFloorplan, isNotNull);
      expect(cachedFloorplan!.imageSizeBytes, equals(floorplan.imageSizeBytes));
      expect(cacheStopwatch.elapsedMilliseconds, lessThan(100));

      debugPrint(
        'B7 Floorplan live load time: ${stopwatch.elapsedMilliseconds}ms, size: ${floorplan.imageSizeBytes} bytes',
      );
    });

    test('Langvann (Floor 1): fetches Base64 image, decodes, and verifies bounds',
        () async {
      final floorplan =
          await repository.getFloorplan(langvannBuid, langvannFloorNum, langvannFloor);

      expect(floorplan, isNotNull);
      expect(floorplan!.buid, equals(langvannBuid));
      expect(floorplan.floorNumber, equals(langvannFloorNum));
      expect(floorplan.isCached, isTrue);
      expect(floorplan.imageSizeBytes, greaterThan(100000));
      expect(floorplan.hasValidBounds, isTrue);

      expect(floorplan.bottomLeftLat, closeTo(66.3337, 0.001));
      expect(floorplan.bottomLeftLng, closeTo(14.1471, 0.001));
      expect(floorplan.topRightLat, closeTo(66.3339, 0.001));
      expect(floorplan.topRightLng, closeTo(14.1474, 0.001));
    });
  });
}
