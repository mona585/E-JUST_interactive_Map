import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

class _FakeSpaceRepository implements SpaceRepository {
  final SpaceModel space;
  final List<FloorModel> floors;
  _FakeSpaceRepository(this.space, this.floors);

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      [space];

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => space;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      floors;
}

class _FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      throw const ApiException('not supported', statusCode: 404);

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

class _FakePoiRepository implements PoiRepository {
  final Map<String, List<PoiModel>> byFloor;
  _FakePoiRepository(this.byFloor);

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      byFloor[floor] ?? const [];

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeNavigationRepository implements NavigationRepository {
  final NavigationRouteModel route;
  final PoiModel connectorF0;
  final PoiModel connectorF2;
  final PoiModel destPoi;
  _FakeNavigationRepository(
    this.route, {
    required this.connectorF0,
    required this.connectorF2,
    required this.destPoi,
  });

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async {
    if (fromPuid == connectorF0.puid && toPuid == connectorF2.puid) {
      return NavigationRouteModel(points: [
        NavigationRoutePoint(
          latitude: connectorF0.latitude,
          longitude: connectorF0.longitude,
          puid: connectorF0.puid,
          buid: connectorF0.buid,
          floorNumber: connectorF0.floorNumber,
          poisType: connectorF0.poisType,
        ),
        NavigationRoutePoint(
          latitude: connectorF2.latitude,
          longitude: connectorF2.longitude,
          puid: connectorF2.puid,
          buid: connectorF2.buid,
          floorNumber: connectorF2.floorNumber,
          poisType: connectorF2.poisType,
        ),
      ]);
    }
    if (fromPuid == connectorF2.puid && toPuid == destPoi.puid) {
      return NavigationRouteModel(points: [
        NavigationRoutePoint(
          latitude: connectorF2.latitude,
          longitude: connectorF2.longitude,
          puid: connectorF2.puid,
          buid: connectorF2.buid,
          floorNumber: connectorF2.floorNumber,
          poisType: connectorF2.poisType,
        ),
        NavigationRoutePoint(
          latitude: destPoi.latitude,
          longitude: destPoi.longitude,
          puid: destPoi.puid,
          buid: destPoi.buid,
          floorNumber: destPoi.floorNumber,
          poisType: destPoi.poisType,
        ),
      ]);
    }
    return route;
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async {
    if (floorNumber == '0' && destinationPuid == connectorF0.puid) {
      return NavigationRouteModel(points: [
        NavigationRoutePoint(
          latitude: latitude,
          longitude: longitude,
          puid: '__position__',
          buid: connectorF0.buid,
          floorNumber: '0',
          poisType: 'None',
        ),
        NavigationRoutePoint(
          latitude: connectorF0.latitude,
          longitude: connectorF0.longitude,
          puid: connectorF0.puid,
          buid: connectorF0.buid,
          floorNumber: connectorF0.floorNumber,
          poisType: connectorF0.poisType,
        ),
      ]);
    }
    return route;
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<UserLocation?> getCurrentPosition() async => null;

  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) =>
      const Stream.empty();
}

class _FakeNativePositioningService implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async =>
      false;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();
}

class _Harness {
  late SpaceProvider spaceProvider;
  late LocationProvider locationProvider;
  bool navigationActive = false;

  static const buid = 'bldg_test_1';
  final space = const SpaceModel(
    buid: buid,
    name: 'Test Building',
    latitude: 30.0000,
    longitude: 32.0000,
  );
  late final FloorModel floor0;
  late final FloorModel floor2;
  late final PoiModel connectorF0;
  late final PoiModel connectorF2;
  late final PoiModel destPoi;
  late final NavigationRouteModel route;

  _Harness() {
    floor0 = FloorModel(buid: buid, floorNumber: '0');
    floor2 = FloorModel(buid: buid, floorNumber: '2');
    connectorF0 = PoiModel(
      puid: 'conn_f0_stairA',
      buid: buid,
      floorNumber: '0',
      name: 'Stair A',
      poisType: 'None',
      latitude: 30.00000,
      longitude: 32.00000,
    );
    connectorF2 = PoiModel(
      puid: 'conn_f2_stairA',
      buid: buid,
      floorNumber: '2',
      name: 'Stair A',
      poisType: 'None',
      latitude: 30.00001,
      longitude: 32.00001,
    );
    destPoi = PoiModel(
      puid: 'poi_f2_dest',
      buid: buid,
      floorNumber: '2',
      name: 'Room 202',
      poisType: 'Office',
      latitude: 30.0005,
      longitude: 32.0005,
    );
    route = NavigationRouteModel(points: [
      NavigationRoutePoint(
        latitude: 30.0001,
        longitude: 32.0001,
        puid: 'p1',
        buid: buid,
        floorNumber: '2',
        poisType: 'None',
      ),
      NavigationRoutePoint(
        latitude: 30.0003,
        longitude: 32.0003,
        puid: 'p2',
        buid: buid,
        floorNumber: '2',
        poisType: 'None',
      ),
      NavigationRoutePoint(
        latitude: destPoi.latitude,
        longitude: destPoi.longitude,
        puid: destPoi.puid,
        buid: buid,
        floorNumber: '2',
        poisType: destPoi.poisType,
      ),
    ]);
  }

  Future<void> pump() async {
    locationProvider = LocationProvider(
      locationService: _FakeLocationService(),
      nativePositioningService: _FakeNativePositioningService(),
    );
    spaceProvider = SpaceProvider(
      repository: _FakeSpaceRepository(space, [floor0, floor2]),
      radioMapRepository: _FakeRadioMapRepository(),
      floorplanRepository: _FakeFloorplanRepository(),
      poiRepository: _FakePoiRepository({
        '0': [connectorF0],
        '2': [connectorF2, destPoi],
      }),
      navigationRepository: _FakeNavigationRepository(
        route,
        connectorF0: connectorF0,
        connectorF2: connectorF2,
        destPoi: destPoi,
      ),
    );
    spaceProvider.setIsNavigationActive(() => navigationActive);
    spaceProvider.setLocationProvider(locationProvider);

    spaceProvider.selectSpace(space);
    await spaceProvider.loadFloorsForSelectedSpace();
    spaceProvider.selectFloor(floor2);
    await spaceProvider.loadPoisForSelectedFloor();

    locationProvider.setGpsLocation(UserLocation(
      latitude: 29.9998,
      longitude: 31.9998,
      accuracy: 5.0,
      timestamp: DateTime.now(),
    ));

    spaceProvider.selectPoi(destPoi);
    await spaceProvider.requestRouteToSelectedPoi();

    expect(spaceProvider.activeNavigationRoute, isNotNull,
        reason: 'harness must produce a loaded route');
    expect(spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);
  }

  void dispose() {
    spaceProvider.dispose();
    locationProvider.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> teardownHarness(_Harness h) async {
    await pumpEventQueue();
    h.dispose();
  }

  test(
    'selectFloor resets navigation route state when navigation is not active (legacy behavior)',
    () async {
      final h = _Harness();
      await h.pump();

      h.spaceProvider.selectFloor(h.floor0);

      expect(h.spaceProvider.selectedFloor?.floorNumber, '0');
      expect(h.spaceProvider.activeNavigationRoute, isNull);
      expect(h.spaceProvider.hasActiveNavigationRoute, isFalse);
      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.idle);
      expect(h.spaceProvider.navigationDestinationPuid, isNull);

      await teardownHarness(h);
    },
  );

  test(
    'selectFloor during active navigation preserves the active route unchanged',
    () async {
      final h = _Harness();
      await h.pump();
      final original = h.spaceProvider.activeNavigationRoute!;
      final originalPointCount = original.points.length;

      h.navigationActive = true;
      h.spaceProvider.selectFloor(h.floor0);

      expect(h.spaceProvider.selectedFloor?.floorNumber, '0');
      expect(identical(h.spaceProvider.activeNavigationRoute, original), isTrue,
          reason: 'route instance must be preserved, not recreated');
      expect(h.spaceProvider.hasActiveNavigationRoute, isTrue);
      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);
      expect(h.spaceProvider.navigationDestinationPuid, h.destPoi.puid);
      expect(h.spaceProvider.activeNavigationRoute!.points.length,
          originalPointCount);

      await teardownHarness(h);
    },
  );

  test(
    'SpaceProvider and NavigationController stay synchronized across a floor change while active',
    () async {
      final h = _Harness();
      await h.pump();
      final controller = NavigationController(
        spaceProvider: h.spaceProvider,
        locationProvider: h.locationProvider,
        navigationRepository: _FakeNavigationRepository(
          h.route,
          connectorF0: h.connectorF0,
          connectorF2: h.connectorF2,
          destPoi: h.destPoi,
        ),
      );
      h.spaceProvider.setIsNavigationActive(() => controller.isActive);
      addTearDown(controller.dispose);

      controller.startRoutePreview(
        destinationPuid: h.destPoi.puid,
        destinationSpace: h.space,
        destinationFloorNumber: h.destPoi.floorNumber,
      );
      controller.startActiveNavigation();
      expect(controller.isActive, isTrue);

      final original = controller.activeRoute!;
      h.spaceProvider.selectFloor(h.floor0);

      expect(identical(controller.activeRoute, original), isTrue,
          reason: 'controller must still hold the same route');
      expect(identical(h.spaceProvider.activeNavigationRoute, original), isTrue,
          reason: 'provider must render the same route after the floor change');

      controller.endNavigation();
      await teardownHarness(h);
    },
  );
}
