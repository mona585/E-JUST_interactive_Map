import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/floorplan_cache.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';

void main() {
  late Directory tempDir;
  late FloorplanCache cache;

  const buid = 'building_123';
  const floor = '0';
  final sampleFloor = const FloorModel(
    buid: buid,
    floorNumber: floor,
    floorName: 'Ground',
    bottomLeftLat: 30.8591,
    bottomLeftLng: 29.5624,
    topRightLat: 30.8601,
    topRightLng: 29.5636,
  );

  final samplePng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02]);
  final sampleBase64 = base64Encode(samplePng);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('floorplan_repo_test_');
    cache = FloorplanCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AnyplaceFloorplanRepository', () {
    test(
        'cache MISS: fetches Base64 from API, decodes to cache, returns FloorplanModel',
        () async {
      int apiCalls = 0;

      final mockClient = MockClient((request) async {
        apiCalls++;
        expect(
          request.url.path,
          '${ApiConfig.endpointFloorplans64}/$buid/$floor',
        );
        return http.Response(sampleBase64, 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplaceFloorplanRepository(
        apiClient: apiClient,
        cache: cache,
      );

      expect(await repo.isFloorplanCached(buid, floor), isFalse);

      final model = await repo.getFloorplan(buid, floor, sampleFloor);

      expect(model, isNotNull);
      expect(model!.buid, buid);
      expect(model.floorNumber, floor);
      expect(model.imageSizeBytes, equals(samplePng.length));
      expect(apiCalls, equals(1));
      expect(await repo.isFloorplanCached(buid, floor), isTrue);
    });

    test(
        'cache HIT: returns FloorplanModel without making HTTP call',
        () async {
      await cache.saveFloorplan(buid, floor, samplePng, sampleFloor);

      int apiCalls = 0;
      final mockClient = MockClient((request) async {
        apiCalls++;
        return http.Response('Error', 500);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplaceFloorplanRepository(
        apiClient: apiClient,
        cache: cache,
      );

      final model = await repo.getFloorplan(buid, floor, sampleFloor);

      expect(model, isNotNull);
      expect(model!.imageSizeBytes, equals(samplePng.length));
      expect(apiCalls, equals(0)); // 0 network calls on cache hit
    });

    test('forceReload: bypasses cache and re-downloads from API', () async {
      await cache.saveFloorplan(buid, floor, samplePng, sampleFloor);

      int apiCalls = 0;
      final mockClient = MockClient((request) async {
        apiCalls++;
        return http.Response(sampleBase64, 200);
      });

      final apiClient = AnyplaceApiClient(client: mockClient);
      final repo = AnyplaceFloorplanRepository(
        apiClient: apiClient,
        cache: cache,
      );

      final model = await repo.getFloorplan(
        buid,
        floor,
        sampleFloor,
        forceReload: true,
      );

      expect(model, isNotNull);
      expect(apiCalls, equals(1));
    });
  });
}
