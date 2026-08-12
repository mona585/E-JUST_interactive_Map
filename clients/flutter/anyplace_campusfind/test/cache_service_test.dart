import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();
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
}
