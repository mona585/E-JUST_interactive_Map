import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/floorplan_model.dart';
import 'package:anyplace_campusfind/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/models/navigation_state.dart';
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';

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


/// Serves an outdoor route whose endpoint is the REQUESTED destination
/// coordinate (CP-8: the reroute destination is the destination building's
/// [SpaceModel.latLng], not a POI id).
class _DestRepo implements NavigationRepository {
  final requestedToLats = <double>[];
  final requestedToLons = <double>[];
  Completer<List<LatLng>>? gate;

  void holdNext() => gate = Completer<List<LatLng>>();

  /// Completes the held request and restores normal serving.
  void release(List<LatLng> points) {
    gate?.complete(points);
    gate = null;
  }

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    requestedToLats.add(toLat);
    requestedToLons.add(toLon);
    final g = gate;
    if (g != null) {
      final points = await g.future;
      if (points.length < 2) throw Exception('stub: no route');
      return points;
    }
    return [const LatLng(30.9000, _lng), LatLng(toLat, _lng)];
  }

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      null;
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
  final repo = _DestRepo();
  late final _Scope scope;
  late final LocationViewModel provider;
  late final NavigationViewModel controller;

  _Harness() {
    scope = _Scope([
      _poi('poiA', 30.8700),
      _poi('poiB', 30.8500),
    ]);
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _routeTo(30.8700);
    provider = LocationViewModel(
      locationService: gpsService,
    );
    controller = NavigationViewModel(
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
    h.repo.release(const [
      LatLng(30.9000, _lng),
      LatLng(30.8700, _lng),
    ]);
    await tester.pump();
    await tester.pump();
    // CP-8: the reroute destination is the destination BUILDING's coordinate
    // (both POIs live in building b1), never a POI-specific point.
    expect(h.repo.requestedToLats, everyElement(30.8650));
    expect(h.scope.activeNavigationRoute!.points.last.puid, 'poiB',
        reason: 'the stale A-result never overwrites the B commit');

    // En-route rerouting now targets the retargeted session's destination.
    now = now.add(const Duration(seconds: 16));
    h.provider.setGpsLocation(_gps(30.9800));
    h.provider.setGpsLocation(_gps(30.9800));
    await tester.pump();
    await tester.pump();
    expect(h.repo.requestedToLats.last, 30.8650,
        reason: 'reroute after retarget must target the NEW destination');

    // The retargeted session delivers the user to the NEW destination building.
    // CP-8: the outdoor route ends at the destination building's outdoor
    // entrance, so reaching it begins the verified entry handoff (rather than a
    // bare outdoor arrival).
    h.provider.setGpsLocation(_gps(30.8650));
    await tester.pump();
    expect(
      h.controller.navigationState,
      anyOf(NavigationState.enteringBuilding, NavigationState.arrived),
      reason: 'the retargeted session reaches the new destination building',
    );
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
    h.repo.release(const [
      LatLng(30.9000, _lng),
      LatLng(30.8700, _lng),
    ]);
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
