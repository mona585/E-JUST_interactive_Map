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
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tick-pipeline cost sanity: 400 GPS ticks average well under 2 ms '
      '(host CPU; indicative only)', () {
    final scope = _Scope()
      ..selectedSpace = _building()
      ..selectedFloor = _floor('0')
      ..activeNavigationRoute = NavigationRouteModel(points: [
        for (final l in [30.9000, 30.8560])
          NavigationRoutePoint.outdoor(latitude: l, longitude: _lng)
      ]);
    final provider = LocationViewModel(
      locationService: _GpsService(),
    );
    final controller = NavigationViewModel(
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
