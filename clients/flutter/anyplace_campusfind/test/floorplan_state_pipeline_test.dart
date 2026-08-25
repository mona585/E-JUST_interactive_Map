import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

// ---------------------------------------------------------------------------
// Floorplan browsing-state pipeline regression tests.
//
// Pins the SELECT FLOOR -> loading -> FLOORPLAN READY / explicit error
// state machine, and that a live navigation session never blocks or cancels
// floorplan browsing (state-ownership independence).
// ---------------------------------------------------------------------------

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.86,
      longitude: 29.58,
    );

FloorplanModel _floorplan() => const FloorplanModel(
      buid: 'b1',
      floorNumber: '0',
      imagePath: '/cache/b1/0/floorplan.png',
      bottomLeftLat: 30.85,
      bottomLeftLng: 29.57,
      topRightLat: 30.87,
      topRightLng: 29.59,
    );

class _FakeSpaceRepository implements SpaceRepository {
  final spaces = [_building()];
  final floors = [FloorModel(buid: 'b1', floorNumber: '0')];

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.where((s) => s.buid == buid).firstOrNull;

  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid,
          {bool forceReload = false}) async =>
      floors;
}

class _FakePoiRepository implements PoiRepository {
  @override
  Future<List<dynamic>> getPoisByFloor(String buid, String floor,
          {bool forceReload = false}) async =>
      const [];

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor,
          {bool forceReload = false}) async =>
      '';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
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

/// Floorplan repository whose outcome is scripted per test.
class _ScriptedFloorplanRepository implements FloorplanRepository {
  FloorplanModel? result;
  Object? throwOnGet;

  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async {
    final error = throwOnGet;
    if (error != null) throw error;
    return result;
  }

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;

  @override
  Future<void> clearFloorplan(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

SpaceProvider _provider(_ScriptedFloorplanRepository floorplanRepo) {
  return SpaceProvider(
    repository: _FakeSpaceRepository(),
    poiRepository: _FakePoiRepository(),
    radioMapRepository: _FakeRadioMapRepository(),
    floorplanRepository: floorplanRepo,
    nativePositioningService: _FakeNativePositioningService(),
  );
}

Future<void> _selectBuildingAndFloor(SpaceProvider provider) async {
  await provider.loadSpaces();
  provider.selectSpace(provider.spaces.first);
  await provider.loadFloorsForSelectedSpace();
  provider.selectFloor(provider.floors.first);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('A. SELECT FLOOR -> loading -> FLOORPLAN READY', (tester) async {
    final repo = _ScriptedFloorplanRepository()..result = _floorplan();
    final provider = _provider(repo);
    addTearDown(provider.dispose);

    expect(provider.floorplanStatus, FloorplanStatus.idle);
    await _selectBuildingAndFloor(provider);
    await provider.loadFloorplanForSelectedFloor();

    expect(provider.floorplanStatus, FloorplanStatus.ready);
    expect(provider.hasActiveFloorplan, isTrue);
    expect(provider.activeFloorplan!.imagePath, '/cache/b1/0/floorplan.png');
  });

  testWidgets('B. missing floorplan -> explicit UNSUPPORTED state, no '
      'infinite loading', (tester) async {
    final repo = _ScriptedFloorplanRepository()..result = null;
    final provider = _provider(repo);
    addTearDown(provider.dispose);

    await _selectBuildingAndFloor(provider);
    await provider.loadFloorplanForSelectedFloor();

    expect(provider.floorplanStatus, FloorplanStatus.unsupported);
    expect(provider.hasActiveFloorplan, isFalse);
    expect(provider.floorplanErrorMessage, isNotNull);
  });

  testWidgets('C. network/API failure -> explicit ERROR state with the '
      'surfaced message', (tester) async {
    final repo = _ScriptedFloorplanRepository()
      ..throwOnGet =
          const ApiException('Connection to Anyplace backend timed out.');
    final provider = _provider(repo);
    addTearDown(provider.dispose);

    await _selectBuildingAndFloor(provider);
    await provider.loadFloorplanForSelectedFloor();

    expect(provider.floorplanStatus, FloorplanStatus.error);
    expect(provider.hasActiveFloorplan, isFalse);
    expect(provider.floorplanErrorMessage, contains('timed out'));
  });

  testWidgets('E. a LIVE navigation session does not block or cancel '
      'floorplan browsing', (tester) async {
    final repo = _ScriptedFloorplanRepository()..result = _floorplan();
    final provider = _provider(repo);
    addTearDown(provider.dispose);
    provider.isNavigationSessionLive = () => true;

    await _selectBuildingAndFloor(provider);
    await provider.loadFloorplanForSelectedFloor();

    expect(provider.floorplanStatus, FloorplanStatus.ready);
    expect(provider.hasActiveFloorplan, isTrue);
  });
}
