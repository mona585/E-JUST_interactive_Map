import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/poi_cache.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';

void main() {
  late Directory tempDir;
  late PoiCache cache;

  const buidA = 'buid_alpha';
  const buidB = 'buid_beta';
  const floor0 = '0';
  const floor1 = '1';

  const poiA0 = PoiModel(
    puid: 'poi_a0',
    buid: buidA,
    floorNumber: floor0,
    name: 'Room A0',
    poisType: 'Room',
    latitude: 30.8591,
    longitude: 29.5624,
  );

  const poiA1 = PoiModel(
    puid: 'poi_a1',
    buid: buidA,
    floorNumber: floor1,
    name: 'Room A1',
    poisType: 'Office',
    latitude: 30.8595,
    longitude: 29.5628,
  );

  const poiB0 = PoiModel(
    puid: 'poi_b0',
    buid: buidB,
    floorNumber: floor0,
    name: 'Elevator B',
    poisType: 'Elevator',
    latitude: 66.3338,
    longitude: 14.1472,
  );

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('poi_cache_test_');
    cache = PoiCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PoiCache', () {
    test('returns null and hasPois is false on cache miss', () async {
      expect(await cache.hasPois(buidA, floor0), isFalse);
      expect(await cache.getPois(buidA, floor0), isNull);
    });

    test('savePois writes JSON to disk, getPois restores list correctly',
        () async {
      await cache.savePois(buidA, floor0, [poiA0]);

      expect(await cache.hasPois(buidA, floor0), isTrue);
      final cachedPois = await cache.getPois(buidA, floor0);

      expect(cachedPois, isNotNull);
      expect(cachedPois!.length, equals(1));
      expect(cachedPois[0].puid, equals('poi_a0'));
      expect(cachedPois[0].name, equals('Room A0'));
      expect(cachedPois[0].latitude, equals(30.8591));
    });

    test('maintains strict cache isolation between buildings and floors',
        () async {
      await cache.savePois(buidA, floor0, [poiA0]);
      await cache.savePois(buidA, floor1, [poiA1]);
      await cache.savePois(buidB, floor0, [poiB0]);

      final cachedA0 = await cache.getPois(buidA, floor0);
      final cachedA1 = await cache.getPois(buidA, floor1);
      final cachedB0 = await cache.getPois(buidB, floor0);
      final cachedB1 = await cache.getPois(buidB, floor1);

      expect(cachedA0?.first.puid, 'poi_a0');
      expect(cachedA1?.first.puid, 'poi_a1');
      expect(cachedB0?.first.puid, 'poi_b0');
      expect(cachedB1, isNull);
    });

    test('clearPois removes only specified floor cache', () async {
      await cache.savePois(buidA, floor0, [poiA0]);
      await cache.savePois(buidA, floor1, [poiA1]);

      await cache.clearPois(buidA, floor0);

      expect(await cache.hasPois(buidA, floor0), isFalse);
      expect(await cache.hasPois(buidA, floor1), isTrue);
    });

    test('clearAll removes entire POI cache directory', () async {
      await cache.savePois(buidA, floor0, [poiA0]);
      await cache.savePois(buidB, floor0, [poiB0]);

      await cache.clearAll();

      expect(await cache.hasPois(buidA, floor0), isFalse);
      expect(await cache.hasPois(buidB, floor0), isFalse);
    });
  });
}
