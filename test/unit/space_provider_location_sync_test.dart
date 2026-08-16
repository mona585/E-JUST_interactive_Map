import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';

class MockSpaceRepo implements SpaceRepository {
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async => [];
  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => null;
  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid, {bool forceReload = false}) async => [];
}

class MockRadioRepo implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor, {bool forceReload = false}) async => '# NaN -110\n';
  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => true;
  @override
  Future<void> clearRadioMap(String buid, String floor) async {}
  @override
  Future<void> clearAllCache() async {}
}

class MockFloorplanRepo implements FloorplanRepository {
  @override
  Future<FloorplanModel?> getFloorplan(String buid, String floor, FloorModel metadata, {bool forceReload = false}) async => null;
  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;
  @override
  Future<void> clearFloorplan(String buid, String floor) async {}
  @override
  Future<void> clearAll() async {}
}

class MockPoiRepo implements PoiRepository {
  @override
  Future<List<PoiModel>> getPoisByFloor(String buid, String floor, {bool forceReload = false}) async => [];
  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;
  @override
  Future<void> clearPois(String buid, String floor) async {}
  @override
  Future<void> clearAll() async {}
}

class MockNativePosService implements NativePositioningService {
  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();
  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async => true;
  @override
  Future<bool> clearRadioMap() async => true;
  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

void main() {
  const building = SpaceModel(
    buid: 'buid_sync_1',
    name: 'Sync Building',
    latitude: 35.14,
    longitude: 33.41,
  );

  const floor0 = FloorModel(
    buid: 'buid_sync_1',
    floorNumber: '0',
    floorName: 'Ground',
  );

  const floor1 = FloorModel(
    buid: 'buid_sync_1',
    floorNumber: '1',
    floorName: 'First Floor',
  );

  late SpaceProvider spaceProvider;
  late LocationProvider locationProvider;

  setUp(() {
    locationProvider = LocationProvider();
    spaceProvider = SpaceProvider(
      repository: MockSpaceRepo(),
      radioMapRepository: MockRadioRepo(),
      floorplanRepository: MockFloorplanRepo(),
      poiRepository: MockPoiRepo(),
      nativePositioningService: MockNativePosService(),
      locationProvider: locationProvider,
    );
  });

  tearDown(() {
    locationProvider.dispose();
  });

  group('SpaceProvider to LocationProvider Sync', () {
    test('selectFloor updates LocationProvider active floor scope', () {
      spaceProvider.selectSpace(building);
      spaceProvider.selectFloor(floor0);

      expect(spaceProvider.selectedFloor?.floorNumber, '0');
    });

    test('clearFloorSelection resets LocationProvider active floor scope', () {
      spaceProvider.selectSpace(building);
      spaceProvider.selectFloor(floor0);

      spaceProvider.clearFloorSelection();
      expect(spaceProvider.selectedFloor, isNull);
    });

    test('clearSelection resets space and floor scope', () {
      spaceProvider.selectSpace(building);
      spaceProvider.selectFloor(floor1);

      spaceProvider.clearSelection();
      expect(spaceProvider.selectedSpace, isNull);
      expect(spaceProvider.selectedFloor, isNull);
    });
  });
}
