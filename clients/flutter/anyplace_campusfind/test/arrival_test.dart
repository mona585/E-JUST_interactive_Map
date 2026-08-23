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
// ORIGINAL PHASE 6 — Arrival.
//
// The evidence producer confirms arrival only after
// [NavigationConfig.arrivalConfirmationCount] consecutive positioning ticks
// within [NavigationConfig.arrivalProximityThresholdMeters] of the resolved
// anchor (destination POI when resolvable, else the route's final point).
// Indoors, proximity alone is never proof: the fix must carry canonically
// confirmed identity matching the anchor building AND floor.
//
// Arbiter facts reused from Phases 1/4/5: the fix published on a scope-flip
// tick is built BEFORE the claim advances (one-emission identity lag);
// >30 m jumps between accepted indoor fixes are rejected as outliers, so
// indoor movement walks in small steps.
// ---------------------------------------------------------------------------

class _FakeLocationService implements LocationService {
  final _gpsController = StreamController<UserLocation>.broadcast();

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
      _gpsController.stream;
}

class _FakeNativePositioningService implements NativePositioningService {
  final _estimateController = StreamController<PositionEstimate>.broadcast();

  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async =>
      true;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => _estimateController.stream;

  void emit(PositionEstimate estimate) => _estimateController.add(estimate);
}

class _StubNavigationRepository implements NavigationRepository {
  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async =>
      throw Exception('stub: unexpected call');

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async =>
      throw Exception('stub: unexpected call');
}

class _FakeSpaceScope extends ChangeNotifier implements NavigationRouteScope {
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

  _FakeSpaceScope({required this.floors, this.pois = const []});

  @override
  bool get hasPois => pois.isNotEmpty;

  @override
  FloorplanModel? get activeFloorplan => null;

  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  final List<String> calls = [];

  @override
  void selectSpace(SpaceModel space) {
    selectedSpace = space;
    calls.add('selectSpace:${space.buid}');
    notifyListeners();
  }

  @override
  void selectFloor(FloorModel floor) {
    selectedFloor = floor;
    calls.add('selectFloor:${floor.floorNumber}');
    notifyListeners();
  }

  @override
  void clearSelection() {
    selectedSpace = null;
    selectedFloor = null;
    activeNavigationRoute = null;
    calls.add('clearSelection');
    notifyListeners();
  }

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    calls.add('adoptNavigatedRoute');
    notifyListeners();
  }

  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    calls.add('clearNavigationRoute');
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Fixtures — collinear on lng 29.5828.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

/// Default route-endpoint anchor (used when no POI matches).
const _endLat = 30.8560;

/// Indoor walk target used as a close-range anchor for indoor tests.
const _indoorAnchorLat = 30.86560;

UserLocation _gps(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

PositionEstimate _wifi({
  String floor = '0',
  String buid = 'b1',
  double lat = 30.86500,
}) =>
    PositionEstimate(
      latitude: lat,
      longitude: _lng,
      buid: buid,
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

PoiModel _poi({
  String puid = 'dest',
  String buid = 'b1',
  String floor = '0',
  double lat = _indoorAnchorLat,
}) =>
    PoiModel(
      puid: puid,
      buid: buid,
      floorNumber: floor,
      name: 'Destination',
      poisType: 'Other',
      latitude: lat,
      longitude: _lng,
    );

/// Flat collinear route ending at [endLat] (the fallback arrival anchor).
NavigationRouteModel _route({double endLat = _endLat}) =>
    NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(
          latitude: 30.8750, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8700, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: endLat, longitude: _lng, buid: 'b1', floorNumber: '0'),
    ]);

/// Collinear indoor corridor covering the Wi-Fi walk region so the deviation
/// detector always sees the walker on-route.
NavigationRouteModel _indoorCorridorRoute() =>
    NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(
          latitude: 30.87000, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.86600, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.86400, longitude: _lng, buid: 'b1', floorNumber: '0'),
    ]);

/// Two-segment journey whose FIRST segment endpoint (30.8740) is not the
/// destination — the anchor must be the FINAL point (30.8700). Points are
/// declared explicitly so every point shares floor '0' (the deviation
/// filter compares against the navigating floor's projection).
NavigationRouteModel _twoSegmentRoute() => NavigationRouteModel(
      points: [
        NavigationRoutePoint.outdoor(
            latitude: 30.8760, longitude: _lng, buid: 'b1', floorNumber: '0'),
        NavigationRoutePoint.outdoor(
            latitude: 30.8740, longitude: _lng, buid: 'b1', floorNumber: '0'),
        NavigationRoutePoint.outdoor(
            latitude: 30.8720, longitude: _lng, buid: 'b1', floorNumber: '0'),
        NavigationRoutePoint.outdoor(
            latitude: 30.8700, longitude: _lng, buid: 'b1', floorNumber: '0'),
      ],
      segments: [
        RouteSegment.outdoor(
          points: [LatLng(30.8760, _lng), LatLng(30.8740, _lng)],
          buildingId: 'b1',
        ),
        RouteSegment.indoor(
          points: [LatLng(30.8720, _lng), LatLng(30.8700, _lng)],
          buildingId: 'b1',
          floorNumber: '0',
        ),
      ],
    );

class _Harness {
  final gpsService = _FakeLocationService();
  final native = _FakeNativePositioningService();
  final stub = _StubNavigationRepository();
  late final _FakeSpaceScope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness({List<PoiModel> pois = const [], NavigationRouteModel? route}) {
    scope = _FakeSpaceScope(
      floors: [_floor('0'), _floor('1')],
      pois: pois,
    );
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = route ?? _route();
    provider = LocationProvider(
      locationService: gpsService,
      nativePositioningService: native,
    );
    controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
      navigationRepository: stub,
    );
  }

  void dispose() {
    controller.dispose();
    provider.dispose();
  }

  Future<void> establishPreview(WidgetTester tester) async {
    await tester.pump();
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
  }

  Future<void> startOutdoor(WidgetTester tester) async {
    provider.setGpsLocation(_gps(30.8750));
    await establishPreview(tester);
    controller.startActiveNavigation();
    expect(controller.navigationState, NavigationState.activeOutdoor);
  }

  Future<void> startIndoor(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      native.emit(_wifi());
    }
    await establishPreview(tester);
    controller.startActiveNavigation();
    expect(controller.navigationState, NavigationState.activeIndoor);
  }

  /// Emits [n] indoor estimates and lets the pipeline process them.
  Future<void> emitWifi(
    WidgetTester tester, {
    String floor = '0',
    String buid = 'b1',
    double lat = 30.86500,
    int n = 1,
  }) async {
    for (var i = 0; i < n; i++) {
      native.emit(_wifi(floor: floor, buid: buid, lat: lat));
    }
    await tester.pump();
  }

  /// Two GPS ticks well inside the anchor radius.
  Future<void> arriveOverGps(WidgetTester tester, double lat) async {
    provider.setGpsLocation(_gps(lat));
    await tester.pump();
    provider.setGpsLocation(_gps(lat));
    await tester.pump();
  }

  Future<void> burnTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }
}

void main() {
  testWidgets(
      'outdoor arrival: two consecutive GPS ticks within the radius confirm '
      'ARRIVED, project the previous activity, and stay inert',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    // First qualifying tick alone is not proof.
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.arrived);
    expect(h.controller.isArrived, isTrue);
    expect(h.controller.subState, NavigationSubState.outdoor,
        reason: 'arrived projects its previous activity');

    // Further updates are inert; End is the only way out.
    h.provider.setGpsLocation(_gps(30.8700));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.arrived);

    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.controller.snapshot.previousActiveState, isNull);
    await h.burnTimers(tester);
  });

  testWidgets(
      'hysteresis: a tick outside the radius resets the confirmation counter',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    // inside / far / inside / inside — only CONSECUTIVE qualifiers count.
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    h.provider.setGpsLocation(_gps(30.8700));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'the far tick reset the counter');

    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets(
      'indoor arrival waits for canonically confirmed identity, then '
      'confirms on two qualifying ticks', (tester) async {
    final h = _Harness(
      pois: [_poi(lat: _indoorAnchorLat)],
      route: _indoorCorridorRoute(),
    );
    addTearDown(h.dispose);
    await h.startIndoor(tester);

    // Walk south in outlier-safe hops toward the anchor. Canonical scope
    // confirmation lands mid-walk (3 consistent identities after provider
    // stability); its flip-tick fix is published WITHOUT identity — built
    // before the claim advanced.
    await h.emitWifi(tester, lat: 30.86525);
    await h.emitWifi(tester, lat: 30.86550);
    // 11 m from the anchor while scope is unconfirmed/just-flipped:
    // proximity alone must NOT confirm.
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.isArrived, isFalse);

    // Park at the anchor: first scoped qualifying tick = candidate #1.
    await h.emitWifi(tester, lat: _indoorAnchorLat);
    expect(h.controller.navigationState, NavigationState.activeIndoor);

    // Second consecutive qualifying tick confirms.
    await h.emitWifi(tester, lat: _indoorAnchorLat);
    expect(h.controller.navigationState, NavigationState.arrived);
    expect(h.controller.subState, NavigationSubState.indoor);
    await h.burnTimers(tester);
  });

  testWidgets(
      'indoor wrong-floor proximity is rejected even with a confirmed '
      'building match', (tester) async {
    final h = _Harness(
      pois: [_poi(floor: '1')],
      route: _indoorCorridorRoute(),
    );
    addTearDown(h.dispose);
    await h.startIndoor(tester);

    // Canonical scope lands on b1/'0'.
    await h.emitWifi(tester, n: 2);

    // Walk to the POI anchor on floor-'0' fixes and linger: floor identity
    // mismatches forever, so the producer must never fire no matter how
    // close the user stands.
    await h.emitWifi(tester, lat: 30.86525);
    await h.emitWifi(tester, lat: 30.86550);
    await h.emitWifi(tester, lat: _indoorAnchorLat, n: 6);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.isArrived, isFalse);
    await h.burnTimers(tester);
  });

  testWidgets(
      'indoor wrong-building proximity never confirms arrival',
      (tester) async {
    final h = _Harness(
      pois: [_poi(buid: 'b2')],
      route: _indoorCorridorRoute(),
    );
    addTearDown(h.dispose);
    await h.startIndoor(tester);

    await h.emitWifi(tester, n: 2);

    // Walk in and park at the anchor coordinates: building identity
    // ('b1' fixes vs 'b2' anchor) mismatches forever.
    await h.emitWifi(tester, lat: 30.86525);
    await h.emitWifi(tester, lat: 30.86550);
    await h.emitWifi(tester, lat: _indoorAnchorLat, n: 6);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.isArrived, isFalse);
    await h.burnTimers(tester);
  });

  testWidgets(
      'overlay gating: no arrival during ENTERING_BUILDING; the flow '
      'completes to ACTIVE_INDOOR and then confirms normally', (tester) async {
    final entrancePoi = PoiModel(
      puid: 'entr',
      buid: 'b1',
      floorNumber: '0',
      name: 'Main Entrance',
      poisType: 'Entrance',
      latitude: 30.8650,
      longitude: _lng,
      isBuildingEntrance: true,
    );
    // Destination anchor resolves from puid 'dest'; the entrance POI only
    // feeds the Phase-4 entry-dwell detection.
    final h = _Harness(pois: [entrancePoi, _poi(lat: 30.8650)]);
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    // Approach within the preload radius, then reach the entrance:
    // ENTERING_BUILDING dwell starts while standing inside the anchor
    // radius — no arrival may fire from an overlay state.
    h.provider.setGpsLocation(_gps(30.8657));
    await tester.pump();
    h.provider.setGpsLocation(_gps(30.86505));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    expect(h.controller.isArrived, isFalse);

    // Wi-Fi corroboration is identity-aware. Five ticks carry the arbiter
    // through provider stability AND the scope streak; the flip tick itself
    // still publishes a lagged, scope-less fix, so the dwell persists.
    await h.emitWifi(tester, lat: 30.8650, n: 5);
    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    expect(h.controller.isArrived, isFalse);

    // The first scoped fix corroborates the entry; the confirmation counter
    // is fresh for the restored activity, so one tick alone cannot arrive.
    await h.emitWifi(tester, lat: 30.8650);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.isArrived, isFalse);

    // Two clean qualifying ticks confirm arrival.
    await h.emitWifi(tester, lat: 30.8650, n: 2);
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets(
      'multi-segment routes anchor arrival at the FINAL point only — '
      'intermediate segment endpoints do not confirm', (tester) async {
    final h = _Harness(route: _twoSegmentRoute());
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    // Linger at the FIRST segment's endpoint: not the destination.
    await h.arriveOverGps(tester, 30.8740);
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    // Final point: two consecutive ticks confirm.
    await h.arriveOverGps(tester, 30.8700);
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets(
      'session hygiene: End clears the anchor; a new preview starts with a '
      'fresh confirmation counter', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.arriveOverGps(tester, _endLat);
    expect(h.controller.navigationState, NavigationState.arrived);
    h.controller.endNavigation();

    // Fresh session (PHASE 2: End cleared the single store, so the new run
    // is preceded by a fresh cascade seed, as in production).
    h.scope.activeNavigationRoute ??= _route();
    // Fresh session: exactly ONE qualifying tick must NOT arrive.
    await h.startOutdoor(tester);
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets(
      'manual hook equivalence: markArrived shares the producer path and '
      'stays guarded outside activities', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.establishPreview(tester);
    h.controller.markArrived();
    expect(h.controller.navigationState, NavigationState.routePreview,
        reason: 'preview is not an activity; hook must ignore it');

    await h.startOutdoor(tester);
    h.controller.markArrived();
    expect(h.controller.navigationState, NavigationState.arrived);
    expect(h.controller.isArrived, isTrue);
    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);
    await h.burnTimers(tester);
  });
}
