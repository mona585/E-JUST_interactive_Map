import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/floorplan_cache.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';

void main() {
  late Directory tempDir;
  late FloorplanCache cache;

  const buidA = 'buid_alpha';
  const buidB = 'buid_beta';
  const floor0 = '0';
  const floor1 = '1';

  final sampleFloorA0 = const FloorModel(
    buid: buidA,
    floorNumber: '0',
    floorName: 'Ground',
    bottomLeftLat: 30.8591,
    bottomLeftLng: 29.5624,
    topRightLat: 30.8601,
    topRightLng: 29.5636,
  );

  final sampleFloorA1 = const FloorModel(
    buid: buidA,
    floorNumber: '1',
    floorName: 'Level 1',
    bottomLeftLat: 30.8591,
    bottomLeftLng: 29.5624,
    topRightLat: 30.8601,
    topRightLng: 29.5636,
  );

  final sampleFloorB0 = const FloorModel(
    buid: buidB,
    floorNumber: '0',
    floorName: 'Ground',
    bottomLeftLat: 66.3337,
    bottomLeftLng: 14.1471,
    topRightLat: 66.3339,
    topRightLng: 14.1475,
  );

  final samplePngA0 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03]);
  final samplePngA1 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x04, 0x05, 0x06]);
  final samplePngB0 = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x07, 0x08, 0x09]);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('floorplan_cache_test_');
    cache = FloorplanCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FloorplanCache', () {
    test('returns null and hasFloorplan is false on cache miss', () async {
      expect(await cache.hasFloorplan(buidA, floor0), isFalse);
      final model = await cache.getFloorplan(buidA, floor0, sampleFloorA0);
      expect(model, isNull);
    });

    test('saveFloorplan writes PNG bytes and metadata, getFloorplan returns cached model',
        () async {
      final model = await cache.saveFloorplan(
        buidA,
        floor0,
        samplePngA0,
        sampleFloorA0,
      );

      expect(model.buid, buidA);
      expect(model.floorNumber, floor0);
      expect(model.isCached, isTrue);
      expect(model.imageSizeBytes, equals(samplePngA0.length));
      expect(model.bottomLeftLat, equals(sampleFloorA0.bottomLeftLat));
      expect(model.bottomLeftLng, equals(sampleFloorA0.bottomLeftLng));
      expect(model.topRightLat, equals(sampleFloorA0.topRightLat));
      expect(model.topRightLng, equals(sampleFloorA0.topRightLng));

      // Verify file exists on disk with exact bytes
      final file = File(model.imagePath);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), equals(samplePngA0));

      // Verify subsequent getFloorplan reads from disk cache
      expect(await cache.hasFloorplan(buidA, floor0), isTrue);
      final cachedModel = await cache.getFloorplan(buidA, floor0, sampleFloorA0);
      expect(cachedModel, isNotNull);
      expect(cachedModel!.isCached, isTrue);
      expect(cachedModel.imageSizeBytes, equals(samplePngA0.length));
      expect(cachedModel.bottomLeftLat, equals(sampleFloorA0.bottomLeftLat));
    });

    test('maintains strict cache isolation between buildings and floors',
        () async {
      await cache.saveFloorplan(buidA, floor0, samplePngA0, sampleFloorA0);
      await cache.saveFloorplan(buidA, floor1, samplePngA1, sampleFloorA1);
      await cache.saveFloorplan(buidB, floor0, samplePngB0, sampleFloorB0);

      final modelA0 = await cache.getFloorplan(buidA, floor0, sampleFloorA0);
      final modelA1 = await cache.getFloorplan(buidA, floor1, sampleFloorA1);
      final modelB0 = await cache.getFloorplan(buidB, floor0, sampleFloorB0);
      final modelB1 = await cache.getFloorplan(buidB, floor1, sampleFloorB0);

      expect(modelA0?.imageSizeBytes, equals(samplePngA0.length));
      expect(modelA1?.imageSizeBytes, equals(samplePngA1.length));
      expect(modelB0?.imageSizeBytes, equals(samplePngB0.length));
      expect(modelB1, isNull);
    });

    test('clearFloorplan removes only specified floor cache', () async {
      await cache.saveFloorplan(buidA, floor0, samplePngA0, sampleFloorA0);
      await cache.saveFloorplan(buidA, floor1, samplePngA1, sampleFloorA1);

      await cache.clearFloorplan(buidA, floor0);

      expect(await cache.hasFloorplan(buidA, floor0), isFalse);
      expect(await cache.hasFloorplan(buidA, floor1), isTrue);
    });

    test('clearAll removes entire floorplans directory', () async {
      await cache.saveFloorplan(buidA, floor0, samplePngA0, sampleFloorA0);
      await cache.saveFloorplan(buidB, floor0, samplePngB0, sampleFloorB0);

      await cache.clearAll();

      expect(await cache.hasFloorplan(buidA, floor0), isFalse);
      expect(await cache.hasFloorplan(buidB, floor0), isFalse);
    });
  });
}
