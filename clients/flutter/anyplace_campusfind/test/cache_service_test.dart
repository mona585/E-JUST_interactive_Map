import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/floor.dart';
import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';

/// Test double so `getApplicationSupportDirectory` works without a device.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory temp;

  _FakePathProvider(this.temp);

  @override
  Future<String?> getApplicationSupportPath() async => temp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('cache_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
    cache = CacheService();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('selected campus id persists', () async {
    expect(await cache.getSelectedCampusId(), isNull);
    await cache.setSelectedCampusId('campus_1');
    expect(await cache.getSelectedCampusId(), 'campus_1');
    await cache.setSelectedCampusId(null);
    expect(await cache.getSelectedCampusId(), isNull);
  });

  test('floors and pois are cached by buid', () {
    expect(cache.floorsOf('b1'), isEmpty);
    expect(cache.poisOf('b1'), isEmpty);

    cache.setFloors('b1', const []);
    cache.setPois('b1', const []);
    cache.setFloors('b2', const []);
    expect(cache.floorsOf('b2'), isEmpty);
    expect(cache.hasData, isFalse);
  });

  test('recent waypoints are deduped and capped', () async {
    SharedPreferences.setMockInitialValues({
      'recent_waypoints': <String>['p1', 'p2'],
    });
    cache = CacheService();

    await cache.addRecentWaypoint('p1'); // move to front
    await cache.addRecentWaypoint('p3'); // add new

    final list = await cache.getRecentWaypoints();
    expect(list, ['p3', 'p1', 'p2']);
  });

  test('clearData resets in-memory dataset', () {
    cache.setSpaces(const []);
    cache.setFloors('b1', const []);
    cache.clearData();
    expect(cache.hasData, isFalse);
  });

  test('offline snapshot round-trips spaces, floors and pois', () async {
    cache.setSpaces(const [
      Space(
        buid: 'b1',
        name: 'Main Building',
        coordinatesLat: 30.85,
        coordinatesLon: 29.59,
        spaceType: 'building',
      ),
    ]);
    cache.setFloors('b1', const [
      Floor(
        fuid: 'b1_1',
        buid: 'b1',
        floorNumber: '1',
        floorName: 'Ground',
      ),
    ]);
    cache.setPois('b1', const [
      Poi(
        puid: 'p1',
        buid: 'b1',
        name: 'Cafeteria',
        coordinatesLat: 30.851,
        coordinatesLon: 29.591,
        floorNumber: '1',
      ),
    ]);

    await cache.saveOfflineSnapshot();

    // A fresh cache restores the dataset from the snapshot.
    final restored = CacheService();
    expect(await restored.loadOfflineSnapshot(), isTrue);
    expect(restored.hasData, isTrue);
    expect(restored.fromOfflineSnapshot, isTrue);
    expect(restored.spaces.single.name, 'Main Building');
    expect(restored.floorsOf('b1').single.floorName, 'Ground');
    expect(restored.poisOf('b1').single.name, 'Cafeteria');
  });

  test('loadOfflineSnapshot returns false when no snapshot exists', () async {
    expect(await cache.loadOfflineSnapshot(), isFalse);
  });
}
