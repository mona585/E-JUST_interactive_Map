import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';

// ---------------------------------------------------------------------------
// PHASE 1 — Navigation Session Identity & Lifecycle Contract
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.8650,
      longitude: _lng,
    );

FloorModel _floor(String n) => FloorModel(buid: 'b1', floorNumber: n);

PoiModel _destPoi() => PoiModel(
      puid: 'dest',
      buid: 'b1',
      floorNumber: '2',
      name: 'Destination Room',
      poisType: 'room',
      latitude: 30.8650,
      longitude: _lng,
    );

NavigationRouteModel _route() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(
          latitude: 30.8750, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8560, longitude: _lng, buid: 'b1', floorNumber: '0'),
    ]);

NavigationRouteModel _replacement() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(
          latitude: 30.8930, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8560, longitude: _lng, buid: 'b1', floorNumber: '0'),
    ]);

class _FakeGpsService implements LocationService {
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

class _FakeNative implements NativePositioningService {
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

class _GatedRepo implements NavigationRepository {
  NavigationRouteModel? served;
  Completer<NavigationRouteModel>? gate;
  int calls = 0;

  void holdNext() => gate = Completer<NavigationRouteModel>();

  void release(NavigationRouteModel route) {
    served = route;
    gate?.complete(route);
    gate = null;
  }

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async =>
      throw UnimplementedError();

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async {
    calls++;
    final g = gate;
    if (g != null) return g.future;
    return served ?? (throw Exception('stub: no route'));
  }
}

class _Scope extends ChangeNotifier implements NavigationRouteScope {
  @override
  NavigationRouteModel? activeNavigationRoute;
  @override
  FloorModel? selectedFloor;
  @override
  SpaceModel? selectedSpace;
  @override
  final List<FloorModel> floors;
  @override
  final List<PoiModel> pois;
  @override
  bool get hasPois => pois.isNotEmpty;
  @override
  FloorplanModel? activeFloorplan;
  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  _Scope({List<PoiModel>? pois})
      : floors = [_floor('0'), _floor('2')],
        pois = pois ?? const [];

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

  int adoptCalls = 0;

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    adoptCalls++;
    notifyListeners();
  }

  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    notifyListeners();
  }
}

class _Harness {
  final gpsService = _FakeGpsService();
  final native = _FakeNative();
  final repo = _GatedRepo();
  late final _Scope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness({List<PoiModel>? scopePois}) {
    scope = _Scope(pois: scopePois);
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _route();
    provider = LocationProvider(
      locationService: gpsService,
      nativePositioningService: native,
    );
    controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
      navigationRepository: repo,
    );
  }

  void dispose() {
    controller.dispose();
    provider.dispose();
  }

  void preview() {
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
  }

  void startOutdoor() {
    // A terminated session cleared the single store; every new run is
    // preceded by a fresh cascade seed (as in production).
    scope.activeNavigationRoute ??= _route();
    provider.setGpsLocation(_gps(30.8750));
    preview();
    controller.startActiveNavigation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a session is created at preview and destroyed by End',
      (tester) async {
    final h = _Harness(scopePois: [_destPoi()]);
    addTearDown(h.dispose);

    expect(h.controller.sessionId, isNull);
    expect(h.controller.destinationPuid, isNull);

    h.preview();
    expect(h.controller.sessionId, isNotNull);
    expect(h.controller.destinationPuid, 'dest');
    expect(h.controller.destinationSpace?.buid, 'b1');
    // Destination floor is derived from the POI now (BUG-15c closure).
    expect(h.controller.sessionForTest!.destinationFloorNumber, '2');
    expect(h.controller.sessionForTest!.routeRevision, 0,
        reason: 'preview seeding is NOT a controller write; revisions count '
            'committed replacements only');

    h.controller.endNavigation();
    expect(h.controller.sessionId, isNull);
    expect(h.controller.destinationPuid, isNull);
    await tester.pump();
  });

  testWidgets('session id stays stable across states; a new run gets a new '
      'identity', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    h.startOutdoor();
    final firstSid = h.controller.sessionId!;
    h.provider.setGpsLocation(_gps(30.8700));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.controller.sessionId, firstSid);

    h.controller.endNavigation();
    h.startOutdoor();
    expect(h.controller.sessionId, isNotNull);
    expect(h.controller.sessionId, isNot(firstSid),
        reason: 'every run must have its own identity');
    await tester.pump();
  });

  testWidgets('late reroute result of an ENDED session mutates nothing',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    h.repo.holdNext();
    h.provider.setGpsLocation(_gps(30.8900)); // off-route -> reroute pending
    await tester.pump();
    expect(h.controller.isRerouting, isTrue);

    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);

    h.repo.release(_replacement());
    await tester.pump();
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.controller.activeRoute, isNull);
    expect(h.scope.activeNavigationRoute, isNull,
        reason: 'PHASE 2: canonical teardown clears the single store, and '
            'the dead result must not resurrect it');
  });

  testWidgets('reroute result superseded by a revision bump commits nothing '
      'and restores the interrupted activity', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();
    final original = h.scope.activeNavigationRoute!;

    h.repo.holdNext();
    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    expect(h.controller.isRerouting, isTrue);

    h.controller.debugBumpRouteRevision();
    h.repo.release(_replacement());
    await tester.pump();
    await tester.pump();

    expect(h.controller.isRerouting, isFalse);
    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'a live session returns to its activity after discard');
    expect(h.controller.activeRoute, same(original),
        reason: 'the stale-geometry result never commits');
  });

  testWidgets('a guarded reroute consumes no cooldown; a real one does',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    // Pause via weak GPS (on-route so deviation cannot fire first).
    h.provider.setGpsLocation(_gps(30.8700, accuracy: 150));
    expect(h.controller.isPaused, isTrue);
    expect(h.controller.lastRerouteTimeForTest, isNull);

    // Guarded entry: paused is not a reroute origin — nothing is stamped.
    await h.controller.debugTriggerReroute();
    expect(h.controller.lastRerouteTimeForTest, isNull,
        reason: 'BUG-13: rejected/guarded transitions must not burn cooldown');

    // Recovery, then a real reroute stamps only after it begins.
    h.provider.setGpsLocation(_gps(30.8700, accuracy: 8));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    final replacement = _replacement();
    h.repo.served = replacement;
    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    await tester.pump();

    expect(h.controller.activeRoute, same(replacement));
    expect(h.controller.lastRerouteTimeForTest, isNotNull);
    expect(h.repo.calls, 1);

    // A further off-route tick inside the cooldown window is ignored.
    h.provider.setGpsLocation(_gps(30.8940));
    await tester.pump();
    await tester.pump();
    expect(h.repo.calls, 1,
        reason: 'cooldown suppresses immediate re-triggering');
  });
}
