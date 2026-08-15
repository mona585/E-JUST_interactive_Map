import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

class MockSpaceRepository implements SpaceRepository {
  List<SpaceModel> spacesToReturn = [];
  Map<String, List<FloorModel>> floorsToReturn = {};
  bool shouldThrowSpaces = false;
  bool shouldThrowFloors = false;
  String errorMessage = 'Failed to load spaces';

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async {
    if (shouldThrowSpaces) {
      throw ApiException(errorMessage);
    }
    return spacesToReturn;
  }

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    if (shouldThrowSpaces) {
      throw ApiException(errorMessage);
    }
    final matching = spacesToReturn.where((s) => s.buid == buid);
    return matching.isNotEmpty ? matching.first : null;
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async {
    if (shouldThrowFloors) {
      throw ApiException('Failed to load floors for $buid');
    }
    return floorsToReturn[buid] ?? [];
  }
}

class FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor, {bool forceReload = false}) async => '';
  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;
  @override
  Future<void> clearRadioMap(String buid, String floor) async {}
  @override
  Future<void> clearAllCache() async {}
}

class FakeFloorplanRepository implements FloorplanRepository {
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

class FakeNativePositioningService implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async => true;
  @override
  Future<bool> clearRadioMap() async => true;
  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpaceProvider', () {
    late MockSpaceRepository repository;
    late SpaceProvider provider;

    final testSpaces = [
      const SpaceModel(
        buid: 'buid_1',
        name: 'Building One',
        latitude: 35.1,
        longitude: 33.1,
        bucode: 'B1',
      ),
      const SpaceModel(
        buid: 'buid_2',
        name: 'Building Two',
        latitude: 35.2,
        longitude: 33.2,
        bucode: 'B2',
      ),
    ];

    final building1Floors = [
      const FloorModel(buid: 'buid_1', floorNumber: '0', floorName: 'Ground'),
      const FloorModel(buid: 'buid_1', floorNumber: '1', floorName: 'First'),
    ];

    final building2Floors = [
      const FloorModel(
        buid: 'buid_2',
        floorNumber: '-1',
        floorName: 'Basement',
      ),
      const FloorModel(buid: 'buid_2', floorNumber: '0', floorName: 'Ground'),
      const FloorModel(buid: 'buid_2', floorNumber: '1', floorName: 'First'),
    ];

    setUp(() {
      repository = MockSpaceRepository();
      repository.spacesToReturn = testSpaces;
      repository.floorsToReturn = {
        'buid_1': building1Floors,
        'buid_2': building2Floors,
      };
      provider = SpaceProvider(
        repository: repository,
        radioMapRepository: FakeRadioMapRepository(),
        floorplanRepository: FakeFloorplanRepository(),
        nativePositioningService: FakeNativePositioningService(),
      );
    });

    test('initial state is clean', () {
      expect(provider.spaces, isEmpty);
      expect(provider.selectedSpace, isNull);
      expect(provider.selectedFloor, isNull);
      expect(provider.floors, isEmpty);
      expect(provider.isLoading, isFalse);
      expect(provider.isLoadingFloors, isFalse);
      expect(provider.errorMessage, isNull);
      expect(provider.floorsErrorMessage, isNull);
      expect(provider.hasError, isFalse);
      expect(provider.hasSelectedSpace, isFalse);
      expect(provider.hasSelectedFloor, isFalse);
    });

    test('loadSpaces successfully fetches and updates state', () async {
      final future = provider.loadSpaces();
      expect(provider.isLoading, isTrue);

      await future;

      expect(provider.isLoading, isFalse);
      expect(provider.spaces.length, 2);
      expect(provider.spaces.first.buid, 'buid_1');
      expect(provider.hasError, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('loadSpaces handles ApiException and sets errorMessage', () async {
      repository.shouldThrowSpaces = true;
      repository.errorMessage = 'Network connection failed';

      await provider.loadSpaces();

      expect(provider.isLoading, isFalse);
      expect(provider.spaces, isEmpty);
      expect(provider.hasError, isTrue);
      expect(provider.errorMessage, 'Network connection failed');
    });

    test('selectSpace loads floors for selected building and resets old floor',
        () async {
      provider.selectSpace(testSpaces.first);
      expect(provider.selectedSpace, equals(testSpaces.first));
      expect(provider.hasSelectedSpace, isTrue);
      expect(provider.selectedFloor, isNull);

      // Wait for floors to load
      await pumpEventQueue();

      expect(provider.floors.length, 2);
      expect(provider.floors.first.floorNumber, '0');
      expect(provider.isLoadingFloors, isFalse);
      expect(provider.floorsErrorMessage, isNull);
    });

    test('selectFloor updates selectedFloor correctly', () async {
      provider.selectSpace(testSpaces.first);
      await pumpEventQueue();

      final targetFloor = building1Floors[1]; // Floor 1
      provider.selectFloor(targetFloor);

      expect(provider.selectedFloor, equals(targetFloor));
      expect(provider.hasSelectedFloor, isTrue);
      expect(provider.selectedFloor!.floorNumber, '1');
      expect(provider.selectedFloor!.buid, 'buid_1');
    });

    test('switching from Building A to Building B resets selectedFloor',
        () async {
      // 1. Select Building 1 and floor 1
      provider.selectSpace(testSpaces.first);
      await pumpEventQueue();
      provider.selectFloor(building1Floors[1]);
      expect(provider.selectedFloor?.floorNumber, '1');
      expect(provider.selectedFloor?.buid, 'buid_1');

      // 2. Switch to Building 2
      provider.selectSpace(testSpaces[1]);

      // Immediately selectedFloor must be reset to null
      expect(provider.selectedFloor, isNull);
      expect(provider.hasSelectedFloor, isFalse);

      await pumpEventQueue();

      // Building 2 floors are loaded
      expect(provider.floors.length, 3);
      expect(provider.floors.first.floorNumber, '-1');
      expect(provider.selectedFloor, isNull);
    });

    test(
        'Building A floor cannot remain or be selected for Building B',
        () async {
      provider.selectSpace(testSpaces[1]); // Building 2 selected
      await pumpEventQueue();

      // Attempt to select Floor from Building 1
      provider.selectFloor(building1Floors[0]);

      // Selection must be rejected because floor.buid != selectedSpace.buid
      expect(provider.selectedFloor, isNull);
      expect(provider.hasSelectedFloor, isFalse);
    });

    test('clearSelection clears both selectedSpace and selectedFloor',
        () async {
      provider.selectSpace(testSpaces.first);
      await pumpEventQueue();
      provider.selectFloor(building1Floors[0]);

      expect(provider.hasSelectedSpace, isTrue);
      expect(provider.hasSelectedFloor, isTrue);

      provider.clearSelection();

      expect(provider.selectedSpace, isNull);
      expect(provider.selectedFloor, isNull);
      expect(provider.floors, isEmpty);
      expect(provider.hasSelectedSpace, isFalse);
      expect(provider.hasSelectedFloor, isFalse);
    });

    test('clearFloorSelection clears only floor while retaining space',
        () async {
      provider.selectSpace(testSpaces.first);
      await pumpEventQueue();
      provider.selectFloor(building1Floors[0]);

      expect(provider.hasSelectedFloor, isTrue);

      provider.clearFloorSelection();

      expect(provider.hasSelectedSpace, isTrue);
      expect(provider.selectedSpace, equals(testSpaces.first));
      expect(provider.selectedFloor, isNull);
      expect(provider.floors.length, 2);
    });

    test('floor loading failure sets floorsErrorMessage and allows retry',
        () async {
      repository.shouldThrowFloors = true;

      provider.selectSpace(testSpaces.first);
      await pumpEventQueue();

      expect(provider.floors, isEmpty);
      expect(provider.hasFloorsError, isTrue);
      expect(provider.floorsErrorMessage, contains('Failed to load floors'));

      // Resolve error and retry
      repository.shouldThrowFloors = false;
      await provider.loadFloorsForSelectedSpace(forceReload: true);

      expect(provider.hasFloorsError, isFalse);
      expect(provider.floorsErrorMessage, isNull);
      expect(provider.floors.length, 2);
    });
  });
}
