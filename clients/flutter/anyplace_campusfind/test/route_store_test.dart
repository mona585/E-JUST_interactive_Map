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
        NavigationRoutePoint.outdoor(
            latitude: lat, longitude: _lng, buid: 'b1', floorNumber: '0'),
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

class _CountingRepo implements NavigationRepository {
  NavigationRouteModel? served;
  int calls = 0;

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
    return served ?? (throw Exception('stub: no route'));
  }
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
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    notifyListeners();
  }
}

class _Harness {
  final gpsService = _FakeGpsService();
  final native = _FakeNative();
  final repo = _CountingRepo();
  late final _RecordingScope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness() {
    scope = _RecordingScope();
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _routeAt([30.8750, 30.8560]);
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

    final replacement = _routeAt([30.8930, 30.8560]);
    h.repo.served = replacement;

    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    await tester.pump();

    // INV-2: visible == evaluated.
    expect(h.scope.activeNavigationRoute, same(replacement));
    expect(h.controller.activeRoute, same(replacement));
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

    final replacement = _routeAt([30.8930, 30.8560]);
    h.repo.served = replacement;
    h.provider.setGpsLocation(_gps(30.8900));
    await tester.pump();
    await tester.pump();

    // Unrelated store notification (browsing selection) post-commit.
    h.scope.selectFloor(_floor('0'));
    h.scope.selectSpace(_building());
    await tester.pump();

    expect(h.controller.activeRoute, same(replacement));
    expect(h.scope.activeNavigationRoute, same(replacement));
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
