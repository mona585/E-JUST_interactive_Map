import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

// FORENSIC REMEDIATION REGRESSION TEST
// Findings: INDOOR-001 / ACTIVE-001 / X-1.
//
// Contract: an ordinary BROWSING tap on another building must NOT strand
// exit detection or entrance proximity of a LIVE session. The controller now
// owns session-scoped destination geometry captured while the scope pointed
// at the destination; browsing wipes of the shared scope fields are ignored.

class _FakeScope extends ChangeNotifier implements NavigationRouteScope {
  List<SpaceModel> spaces = [];
  SpaceModel? selectedSpace;
  List<FloorModel> floors = [];
  FloorModel? selectedFloor;
  List<PoiModel> pois = [];
  FloorplanModel? activeFloorplan;
  NavigationRouteModel? activeNavigationRoute;
  final customRouteRepo = CustomRouteRepository();
  int adopted = 0;
  int storeWrites = 0;

  @override
  bool get hasPois => pois.isNotEmpty;

  @override
  CustomRouteRepository get customRouteRepository => customRouteRepo;

  @override
  void selectSpace(SpaceModel space) {
    selectedSpace = space;
    selectedFloor = null;
    pois = const [];
    activeFloorplan = null;
    notifyListeners();
  }

  @override
  void selectSpaceForNavigation(SpaceModel space) {
    selectedSpace = space;
    notifyListeners();
  }

  @override
  void selectFloor(FloorModel floor) {
    selectedFloor = floor;
    notifyListeners();
  }

  @override
  void selectFloorForNavigation(FloorModel floor) {
    selectedFloor = floor;
    notifyListeners();
  }

  @override
  void clearSelection() {}

  @override
  void releaseIndoorContextForNavigation() {
    activeFloorplan = null;
    pois = const [];
    notifyListeners();
  }

  @override
  Future<bool> requestRouteForRetarget(PoiModel target) async => true;

  @override
  Future<NavigationRouteModel?> requestRouteCandidateForRetarget(
          PoiModel target) async =>
      null;

  @override
  Future<NavigationRouteModel?> requestIndoorRouteForSession(
      {required String destinationPuid,
      required String confirmedBuid,
      required String confirmedFloor}) async {
    return null;
  }

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    adopted++;
    notifyListeners();
  }

  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    storeWrites++;
    notifyListeners();
  }
}

class _FakeNative implements NativePositioningService {
  final _controller = StreamController<PositionEstimate>.broadcast();

  void emit(PositionEstimate e) => _controller.add(e);

  @override
  Stream<PositionEstimate> get positionStream => _controller.stream;

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor,
      {void Function(String detail)? onFailureDetail}) async {
    return true;
  }

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

class _FakeLocationService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<UserLocation?> getCurrentPosition() async => null;

  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) =>
      const Stream.empty();
}

UserLocation _gps(double lat, {double lon = 29.0}) => UserLocation(
      latitude: lat,
      longitude: lon,
      accuracy: 4,
      timestamp: DateTime.now(),
    );

void main() {
  testWidgets('ACTIVE-001: a foreign browsing tap mid-session does NOT '
      'strand building-exit detection', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final native = _FakeNative();
    final lp = LocationProvider(
      locationService: _FakeLocationService(),
      nativePositioningService: native,
    );
    final scope = _FakeScope();
    final destB =
        SpaceModel(buid: 'bB', name: 'B', latitude: 30.8650, longitude: 29.0);
    final otherC =
        SpaceModel(buid: 'bC', name: 'C', latitude: 31.5000, longitude: 29.0);

    scope.selectedSpace = destB;
    scope.pois = [
      PoiModel(
        puid: 'entrance_B',
        buid: 'bB',
        floorNumber: '0',
        name: 'Entrance',
        poisType: 'Entrance',
        latitude: 30.8649,
        longitude: 29.0,
        isBuildingEntrance: true,
      ),
    ];

    final nav = NavigationController(
      spaceProvider: scope,
      locationProvider: lp,
    );
    addTearDown(() {
      nav.dispose();
      lp.dispose();
      native._controller.close();
    });

    // Seed the store: preview adopts whatever the scope already holds.
    scope.activeNavigationRoute = NavigationRouteModel(points: [
      const NavigationRoutePoint(
          latitude: 30.9000,
          longitude: 29.0,
          puid: '__outdoor__',
          buid: '',
          floorNumber: '',
          poisType: 'outdoor',
          isOutdoor: true),
      const NavigationRoutePoint(
          latitude: 30.8649,
          longitude: 29.0,
          puid: 'room_B',
          buid: 'bB',
          floorNumber: '0',
          poisType: 'Room'),
    ]);
    nav.startRoutePreview(destinationPuid: 'room_B', destinationSpace: destB);
    nav.startActiveNavigation();
    expect(nav.navigationState, NavigationState.activeOutdoor);

    // Approach the destination: preload fires and the cache is captured.
    lp.setGpsLocation(_gps(30.8655));
    await tester.pump();
    await tester.pump();
    expect(nav.buildingPreloadedForTest, isTrue);
    expect(nav.destCentroidCapturedForTest, isTrue);
    expect(nav.destEntranceCacheCountForTest, 1);

    // Go INDOOR on believed Wi-Fi: 3 estimates enter indoor mode, a 4th
    // carries the canonically-confirmed scope that corroborates the handoff.
    for (var i = 0; i < 6; i++) { // e6 carries the confirmed scope
      native.emit(PositionEstimate(
        latitude: 30.8651,
        longitude: 29.0,
        buid: 'bB',
        floor: '0',
        matchedAps: 5,
        totalAps: 8,
        durationMs: 3,
        timestamp: DateTime.now(),
        status: 'success',
      ));
      await tester.pump();
    }
    await tester.pump();
    await tester.pump();
    expect(nav.navigationState, NavigationState.activeIndoor,
        reason: 'setup: handoff corroborated by confirmed-scope Wi-Fi');

    // ── The hostile act under test: an ordinary browsing tap elsewhere ──
    scope.selectSpace(otherC); // wipes selectedSpace/pois/floorplan

    // Drop the Wi-Fi belief (3 no-match cycles) so GPS is believed again,
    // mirroring a real walk-out where scans stop matching the resident map.
    for (var i = 0; i < 3; i++) {
      native.emit(PositionEstimate(
        latitude: null,
        longitude: null,
        buid: '',
        floor: '',
        matchedAps: 0,
        totalAps: 6,
        durationMs: 2,
        timestamp: DateTime.now(),
        status: 'no_match',
      ));
      await tester.pump();
    }
    await tester.pump();

    // Exit evidence: good-accuracy GPS far OUTSIDE the DESTINATION. The old
    // implementation measured against whatever building the browser showed
    // (bC here) and never confirmed an exit.
    for (var i = 0; i < 3; i++) {
      lp.setGpsLocation(_gps(30.9000));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(nav.navigationState, NavigationState.exitingBuilding,
        reason:
            'exit detection must keep measuring against the SESSION destination '
            'even after browsing moved the shared scope elsewhere');
  });
  testWidgets('ACTIVE-001: entrance proximity keeps using the cached '
      'destination entrances after a foreign browsing tap', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final lp = LocationProvider(locationService: _FakeLocationService());
    final scope = _FakeScope();
    final destB =
        SpaceModel(buid: 'bB', name: 'B', latitude: 30.8650, longitude: 29.0);
    final otherC =
        SpaceModel(buid: 'bC', name: 'C', latitude: 31.5000, longitude: 29.0);

    scope.selectedSpace = destB;
    scope.pois = [
      PoiModel(
        puid: 'entrance_B',
        buid: 'bB',
        floorNumber: '0',
        name: 'Entrance',
        poisType: 'Entrance',
        latitude: 30.8649,
        longitude: 29.0,
        isBuildingEntrance: true,
      ),
    ];

    final nav = NavigationController(
      spaceProvider: scope,
      locationProvider: lp,
    );
    addTearDown(() {
      nav.dispose();
      lp.dispose();
    });

    // Seed the store: preview adopts whatever the scope already holds.
    scope.activeNavigationRoute = NavigationRouteModel(points: [
      const NavigationRoutePoint(
          latitude: 30.9000,
          longitude: 29.0,
          puid: '__outdoor__',
          buid: '',
          floorNumber: '',
          poisType: 'outdoor',
          isOutdoor: true),
      const NavigationRoutePoint(
          latitude: 30.8649,
          longitude: 29.0,
          puid: 'room_B',
          buid: 'bB',
          floorNumber: '0',
          poisType: 'Room'),
    ]);
    nav.startRoutePreview(
        destinationPuid: 'room_B', destinationSpace: destB);
    nav.startActiveNavigation();

    // Preload + capture.
    lp.setGpsLocation(_gps(30.8655));
    await tester.pump();
    await tester.pump();
    expect(nav.buildingPreloadedForTest, isTrue);

    // Foreign tap wipes the scope POIs entirely.
    scope.selectSpace(otherC);
    expect(scope.hasPois, isFalse);

    // Walk to the CACHED entrance: dwell must still arm (old code saw zero
    // POIs and silently did nothing here).
    lp.setGpsLocation(_gps(30.8649));
    await tester.pump();
    await tester.pump();

    expect(nav.navigationState, NavigationState.enteringBuilding);
  });
}
