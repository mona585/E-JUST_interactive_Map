import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/config/constants.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/quick_access_item.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late SearchService searchService;
  late _FakeSpaceRepository fakeSpaceRepository;
  late _FakePoiRepository fakePoiRepository;
  late SpaceProvider spaceProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();
    searchService = SearchService();
    fakeSpaceRepository = _FakeSpaceRepository();
    fakePoiRepository = _FakePoiRepository();
    spaceProvider = SpaceProvider(
      repository: fakeSpaceRepository,
      poiRepository: fakePoiRepository,
      radioMapRepository: _FakeRadioMapRepository(),
      floorplanRepository: _FakeFloorplanRepository(),
      navigationRepository: _FakeNavigationRepository(),
      nativePositioningService: _FakeNativePositioningService(),
      cacheService: cache,
    );
  });

  SpaceModel space(String name, {String? buid}) => SpaceModel(
        buid: buid ?? 'buid_$name',
        name: name,
        latitude: 30.86,
        longitude: 29.56,
        spaceType: 'building',
      );

  /// Builds a SpaceModel for a verified E-JUST default using its real buid.
  SpaceModel spaceFor(DefaultQuickAccessLocation loc) =>
      space(loc.name, buid: loc.buid);

  PoiModel poi(String puid, String name, {String buid = 'b', String floor = '0'}) =>
      PoiModel(
        puid: puid,
        buid: buid,
        floorNumber: floor,
        name: name,
        poisType: 'room',
        latitude: 30.86,
        longitude: 29.56,
      );

  group('First-run seeding', () {
    test('seeds the six verified E-JUST defaults by buid, in defined order', () async {
      final defaults = AppConstants.kDefaultQuickAccessLocations;
      fakeSpaceRepository.spaces = [
        // An unrelated, similarly named building that must NOT be chosen.
        space('Library of Science', buid: 'building_unrelated_library'),
        space('Missourian Newspaper Library', buid: 'building_unrelated_newspaper'),
        space('Food court (Downtown)', buid: 'building_unrelated_food'),
        ...defaults.map(spaceFor),
      ];
      await spaceProvider.loadSpaces();
      searchService.addSpaces(spaceProvider.spaces);

      await spaceProvider.ensureQuickAccessInitialized(searchService);

      final items = await cache.getQuickAccessItems();
      // Exactly the six verified E-JUST defaults, in defined order.
      expect(items.length, defaults.length);
      expect(items.map((i) => i.name).toList(), defaults.map((d) => d.name).toList());
      expect(items.map((i) => i.id).toList(), defaults.map((d) => d.buid).toList());
      expect(items.every((i) => i.isBuilding), true);
      expect(items.every((i) => i.id.isNotEmpty), true);
    });

    test('reports and skips defaults whose buid is not in the loaded dataset', () async {
      fakeSpaceRepository.spaces = [
        // Only one of the six verified E-JUST entities is loaded.
        spaceFor(AppConstants.kDefaultQuickAccessLocations[0]),
      ];
      await spaceProvider.loadSpaces();
      searchService.addSpaces(spaceProvider.spaces);

      final report =
          await spaceProvider.ensureQuickAccessInitialized(searchService);

      final items = await cache.getQuickAccessItems();
      // Only the loaded entity is seeded; nothing is substituted.
      expect(items.length, 1);
      expect(items.first.id, AppConstants.kDefaultQuickAccessLocations[0].buid);

      // The five unloaded defaults are reported unresolved, never substituted.
      final unresolved = report.where((r) => !r.isResolved).toList();
      expect(unresolved.length, AppConstants.kDefaultQuickAccessLocations.length - 1);
      expect(
        unresolved.every((r) => r.requested.buid != AppConstants.kDefaultQuickAccessLocations[0].buid),
        true,
      );
    });

    test('does not re-seed when the key already exists', () async {
      fakeSpaceRepository.spaces = [spaceFor(AppConstants.kDefaultQuickAccessLocations[0])];
      await spaceProvider.loadSpaces();
      searchService.addSpaces(spaceProvider.spaces);

      await spaceProvider.ensureQuickAccessInitialized(searchService);
      final first = await cache.getQuickAccessItems();

      // User customizes (removes everything) → valid empty state.
      await cache.clearQuickAccessItems();

      // Second launch: ensureQuickAccessInitialized must not re-seed.
      await spaceProvider.ensureQuickAccessInitialized(searchService);
      final after = await cache.getQuickAccessItems();

      expect(first.length, 1);
      expect(after, isEmpty);
    });
  });

  group('Migration from legacy saved_pois', () {
    test('migrates resolvable and unresolvable saved POIs one-time', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefSavedPois: ['poi_resolvable', 'poi_unknown'],
      });

      final resolvable = poi('poi_resolvable', 'Meeting Room');
      searchService.addPois('b', '0', [resolvable]);

      await spaceProvider.ensureQuickAccessInitialized(searchService);

      final items = await cache.getQuickAccessItems();
      final poiItems = items.where((i) => i.isPoi).toList();
      expect(poiItems.length, 2);

      final resolved =
          poiItems.firstWhere((i) => i.id == 'poi_resolvable');
      expect(resolved.name, 'Meeting Room');
      expect(resolved.buid, 'b');
      expect(resolved.floorNumber, '0');

      // Unresolvable items are preserved (not discarded).
      final minimal = poiItems.firstWhere((i) => i.id == 'poi_unknown');
      expect(minimal.hasPoiNavigationIds, false);

      // Legacy key consumed after migration.
      expect(await cache.getSavedPois(), isEmpty);

      // Idempotent: second call does nothing.
      await spaceProvider.ensureQuickAccessInitialized(searchService);
      expect((await cache.getQuickAccessItems()).length, items.length);
    });
  });

  group('Add/remove behavior', () {
    test('toggle adds a building and persists after restart', () async {
      final building = QuickAccessItem.fromSpace(
        space('Cafeteria'),
        addedAt: 1,
        category: 'building',
      );
      await cache.toggleQuickAccessItem(building);
      expect(await cache.isQuickAccessItem('building', building.id), true);

      // Simulate restart: new CacheService over same prefs.
      final restarted = CacheService();
      final items = await restarted.getQuickAccessItems();
      expect(items.length, 1);
      expect(items.first.name, 'Cafeteria');
    });

    test('toggle adds a POI with navigation ids and persists after restart', () async {
      final p = poi('poi_1', 'Office 2', buid: 'b1', floor: '2');
      final item = QuickAccessItem.fromPoi(p, addedAt: 1, category: 'office');
      await cache.toggleQuickAccessItem(item);
      expect(await cache.isQuickAccessItem('poi', 'poi_1'), true);

      final restarted = CacheService();
      final items = await restarted.getQuickAccessItems();
      expect(items.length, 1);
      expect(items.first.buid, 'b1');
      expect(items.first.floorNumber, '2');
    });

    test('duplicate type+id cannot be inserted twice', () async {
      final a = QuickAccessItem.fromSpace(
        space('Cafeteria'),
        addedAt: 1,
        category: 'building',
      );
      final b = QuickAccessItem.fromSpace(
        space('Cafeteria'),
        addedAt: 2,
        category: 'building',
      );
      await cache.toggleQuickAccessItem(a);
      await cache.toggleQuickAccessItem(b);
      // Second toggle of same key removes it → zero entries.
      expect(await cache.getQuickAccessItems(), isEmpty);

      await cache.toggleQuickAccessItem(a);
      await cache.toggleQuickAccessItem(a);
      expect(await cache.getQuickAccessItems(), isEmpty);
    });

    test('toggle removes an existing item', () async {
      final building = QuickAccessItem.fromSpace(
        space('Cafeteria'),
        addedAt: 1,
        category: 'building',
      );
      await cache.toggleQuickAccessItem(building);
      expect((await cache.getQuickAccessItems()).length, 1);

      await cache.toggleQuickAccessItem(building);
      expect((await cache.getQuickAccessItems()).length, 0);
    });

    test('clearing quick access leaves an empty persistent list (no re-seed)',
        () async {
      final building = QuickAccessItem.fromSpace(
        space('Cafeteria'),
        addedAt: 1,
        category: 'building',
      );
      await cache.toggleQuickAccessItem(building);
      await cache.clearQuickAccessItems();

      final restarted = CacheService();
      expect(await restarted.getQuickAccessItems(), isEmpty);
      // The key exists, so seeding is permanently disabled.
      expect(await restarted.hasQuickAccessKey(), true);
    });
  });

  group('Ordering', () {
    test('predefined items come first in defined order, user items appended',
        () async {
      final defaults = AppConstants.kDefaultQuickAccessLocations;
      // Load two of the six verified E-JUST defaults (Food Court, Blue Hall
      // Cafeteria) so seeding resolves them by their real buids.
      fakeSpaceRepository.spaces = [
        spaceFor(defaults[1]),
        spaceFor(defaults[4]),
      ];
      await spaceProvider.loadSpaces();
      searchService.addSpaces(spaceProvider.spaces);
      await spaceProvider.ensureQuickAccessInitialized(searchService);

      await cache.toggleQuickAccessItem(QuickAccessItem.fromSpace(
        space('Gym'),
        addedAt: 999,
        category: 'building',
      ));

      final names = (await cache.getQuickAccessItems()).map((i) => i.name).toList();
      // Seeded defaults first (defined order), then the user-added building.
      expect(names.indexOf(defaults[1].name), lessThan(names.indexOf('Gym')));
      expect(names.indexOf(defaults[4].name), lessThan(names.indexOf('Gym')));
      expect(names.indexOf(defaults[1].name), lessThan(names.indexOf(defaults[4].name)));
    });
  });

  group('Cross-building POI navigation', () {
    test('opens a saved POI even when another building/floor is selected',
        () async {
      fakeSpaceRepository.spaces = [
        space('Building A', buid: 'bA'),
        space('Building B', buid: 'bB'),
      ];
      fakeSpaceRepository.floors = {
        'bA': [FloorModel(buid: 'bA', floorNumber: '0')],
        'bB': [FloorModel(buid: 'bB', floorNumber: '3')],
      };
      fakePoiRepository.pois = {
        'bA_0': [poi('pa1', 'A Room', buid: 'bA', floor: '0')],
        'bB_3': [poi('pb1', 'B Room', buid: 'bB', floor: '3')],
      };

      await spaceProvider.loadSpaces();
      // Select Building A floor 0 first.
      spaceProvider.selectSpace(fakeSpaceRepository.spaces[0]);
      await spaceProvider.loadFloorsForSelectedSpace();
      spaceProvider.selectFloor(spaceProvider.floors.first);
      await spaceProvider.loadPoisForSelectedFloor();

      // Quick Access item points to Building B floor 3 POI (not loaded).
      final item = QuickAccessItem.fromPoi(
        poi('pb1', 'B Room', buid: 'bB', floor: '3'),
        addedAt: 1,
        category: 'room',
      );

      final ok = await spaceProvider.navigateToQuickAccessItem(item);
      expect(ok, true);
      expect(spaceProvider.selectedSpace?.buid, 'bB');
      expect(spaceProvider.selectedFloor?.floorNumber, '3');
      expect(spaceProvider.selectedPoi?.puid, 'pb1');
    });

    test('renders an item even when its entity is not loaded', () async {
      // Store a POI item that has no corresponding entry in the loaded POIs.
      final item = QuickAccessItem.fromPoi(
        poi('offline_poi', 'Offline Room', buid: 'unloaded_b', floor: '9'),
        addedAt: 1,
        category: 'room',
      );
      await cache.toggleQuickAccessItem(item);

      final items = await cache.getQuickAccessItems();
      expect(items.length, 1);
      // Snapshot data renders without resolving the underlying POI.
      expect(items.first.name, 'Offline Room');
      expect(items.first.category, 'room');
    });
  });
}

class _FakeSpaceRepository implements SpaceRepository {
  List<SpaceModel> spaces = const [];
  Map<String, List<FloorModel>> floors = const {};

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.where((s) => s.buid == buid).firstOrNull;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      floors[buid] ?? const [];
}

class _FakePoiRepository implements PoiRepository {
  Map<String, List<PoiModel>> pois = const {};

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      pois['${buid}_$floor'] ?? const [];

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      '';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class _FakeFloorplanRepository implements FloorplanRepository {
  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async =>
      null;

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;

  @override
  Future<void> clearFloorplan(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeNavigationRepository implements NavigationRepository {
  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) =>
      throw UnimplementedError();

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) =>
      throw UnimplementedError();
}

class _FakeNativePositioningService implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async =>
      true;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();
}
