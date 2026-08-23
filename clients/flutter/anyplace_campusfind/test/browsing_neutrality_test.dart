import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

// ---------------------------------------------------------------------------
// PHASE 3 — Browsing/Navigation Separation (INV-4, INV-5)
//
// With a LIVE session, none of the six browsing APIs may mutate the route
// object, destination identity, session id, or revision — while browsing
// state itself still changes. Idle-parity (legacy resets) is pinned in
// navigation_baseline_characterization_test.dart.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

class _GpsService implements LocationService {
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

class _Native implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(String text, String buid, String floor,
          {void Function(String detail)? onFailureDetail}) async =>
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

class _Spaces implements SpaceRepository {
  List<SpaceModel> spaces = const [];
  Map<String, List<FloorModel>> floors = const {};
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;
  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.where((s) => s.buid == buid).firstOrNull;
  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid,
          {bool forceReload = false}) async =>
      floors[buid] ?? const [];
}

class _Pois implements PoiRepository {
  Map<String, List<PoiModel>> pois = const {};
  @override
  Future<List<PoiModel>> getPoisByFloor(String buid, String floor,
          {bool forceReload = false}) async =>
      pois['${buid}_$floor'] ?? const [];
  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;
  @override
  Future<void> clearPois(String buid, String floor) async {}
  @override
  Future<void> clearAll() async {}
}

class _RadioMaps implements RadioMapRepository {
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

class _Floorplans implements FloorplanRepository {
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

class _NavRepo implements NavigationRepository {
  late NavigationRouteModel coordinateRoute;
  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async =>
      coordinateRoute;
  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async =>
      coordinateRoute;
}

SpaceModel _building(String buid, String name, double lat) => SpaceModel(
      buid: buid,
      name: name,
      latitude: lat,
      longitude: _lng,
      spaceType: 'building',
    );

FloorModel _floorOf(String buid, String n) =>
    FloorModel(buid: buid, floorNumber: n);

PoiModel _poi(String puid, String name) => PoiModel(
      puid: puid,
      buid: 'bA',
      floorNumber: '0',
      name: name,
      poisType: 'room',
      latitude: 30.8650,
      longitude: _lng,
    );

/// Live-session harness over the REAL SpaceProvider cascade.
class _LiveFixture {
  late final SpaceProvider sp;
  late final NavigationController nc;
  late final LocationProvider lp;
  late final _Spaces spaces;

  static Future<_LiveFixture> start() async {
    SharedPreferences.setMockInitialValues({});
    final f = _LiveFixture();
    f.spaces = _Spaces()
      ..spaces = [
        _building('bA', 'Building A', 30.8650),
        _building('bB', 'Building B', 30.9100),
      ]
      ..floors = {
        'bA': [_floorOf('bA', '0'), _floorOf('bA', '1')],
        'bB': [_floorOf('bB', '0')],
      };
    final pois = _Pois()
      ..pois = {
        'bA_0': [
          _poi('room104', 'Room 104'),
          _poi('room105', 'Room 105'),
        ],
      };
    final nav = _NavRepo()
      ..coordinateRoute = NavigationRouteModel(points: [
        NavigationRoutePoint(
            latitude: 30.8651,
            longitude: _lng,
            puid: 'p1',
            buid: 'bA',
            floorNumber: '0',
            poisType: 'None'),
        NavigationRoutePoint(
            latitude: 30.8650,
            longitude: _lng,
            puid: 'room104',
            buid: 'bA',
            floorNumber: '0',
            poisType: 'room'),
      ]);

    f.sp = SpaceProvider(
      repository: f.spaces,
      poiRepository: pois,
      radioMapRepository: _RadioMaps(),
      floorplanRepository: _Floorplans(),
      navigationRepository: nav,
      nativePositioningService: _Native(),
      cacheService: CacheService(),
    );
    final lp = LocationProvider(
      locationService: _GpsService(),
      nativePositioningService: _Native(),
    );
    f.lp = lp;
    f.sp.setLocationProvider(lp);
    lp.setGpsLocation(UserLocation(
      latitude: 30.8650,
      longitude: _lng,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));

    await f.sp.loadSpaces();
    f.sp.selectSpace(f.spaces.spaces[0]);
    await f.sp.loadFloorsForSelectedSpace();
    f.sp.selectFloor(f.sp.floors.first);
    await f.sp.loadPoisForSelectedFloor();
    f.sp.selectPoi(pois.pois['bA_0']!.first);

    await f.sp.requestRouteToSelectedPoi();

    f.nc = NavigationController(
      spaceProvider: f.sp,
      locationProvider: lp,
      navigationRepository: nav,
    );
    f.sp.isNavigationSessionLive = () => f.nc.isActive;
    f.sp.terminateActiveSessionForRetarget = () {};
    f.nc.startRoutePreview(
      destinationPuid: 'room104',
      destinationSpace: f.spaces.spaces[0],
    );
    f.nc.startActiveNavigation();
    return f;
  }

  void dispose() {
    nc.dispose();
    lp.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Runs [action] against a live activeOutdoor session and asserts every
  /// INV-4 invariant survives it.
  Future<void> expectNeutral(
    WidgetTester tester,
    _LiveFixture f,
    void Function() action,
  ) async {
    final route = f.sp.activeNavigationRoute!;
    final sid = f.nc.sessionId!;
    final rev = f.nc.sessionForTest!.routeRevision;

    action();

    expect(f.sp.activeNavigationRoute, same(route),
        reason: 'INV-4: the rendered route object must survive browsing');
    expect(f.nc.isActive, isTrue, reason: 'the session must stay live');
    expect(f.nc.sessionId, sid, reason: 'session identity is immutable');
    expect(f.nc.sessionForTest!.routeRevision, rev,
        reason: 'revisions only move on committed replacements');
    expect(f.nc.destinationPuid, 'room104');
  }

  testWidgets('INV-4: all six browsing APIs are neutral during a live '
      'session', (tester) async {
    // selectFloor
    var f = await _LiveFixture.start();
    addTearDown(f.dispose);
    await expectNeutral(tester, f,
        () => f.sp.selectFloor(_floorOf('bA', '1')));
    expect(f.sp.selectedFloor?.floorNumber, '1',
        reason: 'browsing itself still works');

    // clearFloorSelection
    f = await _LiveFixture.start();
    addTearDown(f.dispose);
    await expectNeutral(tester, f, () => f.sp.clearFloorSelection());

    // selectSpace (other building)
    f = await _LiveFixture.start();
    addTearDown(f.dispose);
    await expectNeutral(
        tester, f, () => f.sp.selectSpace(f.spaces.spaces[1]));
    expect(f.sp.selectedSpace?.buid, 'bB',
        reason: 'browsing another building still works');

    // clearSelection
    f = await _LiveFixture.start();
    addTearDown(f.dispose);
    await expectNeutral(tester, f, () => f.sp.clearSelection());

    // selectPoi (different POI)
    f = await _LiveFixture.start();
    addTearDown(f.dispose);
    final other = f.sp.pois.where((p) => p.puid == 'room105').first;
    await expectNeutral(tester, f, () => f.sp.selectPoi(other));
    expect(f.sp.selectedPoi?.puid, 'room105');

    // clearSelectedPoi
    f = await _LiveFixture.start();
    addTearDown(f.dispose);
    await expectNeutral(tester, f, () => f.sp.clearSelectedPoi());

    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('INV-5: navigation-driven selection variants preserve the '
      'route and are recorded distinctly', (tester) async {
    final f = await _LiveFixture.start();
    addTearDown(f.dispose);
    final route = f.sp.activeNavigationRoute!;

    f.sp.selectFloorForNavigation(_floorOf('bA', '1'));
    f.sp.selectSpaceForNavigation(_building('bB', 'Building B', 30.9100));

    expect(f.sp.activeNavigationRoute, same(route));
    expect(f.nc.isActive, isTrue);
    expect(f.sp.selectedSpace?.buid, 'bB');

    // Scoped release keeps the route too (route-safety half of INV-9).
    f.sp.releaseIndoorContextForNavigation();
    expect(f.sp.activeNavigationRoute, same(route));

    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('navigateToPoi during a live session uses the clean-restart '
      'bridge instead of silently destroying the run', (tester) async {
    final f = await _LiveFixture.start();
    addTearDown(f.dispose);
    var terminated = 0;
    final realEnd = f.nc.endNavigation;
    f.sp.terminateActiveSessionForRetarget = () {
      terminated++;
      realEnd();
    };

    final target = _poi('room105', 'Room 105');
    await f.sp.navigateToPoi(target);

    expect(terminated, 1,
        reason: 'the bridge ends the session exactly once, cleanly');
    expect(f.nc.navigationState, NavigationState.idle);
    await tester.pump(const Duration(seconds: 30));
  });
}
