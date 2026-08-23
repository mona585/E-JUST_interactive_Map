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
import 'package:anyplace_campusfind/state/space_provider.dart';

// ---------------------------------------------------------------------------
// PHASE 11 — Radiomap Lifecycle Contract
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

/// Records every destructive native-engine interaction.
class _RecordingNative implements NativePositioningService {
  int clearAllCalls = 0;
  final List<List<String>> targetedRemovals = [];

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor,
      {void Function(String detail)? onFailureDetail}) async =>
      true;

  @override
  Future<bool> clearRadioMap() async {
    clearAllCalls++;
    return true;
  }

  @override
  Future<bool> removeRadioMap(String buid, String floor) async {
    targetedRemovals.add([buid, floor]);
    return true;
  }

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

class _FailingRadiomaps implements RadioMapRepository {
  int fetches = 0;
  @override
  Future<String> getRadioMap(String buid, String floor,
          {bool forceReload = false}) async {
    fetches++;
    throw Exception('radiomap download failed');
  }

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;
  @override
  Future<void> clearRadioMap(String buid, String floor) async {}
  @override
  Future<void> clearAllCache() async {}
}

class _HealthyRadiomaps implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor,
          {bool forceReload = false}) async =>
      '<radiomap/>';

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
    String? floorNumber,
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

NavigationRouteModel _route() => NavigationRouteModel(points: [
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

class _Fixture {
  late final _Pois pois = _Pois();
  late final SpaceProvider sp;
  late final LocationProvider lp;
  late final _Spaces spaces;
  late final _RecordingNative native;
  NavigationController? nc;

  static Future<_Fixture> start({
    RadioMapRepository? radioRepo,
    bool withSession = true,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final f = _Fixture();
    f.native = _RecordingNative();
    f.spaces = _Spaces()
      ..spaces = [
        _building('bA', 'Building A', 30.8650),
        _building('bB', 'Building B', 30.9100),
      ]
      ..floors = {
        'bA': [_floorOf('bA', '0'), _floorOf('bA', '1')],
        'bB': [_floorOf('bB', '0')],
      };
    f.pois.pois = {
      'bA_0': [_poi('room104', 'Room 104')],
    };
    final nav = _NavRepo()..coordinateRoute = _route();

    f.sp = SpaceProvider(
      repository: f.spaces,
      poiRepository: f.pois,
      radioMapRepository: radioRepo ?? _HealthyRadiomaps(),
      floorplanRepository: _Floorplans(),
      navigationRepository: nav,
      nativePositioningService: f.native,
      cacheService: CacheService(),
    );
    f.lp = LocationProvider(
      locationService: _GpsService(),
      nativePositioningService: f.native,
    );
    f.sp.setLocationProvider(f.lp);
    f.lp.setGpsLocation(UserLocation(
      latitude: 30.8650,
      longitude: _lng,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));

    if (withSession) {
      await f._seed();
      f.nc = NavigationController(
        spaceProvider: f.sp,
        locationProvider: f.lp,
        navigationRepository: nav,
      );
      f.sp.isNavigationSessionLive = () => f.nc!.isActive;
      f.sp.terminateActiveSessionForRetarget = () {};
      f.nc!.startRoutePreview(
        destinationPuid: 'room104',
        destinationSpace: f.spaces.spaces[0],
      );
      f.nc!.startActiveNavigation();
    }
    return f;
  }

  Future<void> _seed() async {
    await sp.loadSpaces();
    sp.selectSpace(spaces.spaces[0]);
    await sp.loadFloorsForSelectedSpace();
    sp.selectFloor(sp.floors.first);
    await sp.loadPoisForSelectedFloor();
    sp.selectPoi(pois.pois['bA_0']!.first);
    await sp.requestRouteToSelectedPoi();
  }

  void dispose() {
    nc?.dispose();
    lp.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browsing selections during a live session never wipe the '
      "native engine's resident maps", (tester) async {
    final f = await _Fixture.start(withSession: true);
    addTearDown(f.dispose);
    expect(f.native.clearAllCalls, 0);

    // Heavy browsing churn while the session runs.
    f.sp.selectSpace(f.spaces.spaces[1]);
    await f.sp.loadFloorsForSelectedSpace();
    f.sp.selectFloor(f.sp.floors.first);
    f.sp.clearFloorSelection();
    f.sp.clearSelection();
    f.sp.selectSpace(f.spaces.spaces[0]);
    await tester.pump(const Duration(seconds: 1));

    expect(f.native.clearAllCalls, 0,
        reason: 'INV-9 / Phase 11: browsing may not sabotage navigation '
            'sensing');
    expect(f.native.targetedRemovals, isEmpty);
  });

  testWidgets('session End leaves residency to the LRU — no global wipe',
      (tester) async {
    final f = await _Fixture.start(withSession: true);
    addTearDown(f.dispose);

    f.nc!.endNavigation();
    await tester.pump(const Duration(seconds: 1));

    expect(f.native.clearAllCalls, 0,
        reason: 'End intentionally lets the native LRU manage residency');
  });

  testWidgets('resetAllRadiomaps is the only global wipe', (tester) async {
    final f = await _Fixture.start(withSession: false);
    addTearDown(f.dispose);

    f.sp.resetAllRadiomaps();
    await tester.pump();
    expect(f.native.clearAllCalls, 1);
  });

  testWidgets('a failed radiomap LOAD still evicts that map targetedly',
      (tester) async {
    final failing = _FailingRadiomaps();
    final f = await _Fixture.start(radioRepo: failing, withSession: false);
    addTearDown(f.dispose);

    await f.sp.loadSpaces();
    f.sp.selectSpace(f.spaces.spaces[0]);
    await f.sp.loadFloorsForSelectedSpace();
    f.sp.selectFloor(f.sp.floors.first); // triggers radiomap acquisition
    // Retry policy: initial attempt + 1 retry.
    await tester.pump(const Duration(seconds: 5));

    expect(failing.fetches, greaterThanOrEqualTo(1));
    expect(
      f.native.targetedRemovals
          .any((r) => r[0] == 'bA' && r[1] == '0'),
      isTrue,
      reason: 'targeted eviction on failure keeps other buildings intact',
    );
    expect(f.native.clearAllCalls, 0,
        reason: 'failure eviction must stay targeted');
  });
}
