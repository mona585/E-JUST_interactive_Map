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
// PHASE 14 — Race battery (R1–R12 closure) + stress loop
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

NavigationRouteModel _route({double endLat = 30.8560}) =>
    NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.9000, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: endLat, longitude: _lng),
    ]);

List<LatLng> _routePoints({double endLat = 30.8560}) => [
      const LatLng(30.9000, _lng),
      LatLng(endLat, _lng),
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


class _GatedRepo implements NavigationRepository {
  final queue = <Completer<List<LatLng>>>[];

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    final c = Completer<List<LatLng>>();
    queue.add(c);
    return c.future;
  }

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      null;

  void holdNext() => queue.add(Completer<List<LatLng>>());

  void failAllPending() {
    for (final c in queue) {
      c.completeError(Exception('offline'));
    }
    queue.clear();
  }

  int get pendingGates => queue.length;
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
  final repo = _GatedRepo();
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
    scope.activeNavigationRoute ??= _route();
    provider.setGpsLocation(_gps(30.9000));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();
  }

  /// Fires a reroute trigger sequence (two off-route ticks).
  void fireOffRoute() {
    provider.setGpsLocation(_gps(30.9950));
    provider.setGpsLocation(_gps(30.9950));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('R2/R11: End during backoff cancels the continuation; the '
      'late result is inert', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;

    h.startOutdoor();
    h.fireOffRoute(); // all three attempts fail across the backoff ladder
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
      h.repo.failAllPending();
    }
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.controller.rerouteFailed, isTrue);

    // New cycle; gated request pending across an immediate End.
    now = now.add(const Duration(seconds: 20));
    h.startOutdoor();
    expect(h.controller.sessionId, isNotNull,
        reason: 'fresh session in play');

    h.repo.holdNext();
    h.fireOffRoute();
    await tester.pump();
    expect(h.controller.isRerouting, isTrue);
    expect(h.repo.pendingGates, greaterThanOrEqualTo(1));

    h.controller.endNavigation();
    // Release every pending gate AFTER the session ended.
    while (h.repo.pendingGates > 0) {
      h.repo.queue.removeLast().complete(_routePoints());
    }
    await tester.pump();
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.scope.activeNavigationRoute, isNull);
  });

  testWidgets('R1/R6: superseded gated result never overwrites newer '
      'geometry', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoor();

    h.fireOffRoute(); // fails -> flag + restore (drain with errors)
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 5));
      h.repo.failAllPending();
    }
    await tester.pump();

    now = now.add(const Duration(seconds: 20));
    h.repo.holdNext();
    h.fireOffRoute(); // pending
    await tester.pump();
    // A committed replacement lands while the fetch is pending.
    final newer = _route(endLat: 30.8500);
    h.scope.adoptNavigatedRoute(newer);
    h.controller.debugBumpRouteRevision();

    while (h.repo.pendingGates > 0) {
      h.repo.queue.removeLast().complete(_routePoints(endLat: 30.7000));
    }
    await tester.pump();
    await tester.pump();

    expect(h.scope.activeNavigationRoute, same(newer),
        reason: 'the stale candidate never overwrites the newer commit');
    expect(h.controller.activeRoute, same(newer));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
  });

  testWidgets('stress: 50 rapid preview→active→End cycles stay coherent and '
      'leave no residue', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var lastSid = '';

    for (var i = 0; i < 50; i++) {
      h.startOutdoor();
      final sid = h.controller.sessionId!;
      expect(sid != lastSid || lastSid.isEmpty, isTrue,
          reason: 'session ids must never repeat within a process');
      lastSid = sid;
      expect(h.controller.isActive, isTrue);
      h.controller.endNavigation();
      expect(h.controller.navigationState, NavigationState.idle);
      expect(h.scope.activeNavigationRoute, isNull);
      // Re-seed for the next cycle.
      h.scope.activeNavigationRoute = _route();
    }

    await tester.pump(const Duration(seconds: 12));
    expect(h.controller.sessionId, isNull);

    // The pipeline remains responsive afterwards.
    h.startOutdoor();
    expect(h.controller.isActive, isTrue);
    await tester.pump(const Duration(seconds: 11));
  });
}
