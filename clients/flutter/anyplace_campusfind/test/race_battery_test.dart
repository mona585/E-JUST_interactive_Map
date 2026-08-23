import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';

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

class _Native implements NativePositioningService {
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
  final queue = <Completer<NavigationRouteModel>>[];

  void holdNext() => queue.add(Completer<NavigationRouteModel>());

  void failAllPending() {
    for (final c in queue) {
      c.completeError(Exception('offline'));
    }
    queue.clear();
  }

  int get pendingGates => queue.length;

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
    final c = Completer<NavigationRouteModel>();
    queue.add(c);
    return c.future;
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
  final gpsService = _GpsService();
  final native = _Native();
  final repo = _GatedRepo();
  late final _Scope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness() {
    scope = _Scope();
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
      h.repo.queue.removeLast().complete(_route());
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
      h.repo.queue.removeLast().complete(_route(endLat: 30.7000));
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
