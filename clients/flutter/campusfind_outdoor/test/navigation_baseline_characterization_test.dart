import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/floorplan_model.dart';
import 'package:anyplace_campusfind/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/route_segment.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/repositories/space_repository.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/models/navigation_state.dart';
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';

// ============================================================================
// PHASE 0 CHARACTERIZATION SUITE
//
// These tests PIN today's known-broken behaviors (Master Plan BUG-1, BUG-2,
// BUG-4) so that every later phase must consciously flip them.
//
//   BUG-1 pins -> flip in Phase 2/3
//   BUG-2 pins -> flip in Phase 2
//   BUG-4 pins -> flip in Phase 7
// ============================================================================

const _lng = 29.5828;

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


class _SeedSpaceRepository implements SpaceRepository {
  List<SpaceModel> spaces = const [];
  Map<String, List<FloorModel>> floors = const {};

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.where((s) => s.buid == buid).firstOrNull;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      floors[buid] ?? const [];
}

class _SeedPoiRepository implements PoiRepository {
  Map<String, List<PoiModel>> pois = const {};

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      pois['${buid}_$floor'] ?? const [];

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}


class _SeedNavigationRepository implements NavigationRepository {
  /// Outdoor points served by the reroute request path (CP-8: the reroute
  /// request returns raw coordinates, not a composed route model).
  List<LatLng> replacementPoints = const [];

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      replacementPoints;

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      null;
}

// ---------------------------------------------------------------------------
// BUG-1 fixture: REAL SpaceViewModel + REAL LocationViewModel + controller,
// seeded offline through Strategy 1 of the initial route cascade.
// ---------------------------------------------------------------------------

SpaceModel _building(String buid, String name, double lat) => SpaceModel(
      buid: buid,
      name: name,
      latitude: lat,
      longitude: _lng,
      spaceType: 'building',
    );

FloorModel _floor(String buid, String n) =>
    FloorModel(buid: buid, floorNumber: n);

PoiModel _poi(String puid, String buid, String floor, String name) => PoiModel(
      puid: puid,
      buid: buid,
      floorNumber: floor,
      name: name,
      poisType: 'room',
      latitude: 30.8650,
      longitude: _lng,
    );

class _Bug1Fixture {
  final seedRepo = _SeedSpaceRepository();
  final poiRepo = _SeedPoiRepository();
  final navRepo = _SeedNavigationRepository();
  late final CacheService cache;
  late final SpaceViewModel spaceProvider;
  late final LocationViewModel locationProvider;
  NavigationViewModel? controller;

  static Future<_Bug1Fixture> build() async {
    SharedPreferences.setMockInitialValues({});
    final f = _Bug1Fixture();
    f.cache = CacheService();

    f.seedRepo.spaces = [
      _building('bA', 'Building A', 30.8650),
      _building('bB', 'Building B', 30.9100),
    ];
    f.seedRepo.floors = {
      'bA': [_floor('bA', '0'), _floor('bA', '1')],
      'bB': [_floor('bB', '0')],
    };
    f.poiRepo.pois = {
      'bA_0': [
        _poi('entr', 'bA', '0', 'Main Entrance'),
        _poi('room104', 'bA', '0', 'Room 104'),
        _poi('room105', 'bA', '0', 'Room 105'),
      ],
    };

    f.spaceProvider = SpaceViewModel(
      repository: f.seedRepo,
      poiRepository: f.poiRepo,
      navigationRepository: f.navRepo,
      cacheService: f.cache,
    );
    f.locationProvider = LocationViewModel(
      locationService: _FakeLocationService(),
    );
    f.spaceProvider.setLocationViewModel(f.locationProvider);
    // GPS believed. The destination building exposes no entrance/door POIs, so
    // outdoor-only composition degrades to a renderable straight-line partial
    // route — sufficient for the idle-parity reset assertions below.
    f.locationProvider.setGpsLocation(UserLocation(
      latitude: 30.8650,
      longitude: _lng,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));
    return f;
  }

  /// Drives browsing state to a selected POI and pulls an initial route.
  Future<void> seedRoute() async {
    await spaceProvider.loadSpaces();
    spaceProvider.selectSpace(seedRepo.spaces[0]);
    await spaceProvider.loadFloorsForSelectedSpace();
    spaceProvider.selectFloor(spaceProvider.floors.first);
    await spaceProvider.loadPoisForSelectedFloor();
    spaceProvider.selectPoi(poiRepo.pois['bA_0']!
        .where((p) => p.puid == 'room104')
        .first);
    await spaceProvider.requestRouteToSelectedPoi();
  }

  void startActiveNavigation() {
    controller = NavigationViewModel(
      spaceProvider: spaceProvider,
      locationProvider: locationProvider,
      navigationRepository: navRepo,
    );
    // PHASE 3 wiring: browsing APIs must stay neutral while this runs.
    spaceProvider.isNavigationSessionLive = () => controller!.isActive;
    spaceProvider.terminateActiveSessionForRetarget = () {};
    controller!.startRoutePreview(
      destinationPuid: 'room104',
      destinationSpace: seedRepo.spaces[0],
    );
    controller!.startActiveNavigation();
  }

  void dispose() {
    controller?.dispose();
    locationProvider.dispose();
  }
}

// ---------------------------------------------------------------------------
// BUG-2 fixture: fake NavigationRouteScope harness (controller level).
// ---------------------------------------------------------------------------

class _FakeScope extends ChangeNotifier implements NavigationRouteScope {
  @override
  NavigationRouteModel? activeNavigationRoute;
  @override
  FloorModel? selectedFloor;
  @override
  SpaceModel? selectedSpace;

  @override
  final List<FloorModel> floors;
  @override
  final List<PoiModel> pois = const [];

  _FakeScope({required this.floors});

  @override
  bool get hasPois => pois.isNotEmpty;

  @override
  FloorplanModel? activeFloorplan;

  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  @override
  void selectSpace(SpaceModel space) {
    selectedSpace = space;
    notifyListeners();
  }

  @override
  void selectFloor(FloorModel floor) {
    selectedFloor = floor;
    notifyListeners();
  }

  @override
  void clearSelection() {
    selectedSpace = null;
    selectedFloor = null;
    activeNavigationRoute = null;
    notifyListeners();
  }
  @override
  void selectFloorForNavigation(FloorModel floor) {
    selectedFloor = floor;
    notifyListeners();
  }

  @override
  void selectSpaceForNavigation(SpaceModel space) {
    selectedSpace = space;
    notifyListeners();
  }

  @override
  void releaseIndoorContextForNavigation() {
    activeFloorplan = null;
    notifyListeners();
  }

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    notifyListeners();
  }

  @override
  Future<bool> requestRouteForRetarget(PoiModel poi) async => true;
  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    notifyListeners();
  }
}

UserLocation _gpsAt(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

/// Collinear outdoor route along lng=_lng through every fixture latitude.
NavigationRouteModel _outdoorRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8750, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

/// A clearly different geometry served by the reroute stub.
final NavigationRouteModel _replacementRoute = NavigationRouteModel(points: [
  NavigationRoutePoint.outdoor(latitude: 30.8930, longitude: _lng + 0.004),
  NavigationRoutePoint.outdoor(latitude: 30.8650, longitude: _lng + 0.004),
]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // PHASE 3 FLIP of BUG-1: live-session neutrality is covered comprehensively
  // in test/browsing_neutrality_test.dart (route object, destination, session
  // id and revision preserved across all six browsing APIs). This group pins
  // the complementary, permanently-true half: WITHOUT a live session every
  // browsing API still resets navigation fields exactly as before Phase 3.
  group('CHARACTERIZATION BUG-1 (idle-parity half, permanent): browsing APIs '
      'still reset navigation fields when NO session is live', () {
    Future<_Bug1Fixture> seeded() async {
      final f = await _Bug1Fixture.build();
      await f.seedRoute();
      expect(f.spaceProvider.activeNavigationRoute, isNotNull);
      return f;
    }

    testWidgets('selectFloor resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.selectFloor(_floor('bA', '1'));
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('clearFloorSelection resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.clearFloorSelection();
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('selectSpace resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.selectSpace(f.seedRepo.spaces[1]);
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('clearSelection resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.clearSelection();
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('selectPoi (different POI) resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.selectPoi(f.poiRepo.pois['bA_0']!
          .where((p) => p.puid == 'room105')
          .first);
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });

    testWidgets('clearSelectedPoi resets the seeded route while idle',
        (tester) async {
      final f = await seeded();
      addTearDown(f.dispose);
      f.spaceProvider.clearSelectedPoi();
      expect(f.spaceProvider.activeNavigationRoute, isNull);
      await tester.pump(const Duration(seconds: 30));
    });
  });
testWidgets('PHASE 2 FLIP of BUG-2: a committed reroute reaches the '
    'rendered store atomically and later scope notifications can never '
    'revert it', (tester) async {
  final scope = _FakeScope(floors: [_floor('bA', '0')]);
  final buildingA = _building('bA', 'Building A', 30.8650);
  scope.selectedSpace = buildingA;
  scope.selectedFloor = _floor('bA', '0');
  scope.activeNavigationRoute = _outdoorRoute();
  final originalRoute = scope.activeNavigationRoute!;

  final provider = LocationViewModel(
    locationService: _FakeLocationService(),
  );
  final rerouteRepo = _SeedNavigationRepository()
    ..replacementPoints = [
      for (final p in _replacementRoute.points)
        LatLng(p.latitude, p.longitude),
    ];

  final controller = NavigationViewModel(
    spaceProvider: scope,
    locationProvider: provider,
    navigationRepository: rerouteRepo,
  );
  addTearDown(() {
    controller.dispose();
    provider.dispose();
  });

  provider.setGpsLocation(_gpsAt(30.8750));
  controller.startRoutePreview(
    destinationPuid: 'dest',
    destinationSpace: buildingA,
  );
  controller.startActiveNavigation();
  expect(controller.navigationState, NavigationState.activeOutdoor);
  expect(controller.activeRoute, same(originalRoute));

  // One far off-route tick pair (>15 m threshold) fires the reroute.
  provider.setGpsLocation(_gpsAt(30.8900));
  provider.setGpsLocation(_gpsAt(30.8900));
  await tester.pump();
  await tester.pump();

  expect(controller.isRerouting, isFalse);
  // THE FLIP: store and evaluation are one object — the rerouted geometry
  // is what the map renders (INV-1/INV-2/INV-6).
  final adopted = scope.activeNavigationRoute;
  expect(adopted, isNotNull);
  expect(controller.activeRoute, same(adopted),
      reason: 'store and evaluation are one object');
  expect(identical(adopted, originalRoute), isFalse,
      reason: 'a freshly composed outdoor route replaces the previous one');
  expect(scope.selectedFloor, isNotNull,
      reason: 'write-through touches nothing but the route');

  // No ping-pong: an unrelated scope notification cannot revert anything.
  scope.selectFloor(_floor('bA', '0'));
  await tester.pump();
  expect(controller.activeRoute, same(adopted),
      reason: 'with one store there is nothing to re-adopt');
});

// ---------------------------------------------------------------------------
// CHARACTERIZATION BUG-4 (flips in Phase 7): model-level metadata lies.
// ---------------------------------------------------------------------------

// PHASE 7 FLIP of BUG-4: the model now tells the truth.
// ---------------------------------------------------------------------------

group('PHASE 7 FLIP of BUG-4: outdoor points are identity-free and '
    'outdoor-ness is derived, never stamped', () {
  test('NavigationRoutePoint.outdoor carries NO building/floor identity', () {
    final p = NavigationRoutePoint.outdoor(latitude: 30.87,
      longitude: _lng);
    expect(p.isOutdoor, isTrue);
    expect(p.buid, '',
        reason: 'INV-7: isOutdoor => no building id');
    expect(p.floorNumber, '',
        reason: 'INV-7: isOutdoor => no floor');
  });

  test('fromJson derives isOutdoor from pois_type / synthetic puid', () {
    final route = NavigationRouteModel.fromJson(const {
      'pois': [
        {
          'puid': 'a',
          'lat': '30.0',
          'lon': '29.5',
          'buid': 'bX',
          'floor_number': '2',
          'pois_type': 'None',
        },
        {
          'puid': '__outdoor__',
          'lat': '30.001',
          'lon': '29.5',
          'buid': 'bX',
          'floor_number': '0',
          'pois_type': 'outdoor',
        },
      ],
    });
    expect(route.points, hasLength(2));
    expect(route.points[0].isOutdoor, isFalse,
        reason: 'server POI waypoints stay indoor-flagged with real ids');
    expect(route.points[1].isOutdoor, isTrue,
        reason: 'outdoor markers are honored');
    expect(route.hasOutdoorSegment, isTrue);
  });

  test("derived points do NOT fabricate transitions at '' boundaries", () {
    final route = NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.outdoor(points: const [
          LatLng(30.0, 29.5),
          LatLng(30.0005, 29.5),
        ], buildingId: 'bX'),
        RouteSegment.indoor(
          points: const [LatLng(30.001, 29.5)],
          buildingId: 'bX',
          floorNumber: '0',
        ),
      ],
      status: RouteModelStatus.ready,
    );
    expect(route.points.first.floorNumber, '');
    expect(route.floorTransitionIndices, isEmpty,
        reason: "the '' <-> '0' boundary is an entrance boundary, "
            'not a floor transition');
  });
});

}
