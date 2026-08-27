import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/cross_building_router.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

// FORENSIC REMEDIATION REGRESSION TESTS
// Findings: OUTDOOR-001 (+PREVIEW-001), OUTDOOR-002 (+PREVIEW-002),
// OUTDOOR-005, ACTIVE-002.
//
// Semantic contract (master plan Â§12/Â§13):
//   CASE A: the outdoor leg terminates at the SELECTED DESTINATION ENTRANCE
//   and the indoor leg starts at that same entrance â€” never at room
//   coordinates, building center, or an arbitrary POI. Buildings without an
//   entrance record FAIL EXPLICITLY instead of inventing an anchor. All-tier
//   outdoor failure degrades VISIBLY while still anchoring on the entrance.

const _buidA = 'building_entrance_ok';
const _buidB = 'building_no_entrance';

SpaceModel _space(String buid) => SpaceModel(
      buid: buid,
      name: buid,
      // Distinct centroids so containment detection is unambiguous.
      latitude: buid == _buidA ? 30.0 : 30.05,
      longitude: 29.0,
    );

PoiModel _poi({
  required String puid,
  required String buid,
  required double lat,
  required String type,
  bool entrance = false,
}) {
  return PoiModel(
    puid: puid,
    buid: buid,
    floorNumber: '0',
    name: puid,
    poisType: type,
    latitude: lat,
    longitude: 29.0 + (lat - 30.0),
    isBuildingEntrance: entrance,
  );
}

class _FakeSpaceRepo implements SpaceRepository {
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      [_space(_buidA), _space(_buidB)];

  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid,
          {bool forceReload = false}) async =>
      [FloorModel(buid: buid, floorNumber: '0')];

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => _space(buid);
}

class _FakePoiRepo implements PoiRepository {
  final Map<String, List<PoiModel>> byBuid;
  _FakePoiRepo(this.byBuid);

  @override
  Future<List<PoiModel>> getPoisByFloor(String buid, String floorNumber,
      {bool forceReload = false}) async {
    return byBuid[buid] ?? const [];
  }

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeFloorplanRepo implements FloorplanRepository {
  @override
  Future<FloorplanModel?> getFloorplan(
      String buid, String floor, FloorModel floorMetadata,
      {bool forceReload = false}) async {
    return null;
  }

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;

  @override
  Future<void> clearFloorplan(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeNavRepo implements NavigationRepository {
  @override
  Future<NavigationRouteModel> getRouteBetweenPois(
      {required String fromPuid, required String toPuid}) async {
    // Indoor graph route anchored on whatever origin the cascade selected:
    // coordinates mirror the near entrance / target room fixture below.
    final fromLat = fromPuid == 'poi_entrance' ? 30.0005 : 30.0010;
    return NavigationRouteModel(points: [
      NavigationRoutePoint(
          latitude: fromLat,
          longitude: 29.0 + (fromLat - 30.0),
          puid: fromPuid,
          buid: _buidA,
          floorNumber: '0',
          poisType: 'Entrance'),
      NavigationRoutePoint(
          latitude: 30.0010,
          longitude: 29.0010,
          puid: toPuid,
          buid: _buidA,
          floorNumber: '0',
          poisType: 'Room'),
    ]);
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates(
      {required double latitude,
      required double longitude,
      String? floorNumber,
      required String destinationPuid}) async {
    throw ApiException('No route found between the requested locations.',
        statusCode: 400);
  }
}

class _FakeLocationService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<UserLocation?> getCurrentPosition() async => null;

  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) =>
      const Stream.empty();
}

class _FakeRadioMapRepo implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor,
      {bool forceReload = false}) async =>
      '# NaN -110\n# X, Y, HEADING, mac\n';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => true;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class _FakeNativePositioning implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(String text, String buid, String floor,
      {void Function(String detail)? onFailureDetail}) async {
    // Reject deterministically: mirrors a host without the native engine.
    onFailureDetail?.call('unavailable in tests');
    return false;
  }

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();
}

UserLocation _userInside() => UserLocation(
      // Inside building-A's 100 m containment circle: same-building cascade.
      latitude: 30.0001,
      longitude: 29.0001,
      accuracy: 5,
      timestamp: DateTime.now(),
    );

UserLocation _userOutside() => UserLocation(
      // Outside every containment circle: exercises the outdoor S3 path when
      // the cross-building router is unavailable (throwing stub below).
      latitude: 29.9950,
      longitude: 28.9950,
      accuracy: 5,
      timestamp: DateTime.now(),
    );

UserLocation _userInsideB() => UserLocation(
      latitude: 30.0501,
      longitude: 29.0001,
      accuracy: 5,
      timestamp: DateTime.now(),
    );

class _ThrowingRouter extends CrossBuildingRouter {
  _ThrowingRouter()
      : super(
          isPositionInBuilding: (_, __) => false,
          loadPois: (buid, floorNumber) async => <PoiModel>[],
          loadFloorNumbers: (buid) async => <String>[],
        );

  @override
  Future<NavigationRouteModel?> composeRoute({
    required LatLng userLocation,
    required SpaceModel targetSpace,
    required List<SpaceModel> allBuildings,
    String? targetPuid,
  }) async {
    throw ApiException('cross-building router unavailable', statusCode: 503);
  }
}

Future<SpaceProvider> _providerFor(Map<String, List<PoiModel>> pois,
    {UserLocation? user, CrossBuildingRouter? router}) async {
  final lp = LocationProvider(locationService: _FakeLocationService());
  lp.setGpsLocation(user ?? _userInside());
  final sp = SpaceProvider(
    repository: _FakeSpaceRepo(),
    radioMapRepository: _FakeRadioMapRepo(),
    floorplanRepository: _FakeFloorplanRepo(),
    poiRepository: _FakePoiRepo(pois),
    navigationRepository: _FakeNavRepo(),
    nativePositioningService: _FakeNativePositioning(),
    locationProvider: lp,
    crossBuildingRouterOverride: router,
  );
  await sp.loadSpaces();
  return sp;
}

Future<void> _selectPoiOnGroundFloor(SpaceProvider sp, PoiModel poi) async {
  final space = sp.spaces.firstWhere((s) => s.buid == poi.buid);
  sp.selectSpace(space);
  await sp.loadFloorsForSelectedSpace();
  sp.selectFloor(sp.floors.first);
  await sp.loadPoisForSelectedFloor();
  sp.selectPoi(poi);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final entrance = _poi(
      puid: 'poi_entrance',
      buid: _buidA,
      lat: 30.0005,
      type: 'Entrance',
      entrance: true);
  final farDoor = _poi(
      puid: 'poi_far_door',
      buid: _buidA,
      lat: 30.0090,
      type: 'Entrance',
      entrance: true);
  final room = _poi(puid: 'poi_room', buid: _buidA, lat: 30.0010, type: 'Room');
  final lonelyRoom =
      _poi(puid: 'poi_lonely', buid: _buidB, lat: 30.0020, type: 'Room');

  setUp(() {
    // OSRM echo: two-point path ending exactly at the requested terminus so
    // the outdoor anchor is observable per tier invocation.
    SpaceProvider.osrmWalkingRoute = ({
      required fromLat,
      required fromLon,
      required toLat,
      required toLon,
    }) async =>
        [
          LatLng(fromLat, fromLon),
          LatLng(toLat, toLon),
        ];
    SpaceProvider.osrmRouteWithMetadata = ({
      required fromLat,
      required fromLon,
      required toLat,
      required toLon,
    }) async =>
        null;
  });

  tearDown(() {
    SpaceProvider.osrmWalkingRoute =
        AnyplaceApiClient.fetchOutdoorWalkingRoute;
    SpaceProvider.osrmRouteWithMetadata =
        AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata;
  });

  test(
      'CASE B (user inside destination): S2 indoor route roots at the '
      'nearest graph POI and ends at the destination â€” no outdoor leg',
      () async {
    final sp = await _providerFor({
      _buidA: [farDoor, entrance, room],
    });

    await _selectPoiOnGroundFloor(sp, room);
    await sp.requestRouteToSelectedPoi();

    expect(sp.navigationRouteStatus, NavigationRouteStatus.ready);
    final route = sp.activeNavigationRoute!;
    expect(route.points.every((p) => !p.isOutdoor), isTrue);
    // Deterministic Â§14 origin: nearest loaded POI (entrance) to the fix.
    expect(route.points.first.puid, entrance.puid);
    expect(route.points.last.puid, room.puid);
  });

  test(
      'OUTDOOR-001/002: with the user OUTSIDE and the cross-building router '
      'unavailable, S3 anchors the outdoor tail on the NEAREST entrance, '
      'roots the indoor leg there, and never emits room coordinates as '
      'outdoor points',
      () async {
    final sp = await _providerFor(
      {
        _buidA: [farDoor, entrance, room], // far door first in load order
        _buidB: [lonelyRoom],
      },
      user: _userOutside(),
      router: _ThrowingRouter(),
    );

    await _selectPoiOnGroundFloor(sp, room);

    final model = await sp.requestRouteCandidateForRetarget(room);
    expect(model, isNotNull);
    final route = model!;

    final outdoor = route.points.where((p) => p.isOutdoor).toList();
    final indoor = route.points.where((p) => !p.isOutdoor).toList();

    // Nearest entrance wins despite load order favoring the far door.
    expect(outdoor.last.latitude, entrance.latitude);
    expect(outdoor.last.longitude, entrance.longitude);

    expect(indoor.first.puid, entrance.puid);
    expect(indoor.last.puid, room.puid);

    final roomAsOutdoor = outdoor.any(
        (p) => p.latitude == room.latitude && p.longitude == room.longitude);
    expect(roomAsOutdoor, isFalse,
        reason: 'outdoor leg must not terminate at room coordinates');
  });

  test(
      'OUTDOOR-001 fail-explicit: building with no entrance yields error '
      'status plus explanatory message instead of an invented anchor',
      () async {
    final sp = await _providerFor({_buidB: [lonelyRoom]}, user: _userInsideB());

    await _selectPoiOnGroundFloor(sp, lonelyRoom);
    await sp.requestRouteToSelectedPoi();


    expect(sp.navigationRouteStatus, NavigationRouteStatus.error);
    expect(sp.activeNavigationRoute, isNull);
    expect(sp.navigationRouteErrorMessage, contains('No building entrance'));
  });

  test(
      'OUTDOOR-005: all-tiers-failed degrades visibly but anchors the '
      'straight line on the entrance', () async {
    SpaceProvider.osrmWalkingRoute = ({
      required fromLat,
      required fromLon,
      required toLat,
      required toLon,
    }) async =>
        <LatLng>[];

    final sp = await _providerFor(
      {
        _buidA: [entrance, room],
        _buidB: [lonelyRoom],
      },
      user: _userOutside(),
      router: _ThrowingRouter(),
    );

    await _selectPoiOnGroundFloor(sp, room);
    await sp.requestRouteToSelectedPoi();

    expect(sp.navigationRouteStatus, NavigationRouteStatus.ready);
    expect(sp.navigationRouteErrorMessage, contains('direct line'));

    final route = sp.activeNavigationRoute!;
    final outdoor = route.points.where((p) => p.isOutdoor).toList();
    expect(outdoor.last.latitude, entrance.latitude);
    expect(outdoor.last.longitude, entrance.longitude);
  });

  test(
      'building flow: pure outdoor composition ends at the entrance and '
      'never appends a reversed indoor tail (OUTDOOR-001 variant S7)',
      () async {
    final sp = await _providerFor(
      {
        _buidA: [room, entrance],
        _buidB: [lonelyRoom],
      },
      user: _userOutside(),
      router: _ThrowingRouter(),
    );

    final space = sp.spaces.firstWhere((s) => s.buid == _buidA);
    sp.selectSpace(space);
    await sp.loadFloorsForSelectedSpace();
    sp.selectFloor(sp.floors.first);
    await sp.loadPoisForSelectedFloor();

    await sp.requestRouteToBuilding(space);

    expect(sp.navigationRouteStatus, NavigationRouteStatus.ready);
    final route = sp.activeNavigationRoute!;
    expect(route.points.every((p) => p.isOutdoor), isTrue,
        reason: 'no indoor leg may follow an outdoor arrival at the entrance');
    expect(route.points.last.latitude, entrance.latitude);
    expect(route.points.last.longitude, entrance.longitude);
  });
}
