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
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';

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

/// Records the exact wire payload of every coordinate-route request.
class _RecordingRepo implements NavigationRepository {
  final floors = <String?>[];
  final destinations = <String>[];
  NavigationRouteModel? served;
  bool failAll = false;

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
    floors.add(floorNumber);
    destinations.add(destinationPuid);
    if (failAll) throw Exception('offline');
    return served ?? (throw Exception('no route'));
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
  final native = _Native();
  final repo = _RecordingRepo();
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
    expect(h.repo.floors, isEmpty);

    // Second consecutive qualifying tick crosses the threshold.
    h.repo.served = _route();
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    await tester.pump();

    expect(h.controller.isRerouting, isFalse,
        reason: 'fast stub resolves within the pumps');
    expect(h.controller.activeRoute, same(h.scope.activeNavigationRoute));
    expect(h.repo.floors.length, 1);
  });

  testWidgets('wire format: an outdoor reroute sends a NULL floor and the '
      "current destination - never a fabricated '0'", (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoor();

    h.repo.served = _route();
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    await tester.pump();

    expect(h.repo.floors, [null],
        reason: 'BUG-12 closure: outdoor reroutes omit floor entirely');
    expect(h.repo.destinations, ['dest']);

    // Cooldown respected on the injected clock: inside the window nothing
    // fires even with fresh evidence.
    now = now.add(const Duration(seconds: 5));
    h.provider.setGpsLocation(_gps(30.9860));
    h.provider.setGpsLocation(_gps(30.9860));
    await tester.pump();
    await tester.pump();
    expect(h.repo.floors.length, 1);

    // Past the window the next confirmed deviation fires again.
    now = now.add(const Duration(seconds: 20));
    h.provider.setGpsLocation(_gps(30.9700));
    h.provider.setGpsLocation(_gps(30.9700));
    await tester.pump();
    await tester.pump();
    expect(h.repo.floors.length, 2);
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
    expect(navigationStatusLabel(h.controller),
        'Recalculation failed \u2014 retrying soon');

    // Next successful cycle clears the flag.
    h.repo.failAll = false;
    h.repo.served = _route();
    now = now.add(const Duration(seconds: 20));
    h.provider.setGpsLocation(_gps(30.9800));
    h.provider.setGpsLocation(_gps(30.9800));
    await tester.pump();
    await tester.pump();
    expect(h.controller.rerouteFailed, isFalse);
    expect(navigationStatusLabel(h.controller), isNot(contains('failed')));

    // End clears everything.
    h.controller.endNavigation();
    expect(h.controller.rerouteFailed, isFalse);
  });
}
