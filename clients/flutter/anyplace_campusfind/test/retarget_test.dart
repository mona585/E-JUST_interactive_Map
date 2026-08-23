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
// PHASE 4 — Route Lifecycle & Destination-Change Protocol (BUG-3, BUG-8)
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    );

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.8650,
      longitude: _lng,
    );

FloorModel _floor(String n) => FloorModel(buid: 'b1', floorNumber: n);

PoiModel _poi(String puid, double lat, {String floor = '0'}) => PoiModel(
      puid: puid,
      buid: 'b1',
      floorNumber: floor,
      name: 'POI $puid',
      poisType: 'room',
      latitude: lat,
      longitude: _lng,
    );

NavigationRouteModel _routeTo(double endLat) =>
    NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.9000, longitude: _lng),
      NavigationRoutePoint(
          latitude: endLat,
          longitude: _lng,
          puid: endLat == 30.8500 ? 'poiB' : 'poiA',
          buid: 'b1',
          floorNumber: '0',
          poisType: 'room'),
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

/// Serves a route whose endpoint matches the requested destination.
class _DestRepo implements NavigationRepository {
  final requestedDestinationPuids = <String>[];
  Completer<NavigationRouteModel>? gate;

  void holdNext() => gate = Completer<NavigationRouteModel>();

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
    String? floorNumber,
    required String destinationPuid,
  }) async {
    requestedDestinationPuids.add(destinationPuid);
    final g = gate;
    if (g != null) return g.future;
    return _routeTo(destinationPuid == 'poiB' ? 30.8500 : 30.8700);
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
  final List<FloorModel> floors = [_floor('0')];
  @override
  final List<PoiModel> pois;
  @override
  bool get hasPois => pois.isNotEmpty;
  @override
  FloorplanModel? activeFloorplan;
  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  _Scope(this.pois);

  PoiModel? lastRetarget;

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
  Future<bool> requestRouteForRetarget(PoiModel target) async {
    lastRetarget = target;
    // Mirrors the cascade contract: commits the new geometry write-through.
    activeNavigationRoute = _routeTo(target.puid == 'poiB' ? 30.8500 : 30.8700);
    notifyListeners();
    return true;
  }

  @override
  Future<NavigationRouteModel?> requestIndoorRouteForSession({
    required String destinationPuid,
    required String confirmedBuid,
    required String confirmedFloor,
  }) async =>
      null;

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

class _Harness {
  final gpsService = _FakeGpsService();
  final native = _FakeNative();
  final repo = _DestRepo();
  late final _Scope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness() {
    scope = _Scope([
      _poi('poiA', 30.8700),
      _poi('poiB', 30.8500),
    ]);
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _routeTo(30.8700);
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

  void startOutdoor() {
    provider.setGpsLocation(_gps(30.9000));
    controller.startRoutePreview(
      destinationPuid: 'poiA',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('retarget mid-outdoor: new session id, new polyline, reroutes '
      'and arrival target B; old-session results are dead', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoor();
    final sidA = h.controller.sessionId!;

    // An A-reroute is left pending across the retarget.
    h.repo.holdNext();
    // PHASE 6 hysteresis: two consecutive off-route ticks fire the reroute.
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();

    final ok = await h.controller.retargetDestination(_poi('poiB', 30.8500));

    expect(ok, isTrue);
    expect(h.scope.lastRetarget?.puid, 'poiB');
    expect(h.controller.sessionId, isNotNull);
    expect(h.controller.sessionId, isNot(sidA),
        reason: 'retarget replaces the session wholesale');
    expect(h.controller.destinationPuid, 'poiB');
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    // The new geometry is committed and visible.
    expect(h.scope.activeNavigationRoute!.points.last.puid, 'poiB');
    expect(h.controller.activeRoute, same(h.scope.activeNavigationRoute));

    // Release the OLD session's pending result: it must be dropped silently.
    h.repo.gate?.complete(_routeTo(30.8700));
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedDestinationPuids, everyElement('poiA'),
        reason: 'only the pre-retarget request was made so far');
    expect(h.scope.activeNavigationRoute!.points.last.puid, 'poiB',
        reason: 'the stale A-result never overwrites the B commit');

    // En-route rerouting now targets B (cooldown expired on the fake clock).
    now = now.add(const Duration(seconds: 16));
    h.provider.setGpsLocation(_gps(30.9800));
    h.provider.setGpsLocation(_gps(30.9800));
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedDestinationPuids.last, 'poiB',
        reason: 'reroute after retarget must target the NEW destination');

    // Arrival anchor resolves B: two ticks near B arrive at poiB.
    h.provider.setGpsLocation(_gps(30.8500));
    await tester.pump();
    h.provider.setGpsLocation(_gps(30.8500));
    await tester.pump();
    expect(h.controller.isArrived, isTrue);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('retarget during REROUTING overlay: pending old result is '
      'discarded and the activity restores', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    h.repo.holdNext();
    // PHASE 6 hysteresis: two consecutive off-route ticks fire the reroute.
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    expect(h.controller.isRerouting, isTrue);

    final ok = await h.controller.retargetDestination(_poi('poiB', 30.8500));
    expect(ok, isTrue);

    // Old gated result lands AFTER the retarget completed.
    h.repo.gate?.complete(_routeTo(30.8700));
    await tester.pump();
    await tester.pump();

    expect(h.controller.isRerouting, isFalse);
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.scope.activeNavigationRoute!.points.last.puid, 'poiB',
        reason: 'the stale A-result never overwrites the B commit');
    expect(h.controller.destinationPuid, 'poiB');
  });

  testWidgets('closing a preview leaves zero route residue (BUG-8)',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.provider.setGpsLocation(_gps(30.9000));
    h.controller.startRoutePreview(
      destinationPuid: 'poiA',
      destinationSpace: _building(),
    );
    expect(h.controller.isPreview, isTrue);
    expect(h.scope.activeNavigationRoute, isNotNull);

    // Bottom-sheet onClose pairing: clearSelectedPoi + endNavigation. The
    // fake scope has no POI selection field, so only the teardown matters
    // for the residue assertion.
    h.controller.endNavigation();

    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.scope.activeNavigationRoute, isNull,
        reason: 'canonical teardown clears the store - no ghost preview');
    expect(h.controller.activeRoute, isNull);
  });
}
