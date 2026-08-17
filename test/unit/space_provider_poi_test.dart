import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

class MockSpaceRepo implements SpaceRepository {
  final List<SpaceModel> spaces;
  final Map<String, List<FloorModel>> floors;

  MockSpaceRepo({required this.spaces, required this.floors});

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.cast<SpaceModel?>().firstWhere(
            (s) => s?.buid == buid,
            orElse: () => null,
          );

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      floors[buid] ?? [];
}

class MockRadioRepo implements RadioMapRepository {
  @override
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      '# NaN -110\n1.0, 2.0, 0, -80\n';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => true;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class MockFloorplanRepo implements FloorplanRepository {
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

class MockPoiRepo implements PoiRepository {
  final Map<String, List<PoiModel>> pois;
  final Duration delay;
  final Map<String, Duration> customDelays;

  MockPoiRepo({
    required this.pois,
    this.delay = Duration.zero,
    this.customDelays = const {},
  });

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async {
    final key = '$buid/$floor';
    final reqDelay = customDelays[key] ?? delay;
    if (reqDelay > Duration.zero) {
      await Future<void>.delayed(reqDelay);
    }
    return pois[key] ?? [];
  }

  @override
  Future<bool> isPoisCached(String buid, String floor) async =>
      pois.containsKey('$buid/$floor');

  @override
  Future<void> clearPois(String buid, String floor) async {
    pois.remove('$buid/$floor');
  }

  @override
  Future<void> clearAll() async {
    pois.clear();
  }
}

class MockNativePosService implements NativePositioningService {
  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async =>
      true;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

void main() {
  const buildingA = SpaceModel(
    buid: 'buid_A',
    name: 'Building A',
    latitude: 35.14,
    longitude: 33.41,
  );
  const buildingB = SpaceModel(
    buid: 'buid_B',
    name: 'Building B',
    latitude: 35.15,
    longitude: 33.42,
  );

  const floorA1 = FloorModel(
    buid: 'buid_A',
    floorNumber: '1',
    floorName: 'Floor 1',
    bottomLeftLat: 35.140,
    bottomLeftLng: 33.410,
    topRightLat: 35.145,
    topRightLng: 33.415,
  );
  const floorA2 = FloorModel(
    buid: 'buid_A',
    floorNumber: '2',
    floorName: 'Floor 2',
    bottomLeftLat: 35.140,
    bottomLeftLng: 33.410,
    topRightLat: 35.145,
    topRightLng: 33.415,
  );
  const floorB1 = FloorModel(
    buid: 'buid_B',
    floorNumber: '1',
    floorName: 'Floor 1',
    bottomLeftLat: 35.150,
    bottomLeftLng: 33.420,
    topRightLat: 35.155,
    topRightLng: 33.425,
  );

  const poiA1 = PoiModel(
    puid: 'poi_A1',
    buid: 'buid_A',
    floorNumber: '1',
    name: 'G01 Room',
    poisType: 'Room',
    latitude: 35.141,
    longitude: 33.411,
  );

  const poiA2 = PoiModel(
    puid: 'poi_A2',
    buid: 'buid_A',
    floorNumber: '2',
    name: 'Office 201',
    poisType: 'Office',
    latitude: 35.142,
    longitude: 33.412,
  );

  const poiB1 = PoiModel(
    puid: 'poi_B1',
    buid: 'buid_B',
    floorNumber: '1',
    name: 'Main Entrance',
    poisType: 'Entrance',
    latitude: 35.151,
    longitude: 33.421,
  );

  late MockSpaceRepo spaceRepo;
  late MockRadioRepo radioRepo;
  late MockFloorplanRepo floorplanRepo;
  late MockPoiRepo poiRepo;
  late MockNativePosService nativePosService;
  late SpaceProvider provider;

  setUp(() {
    spaceRepo = MockSpaceRepo(
      spaces: [buildingA, buildingB],
      floors: {
        'buid_A': [floorA1, floorA2],
        'buid_B': [floorB1],
      },
    );
    radioRepo = MockRadioRepo();
    floorplanRepo = MockFloorplanRepo();
    poiRepo = MockPoiRepo(pois: {
      'buid_A/1': [poiA1],
      'buid_A/2': [poiA2],
      'buid_B/1': [poiB1],
    });
    nativePosService = MockNativePosService();

    provider = SpaceProvider(
      repository: spaceRepo,
      radioMapRepository: radioRepo,
      floorplanRepository: floorplanRepo,
      poiRepository: poiRepo,
      nativePositioningService: nativePosService,
    );
  });

  group('SpaceProvider POI Integration', () {
    test('Floor selection triggers POI acquisition and sets ready state',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasPois, isTrue);
      expect(provider.poiStatus, PoiStatus.ready);
      expect(provider.pois.length, equals(1));
      expect(provider.pois.first.name, equals('G01 Room'));
    });

    test('Switching floors (A/1 -> A/2) replaces POIs', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.pois.first.puid, 'poi_A1');

      provider.selectFloor(floorA2);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasPois, isTrue);
      expect(provider.pois.first.puid, 'poi_A2');
      expect(provider.pois.first.name, 'Office 201');
    });

    test('Switching buildings (A/1 -> B/1) clears old POIs and loads new POIs',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasPois, isTrue);

      // Select Building B
      provider.selectSpace(buildingB);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasPois, isFalse);
      expect(provider.poiStatus, PoiStatus.idle);

      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorB1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasPois, isTrue);
      expect(provider.pois.first.puid, 'poi_B1');
    });

    test('Clearing selection resets POIs and selected POI', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasPois, isTrue);

      provider.selectPoi(poiA1);
      expect(provider.selectedPoi, equals(poiA1));

      provider.clearSelection();

      expect(provider.selectedSpace, isNull);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasPois, isFalse);
      expect(provider.selectedPoi, isNull);
      expect(provider.poiStatus, PoiStatus.idle);
    });

    test(
        'Rapid switching out-of-order race condition preserves newest POIs',
        () async {
      final slowPoiRepo = MockPoiRepo(
        pois: {
          'buid_A/1': [poiA1],
          'buid_A/2': [poiA2],
        },
        customDelays: {
          'buid_A/1': const Duration(milliseconds: 100),
          'buid_A/2': const Duration(milliseconds: 10),
        },
      );

      final raceProvider = SpaceProvider(
        repository: spaceRepo,
        radioMapRepository: radioRepo,
        floorplanRepository: floorplanRepo,
        poiRepository: slowPoiRepo,
        nativePositioningService: nativePosService,
      );

      raceProvider.selectSpace(buildingA);
      await raceProvider.loadFloorsForSelectedSpace();

      // Trigger slow A/1 POI request
      raceProvider.selectFloor(floorA1);
      // Immediately switch to fast A/2 POI request
      raceProvider.selectFloor(floorA2);

      // Wait for both to complete
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(raceProvider.selectedFloor?.floorNumber, '2');
      expect(raceProvider.hasPois, isTrue);
      expect(raceProvider.pois.first.puid, 'poi_A2');
    });
  });
}
