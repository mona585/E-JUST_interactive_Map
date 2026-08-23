import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/cross_building_router.dart';
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
  final List<SpaceModel> spaces;
  final List<FloorModel> floors;
  _FakeSpaceRepository(this.spaces, this.floors);

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    for (final s in spaces) {
      if (s.buid == buid) return s;
    }
    return null;
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      floors;
}

/// Records whether CrossBuildingRouter.composeRoute is consulted and what it
/// is asked for. Returns [routeToReturn] when set, otherwise null.
class _SpyCrossBuildingRouter extends CrossBuildingRouter {
  final List<({LatLng userLocation, String targetBuid, String? targetPuid})>
      calls = [];
  NavigationRouteModel? routeToReturn;

  _SpyCrossBuildingRouter() : super(
          isPositionInBuilding: (_, _) => false,
          loadPois: (_, _) async => const [],
          loadFloorNumbers: (_) async => const [],
        );

  @override
  Future<NavigationRouteModel?> composeRoute({
    required LatLng userLocation,
    required SpaceModel targetSpace,
    required List<SpaceModel> allBuildings,
    String? targetPuid,
  }) async {
    calls.add((
      userLocation: userLocation,
      targetBuid: targetSpace.buid,
      targetPuid: targetPuid,
    ));
    return routeToReturn;
  }
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
  _SpyCrossBuildingRouter? crossBuildingSpy;

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
  late PoiModel entranceF0;

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
    entranceF0 = _poi(
      puid: 'poi_entrance_f0',
      floor: '0',
      type: 'Entrance',
      lat: 30.00006,
      lon: 32.00002,
      name: 'Entrance',
    );
  }

  /// Standard fixture: user GPS-grounded (effective floor '0'),
  /// destination POI selected on Floor 2.
  Future<void> pump({
    List<PoiModel>? floor0Pois,
    Map<String, List<PoiModel>>? extraFloors,
    double userLatitude = 29.9998,
    double userLongitude = 31.9998,
    List<SpaceModel>? allSpaces,
    _SpyCrossBuildingRouter? spyRouter,
  }) async {
    locationProvider = LocationProvider(
      locationService: _StubLocationService(),
      nativePositioningService: _StubNativePositioningService(),
    );
    navRepo = _ScriptedNavigationRepository();
    crossBuildingSpy = spyRouter;

    spaceProvider = SpaceProvider(
      repository: _FakeSpaceRepository(
        allSpaces ?? [space],
        [floor0, floor2],
      ),
      radioMapRepository: _FakeRadioMapRepository(),
      floorplanRepository: _FakeFloorplanRepository(),
      poiRepository: _FakePoiRepository({
        '0': floor0Pois ?? [connectorF0, roomOnF0, entranceF0],
        '2': [connectorF2, destOnF2],
        ...?extraFloors,
      }),
      navigationRepository: navRepo,
      crossBuildingRouter: spyRouter,
    );
    spaceProvider.setLocationProvider(locationProvider);

    await spaceProvider.loadSpaces();

    spaceProvider.selectSpace(space);
    await spaceProvider.loadFloorsForSelectedSpace();
    spaceProvider.selectFloor(floor0);
    await spaceProvider.loadPoisForSelectedFloor();

    locationProvider.setGpsLocation(UserLocation(
      latitude: userLatitude,
      longitude: userLongitude,
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

  test(
    'staged cross-floor route prepends an outdoor leg ending at the building entrance',
    () async {
      final spy = _SpyCrossBuildingRouter();
      final h = _Harness();
      await h.pump(
        userLatitude: 30.0100,
        userLongitude: 32.0100,
        spyRouter: spy,
      );

      h.navRepo.onCoordinateRoute = (lat, lon, floorNumber, destinationPuid) {
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
      final puids = route.points.map((p) => p.puid).toList();

      expect(puids.first, startsWith('__outdoor_'),
          reason: 'the journey must begin with outdoor geometry from the GPS fix');
      expect(puids, contains(h.entranceF0.puid),
          reason: 'the outdoor leg must terminate at the entrance POI');
      expect(
        puids.indexOf(h.entranceF0.puid),
        lessThan(puids.indexOf(h.connectorF0.puid)),
        reason: 'entrance must precede the origin-floor stair',
      );
      expect(route.points.where((p) => p.isOutdoor), isNotEmpty);

      // Ordering of the full journey:
      // outdoor… → entrance → F0 stair → F1 stair → destination POI
      final order = [
        0, // first outdoor point
        puids.indexOf(h.entranceF0.puid),
        puids.indexOf(h.connectorF0.puid),
        puids.indexOf(h.connectorF2.puid),
        puids.indexOf(h.destOnF2.puid),
      ];
      final sorted = [...order]..sort();
      expect(order, sorted,
          reason: 'journey order must be outdoor → entrance → F0 conn → F1 conn → POI');

      await settle(h);
    },
  );

  test(
    'OUTSIDE user + Floor-1 destination: staged cross-floor routing wins over CrossBuildingRouter',
    () async {
      final spy = _SpyCrossBuildingRouter();
      final h = _Harness();
      // ~1.4 km from the target building — beyond the 100 m detection radius,
      // the exact geometry that previously pre-empted with composeRoute().
      await h.pump(
        userLatitude: 30.0100,
        userLongitude: 32.0100,
        spyRouter: spy,
      );

      h.navRepo.onCoordinateRoute =
          (lat, lon, floorNumber, destinationPuid) {
        expect(floorNumber, '0',
            reason: 'coordinates must be routed on the USER floor');
        expect(destinationPuid, h.connectorF0.puid);
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

      expect(spy.calls, isEmpty,
          reason: 'CrossBuildingRouter must NOT run for a cross-floor trip '
              'to the target building');
      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);
      final route = h.spaceProvider.activeNavigationRoute!;
      expect(
        route.points.map((p) => p.puid),
        containsAll([h.connectorF0.puid, h.connectorF2.puid, h.destOnF2.puid]),
      );
      expect(route.floorsInOrder, ['0', '2']);

      await settle(h);
    },
  );

  test(
    'OUTSIDE user + SAME-FLOOR destination still uses CrossBuildingRouter',
    () async {
      final canned = NavigationRouteModel.fromSegments(
        segments: [
          RouteSegment.outdoor(
            points: const [
              LatLng(30.0010, 32.0010),
              LatLng(30.0005, 32.0005),
            ],
            buildingId: _buid,
          ),
        ],
        status: RouteModelStatus.ready,
      );
      final spy = _SpyCrossBuildingRouter()..routeToReturn = canned;
      final h = _Harness();
      await h.pump(userLatitude: 30.0100, userLongitude: 32.0100, spyRouter: spy);

      h.spaceProvider.selectPoi(h.roomOnF0);
      await h.requestRoute();

      expect(spy.calls, hasLength(1));
      expect(spy.calls.single.targetBuid, _buid);
      expect(spy.calls.single.targetPuid, h.roomOnF0.puid);
      expect(identical(h.spaceProvider.activeNavigationRoute, canned), isTrue,
          reason: 'composeRoute result must be adopted as before');
      expect(h.navRepo.calls, isEmpty,
          reason: 'cascade must not run after a successful composeRoute');
      expect(h.spaceProvider.navigationRouteStatus, NavigationRouteStatus.ready);

      await settle(h);
    },
  );

  test(
    'genuinely different building still routes via CrossBuildingRouter',
    () async {
      const otherBuilding = SpaceModel(
        buid: 'bldg_other_9',
        name: 'Other Building',
        latitude: 30.0060,
        longitude: 32.0060,
      );
      final canned = NavigationRouteModel.fromSegments(
        segments: [
          RouteSegment.outdoor(
            points: const [
              LatLng(30.0058, 32.0058),
              LatLng(30.0005, 32.0005),
            ],
            buildingId: _buid,
          ),
        ],
        status: RouteModelStatus.ready,
      );
      final spy = _SpyCrossBuildingRouter()..routeToReturn = canned;
      final h = _Harness();
      // User near the OTHER building (well inside its 100 m radius, far from
      // the target), destination POI on Floor 0 of the target building.
      await h.pump(
        allSpaces: [h.space, otherBuilding],
        userLatitude: 30.0062,
        userLongitude: 32.0062,
        spyRouter: spy,
      );

      h.spaceProvider.selectPoi(h.roomOnF0);
      await h.requestRoute();

      expect(spy.calls, hasLength(1));
      expect(spy.calls.single.targetBuid, _buid,
          reason: 'router must be pointed at the destination building');
      expect(identical(h.spaceProvider.activeNavigationRoute, canned), isTrue);
      expect(h.navRepo.calls, isEmpty);

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
