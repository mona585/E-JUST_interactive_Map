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
import 'package:anyplace_campusfind/state/space_provider.dart';

const _buid = 'bldg_crossfloor_1';

PoiModel _poi({
  required String puid,
  required String floor,
  required String type,
  required double lat,
  required double lon,
  String name = '',
}) {
  return PoiModel(
    puid: puid,
    buid: _buid,
    floorNumber: floor,
    name: name.isEmpty ? puid : name,
    poisType: type,
    latitude: lat,
    longitude: lon,
  );
}

class _RecordedRouteCall {
  final bool isCoordinateCall;
  final String? coordinateFloor;
  final String? fromPuid;
  final String? toPuid;
  const _RecordedRouteCall.coordinate(this.coordinateFloor)
      : isCoordinateCall = true,
        fromPuid = null,
        toPuid = null;
  const _RecordedRouteCall.pois(this.fromPuid, this.toPuid)
      : isCoordinateCall = false,
        coordinateFloor = null;
}

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

/// Scripted navigation backend that records every routing request.
class _ScriptedNavigationRepository implements NavigationRepository {
  final List<_RecordedRouteCall> calls = [];

  NavigationRouteModel Function(
    double lat,
    double lon,
    String floorNumber,
    String destinationPuid,
  )? onCoordinateRoute;
  NavigationRouteModel Function(String fromPuid, String toPuid)? onPoiRoute;

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async {
    calls.add(_RecordedRouteCall.coordinate(floorNumber));
    final handler = onCoordinateRoute;
    if (handler == null) {
      throw const ApiException('No route found', statusCode: 400);
    }
    return handler(latitude, longitude, floorNumber, destinationPuid);
  }

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async {
    calls.add(_RecordedRouteCall.pois(fromPuid, toPuid));
    final handler = onPoiRoute;
    if (handler == null) {
      throw const ApiException('No route found', statusCode: 400);
    }
    return handler(fromPuid, toPuid);
  }
}

NavigationRouteModel _routeOf(List<PoiModel> pois, {UserLocation? prepend}) {
  final points = <NavigationRoutePoint>[
    if (prepend != null)
      NavigationRoutePoint(
        latitude: prepend.latitude,
        longitude: prepend.longitude,
        puid: '__position__',
        buid: _buid,
        floorNumber: '0',
        poisType: 'None',
      ),
    ...pois.map((p) => NavigationRoutePoint(
          latitude: p.latitude,
          longitude: p.longitude,
          puid: p.puid,
          buid: p.buid,
          floorNumber: p.floorNumber,
          poisType: p.poisType,
        )),
  ];
  return NavigationRouteModel(points: points);
}

class _Harness {
  late SpaceProvider spaceProvider;
  late LocationProvider locationProvider;
  late _ScriptedNavigationRepository navRepo;

  final space = const SpaceModel(
    buid: _buid,
    name: 'Tower',
    latitude: 30.0000,
    longitude: 32.0000,
  );
  late final FloorModel floor0;
  late final FloorModel floor2;

  late PoiModel connectorF0;
  late PoiModel connectorF2;
  late PoiModel destOnF2;
  late PoiModel roomOnF0;

  _Harness() {
    floor0 = FloorModel(buid: _buid, floorNumber: '0');
    floor2 = FloorModel(buid: _buid, floorNumber: '2');

    // Stacked stair shaft: ~1m apart horizontally across floors.
    connectorF0 = _poi(
      puid: 'conn_f0_stairA',
      floor: '0',
      type: 'None',
      lat: 30.00000,
      lon: 32.00000,
      name: 'Stair A',
    );
    connectorF2 = _poi(
      puid: 'conn_f2_stairA',
      floor: '2',
      type: 'None',
      lat: 30.00001,
      lon: 32.00001,
      name: 'Stair A',
    );
    destOnF2 = _poi(
      puid: 'poi_f2_dest',
      floor: '2',
      type: 'Office',
      lat: 30.0005,
      lon: 32.0005,
      name: 'Room 202',
    );
    roomOnF0 = _poi(
      puid: 'room_f0_near',
      floor: '0',
      type: 'Office',
      lat: 30.0004,
      lon: 31.9996,
      name: 'Room 001',
    );
  }

  /// Standard fixture: user GPS-grounded (effective floor '0'),
  /// destination POI selected on Floor 2.
  Future<void> pump({
    List<PoiModel>? floor0Pois,
    Map<String, List<PoiModel>>? extraFloors,
  }) async {
    locationProvider = LocationProvider(
      locationService: _StubLocationService(),
      nativePositioningService: _StubNativePositioningService(),
    );
    navRepo = _ScriptedNavigationRepository();

    spaceProvider = SpaceProvider(
      repository: _FakeSpaceRepository(space, [floor0, floor2]),
      radioMapRepository: _FakeRadioMapRepository(),
      floorplanRepository: _FakeFloorplanRepository(),
      poiRepository: _FakePoiRepository({
        '0': floor0Pois ?? [connectorF0, roomOnF0],
        '2': [connectorF2, destOnF2],
        ...?extraFloors,
      }),
      navigationRepository: navRepo,
    );
    spaceProvider.setLocationProvider(locationProvider);

    spaceProvider.selectSpace(space);
    await spaceProvider.loadFloorsForSelectedSpace();
    spaceProvider.selectFloor(floor0);
    await spaceProvider.loadPoisForSelectedFloor();

    locationProvider.setGpsLocation(UserLocation(
      latitude: 29.9998,
      longitude: 31.9998,
      accuracy: 5.0,
      timestamp: DateTime.now(),
    ));

    spaceProvider.selectPoi(destOnF2);
  }

  Future<void> requestRoute() => spaceProvider.requestRouteToSelectedPoi();

  void dispose() {
    spaceProvider.dispose();
    locationProvider.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(_Harness h) async {
    await pumpEventQueue();
    h.dispose();
  }

  test(
    'same-floor destination keeps legacy coordinate routing unchanged',
    () async {
      final h = _Harness();
      await h.pump();
      h.spaceProvider.selectPoi(h.roomOnF0);

      h.navRepo.onCoordinateRoute =
          (lat, lon, floorNumber, destinationPuid) {
        expect(floorNumber, '0');
        return _routeOf([h.connectorF0, h.roomOnF0]);
      };

      await h.requestRoute();

      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);
      expect(h.spaceProvider.activeNavigationRoute, isNotNull);
      final floors =
          h.spaceProvider.activeNavigationRoute!.points.map((p) => p.floorNumber).toSet();
      expect(floors, {'0'});

      await settle(h);
    },
  );

  test(
    'cross-floor route uses the USER floor for coordinate routing and stages connectors',
    () async {
      final h = _Harness();
      await h.pump();

      h.navRepo.onCoordinateRoute =
          (lat, lon, floorNumber, destinationPuid) {
        expect(destinationPuid, h.connectorF0.puid,
            reason: 'LEG 1 must target the origin-floor connector');
        return _routeOf([h.roomOnF0, h.connectorF0]);
      };
      h.navRepo.onPoiRoute = (fromPuid, toPuid) {
        if (fromPuid == h.connectorF0.puid && toPuid == h.connectorF2.puid) {
          return _routeOf([h.connectorF0, h.connectorF2]);
        }
        if (fromPuid == h.connectorF2.puid && toPuid == h.destOnF2.puid) {
          return _routeOf([h.connectorF2, h.destOnF2]);
        }
        throw const ApiException('no edge', statusCode: 400);
      };

      await h.requestRoute();

      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);
      final route = h.spaceProvider.activeNavigationRoute!;
      expect(route.hasRenderablePath, isTrue);

      final puids = route.points.map((p) => p.puid).toList();
      expect(puids, contains(h.connectorF0.puid));
      expect(puids, contains(h.connectorF2.puid));
      expect(puids, contains(h.destOnF2.puid));

      expect(route.floorsInOrder, ['0', '2'],
          reason: 'floor numbers must be preserved along the stitched route');
      expect(route.points.first.floorNumber, '0');
      expect(route.hasFloorTransitions, isTrue);
      expect(route.nextFloorFrom('0'), '2');

      final coordCalls =
          h.navRepo.calls.where((c) => c.isCoordinateCall).toList();
      expect(coordCalls, hasLength(1));
      expect(coordCalls.single.coordinateFloor, '0',
          reason: 'coordinates must be routed on the USER floor, '
              'never the destination floor');

      await settle(h);
    },
  );

  test(
    'cross-floor route does NOT start at the nearest POI on the destination floor',
    () async {
      final h = _Harness();
      await h.pump();

      h.navRepo.onCoordinateRoute =
          (lat, lon, floorNumber, destinationPuid) {
        return _routeOf([h.roomOnF0, h.connectorF0]);
      };
      h.navRepo.onPoiRoute = (fromPuid, toPuid) {
        if (fromPuid == h.connectorF0.puid && toPuid == h.connectorF2.puid) {
          return _routeOf([h.connectorF0, h.connectorF2]);
        }
        if (fromPuid == h.connectorF2.puid && toPuid == h.destOnF2.puid) {
          return _routeOf([h.connectorF2, h.destOnF2]);
        }
        throw const ApiException('no edge', statusCode: 400);
      };

      await h.requestRoute();

      final route = h.spaceProvider.activeNavigationRoute!;
      final destinationFloorPuids = {h.connectorF2.puid, h.destOnF2.puid};
      expect(
        destinationFloorPuids.contains(route.points.first.puid),
        isFalse,
        reason: 'route must not begin on Floor 2; it begins on Floor 0',
      );
      expect(route.points.first.floorNumber, '0');
      expect(
        route.points.last.puid,
        h.destOnF2.puid,
        reason: 'the last point must be the requested destination POI',
      );

      await settle(h);
    },
  );

  test(
    'missing connectors fail cleanly without fabricating a direct route',
    () async {
      final h = _Harness();
      // Floor 0 has rooms only — no vertical connectors at all.
      await h.pump(floor0Pois: [h.roomOnF0]);

      await h.requestRoute();

      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.error);
      expect(h.spaceProvider.activeNavigationRoute, isNull,
          reason: 'must not silently produce a wrong-floor direct route');
      expect(h.spaceProvider.navigationRouteErrorMessage, isNotNull);
      expect(
        h.spaceProvider.navigationRouteErrorMessage!.toLowerCase(),
        contains('connector'),
      );

      expect(h.navRepo.calls.where((c) => c.isCoordinateCall), isEmpty,
          reason: 'no coordinate routing may be attempted when no connector exists');

      await settle(h);
    },
  );
}

class _StubLocationService implements LocationService {
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

class _StubNativePositioningService implements NativePositioningService {
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
