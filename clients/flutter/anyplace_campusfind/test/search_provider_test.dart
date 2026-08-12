import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/providers/search_provider.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/utils/category_deriver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();

    final spaces = [
      Space(
        buid: 'building_1',
        name: 'Engineering Building',
        coordinatesLat: 30.8,
        coordinatesLon: 29.5,
        spaceType: 'building',
      ),
    ];
    cache.setSpaces(spaces);
    cache.setPois('building_1', [
      Poi(
        puid: 'poi_prof',
        buid: 'building_1',
        name: 'Dr. Ahmed',
        coordinatesLat: 30.8001,
        coordinatesLon: 29.5001,
        floorNumber: '0',
        description: 'Associate Professor | ECE Dept',
      ),
      Poi(
        puid: 'poi_cafe',
        buid: 'building_1',
        name: 'Main Cafeteria',
        coordinatesLat: 30.8002,
        coordinatesLon: 29.5002,
        floorNumber: '0',
      ),
    ]);

    container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);
  });

  test('search index builds buildings and POIs as results', () {
    final index = container.read(searchIndexProvider);
    expect(index.all, hasLength(3));
    expect(index.all[0].isSpace, isTrue);
    expect(index.all[0].category, EntityCategory.building);
  });

  test('search query filters by name', () {
    final index = container.read(searchIndexProvider);
    final results = index.query('cafeteria');
    expect(results, hasLength(1));
    expect(results.single.name, 'Main Cafeteria');
  });

  test('search query filters by category', () {
    final index = container.read(searchIndexProvider);
    final professors = index.query('', category: EntityCategory.professor);
    expect(professors, hasLength(1));
    expect(professors.single.name, 'Dr. Ahmed');
  });

  test('search query combines query and category', () {
    final index = container.read(searchIndexProvider);
    expect(index.query('building', category: EntityCategory.professor), isEmpty);
    expect(
      index.query('engineering', category: EntityCategory.building),
      hasLength(1),
    );
  });
}
