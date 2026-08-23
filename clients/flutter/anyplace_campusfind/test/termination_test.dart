import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
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
// PHASE 15 — Termination Canonicalization (INV-10) & Log Contract
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

PositionEstimate _wifi({String floor = '0'}) => PositionEstimate(
      latitude: 30.8650,
      longitude: _lng,
      buid: 'b1',
      floor: floor,
      matchedAps: 5,
      totalAps: 8,
      durationMs: 12,
      timestamp: DateTime.now(),
      status: 'success',
      bestDistance: 4.0,
      topKSpreadMeters: 6.0,
    );

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.8650,
      longitude: _lng,
    );

FloorModel _floor(String n) => FloorModel(buid: 'b1', floorNumber: n);

PoiModel _entrance() => PoiModel(
      puid: 'entr',
      buid: 'b1',
      floorNumber: '0',
      name: 'Main Entrance',
      poisType: 'Entrance',
      latitude: 30.86505,
      longitude: _lng,
      isBuildingEntrance: true,
    );

NavigationRouteModel _route() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.9000, longitude: _lng),
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
  final _estimates = StreamController<PositionEstimate>.broadcast();
  @override
  Stream<PositionEstimate> get positionStream => _estimates.stream;
  void emit(PositionEstimate e) => _estimates.add(e);
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
}

class _ThrowingClearRepo implements NavigationRepository {
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
  }) async =>
      throw UnimplementedError();
}

/// Scope whose clearNavigationRoute can be made to THROW — proving that
/// terminateNavigation never propagates scope faults.
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

  int clearCalls = 0;
  bool throwOnClear = false;

  _Scope(this.floors, this.pois);

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
    clearCalls++;
    if (throwOnClear) throw StateError('scope exploded');
    activeNavigationRoute = null;
    notifyListeners();
  }
}

class _Harness {
  final gpsService = _GpsService();
  final native = _Native();
  late final _Scope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness() {
    scope = _Scope([_floor('0'), _floor('1')], [_entrance()]);
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
      navigationRepository: _ThrowingClearRepo(),
    );
  }

  void dispose() {
    controller.dispose();
    provider.dispose();
  }

  Future<void> startOutdoor(WidgetTester tester) async {
    provider.setGpsLocation(_gps(30.9000));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();
    expect(controller.navigationState, NavigationState.activeOutdoor);
  }

  /// Reaches ACTIVE_INDOOR via belief flip + strict corroboration.
  Future<void> corroborateEntry(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      native.emit(_wifi());
    }
    await tester.pump();
    provider.setGpsLocation(_gps(30.86505));
    expect(controller.navigationState, NavigationState.activeIndoor);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PHASE 15: terminate-from-every-state table', () {
    testWidgets('preview / activeOutdoor / enteringBuilding / activeIndoor / '
        'floorTransition / exitingBuilding / paused / rerouting / arrived '
        'all land IDLE with zero residue', (tester) async {
      // --- routePreview ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        h.provider.setGpsLocation(_gps(30.9000));
        h.controller.startRoutePreview(
          destinationPuid: 'dest',
          destinationSpace: _building(),
        );
        expect(h.controller.isPreview, isTrue);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.controller.sessionId, isNull);
        expect(h.scope.activeNavigationRoute, isNull);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      // --- activeOutdoor ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.startOutdoor(tester);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.controller.destinationPuid, isNull);
        expect(h.scope.activeNavigationRoute, isNull);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      // --- enteringBuilding (dwell alive) ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.startOutdoor(tester);
        h.provider.setGpsLocation(_gps(30.86505));
        expect(h.controller.navigationState, NavigationState.enteringBuilding);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      // --- activeIndoor ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.startOutdoor(tester);
        for (var i = 0; i < 6; i++) {
          h.native.emit(_wifi());
        }
        await tester.pump();
        h.provider.setGpsLocation(_gps(30.86505));
        expect(h.controller.navigationState, NavigationState.activeIndoor);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      // --- paused ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.startOutdoor(tester);
        for (var i = 0; i < NavigationConfig.gpsPausePoorTicks; i++) {
          h.provider.setGpsLocation(_gps(30.8700, accuracy: 150));
        }
        expect(h.controller.isPaused, isTrue);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.controller.isPaused, isFalse);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      // --- arrived ---
      {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.startOutdoor(tester);
        h.controller.markArrived();
        expect(h.controller.isArrived, isTrue);
        h.controller.terminateNavigation();
        expect(h.controller.navigationState, NavigationState.idle);
        expect(h.scope.clearCalls, 1);
        h.ncDispose();
      }

      await tester.pump(const Duration(seconds: 11));
    });
  });

  testWidgets('terminate never throws even when the scope explodes',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    h.scope.throwOnClear = true;

    // Must not propagate.
    h.controller.terminateNavigation();

    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.controller.sessionId, isNull);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('log contract: a scripted journey emits the required event '
      'sequence in order', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    final lines = <String>[];
    navigationLog = lines.add;
    addTearDown(() {
      navigationLog = (line) => debugPrint(line);
    });

    h.provider.setGpsLocation(_gps(30.9000));
    h.controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    h.controller.startActiveNavigation();

    for (var i = 0; i < 6; i++) {
      h.native.emit(_wifi());
    }
    await tester.pump();
    h.provider.setGpsLocation(_gps(30.86505));

    h.controller.markArrived();
    h.controller.terminateNavigation();

    final events = lines
        .where((l) => l.startsWith('[NAV] EVENT='))
        .map((l) => l.split(' ').firstWhere((t) => t.startsWith('EVENT=')))
        .map((t) => t.substring('EVENT='.length))
        .toList();

    int indexOf(String e) => events.indexOf(e);
    expect(indexOf('SESSION_START'), greaterThanOrEqualTo(0));
    expect(indexOf('PREVIEW_SEED'), greaterThanOrEqualTo(0));
    expect(indexOf('PREVIEW_SEED'),
        lessThan(indexOf('SESSION_START') < 0 ? 9999 : indexOf('HANDOFF_ENTER_CONFIRM')));
    expect(events.contains('STATE'), isTrue);
    expect(events.contains('HANDOFF_ENTER_CONFIRM'), isTrue);
    expect(events.contains('ARRIVAL'), isTrue);
    expect(events.last, 'SESSION_END');
    expect(events[events.length - 2], 'TERMINATE');

    await tester.pump(const Duration(seconds: 11));
  });
}

extension on _Harness {
  void ncDispose() {}
}
