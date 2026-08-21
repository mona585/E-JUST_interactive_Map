import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/radiomap_cache.dart';

void main() {
  late Directory tempDir;
  late RadioMapCache cache;

  const buidA = 'buid_alpha';
  const buidB = 'buid_beta';
  const floor1 = '1';
  const floor2 = '2';
  const sampleMapA1 = '# NaN -110\n# X, Y, HEADING, macA\n1.0, 2.0, 0, -80\n';
  const sampleMapA2 = '# NaN -110\n# X, Y, HEADING, macA\n3.0, 4.0, 0, -75\n';
  const sampleMapB1 = '# NaN -110\n# X, Y, HEADING, macB\n5.0, 6.0, 0, -70\n';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('radiomap_cache_test_');
    cache = RadioMapCache(customBaseDir: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('RadioMapCache', () {
    test('returns null on cache miss', () async {
      final result = await cache.getRadioMap(buidA, floor1);
      expect(result, isNull);
      expect(await cache.hasRadioMap(buidA, floor1), isFalse);
    });

    test('saves and retrieves cached radiomap content', () async {
      await cache.saveRadioMap(buidA, floor1, sampleMapA1);

      expect(await cache.hasRadioMap(buidA, floor1), isTrue);
      final loaded = await cache.getRadioMap(buidA, floor1);
      expect(loaded, equals(sampleMapA1));
    });

    test('maintains strict isolation between buildings and floors', () async {
      await cache.saveRadioMap(buidA, floor1, sampleMapA1);
      await cache.saveRadioMap(buidA, floor2, sampleMapA2);
      await cache.saveRadioMap(buidB, floor1, sampleMapB1);

      expect(await cache.getRadioMap(buidA, floor1), equals(sampleMapA1));
      expect(await cache.getRadioMap(buidA, floor2), equals(sampleMapA2));
      expect(await cache.getRadioMap(buidB, floor1), equals(sampleMapB1));
      expect(await cache.getRadioMap(buidB, floor2), isNull);
    });

    test('clears specific floor cache without affecting other floors',
        () async {
      await cache.saveRadioMap(buidA, floor1, sampleMapA1);
      await cache.saveRadioMap(buidA, floor2, sampleMapA2);

      await cache.clearRadioMap(buidA, floor1);

      expect(await cache.hasRadioMap(buidA, floor1), isFalse);
      expect(await cache.getRadioMap(buidA, floor1), isNull);
      expect(await cache.hasRadioMap(buidA, floor2), isTrue);
      expect(await cache.getRadioMap(buidA, floor2), equals(sampleMapA2));
    });

    test('clearAll removes entire radiomaps cache directory', () async {
      await cache.saveRadioMap(buidA, floor1, sampleMapA1);
      await cache.saveRadioMap(buidB, floor1, sampleMapB1);

      await cache.clearAll();

      expect(await cache.hasRadioMap(buidA, floor1), isFalse);
      expect(await cache.hasRadioMap(buidB, floor1), isFalse);
    });

    test('loads and parses real radiomap fixture file', () async {
      final fixtureFile = File('test/fixtures/indoor-radiomap-mean-sample.txt');
      expect(await fixtureFile.exists(), isTrue);

      final fixtureContent = await fixtureFile.readAsString();
      await cache.saveRadioMap(buidA, floor1, fixtureContent);

      final cachedContent = await cache.getRadioMap(buidA, floor1);
      expect(cachedContent, equals(fixtureContent));
      expect(cachedContent, contains('84:c9:b2:6a:bd:ba'));
      expect(cachedContent, contains('66.33389809983995'));
    });
  });
}
