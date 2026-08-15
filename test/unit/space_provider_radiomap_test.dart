import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

class MockSpaceRepository implements SpaceRepository {
  final List<SpaceModel> spaces;
  final Map<String, List<FloorModel>> floors;

  MockSpaceRepository({required this.spaces, required this.floors});

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.cast<SpaceModel?>().firstWhere((s) => s?.buid == buid, orElse: () => null);

  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid, {bool forceReload = false}) async =>
      floors[buid] ?? [];
}

class MockRadioMapRepository implements RadioMapRepository {
  final Map<String, String> radiomaps;
  final Duration delay;
  final Map<String, Duration> customDelays;

  MockRadioMapRepository({
    required this.radiomaps,
    this.delay = Duration.zero,
    this.customDelays = const {},
  });

  @override
  Future<String> getRadioMap(String buid, String floor, {bool forceReload = false}) async {
    final key = '$buid/$floor';
    final requestDelay = customDelays[key] ?? delay;
    if (requestDelay > Duration.zero) {
      await Future<void>.delayed(requestDelay);
    }
    final content = radiomaps[key];
    if (content == null) {
      throw Exception('Area not supported yet!');
    }
    return content;
  }

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async =>
      radiomaps.containsKey('$buid/$floor');

  @override
  Future<void> clearRadioMap(String buid, String floor) async {
    radiomaps.remove('$buid/$floor');
  }

  @override
  Future<void> clearAllCache() async {
    radiomaps.clear();
  }
}

class MockNativePositioningService implements NativePositioningService {
  String? loadedText;
  String? activeBuid;
  String? activeFloor;
  bool shouldAccept = true;

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async {
    if (!shouldAccept) {
      return false;
    }
    loadedText = text;
    activeBuid = buid;
    activeFloor = floor;
    return true;
  }

  @override
  Future<bool> clearRadioMap() async {
    loadedText = null;
    activeBuid = null;
    activeFloor = null;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async {
    if (activeBuid == null) return null;
    return {
      'buid': activeBuid,
      'floor': activeFloor,
      'apCount': 10,
      'fingerprintCount': 50,
    };
  }
}

void main() {
  const buildingA = SpaceModel(
    buid: 'buid_A',
    name: 'Building Alpha',
    latitude: 35.14,
    longitude: 33.41,
  );
  const buildingB = SpaceModel(
    buid: 'buid_B',
    name: 'Building Beta',
    latitude: 35.15,
    longitude: 33.42,
  );

  const floorA1 = FloorModel(buid: 'buid_A', floorNumber: '1', floorName: 'Floor 1');
  const floorA2 = FloorModel(buid: 'buid_A', floorNumber: '2', floorName: 'Floor 2');
  const floorB1 = FloorModel(buid: 'buid_B', floorNumber: '1', floorName: 'Floor 1');

  const mapContentA1 = '# NaN -110\n# X, Y, HEADING, macA1\n35.14, 33.41, 0, -80\n';
  const mapContentA2 = '# NaN -110\n# X, Y, HEADING, macA2\n35.14, 33.41, 0, -75\n';
  const mapContentB1 = '# NaN -110\n# X, Y, HEADING, macB1\n35.15, 33.42, 0, -70\n';

  late MockSpaceRepository spaceRepo;
  late MockRadioMapRepository radioRepo;
  late MockNativePositioningService nativeService;
  late SpaceProvider provider;

  setUp(() {
    spaceRepo = MockSpaceRepository(
      spaces: [buildingA, buildingB],
      floors: {
        'buid_A': [floorA1, floorA2],
        'buid_B': [floorB1],
      },
    );

    radioRepo = MockRadioMapRepository(radiomaps: {
      'buid_A/1': mapContentA1,
      'buid_A/2': mapContentA2,
      'buid_B/1': mapContentB1,
    });

    nativeService = MockNativePositioningService();

    provider = SpaceProvider(
      repository: spaceRepo,
      radioMapRepository: radioRepo,
      nativePositioningService: nativeService,
    );
  });

  group('SpaceProvider RadioMap Integration', () {
    test('Floor selection triggers RadioMap acquisition and native load',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      // Wait for async radiomap load
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveRadioMap, isTrue);
      expect(provider.radioMapStatus, RadioMapStatus.ready);
      expect(provider.activeRadioMapBuid, 'buid_A');
      expect(provider.activeRadioMapFloor, '1');
      expect(nativeService.activeBuid, 'buid_A');
      expect(nativeService.activeFloor, '1');
      expect(nativeService.loadedText, mapContentA1);
    });

    test('Switching floors (A/1 -> A/2) replaces native RadioMap', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(nativeService.activeFloor, '1');

      provider.selectFloor(floorA2);
      await Future<void>.delayed(Duration.zero);

      expect(provider.radioMapStatus, RadioMapStatus.ready);
      expect(provider.activeRadioMapFloor, '2');
      expect(nativeService.activeFloor, '2');
      expect(nativeService.loadedText, mapContentA2);
    });

    test('Switching buildings (A/1 -> B/1) clears previous floor and loads new RadioMap',
        () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();

      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);
      expect(nativeService.activeBuid, 'buid_A');

      // Select Building B
      provider.selectSpace(buildingB);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasActiveRadioMap, isFalse);
      expect(nativeService.activeBuid, isNull);

      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorB1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveRadioMap, isTrue);
      expect(nativeService.activeBuid, 'buid_B');
      expect(nativeService.activeFloor, '1');
      expect(nativeService.loadedText, mapContentB1);
    });

    test('Clearing selection resets active RadioMap in native engine', () async {
      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);

      expect(nativeService.activeBuid, 'buid_A');

      provider.clearSelection();

      expect(provider.selectedSpace, isNull);
      expect(provider.selectedFloor, isNull);
      expect(provider.hasActiveRadioMap, isFalse);
      expect(nativeService.activeBuid, isNull);
      expect(nativeService.loadedText, isNull);
    });

    test('Rapid switching out-of-order race condition preserves newest floor',
        () async {
      // Configure A/1 to be slow (100ms) and A/2 to be fast (10ms)
      final slowRadioRepo = MockRadioMapRepository(
        radiomaps: {
          'buid_A/1': mapContentA1,
          'buid_A/2': mapContentA2,
        },
        customDelays: {
          'buid_A/1': const Duration(milliseconds: 100),
          'buid_A/2': const Duration(milliseconds: 10),
        },
      );

      final raceProvider = SpaceProvider(
        repository: spaceRepo,
        radioMapRepository: slowRadioRepo,
        nativePositioningService: nativeService,
      );

      raceProvider.selectSpace(buildingA);
      await raceProvider.loadFloorsForSelectedSpace();

      // Trigger slow A/1 download
      raceProvider.selectFloor(floorA1);
      // Immediately switch to fast A/2 download
      raceProvider.selectFloor(floorA2);

      // Wait 150ms for both to complete
      await Future<void>.delayed(const Duration(milliseconds: 150));

      // Final active map MUST be A/2, not the late-arriving A/1
      expect(raceProvider.selectedFloor?.floorNumber, '2');
      expect(raceProvider.activeRadioMapFloor, '2');
      expect(nativeService.activeFloor, '2');
      expect(nativeService.loadedText, mapContentA2);
    });

    test('Native rejection sets error status and clears native engine',
        () async {
      nativeService.shouldAccept = false;

      provider.selectSpace(buildingA);
      await provider.loadFloorsForSelectedSpace();
      provider.selectFloor(floorA1);
      await Future<void>.delayed(Duration.zero);

      expect(provider.hasActiveRadioMap, isFalse);
      expect(provider.radioMapStatus, RadioMapStatus.error);
      expect(nativeService.activeBuid, isNull);
    });
  });
}
