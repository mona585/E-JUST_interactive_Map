import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
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
      '# NaN -110\n# X, Y, HEADING, mac\n1.0, 2.0, 0, -80\n';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => true;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class MockFloorplanRepo implements FloorplanRepository {
  final Map<String, FloorplanModel> floorplans;
  final Duration delay;
  final Map<String, Duration> customDelays;

  MockFloorplanRepo({
    required this.floorplans,
    this.delay = Duration.zero,
    this.customDelays = const {},
  });

  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async {
    final key = '$buid/$floor';
    final reqDelay = customDelays[key] ?? delay;
    if (reqDelay > Duration.zero) {
      await Future<void>.delayed(reqDelay);
    }
    return floorplans[key];
  }

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async =>
      floorplans.containsKey('$buid/$floor');

  @override
  Future<void> clearFloorplan(String buid, String floor) async {
    floorplans.remove('$buid/$floor');
  }

  @override
  Future<void> clearAll() async {
    floorplans.clear();
  }
}

class MockNativePosService implements NativePositioningService {
  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();

  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor,
  ) async =>
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

  const planA1 = FloorplanModel(
    buid: 'buid_A',
    floorNumber: '1',
    imagePath: '/path/buid_A/1/floorplan.png',
    bottomLeftLat: 35.140,
    bottomLeftLng: 33.410,
    topRightLat: 35.145,
    topRightLng: 33.415,
    imageSizeBytes: 150000,
    isCached: true,
  );

  const planA2 = FloorplanModel(
    buid: 'buid_A',
    floorNumber: '2',
    imagePath: '/path/buid_A/2/floorplan.png',
    bottomLeftLat: 35.140,
    bottomLeftLng: 33.410,
    topRightLat: 35.145,
    topRightLng: 33.415,
    imageSizeBytes: 180000,
    isCached: true,
  );

  const planB1 = FloorplanModel(
    buid: 'buid_B',
    floorNumber: '1',
    imagePath: '/path/buid_B/1/floorplan.png',
    bottomLeftLat: 35.150,
    bottomLeftLng: 33.420,
    topRightLat: 35.155,
    topRightLng: 33.425,
    imageSizeBytes: 120000,
    isCached: true,
  );

  late MockSpaceRepo spaceRepo;
  late MockRadioRepo radioRepo;
  late MockFloorplanRepo floorplanRepo;
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
    floorplanRepo = MockFloorplanRepo(floorplans: {
      'buid_A/1': planA1,
      'buid_A/2': planA2,
      'buid_B/1': planB1,
    });
    nativePosService = MockNativePosService();

    provider = SpaceProvider(
      repository: spaceRepo,
      radioMapRepository: radioRepo,
      floorplanRepository: floorplanRepo,
      nativePositioningService: nativePosService,
    );
  });

  group('SpaceProvider Floorplan Integration', () {
    test('Floor selection triggers floorplan acquisition and sets ready state',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveFloorplan, isTrue);
      expect(provider.floorplanStatus, FloorplanStatus.ready);
      expect(provider.activeFloorplan?.imageSizeBytes, equals(150000));
      expect(
        provider.activeFloorplanImagePath,
        equals('/path/buid_A/1/floorplan.png'),
      );
    });

    test('Switching floors (A/1 -> A/2) replaces active floorplan', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.activeFloorplan?.floorNumber, '1');

      provider.selectFloor(floorA2);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveFloorplan, isTrue);
      expect(provider.activeFloorplan?.floorNumber, '2');
      expect(provider.activeFloorplan?.imageSizeBytes, equals(180000));
      expect(
        provider.activeFloorplanImagePath,
        equals('/path/buid_A/2/floorplan.png'),
      );
    });

    test(
        'Switching buildings (A/1 -> B/1) clears previous floorplan and loads new one',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasActiveFloorplan, isTrue);

      // Select Building B
      provider.selectSpace(buildingB);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasActiveFloorplan, isFalse);
      expect(provider.floorplanStatus, FloorplanStatus.idle);

      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorB1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveFloorplan, isTrue);
      expect(provider.activeFloorplan?.buid, 'buid_B');
      expect(provider.activeFloorplan?.imageSizeBytes, equals(120000));
    });

    test('Clearing selection resets active floorplan', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(provider.hasActiveFloorplan, isTrue);

      provider.clearSelection();

      expect(provider.selectedSpace, isNull);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasActiveFloorplan, isFalse);
      expect(provider.activeFloorplan, isNull);
      expect(provider.floorplanStatus, FloorplanStatus.idle);
    });

    test(
        'Rapid switching out-of-order race condition preserves newest floorplan',
        () async {
      final slowFloorplanRepo = MockFloorplanRepo(
        floorplans: {
          'buid_A/1': planA1,
          'buid_A/2': planA2,
        },
        customDelays: {
          'buid_A/1': const Duration(milliseconds: 100),
          'buid_A/2': const Duration(milliseconds: 10),
        },
      );

      final raceProvider = SpaceProvider(
        repository: spaceRepo,
        radioMapRepository: radioRepo,
        floorplanRepository: slowFloorplanRepo,
        nativePositioningService: nativePosService,
      );

      raceProvider.selectSpace(buildingA);
      await raceProvider.loadFloorsForSelectedSpace();

      // Trigger slow A/1 download
      raceProvider.selectFloor(floorA1);
      // Immediately switch to fast A/2 download
      raceProvider.selectFloor(floorA2);

      // Wait for both to complete
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(raceProvider.selectedFloor?.floorNumber, '2');
      expect(raceProvider.hasActiveFloorplan, isTrue);
      expect(raceProvider.activeFloorplan?.floorNumber, '2');
      expect(raceProvider.activeFloorplan?.imageSizeBytes, equals(180000));
    });
  });
}
