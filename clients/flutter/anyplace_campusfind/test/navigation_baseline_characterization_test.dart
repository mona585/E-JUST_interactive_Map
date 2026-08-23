import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
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

class _SeedRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      '';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class _SeedFloorplanRepository implements FloorplanRepository {
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

class _SeedNavigationRepository implements NavigationRepository {
  NavigationRouteModel? coordinateRoute;

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async =>
      coordinateRoute ?? (throw Exception('stub: no route'));

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async =>
      coordinateRoute ?? (throw Exception('stub: no route'));
}

// ---------------------------------------------------------------------------
// BUG-1 fixture: REAL SpaceProvider + REAL LocationProvider + controller,
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

/// Renderable server-style route (Strategy 1 payload).
NavigationRouteModel _serverRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint(
        latitude: 30.8651,
        longitude: _lng,
        puid: 'p1',
        buid: 'bA',
        floorNumber: '0',
        poisType: 'None',
      ),
      NavigationRoutePoint(
        latitude: 30.8650,
        longitude: _lng,
        puid: 'room104',
        buid: 'bA',
        floorNumber: '0',
        poisType: 'room',
      ),
    ]);

class _Bug1Fixture {
  final seedRepo = _SeedSpaceRepository();
  final poiRepo = _SeedPoiRepository();
  final navRepo = _SeedNavigationRepository();
  late final CacheService cache;
  late final SpaceProvider spaceProvider;
  late final LocationProvider locationProvider;
  NavigationController? controller;

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
    f.navRepo.coordinateRoute = _serverRoute();

    f.spaceProvider = SpaceProvider(
      repository: f.seedRepo,
      poiRepository: f.poiRepo,
      radioMapRepository: _SeedRadioMapRepository(),
      floorplanRepository: _SeedFloorplanRepository(),
      navigationRepository: f.navRepo,
      nativePositioningService: _FakeNativePositioningService(),
      cacheService: f.cache,
    );
    f.locationProvider = LocationProvider(
      locationService: _FakeLocationService(),
      nativePositioningService: _FakeNativePositioningService(),
    );
    f.spaceProvider.setLocationProvider(f.locationProvider);
    // GPS believed and inside the destination-building radius (<100 m) so the
    // cross-building tier is skipped and Strategy 1 serves the seeded route.
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
    controller = NavigationController(
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
    selectedFloor = null;
    activeFloorplan = null;
    notifyListeners();
  }

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    notifyListeners();
  }

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
      NavigationRoutePoint.outdoor(
          latitude: 30.8750, longitude: _lng, buid: 'bA', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8560, longitude: _lng, buid: 'bA', floorNumber: '0'),
    ]);

/// A clearly different geometry served by the reroute stub.
final NavigationRouteModel _replacementRoute = NavigationRouteModel(points: [
  NavigationRoutePoint.outdoor(
      latitude: 30.8930, longitude: _lng + 0.004, buid: 'bA', floorNumber: '0'),
  NavigationRoutePoint.outdoor(
      latitude: 30.8650, longitude: _lng + 0.004, buid: 'bA', floorNumber: '0'),
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

  final provider = LocationProvider(
    locationService: _FakeLocationService(),
    nativePositioningService: _FakeNativePositioningService(),
  );
  final rerouteRepo = _SeedNavigationRepository()
    ..coordinateRoute = _replacementRoute;

  final controller = NavigationController(
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

  // One far off-route tick (>15 m threshold) fires the reroute.
  provider.setGpsLocation(_gpsAt(30.8900));
  await tester.pump();
  await tester.pump();

  expect(controller.isRerouting, isFalse);
  // THE FLIP: store and evaluation are one object — the rerouted geometry
  // is what the map renders (INV-1/INV-2/INV-6).
  expect(scope.activeNavigationRoute, same(_replacementRoute));
  expect(controller.activeRoute, same(_replacementRoute));
  expect(scope.selectedFloor, isNotNull,
      reason: 'write-through touches nothing but the route');

  // No ping-pong: an unrelated scope notification cannot revert anything.
  scope.selectFloor(_floor('bA', '0'));
  await tester.pump();
  expect(controller.activeRoute, same(_replacementRoute),
      reason: 'with one store there is nothing to re-adopt');
});

// ---------------------------------------------------------------------------
// CHARACTERIZATION BUG-4 (flips in Phase 7): model-level metadata lies.
// ---------------------------------------------------------------------------

group('CHARACTERIZATION BUG-4 (flips in Phase 7): outdoor points lie about '
    'identity at model level', () {
  test('NavigationRoutePoint.outdoor retains destination building/floor '
      'metadata instead of being identity-free', () {
    // The hybrid builders stamp the DESTINATION building+floor onto pure
    // GPS waypoints; the factory accepts and keeps the lie.
    final p = NavigationRoutePoint.outdoor(
      latitude: 30.87,
      longitude: _lng,
      buid: 'bDest',
      floorNumber: '2',
    );
    expect(p.isOutdoor, isTrue);
    expect(p.buid, 'bDest');
    expect(p.floorNumber, '2');
  });

  test('fromJson never derives isOutdoor from pois_type', () {
    final route = NavigationRouteModel.fromJson(const {
      'pois': [
        {
          'puid': 'a',
          'lat': '30.0',
          'lon': '29.5',
          'buid': 'bX',
          'floor_number': '',
          'pois_type': 'None',
        },
        {
          'puid': 'b',
          'lat': '30.001',
          'lon': '29.5',
          'buid': 'bY',
          'floor_number': '0',
          'pois_type': 'outdoor',
        },
      ],
    });
    expect(route.points.every((p) => p.isOutdoor), isFalse,
        reason: 'server-derived points are never outdoor-flagged today');
    expect(route.hasOutdoorSegment, isFalse);
  });

  test("derived points fabricate phantom transitions between '' and '0'",
      () {
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
    // Outdoor-derived points carry empty-string floors, so a boundary vs
    // the ground-floor indoor point is reported as a "floor transition".
    expect(route.floorTransitionIndices, isNotEmpty);
    final i = route.floorTransitionIndices.first;
    expect(route.points[i].floorNumber, '');
    expect(route.points[i + 1].floorNumber, '0');
  });
});

}
