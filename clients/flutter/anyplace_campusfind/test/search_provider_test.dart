import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/floor.dart';
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
        bucode: 'G12',
        coordinatesLat: 30.8,
        coordinatesLon: 29.5,
        spaceType: 'building',
        description: 'Main Campus West | Opened 2021',
      ),
      Space(
        buid: 'building_2',
        name: 'Research Tower',
        bucode: 'T3',
        coordinatesLat: 30.81,
        coordinatesLon: 29.51,
        spaceType: 'building',
        description: 'Advanced Engineering Laboratories',
      ),
    ];
    cache.setSpaces(spaces);
    cache.setFloors('building_1', [
      Floor(
        fuid: 'building_1_0',
        buid: 'building_1',
        floorNumber: '0',
        floorName: 'Ground Floor',
        description: 'Lobby and lecture halls',
      ),
    ]);
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
        poisType: 'Cafeteria',
      ),
      Poi(
        puid: 'poi_elv',
        buid: 'building_1',
        name: 'Elevator Lobby',
        coordinatesLat: 30.8003,
        coordinatesLon: 29.5003,
        floorNumber: '0',
        poisType: 'Elevator',
      ),
    ]);
    cache.setPois('building_2', [
      Poi(
        puid: 'poi_lab',
        buid: 'building_2',
        name: 'Engineering Lab 1',
        coordinatesLat: 30.8101,
        coordinatesLon: 29.5101,
        floorNumber: '0',
        poisType: 'LAB',
        description: 'Advanced Engineering Laboratories',
      ),
    ]);

    container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);
  });

  test('search index builds buildings, floors and POIs as results', () {
    final index = container.read(searchIndexProvider);
    expect(index.all, hasLength(7));
    expect(index.all[0].isSpace, isTrue);
    expect(index.all[0].category, EntityCategory.building);
    expect(index.all.where((r) => r.isFloor), hasLength(1));
    expect(index.all.where((r) => r.isPoi), hasLength(4));
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
    // Both buildings match "engineering": one by name-prefix, one by
    // description; the name-prefix match must rank first.
    final results =
        index.query('engineering', category: EntityCategory.building);
    expect(results, hasLength(2));
    expect(results.first.name, 'Engineering Building');
  });

  test('exact building code ranks above everything else', () {
    final index = container.read(searchIndexProvider);
    final results = index.query('G12');
    expect(results.first.name, 'Engineering Building');
    expect(results.first.code, 'G12');
  });

  test('exact POI type (elevator) ranks above name matches', () {
    final index = container.read(searchIndexProvider);
    final results = index.query('elevator');
    expect(results.first.name, 'Elevator Lobby');
  });

  test('name-prefix match (engineering) ranks above description-only', () {
    // "Engineering Building" starts with "engineering";
    // "Research Tower" / "Engineering Lab 1" only match via description
    // or name-contains, so they must rank strictly lower.
    final index = container.read(searchIndexProvider);
    final results = index.query('engineering');
    expect(results.first.name, 'Engineering Building');
    final ordered = results.map((r) => r.name).toList();
    expect(ordered.indexOf('Engineering Building'),
        lessThan(ordered.indexOf('Research Tower')));
    expect(ordered.indexOf('Engineering Building'),
        lessThan(ordered.indexOf('Engineering Lab 1')));
  });

  test('description/token match finds floors and POIs', () {
    final index = container.read(searchIndexProvider);
    final results = index.query('lecture halls');
    expect(results, isNotEmpty);
    expect(results.firstWhere((r) => r.isFloor).floor?.floorNumber, '0');
  });

  test('partial POI type matches via backend pois_type', () {
    final index = container.read(searchIndexProvider);
    final results = index.query('elev');
    expect(results, isNotEmpty);
    expect(results.first.name, 'Elevator Lobby');
  });

  test('toilet search matches real backend pois_type values', () {
    cache.setPois('building_1', [
      Poi(
        puid: 'poi_wc',
        buid: 'building_1',
        name: 'WC-02',
        coordinatesLat: 30.8004,
        coordinatesLon: 29.5004,
        floorNumber: '0',
        poisType: 'Disabled Toilet',
      ),
    ]);
    final index = container.read(searchIndexProvider);
    final results = index.query('toilet');
    expect(results, isNotEmpty);
    expect(results.first.name, 'WC-02');
  });
}