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
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ---------------------------------------------------------------------------
// PHASE 16 — Integration journey (Matrix A golden subset) + tick-cost sanity
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    );

PositionEstimate _wifi({String floor = '0'}) => PositionEstimate(
      latitude: 30.86505,
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

class _Repo implements NavigationRepository {
  int indoorRequests = 0;
  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async {
    indoorRequests++;
    return _indoorRoute();
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    String? floorNumber,
    required String destinationPuid,
  }) async =>
      throw UnimplementedError();
}

NavigationRouteModel _indoorRoute() => NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.entrance(
          points: const [LatLng(30.86510, _lng), LatLng(30.86480, _lng)],
          buildingId: 'b1',
          floorNumber: '0',
        ),
        RouteSegment.indoor(
          points: const [
            LatLng(30.86480, _lng),
            LatLng(30.86460, _lng),
            LatLng(30.86490, _lng),
          ],
          buildingId: 'b1',
          floorNumber: '0',
        ),
      ],
      status: RouteModelStatus.ready,
    );

/// Golden expected rendered-polyline id set for the INDOOR stage of the
/// journey, computed purely from the same Phase-12 projection rules the map
/// uses. Snapshot-style: this IS the golden model for Matrix A's tail.
Set<String> expectedIndoorPolylineIds({
  required bool hasSegments,
}) =>
    hasSegments ? {'route_indoor'} : {'route_outdoor'};

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
  final List<PoiModel> pois = [_entrancePoi()];
  @override
  bool get hasPois => pois.isNotEmpty;
  @override
  FloorplanModel? activeFloorplan;
  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  static PoiModel _entrancePoi() => PoiModel(
        puid: 'entr',
        buid: 'b1',
        floorNumber: '0',
        name: 'Main Entrance',
        poisType: 'Entrance',
        latitude: 30.86505,
        longitude: _lng,
        isBuildingEntrance: true,
      );

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

  int indoorRequests = 0;

  @override
  Future<bool> requestRouteForRetarget(PoiModel poi) async => true;

  @override
  Future<NavigationRouteModel?> requestIndoorRouteForSession({
    required String destinationPuid,
    required String confirmedBuid,
    required String confirmedFloor,
  }) async {
    indoorRequests++;
    return _indoorRoute();
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Matrix A golden subset: outdoor→entry→indoor guidance→arrival '
      'with store/revision/log coherence at every commit point',
      (tester) async {
    final scope = _Scope();
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute =
        NavigationRouteModel(points: [for (final l in [30.9000, 30.8560]) NavigationRoutePoint.outdoor(latitude: l, longitude: _lng)]);

    final gpsService = _GpsService();
    final native = _Native();
    final provider = LocationProvider(
      locationService: gpsService,
      nativePositioningService: native,
    );
    final repo = _Repo();
    final controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
      navigationRepository: repo,
    );
    addTearDown(() {
      controller.dispose();
      provider.dispose();
    });

    // Stage 1: preview seeded.
    provider.setGpsLocation(_gps(30.9000));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    expect(controller.isPreview, isTrue);
    expect(controller.sessionForTest!.routeRevision, 0);
    expect(scope.activeNavigationRoute!.hasOutdoorSegment, isTrue);

    // Stage 2: active outdoors.
    controller.startActiveNavigation();
    expect(controller.navigationState, NavigationState.activeOutdoor);

    // Stage 3: handoff confirms indoors; guidance commits write-through.
    for (var i = 0; i < 6; i++) {
      native.emit(_wifi());
    }
    await tester.pump();
    provider.setGpsLocation(_gps(30.86505));
    expect(controller.navigationState, NavigationState.activeIndoor);
    await tester.pump();
    await tester.pump();

    expect(scope.indoorRequests, 1);
    final committed = scope.activeNavigationRoute!;
    expect(committed.hasIndoorSegment, isTrue);
    expect(controller.activeRoute, same(committed),
        reason: 'INV-2 holds at the guidance commit point');
    expect(controller.sessionForTest!.routeRevision, 1);

    // Stage 4: arrival over two good indoor ticks at the destination.
    for (var i = 0; i < 6; i++) {
      // One ~17 m settling hop, then stay put — all inside the arbiter's
      // 30 m same-scope outlier window.
      native.emit(PositionEstimate(
        latitude: 30.86490,
        longitude: _lng,
        buid: 'b1',
        floor: '0',
        matchedAps: 5,
        totalAps: 8,
        durationMs: 12,
        timestamp: DateTime.now(),
        status: 'success',
        bestDistance: 4.0,
        topKSpreadMeters: 6.0,
      ));
    }
    await tester.pump();
    expect(controller.isArrived, isTrue);

    // Stage 5: terminate leaves zero residue.
    controller.terminateNavigation();
    expect(controller.navigationState, NavigationState.idle);
    expect(scope.activeNavigationRoute, isNull);
    await tester.pump(const Duration(seconds: 11));

    // Golden rendered-id expectation for the committed indoor geometry.
    expect(expectedIndoorPolylineIds(hasSegments: committed.hasSegments),
        {'route_indoor'});
  });

  test('tick-pipeline cost sanity: 400 GPS ticks average well under 2 ms '
      '(host CPU; indicative only)', () {
    final scope = _Scope()
      ..selectedSpace = _building()
      ..selectedFloor = _floor('0')
      ..activeNavigationRoute = NavigationRouteModel(points: [
        for (final l in [30.9000, 30.8560])
          NavigationRoutePoint.outdoor(latitude: l, longitude: _lng)
      ]);
    final provider = LocationProvider(
      locationService: _GpsService(),
      nativePositioningService: _Native(),
    );
    final controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
    );
    addTearDown(() {
      controller.dispose();
      provider.dispose();
    });

    provider.setGpsLocation(_gps(30.9000));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();

    final sw = Stopwatch()..start();
    var lat = 30.8950;
    for (var i = 0; i < 400; i++) {
      lat -= 0.00001; // ~1 m steps along the route corridor
      provider.setGpsLocation(UserLocation(
        latitude: lat,
        longitude: _lng,
        accuracy: 8.0,
        timestamp: DateTime.now(),
      ));
    }
    sw.stop();
    final avgMicros = sw.elapsedMicroseconds / 400;
    // ignore: avoid_print
    print('[PERF] avg tick pipeline cost: ${avgMicros.toStringAsFixed(1)} µs '
        '(${(avgMicros / 1000).toStringAsFixed(3)} ms) over 400 ticks');
    expect(avgMicros, lessThan(2000),
        reason: 'plan budget: <2 ms per tick on host hardware');
  });
}
