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
import 'package:anyplace_campusfind/utils/navigation_display.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';

// ---------------------------------------------------------------------------
// PHASE 6 — Outdoor Rerouting Correctness (BUG-5, BUG-12; INV-6/INV-8)
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

NavigationRouteModel _route() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8750, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

List<LatLng> _routePoints() => const [
      LatLng(30.8750, _lng),
      LatLng(30.8560, _lng),
    ];

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


/// Records the destination coordinates of every outdoor reroute request.
///
/// CP-8: the indoor coordinate-route API was removed, so an outdoor reroute
/// now goes through `getOutdoorWalkingRoute` and carries NO floor field. The
/// former "null floor" wire-format assertion becomes "the reroute targets the
/// destination Space's coordinates" (there is no floor parameter to leak).
class _RecordingRepo implements NavigationRepository {
  final toLats = <double>[];
  int calls = 0;
  List<LatLng>? servedPoints;
  bool failAll = false;

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    calls++;
    toLats.add(toLat);
    if (failAll) throw Exception('offline');
    final points = servedPoints;
    if (points == null || points.length < 2) {
      throw Exception('no route');
    }
    return points;
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
  final List<PoiModel> pois = const [];
  @override
  bool get hasPois => false;
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
  Future<bool> requestRouteForRetarget(PoiModel poi) async => true;

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
  final gpsService = _GpsService();
  final repo = _RecordingRepo();
  late final _Scope scope;
  late final LocationViewModel provider;
  late final NavigationViewModel controller;

  _Harness() {
    scope = _Scope();
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _route();
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
    provider.setGpsLocation(_gps(30.8750));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hysteresis: one off-route tick never reroutes; two '
      'consecutive do (Matrix F trigger)', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    // Single garbage tick: no fetch, no overlay.
    h.provider.setGpsLocation(_gps(30.9950));
    expect(h.controller.isRerouting, isFalse);
    expect(h.repo.calls, 0);

    // Second consecutive qualifying tick crosses the threshold.
    h.repo.servedPoints = _routePoints();
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    await tester.pump();

    expect(h.controller.isRerouting, isFalse,
        reason: 'fast stub resolves within the pumps');
    expect(h.controller.activeRoute, same(h.scope.activeNavigationRoute));
    expect(h.repo.calls, 1);
  });

  testWidgets('wire format: an outdoor reroute targets the destination '
      "Space's coordinates and never carries an indoor floor", (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoor();

    h.repo.servedPoints = _routePoints();
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    await tester.pump();

    expect(h.repo.calls, 1,
        reason: 'BUG-12 closure: outdoor reroutes never send an indoor floor');
    expect(h.repo.toLats, everyElement(_building().latitude));

    // Cooldown respected on the injected clock: inside the window nothing
    // fires even with fresh evidence.
    now = now.add(const Duration(seconds: 5));
    h.provider.setGpsLocation(_gps(30.9860));
    h.provider.setGpsLocation(_gps(30.9860));
    await tester.pump();
    await tester.pump();
    expect(h.repo.calls, 1);

    // Past the window the next confirmed deviation fires again.
    now = now.add(const Duration(seconds: 20));
    h.provider.setGpsLocation(_gps(30.9700));
    h.provider.setGpsLocation(_gps(30.9700));
    await tester.pump();
    await tester.pump();
    expect(h.repo.calls, 2);
  });

  testWidgets('failure keeps the old route, sets the visible flag, and the '
      'flag clears on success and End', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoor();
    final original = h.scope.activeNavigationRoute!;

    h.repo.failAll = true;
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    // Backoff: 1s + 2s + 4s across three attempts, then restore.
    await tester.pump(const Duration(seconds: 10));

    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.scope.activeNavigationRoute, same(original),
        reason: 'INV-6 failure semantics: old valid route persists');
    expect(h.controller.rerouteFailed, isTrue);
    expect(navigationStatusLabel((
          state: h.controller.navigationState,
          destinationName: h.controller.destinationSpace?.name,
          pauseMessage: h.controller.pauseMessage,
          rerouteFailed: h.controller.rerouteFailed,
          isActive: h.controller.isActive,
          positioningStatus: h.controller.positioningStatus,
        )),
        'Recalculation failed \u2014 retrying soon');

    // Next successful cycle clears the flag.
    h.repo.failAll = false;
    h.repo.servedPoints = _routePoints();
    now = now.add(const Duration(seconds: 20));
    h.provider.setGpsLocation(_gps(30.9800));
    h.provider.setGpsLocation(_gps(30.9800));
    await tester.pump();
    await tester.pump();
    expect(h.controller.rerouteFailed, isFalse);
    expect(navigationStatusLabel((
          state: h.controller.navigationState,
          destinationName: h.controller.destinationSpace?.name,
          pauseMessage: h.controller.pauseMessage,
          rerouteFailed: h.controller.rerouteFailed,
          isActive: h.controller.isActive,
          positioningStatus: h.controller.positioningStatus,
        )), isNot(contains('failed')));

    // End clears everything.
    h.controller.endNavigation();
    expect(h.controller.rerouteFailed, isFalse);
  });
}
