import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floor_transition_event.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ---------------------------------------------------------------------------
// ORIGINAL PHASE 5 — Floor Transitions (navigation half).
//
// Verifies the first-class event lifecycle: EXPECTED (connector approached),
// DETECTED (first consistent divergent evidence), CONFIRMED (evidence-gated
// acceptance), ABORTED (dwell timeout) — plus position hold, post-switch
// suppression, history bounds, and session teardown.
//
// Arbiter timing facts these tests rely on (Phase 1 notes):
//  * From cold, the 3rd Wi-Fi estimate flips belief to indoor and RESETS the
//    identity-claim streak; canonical scope lands on the 3rd consecutive
//    same-identity emission AFTER that (6th overall).
//  * While scope is unconfirmed, [_evidenceFloor] falls back to the raw
//    latest estimate, so divergence registers immediately.
//  * While scope is confirmed on floor X, an X->Y stream flips canonical
//    scope on its 3rd Y-emission: detection@3rd, confirmation@5th.
//  * The provider rejects >30 m jumps between accepted indoor fixes — test
//    movement walks in small corridor steps instead of teleporting.
//
// Geometry: everything collinear on lng 29.5828. The base position
// (lat 30.8660) sits on the floor-'0' corridor ~55 m NORTH of the connector
// (lat 30.8655) — far enough that organic tests never trip the connector,
// close enough to the corridor for ~0 deviation. Connector tests walk in
// two sub-30 m hops down to lat 30.86565.
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
    String? floorNumber,
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
  final List<PoiModel> pois = const [];

  _FakeSpaceScope({required this.floors});

  @override
  bool get hasPois => false;

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
  Future<NavigationRouteModel?> requestIndoorRouteForSession({
    required String destinationPuid,
    required String confirmedBuid,
    required String confirmedFloor,
  }) async {
    calls.add('requestIndoorRouteForSession:$destinationPuid');
    return null;
  }

  @override
  void clearNavigationRoute() {
    activeNavigationRoute = null;
    calls.add('clearNavigationRoute');
    notifyListeners();
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _lng = 29.5828;

/// Base indoor position: on the floor-'0' corridor, ~55 m from the connector.
const _baseLat = 30.8660;

/// Two-hop walk target inside the connector proximity threshold.
const _atConnectorLat = 30.86565;

UserLocation _gps(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

PositionEstimate _wifi({
  String floor = '0',
  String buid = 'b1',
  double lat = _baseLat,
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

/// Indoor route on b1 crossing floor '0' -> '1' at connector index 2
/// (points[2] is the connector on floor '0'; points[3] starts floor '1').
/// BOTH floor polylines run beneath the base latitude, so the deviation
/// checker stays quiet whichever floor the machine currently claims.
NavigationRouteModel _floorRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint(
        latitude: 30.86900,
        longitude: _lng,
        puid: 'p0',
        buid: 'b1',
        floorNumber: '0',
        poisType: 'waypoint',
      ),
      NavigationRoutePoint(
        latitude: 30.86700,
        longitude: _lng,
        puid: 'p1',
        buid: 'b1',
        floorNumber: '0',
        poisType: 'waypoint',
      ),
      NavigationRoutePoint(
        latitude: 30.86550,
        longitude: _lng,
        puid: 'conn',
        buid: 'b1',
        floorNumber: '0',
        poisType: 'connector',
      ),
      NavigationRoutePoint(
        latitude: 30.86500,
        longitude: _lng,
        puid: 'p3',
        buid: 'b1',
        floorNumber: '1',
        poisType: 'waypoint',
      ),
      NavigationRoutePoint(
        latitude: 30.86700,
        longitude: _lng,
        puid: 'p4',
        buid: 'b1',
        floorNumber: '1',
        poisType: 'waypoint',
      ),
      NavigationRoutePoint(
        latitude: 30.86900,
        longitude: _lng,
        puid: 'p5',
        buid: 'b1',
        floorNumber: '1',
        poisType: 'waypoint',
      ),
    ]);

class _Harness {
  final gpsService = _FakeLocationService();
  final native = _FakeNativePositioningService();
  final stub = _StubNavigationRepository();
  late final _FakeSpaceScope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  /// Injectable controller clock — DateTime.now() does not advance under
  /// widget-test pump().
  DateTime fakeNow = DateTime.now();

  _Harness() {
    scope = _FakeSpaceScope(floors: [_floor('0'), _floor('1')]);
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _floorRoute();
    provider = LocationProvider(
      locationService: gpsService,
      nativePositioningService: native,
    );
    controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
      navigationRepository: stub,
    );
    controller.debugNowOverride = () => fakeNow;
  }

  void dispose() {
    controller.dispose();
    provider.dispose();
  }

  /// Drives positioning into WiFi belief (pumped BEFORE starting so the
  /// belief flip lands while the machine is idle), then starts indoor
  /// navigation on the floor-crossing route: ACTIVE_INDOOR, floor '0'.
  Future<void> startIndoorOnFloorRoute(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      native.emit(_wifi());
    }
    await tester.pump();
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),

    );
    controller.startActiveNavigation();
    expect(controller.navigationState, NavigationState.activeIndoor);
    expect(controller.currentNavigatingFloor, '0');
  }

  /// Emits [n] estimates and lets the pipeline process them.
  Future<void> emitWifi(
    WidgetTester tester, {
    String floor = '0',
    double lat = _baseLat,
    int n = 1,
  }) async {
    for (var i = 0; i < n; i++) {
      native.emit(_wifi(floor: floor, lat: lat));
    }
    await tester.pump();
  }

  /// Walks the user south into the connector threshold in sub-30 m hops so
  /// the provider's outlier guard accepts every step. The second hop enters
  /// the 30 m radius and triggers the connector-initiated dwell.
  Future<void> approachConnector(WidgetTester tester) async {
    await emitWifi(tester, lat: 30.8658);
    await emitWifi(tester, lat: _atConnectorLat);
  }

  /// Burns the pending indoor-stale timer so the test ends clean.
  Future<void> burnTimers(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }

  void bumpClockBy(int seconds) {
    fakeNow = fakeNow.add(Duration(seconds: seconds));
  }
}

void main() {
  testWidgets(
      'connector approach emits EXPECTED and enters FLOOR_TRANSITION with '
      'held position and preloaded target floor', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);

    await h.approachConnector(tester);

    expect(h.controller.navigationState, NavigationState.floorTransition);
    expect(h.controller.isTransitioningFloors, isTrue);
    expect(h.controller.subState, NavigationSubState.transitioning);
    expect(h.controller.snapshot.expectedNextFloor, '1');
    expect(h.controller.positioningStatus, contains('Moving to Floor 1'));
    // Position held where the dwell began, not jumping to live updates.
    expect(h.controller.heldPositionDuringTransition, isNotNull);
    expect(h.controller.heldPositionDuringTransition!.latitude,
        closeTo(_atConnectorLat, 0.00001));
    // Residency preload happened at the EXPECTED stage — candidacy only,
    // never physical-floor proof.
    expect(h.scope.calls, contains('selectFloorForNavigation:1'));
    // Route bookkeeping must NOT have claimed the new floor yet.
    expect(h.controller.currentNavigatingFloor, '0');

    final event = h.controller.lastFloorTransitionEvent;
    expect(event, isNotNull);
    expect(event!.stage, FloorTransitionStage.expected);
    expect(event.trigger, FloorTransitionTrigger.connectorProximity);
    expect(event.fromFloor, '0');
    expect(event.toFloor, '1');

    await h.burnTimers(tester);
  });

  testWidgets(
      'organic drift: raw divergent evidence emits DETECTED immediately; '
      'three consecutive ticks CONFIRM via the organic path', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);

    // Far from the connector — pure evidence-driven flow. Scope is still
    // unconfirmed after the belief flip, so the RAW estimate fallback makes
    // the very first divergent tick register as DETECTED.
    await h.emitWifi(tester, floor: '1', lat: _baseLat);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    var detected = h.controller.lastFloorTransitionEvent;
    expect(detected!.stage, FloorTransitionStage.detected);
    expect(detected.trigger, FloorTransitionTrigger.evidence);
    expect(detected.fromFloor, '0');
    expect(detected.toFloor, '1');

    // Second tick accumulates; third reaches stabilityMinEstimates — the
    // organic path begins and completes in the same pipeline pass.
    await h.emitWifi(tester, floor: '1', lat: _baseLat, n: 2);

    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.currentNavigatingFloor, '1');
    expect(h.controller.snapshot.expectedNextFloor, isNull);

    final events = h.controller.floorTransitionEvents;
    expect(events.length, 2);
    expect(events[0].stage, FloorTransitionStage.detected);
    expect(events[1].stage, FloorTransitionStage.confirmed);
    expect(events[1].trigger, FloorTransitionTrigger.evidence);
    expect(events[1].fromFloor, '0');
    expect(events[1].toFloor, '1');
    // Completion synced residency to the proven floor.
    expect(h.scope.calls, contains('selectFloorForNavigation:1'));

    await h.burnTimers(tester);
  });

  testWidgets(
      'position hold suppresses evidence evaluation while the connector '
      'dwell is alive', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);
    await h.approachConnector(tester);
    expect(h.controller.floorTransitionEvents.length, 1);

    // Divergent estimates during the dwell cannot advance detection: the
    // held-position branch short-circuits the pipeline before the evidence
    // checker runs.
    await h.emitWifi(tester, floor: '1', lat: _atConnectorLat, n: 3);

    expect(h.controller.navigationState, NavigationState.floorTransition);
    expect(h.controller.floorTransitionEvents.length, 1);
    expect(h.controller.currentNavigatingFloor, '0');

    await h.burnTimers(tester);
  });

  testWidgets(
      'timeout emits ABORTED, reverts to ACTIVE_INDOOR, clears expectation; '
      'loitering re-dwells; leaving lets organic evidence confirm',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);
    await h.approachConnector(tester);
    expect(h.controller.navigationState, NavigationState.floorTransition);

    // Advance past the transition timeout. The abort tick falls through to
    // the full pipeline while the user still stands inside the connector
    // radius — so proximity legitimately RE-DWELLS immediately (pre-existing
    // behavior this test pins).
    h.bumpClockBy(NavigationConfig.transitionTimeoutSeconds + 1);
    await h.emitWifi(tester, floor: '1', lat: _atConnectorLat);

    expect(h.controller.navigationState, NavigationState.floorTransition);
    expect(h.controller.snapshot.expectedNextFloor, '1');
    var events = h.controller.floorTransitionEvents;
    expect(events.length, 3);
    expect(events[0].stage, FloorTransitionStage.expected);
    expect(events[1].stage, FloorTransitionStage.aborted);
    expect(events[1].trigger, FloorTransitionTrigger.timeout);
    expect(events[1].toFloor, '1');
    expect(events[2].stage, FloorTransitionStage.expected);

    // Second timeout, walking north out of the radius in an outlier-safe
    // 22 m hop: abort lands at lat 30.86585 (39 m from the connector) and
    // STAYS — no re-trigger.
    h.bumpClockBy(NavigationConfig.transitionTimeoutSeconds + 1);
    await h.emitWifi(tester, floor: '1', lat: 30.86585);

    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.snapshot.expectedNextFloor, isNull);
    expect(h.controller.currentNavigatingFloor, '0');
    events = h.controller.floorTransitionEvents;
    expect(events.length, 4);
    expect(events[3].stage, FloorTransitionStage.aborted);

    // Away from the connector, organic evidence completes the crossing.
    // Canonical scope was confirmed on floor '0' by the approach walk, and
    // the identity-lagged fix on the scope-flip tick still reads '0', so the
    // confirmed-scope cadence is DETECTED@4th / CONFIRMED@6th of these
    // post-abort emissions.
    await h.emitWifi(tester, floor: '1', lat: _baseLat, n: 4);

    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.currentNavigatingFloor, '1');
    events = h.controller.floorTransitionEvents;
    expect(events.length, 6);
    expect(events[4].stage, FloorTransitionStage.detected);
    expect(events[4].toFloor, '1');
    expect(events[5].stage, FloorTransitionStage.confirmed);
    expect(events[5].trigger, FloorTransitionTrigger.evidence);
    expect(events[5].toFloor, '1');

    await h.burnTimers(tester);
  });

  testWidgets(
      'post-switch suppression gates detection until the cooldown expires',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);

    // Complete an organic flip to floor '1'. Unconfirmed scope means raw
    // fallback drives detection: detected@1st, confirmed@3rd of these.
    await h.emitWifi(tester, floor: '1', lat: _baseLat, n: 5);
    expect(h.controller.currentNavigatingFloor, '1');
    expect(h.controller.floorTransitionEvents.length, 2);

    // Inside the suppression window: ticks short-circuit before detection.
    await h.emitWifi(tester, floor: '0', lat: _baseLat);
    expect(h.controller.floorTransitionEvents.length, 2);

    // Past the window, accumulation resumes. Scope is NOW confirmed on
    // floor '1'; the identity-lagged fix on the scope-flip tick still reads
    // the old floor, so the flip back needs 6 emissions:
    // DETECTED@4th, CONFIRMED@6th.
    h.bumpClockBy(NavigationConfig.postFloorSwitchSuppressSeconds + 1);
    await h.emitWifi(tester, floor: '0', lat: _baseLat, n: 6);

    expect(h.controller.currentNavigatingFloor, '0');
    final stages =
        h.controller.floorTransitionEvents.map((e) => e.stage).toList();
    expect(stages, [
      FloorTransitionStage.detected,
      FloorTransitionStage.confirmed,
      FloorTransitionStage.detected,
      FloorTransitionStage.confirmed,
    ]);

    await h.burnTimers(tester);
  });

  testWidgets('endNavigation mid-dwell clears machine context and history',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);
    await h.approachConnector(tester);
    expect(h.controller.navigationState, NavigationState.floorTransition);

    h.controller.endNavigation();

    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.controller.currentNavigatingFloor, isNull);
    expect(h.controller.snapshot.expectedNextFloor, isNull);
    expect(h.controller.heldPositionDuringTransition, isNull);
    expect(h.controller.floorTransitionEvents.length, 0);
    expect(h.controller.lastFloorTransitionEvent, isNull);

    // Late ticks after teardown are inert.
    await h.emitWifi(tester, floor: '1', lat: _atConnectorLat);
    expect(h.controller.navigationState, NavigationState.idle);
    expect(h.controller.floorTransitionEvents.length, 0);

    await h.burnTimers(tester);
  });

  testWidgets(
      'event history is bounded by the config limit and cleared when a new '
      'session previews', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);

    // Seed canonical scope onto floor '0' (claim completes) so every flip
    // below follows the uniform confirmed-scope cadence: detect@3rd, @5th.
    await h.emitWifi(tester, floor: '0', lat: _baseLat, n: 2);
    expect(h.controller.floorTransitionEvents.length, 0);

    // Four completed flips (det+conf each) plus one bare detection:
    // 9 events pushed against a limit of 8 — the oldest drops. Confirmed-
    // scope cadence (identity-lag): 6 emissions per completed flip.
    for (var round = 0; round < 4; round++) {
      final floor = round.isEven ? '1' : '0';
      await h.emitWifi(tester, floor: floor, lat: _baseLat, n: 6);
      expect(h.controller.currentNavigatingFloor, floor,
          reason: 'flip $round should complete');
      h.bumpClockBy(NavigationConfig.postFloorSwitchSuppressSeconds + 1);
    }
    await h.emitWifi(tester, floor: '1', lat: _baseLat, n: 4);

    final limit = NavigationConfig.floorTransitionEventHistoryLimit;
    final events = h.controller.floorTransitionEvents;
    expect(limit, 8);
    expect(events.length, limit);
    // Oldest dropped: first survivor is round-A's CONFIRMED.
    expect(events.first.stage, FloorTransitionStage.confirmed);
    expect(events.first.toFloor, '1');
    expect(events.last.stage, FloorTransitionStage.detected);
    expect(events.last.toFloor, '1');

    // A brand-new session starts with a clean slate.
    h.controller.endNavigation();
    h.scope.activeNavigationRoute = _floorRoute();
    h.controller.startRoutePreview(
      destinationPuid: 'dest2',
      destinationSpace: _building(),

    );
    expect(h.controller.floorTransitionEvents.length, 0);
    expect(h.controller.lastFloorTransitionEvent, isNull);

    await h.burnTimers(tester);
  });

  testWidgets('GPS-only ticks never advance floor detection', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startIndoorOnFloorRoute(tester);

    // GPS fixes near the corridor (so deviation checks stay quiet) carry no
    // floor evidence and must not disturb the machine or emit events.
    for (var i = 0; i < 4; i++) {
      h.provider.setGpsLocation(_gps(30.86595 + i * 0.000005));
      await tester.pump();
    }
    expect(h.controller.floorTransitionEvents.length, 0);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.currentNavigatingFloor, '0');

    await h.burnTimers(tester);
  });

  // ── PHASE 9 — Floor-Transition Hardening & Rendering Continuity ──

  group('PHASE 9: guidance continuity across the transition lifecycle', () {
    testWidgets('route object identity survives EXPECTED, ABORTED, DETECTED '
        'and CONFIRMED across one scripted journey', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      await h.startIndoorOnFloorRoute(tester);
      final route = h.scope.activeNavigationRoute!;

      // EXPECTED — connector proximity arms the dwell with a held position.
      await h.approachConnector(tester);
      expect(h.controller.lastFloorTransitionEvent!.stage,
          FloorTransitionStage.expected);
      expect(h.scope.activeNavigationRoute, same(route));
      expect(h.controller.activeRoute, same(route));

      // ABORTED — timeout reverts safely while still inside the radius
      // (proximity legitimately re-dwells on that same tick).
      h.bumpClockBy(NavigationConfig.transitionTimeoutSeconds + 1);
      await h.emitWifi(tester, floor: '0');
      expect(
        h.controller.floorTransitionEvents
            .any((e) => e.stage == FloorTransitionStage.aborted),
        isTrue,
      );
      expect(h.scope.activeNavigationRoute, same(route));

      // Second timeout with a 22 m hop north out of the radius: abort lands
      // and STAYS — no re-trigger.
      h.bumpClockBy(NavigationConfig.transitionTimeoutSeconds + 1);
      await h.emitWifi(tester, floor: '1', lat: 30.86585);
      expect(h.controller.navigationState, NavigationState.activeIndoor);
      expect(h.scope.activeNavigationRoute, same(route));

      // Away from the connector, organic evidence completes the crossing:
      // scope-confirmation lag means DETECTED lands a few ticks in — emit
      // enough for the full detected->confirmed cycle.
      await h.emitWifi(tester, floor: '1', lat: _baseLat, n: 6);
      expect(h.controller.currentNavigatingFloor, '1');
      final events = h.controller.floorTransitionEvents;
      expect(events[events.length - 2].stage, FloorTransitionStage.detected);
      expect(events.last.stage, FloorTransitionStage.confirmed);
      expect(h.scope.activeNavigationRoute, same(route));
      expect(h.controller.activeRoute, same(route));

      await h.burnTimers(tester);
    });
  });

  group('PHASE 9: connector-last-point robustness (BUG-15)', () {
    testWidgets('a route whose final point is a connector neither crashes '
        'nor fabricates a transition', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.scope.activeNavigationRoute = NavigationRouteModel(points: [
        NavigationRoutePoint(
            latitude: 30.86900,
            longitude: _lng,
            puid: 'p0',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'waypoint'),
        NavigationRoutePoint(
            latitude: 30.86550,
            longitude: _lng,
            puid: 'conn-last',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'connector'),
      ]);
      await h.startIndoorOnFloorRoute(tester);

      // Walk straight into the final connector point.
      await h.emitWifi(tester, lat: 30.8655);
      await h.emitWifi(tester, lat: 30.8655);

      expect(h.controller.navigationState, NavigationState.activeIndoor,
          reason: 'no successor floor exists — nothing may fire');
      expect(h.controller.floorTransitionEvents, isEmpty);

      await h.burnTimers(tester);
    });
  });

  group('PHASE 9: segment-exhaustion semantics', () {
    LatLng pLocal(double lat) => LatLng(lat, _lng);

    NavigationRouteModel singleSegRoute() =>
        NavigationRouteModel.fromSegments(
          segments: [
            RouteSegment.indoor(
              points: [pLocal(30.86600), pLocal(30.86550)],
              buildingId: 'b1',
              floorNumber: '0',
            ),
          ],
          status: RouteModelStatus.ready,
        );

    testWidgets('exhausting segments NEAR the anchor defers to arrival',
        (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.scope.activeNavigationRoute = singleSegRoute();
      await h.startIndoorOnFloorRoute(tester);

      // Walk onto the segment endpoint in outlier-safe hops.
      await h.emitWifi(tester, lat: 30.86575);
      await h.emitWifi(tester, lat: 30.86550);

      expect(h.controller.routeIncomplete, isFalse,
          reason: 'arrival owns completion near the anchor');
      expect(h.controller.isActive, isTrue);
      await h.burnTimers(tester);
    });

    testWidgets('exhausting segments AWAY from the anchor flags incompleteness'
        ' and keeps the session alive', (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.scope.activeNavigationRoute = singleSegRoute();
      await h.startIndoorOnFloorRoute(tester);
      h.controller.debugClearArrivalAnchorForTest();

      await h.emitWifi(tester, lat: 30.86575);
      await h.emitWifi(tester, lat: 30.86550);

      expect(h.controller.routeIncomplete, isTrue);
      expect(h.controller.isActive, isTrue);
      await h.burnTimers(tester);
    });
  });
}
