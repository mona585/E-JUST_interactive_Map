import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/floorplan_model.dart';
import 'package:anyplace_campusfind/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/models/position_estimate.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/route_segment.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/models/navigation_state.dart';
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';
import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ---------------------------------------------------------------------------
// ORIGINAL PHASE 6 â€” Arrival.
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

class _FakeNativePositioningService {
  final _estimateController = StreamController<PositionEstimate>.broadcast();

  void emit(PositionEstimate estimate) => _estimateController.add(estimate);
}

class _StubNavigationRepository implements NavigationRepository {
  List<LatLng>? servedPoints;

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    final points = servedPoints;
    if (points == null || points.length < 2) {
      throw Exception('stub: unexpected call');
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
  void selectFloorForNavigation(FloorModel floor) {
    selectedFloor = floor;
    calls.add('selectFloorForNavigation:${floor.floorNumber}');
    notifyListeners();
  }

  @override
  void selectSpaceForNavigation(SpaceModel space) {
    selectedSpace = space;
    calls.add('selectSpaceForNavigation:${space.buid}');
    notifyListeners();
  }

  @override
  void releaseIndoorContextForNavigation() {
    calls.add('releaseIndoorContextForNavigation');
    notifyListeners();
  }

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {
    activeNavigationRoute = route;
    calls.add('adoptNavigatedRoute');
    notifyListeners();
  }

  @override
  Future<bool> requestRouteForRetarget(PoiModel poi) async {
    calls.add('requestRouteForRetarget:${poi.puid}');
    return true;
  }

  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    calls.add('clearNavigationRoute');
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Fixtures â€” collinear on lng 29.5828.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

/// Default route-endpoint anchor (used when no POI matches).
const _endLat = 30.8560;

UserLocation _gps(double lat,
    {double accuracy = 8.0, DateTime? at}) =>
    UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: at ?? DateTime.now(),
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

/// Flat collinear route ending at [endLat] (the fallback arrival anchor).
NavigationRouteModel _route({double endLat = _endLat}) =>
    NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8750, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8700, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: endLat, longitude: _lng),
    ]);

/// Two-segment journey whose FIRST segment endpoint (30.8740) is not the
/// destination â€” the anchor must be the FINAL point (30.8700). Points are
/// declared explicitly so every point shares floor '0' (the deviation
/// filter compares against the navigating floor's projection).
NavigationRouteModel _twoSegmentRoute() => NavigationRouteModel(
      points: [
        NavigationRoutePoint.outdoor(latitude: 30.8760, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8740, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8720, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8700, longitude: _lng),
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
  late final LocationViewModel provider;
  late final NavigationViewModel controller;

  _Harness({List<PoiModel> pois = const [], NavigationRouteModel? route}) {
    scope = _FakeSpaceScope(
      floors: [_floor('0'), _floor('1')],
      pois: pois,
    );
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = route ?? _route();
    provider = LocationViewModel(
      locationService: gpsService,
    );
    controller = NavigationViewModel(
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

    // inside / far / inside / inside â€” only CONSECUTIVE qualifiers count.
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
      'multi-segment routes anchor arrival at the FINAL point only â€” '
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

  // â”€â”€ PHASE 13 â€” outdoor arrival evidence-quality gating â”€â”€

  testWidgets('PHASE 13: a poor-accuracy pair inside the radius does NOT '
      'arrive; a good pair does', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    for (var i = 0; i < 2; i++) {
      h.provider.setGpsLocation(_gps(_endLat, accuracy: 40));
      await tester.pump();
    }
    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'INV-8: poor-band fixes are not arrival evidence');

    await h.arriveOverGps(tester, _endLat);
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets('PHASE 13: a stale tick resets the confirmation counter',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);

    // One good qualifying tick (counter = 1).
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();

    // A stale fix inside the radius must reset, not confirm.
    h.provider.setGpsLocation(_gps(_endLat,
        at: DateTime.now().subtract(const Duration(seconds: 30))));
    await tester.pump();

    // A single further good tick is NOT enough after the reset.
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    // The second good tick completes the fresh pair.
    h.provider.setGpsLocation(_gps(_endLat));
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnTimers(tester);
  });

  testWidgets('PHASE 13: the anchor is cached per (session, revision) and '
      're-resolves on committed replacement', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    final anchor1 = h.controller.arrivalAnchorForTest;
    expect(anchor1, isNotNull);

    // Unrelated scope churn cannot move the anchor.
    h.scope.selectFloor(_floor('0'));
    expect(identical(h.controller.arrivalAnchorForTest, anchor1), isTrue);

    // A committed reroute bumps the revision â†’ the anchor re-resolves.
    final replacementPoints = [
      const LatLng(30.8930, _lng),
      const LatLng(_endLat, _lng),
    ];
    h.stub.servedPoints = replacementPoints;
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    now = now.add(const Duration(seconds: 20));
    h.provider.setGpsLocation(_gps(30.9950));
    h.provider.setGpsLocation(_gps(30.9950));
    await tester.pump();
    await tester.pump();

    expect(h.controller.sessionForTest!.routeRevision, 1);
    expect(identical(h.controller.arrivalAnchorForTest, anchor1), isFalse,
        reason: 'revision bump re-resolves the anchor');
    await h.burnTimers(tester);
  });
}
