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
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';

// ---------------------------------------------------------------------------
// PHASE 2 — Single Route Ownership & Write-Through (INV-1, INV-2, INV-6)
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

NavigationRouteModel _routeAt(List<double> lats) =>
    NavigationRouteModel(points: [
      for (final lat in lats)
        NavigationRoutePoint.outdoor(latitude: lat, longitude: _lng),
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


class _CountingRepo implements NavigationRepository {
  List<LatLng>? servedPoints;
  int calls = 0;

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    calls++;
    final points = servedPoints;
    if (points == null || points.length < 2) {
      throw Exception('stub: no route');
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

/// Recording scope: proves exactly what the controller writes into the store.
class _RecordingScope extends ChangeNotifier implements NavigationRouteScope {
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

  int adoptCalls = 0;
  final List<NavigationRouteModel> adoptedRoutes = [];
  int notificationsDuringAdopt = 0;
  bool reentrantAdoptObserved = false;
  bool _notifying = false;

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
    // Never assert() inside the notify chain: record and verify from the
    // test body instead.
    if (_notifying) reentrantAdoptObserved = true;
    _notifying = true;
    activeNavigationRoute = route;
    adoptedRoutes.add(route);
    adoptCalls++;
    notifyListeners();
    _notifying = false;
    notificationsDuringAdopt++;
  }

  @override
  Future<bool> requestRouteForRetarget(PoiModel poi) async => true;
  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    notifyListeners();
  }
}

class _Harness {
  final gpsService = _FakeGpsService();
  final repo = _CountingRepo();
  late final _RecordingScope scope;
  late final LocationViewModel provider;
  late final NavigationViewModel controller;

  _Harness() {
    scope = _RecordingScope();
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _routeAt([30.8750, 30.8560]);
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

  testWidgets('reroute write-through: the store receives the new route, '
      'evaluation sees it, revision increments exactly once',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    final replacementPoints = [const LatLng(30.8930, _lng), const LatLng(30.8560, _lng)];
    h.repo.servedPoints = replacementPoints;

    // PHASE 6 hysteresis: two consecutive off-route ticks fire the reroute.
    h.provider.setGpsLocation(_gps(30.8900));
    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    await tester.pump();

    // INV-2: visible == evaluated. Reroute now composes a new model via outdoor-only path.
    final adopted = h.scope.activeNavigationRoute;
    expect(adopted, isNotNull);
    expect(h.scope.activeNavigationRoute, same(adopted));
    expect(h.controller.activeRoute, same(adopted));
    expect(h.scope.adoptedRoutes.isNotEmpty, isTrue);
    // INV-6 mechanics: one adopt, one revision increment, no reentrancy.
    expect(h.scope.adoptCalls, 1);
    expect(h.scope.notificationsDuringAdopt, 1);
    expect(h.scope.reentrantAdoptObserved, isFalse);
    expect(h.controller.sessionForTest!.routeRevision, 1,
        reason: 'preview seeded at 0; first committed replacement -> 1');
    expect(h.repo.calls, 1);

    // A second off-route tick inside the cooldown must NOT double-write.
    h.provider.setGpsLocation(_gps(30.8945));
    await tester.pump();
    await tester.pump();
    expect(h.scope.adoptCalls, 1);
    expect(h.controller.sessionForTest!.routeRevision, 1);
  });

  testWidgets('no ping-pong: unrelated scope notifications after a committed '
      'reroute leave evaluation untouched', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    final replacementPoints = [const LatLng(30.8930, _lng), const LatLng(30.8560, _lng)];
    h.repo.servedPoints = replacementPoints;
    // PHASE 6 hysteresis: two consecutive off-route ticks fire the reroute.
    h.provider.setGpsLocation(_gps(30.8900));
    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    await tester.pump();

    final adopted = h.scope.activeNavigationRoute;

    // Unrelated store notification (browsing selection) post-commit.
    h.scope.selectFloor(_floor('0'));
    h.scope.selectSpace(_building());
    await tester.pump();

    expect(h.controller.activeRoute, same(adopted));
    expect(h.scope.activeNavigationRoute, same(adopted));
  });

  testWidgets('preview seeding records revision 0 and performs no store '
      'write of its own', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    final storedRoute = h.scope.activeNavigationRoute!;
    h.provider.setGpsLocation(_gps(30.8750));
    h.controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );

    expect(h.controller.isPreview, isTrue);
    expect(h.scope.adoptCalls, 0,
        reason: 'preview pulls from the store; it never writes it');
    expect(h.controller.sessionForTest!.routeRevision, 0);
    expect(h.controller.activeRoute, same(storedRoute));

    h.controller.endNavigation();
    await tester.pump();
    // Canonical teardown clears the single store (INV-10 groundwork).
    expect(h.scope.activeNavigationRoute, isNull);
    expect(h.controller.activeRoute, isNull);
  });
}
