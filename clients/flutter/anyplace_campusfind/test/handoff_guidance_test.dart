import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
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
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/navigation_state_model.dart';
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';

// ---------------------------------------------------------------------------
// PHASE 8 — Outdoor→Indoor Handoff Completion (BUG-7)
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: 8.0,
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

PoiModel _poi(String puid, String name, {String floor = '0'}) => PoiModel(
      puid: puid,
      buid: 'b1',
      floorNumber: floor,
      name: name,
      poisType: puid == 'entr' ? 'Entrance' : 'room',
      // Far from the fixture GPS position so neither proximity-arrival
      // nor indoor-identity arrival fires mid-test.
      latitude: 30.8400,
      longitude: _lng,
      isBuildingEntrance: puid == 'entr',
    );

NavigationRouteModel _outdoorRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8750, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

/// Indoor route ending at the destination on the given floor.
NavigationRouteModel _indoorRoute(String destPuid, String floor) =>
    NavigationRouteModel(points: [
      NavigationRoutePoint(
          latitude: 30.8650,
          longitude: _lng,
          puid: 'entr',
          buid: 'b1',
          floorNumber: '0',
          poisType: 'Entrance'),
      NavigationRoutePoint(
          latitude: 30.8650,
          longitude: _lng,
          puid: destPuid,
          buid: 'b1',
          floorNumber: floor,
          poisType: 'room'),
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
  List<PoiModel> pois;
  @override
  bool get hasPois => pois.isNotEmpty;
  @override
  FloorplanModel? activeFloorplan;
  @override
  final CustomRouteRepository customRouteRepository = CustomRouteRepository();

  /// PHASE 8 recording.
  final indoorRequests = <Map<String, String>>[];
  NavigationRouteModel? Function(Map<String, String>)? onIndoorRequest;

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
    selectedFloor = null;
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
  }) async {
    final req = {
      'dest': destinationPuid,
      'buid': confirmedBuid,
      'floor': confirmedFloor,
    };
    indoorRequests.add(req);
    return onIndoorRequest?.call(req);
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

class _Harness {
  final gpsService = _GpsService();
  final native = _Native();
  late final _Scope scope;
  late final LocationProvider provider;
  late final NavigationController controller;

  _Harness() {
    scope = _Scope(
      [_floor('0'), _floor('2')],
      [
        _poi('entr', 'Main Entrance'),
        _poi('dest', 'Room 104'),
        _poi('dest2', 'Room 105'),
      ],
    );
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _outdoorRoute();
    provider = LocationProvider(
      locationService: gpsService,
      nativePositioningService: native,
    );
    controller = NavigationController(
      spaceProvider: scope,
      locationProvider: provider,
      navigationRepository: null,
    );
  }

  void dispose() {
    controller.dispose();
    provider.dispose();
  }

  void startOutdoorAtEntrance() {
    provider.setGpsLocation(_gps(30.86505));
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),
    );
    controller.startActiveNavigation();
  }

  /// Drives a cold arbiter through belief flip + scope confirmation so the
  /// strict entry corroboration accepts (same choreography as the machine
  /// suite).
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

  testWidgets('scripted O→I handoff fetches exactly one indoor route for '
      'the confirmed scope and commits it write-through', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoorAtEntrance();

    h.scope.onIndoorRequest =
        (req) => _indoorRoute('dest', req['floor'] ?? '0');

    await h.corroborateEntry(tester);
    // Let the unawaited guidance future run.
    await tester.pump();
    await tester.pump();

    expect(h.scope.indoorRequests.length, 1);
    expect(h.scope.indoorRequests.first['dest'], 'dest');
    expect(h.scope.indoorRequests.first['buid'], 'b1');

    // Write-through commit: store == evaluation == indoor geometry.
    final committed = h.scope.activeNavigationRoute!;
    expect(committed.hasIndoorSegment, isTrue);
    expect(committed.points.last.puid, 'dest');
    expect(h.controller.activeRoute, same(committed));
    expect(h.controller.sessionForTest!.routeRevision, 1);

    // The latch holds: more ticks produce no duplicate requests.
    h.provider.setGpsLocation(_gps(30.86505));
    await tester.pump();
    await tester.pump();
    expect(h.scope.indoorRequests.length, 1,
        reason: 'once-per-session latch prevents duplicates');

    // Status bar shows the normal line — no hint flag set.
    expect(h.controller.indoorGuidanceUnavailable, isFalse);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('guidance failure keeps the old route, surfaces the hint, and '
      'a later floor confirmation retries', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var now = DateTime.now();
    h.controller.debugNowOverride = () => now;
    h.startOutdoorAtEntrance();

    // First attempt fails.
    h.scope.onIndoorRequest = (_) => null;

    await h.corroborateEntry(tester);
    await tester.pump();
    await tester.pump();

    expect(h.scope.indoorRequests.length, 1);
    expect(h.scope.activeNavigationRoute!.hasIndoorSegment, isFalse,
        reason: 'failure keeps the outdoor-built general path');
    expect(h.controller.indoorGuidanceUnavailable, isTrue);
    expect(navigationStatusLabel(h.controller),
        'Indoor route unavailable \u2014 following general path');

    // A floor confirmation retries the fetch and succeeds now.
    now = now.add(const Duration(seconds: 20));
    h.scope.onIndoorRequest =
        (req) => _indoorRoute('dest', req['floor'] ?? '2');
    // Estimates 1-3 re-confirm the arbiter scope onto floor '2'; the
    // following ones feed the controller's 3-tick organic-drift detector.
    for (var i = 0; i < 8; i++) {
      h.native.emit(_wifi(floor: '2'));
    }
    await tester.pump();
    await tester.pump();

    expect(h.scope.indoorRequests.length, 2,
        reason: 'the latch stayed open after failure');
    final committed = h.scope.activeNavigationRoute!;
    expect(committed.points.last.puid, 'dest');
    expect(committed.points.last.floorNumber, '2');
    expect(h.controller.indoorGuidanceUnavailable, isFalse);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('PHASE-R: a composed segmented journey already ending at the '
      'destination is recognized by the handoff latch and NOT replaced',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    // Composed cross-building shape: outdoorWalking + destination-building
    // indoorRouting leg. The leg starts at the building entrance (where the
    // corroborating device stands) and ends at the destination POI itself
    // ((30.8400, _lng) per the _poi fixture). The derived points carry
    // synthetic '<segmentType>_<n>' puids — exactly the identity shape the
    // old `points.last.puid == destinationPuid` latch could never recognize.
    final composed = NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.outdoor(
          points: const [LatLng(30.8750, _lng), LatLng(30.8500, _lng)],
          buildingId: 'b1',
        ),
        RouteSegment.indoor(
          points: const [LatLng(30.8650, _lng), LatLng(30.8400, _lng)],
          buildingId: 'b1',
          floorNumber: '0',
          instruction: 'Enter Building One',
        ),
      ],
      status: RouteModelStatus.ready,
    );
    h.scope.activeNavigationRoute = composed;

    var fetchAttempts = 0;
    h.scope.onIndoorRequest = (req) {
      fetchAttempts++;
      return null;
    };

    h.startOutdoorAtEntrance();
    final seededRoute = h.scope.activeNavigationRoute;
    final sid = h.controller.sessionId!;
    expect(seededRoute, same(composed));

    await h.corroborateEntry(tester);
    // Let any unawaited guidance future run — there must be none.
    await tester.pump();
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(fetchAttempts, 0,
        reason: 'an already-complete composed journey must not be refetched');
    expect(h.scope.activeNavigationRoute, same(seededRoute),
        reason: 'the valid segmented route must be preserved verbatim');
    expect(h.controller.activeRoute, same(seededRoute));
    expect(h.controller.sessionId, sid);
    expect(h.controller.sessionForTest!.routeRevision, 0,
        reason: 'recognition is not a committed replacement');
    expect(h.controller.indoorGuidanceUnavailable, isFalse);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('PHASE-R: an incomplete composed journey (fallback leg ending '
      'away from the destination) still triggers the guidance refetch',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    // Degraded composed shape: the entrance leg ends at the BUILDING CENTROID
    // (30.8650), far from the destination POI (30.8400) — the journey does
    // NOT reach the destination, so guidance must legitimately be fetched.
    final degraded = NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.outdoor(
          points: const [LatLng(30.8750, _lng), LatLng(30.8500, _lng)],
          buildingId: 'b1',
        ),
        RouteSegment.entrance(
          points: const [LatLng(30.8655, _lng), LatLng(30.8650, _lng)],
          buildingId: 'b1',
          floorNumber: '0',
          isIncomplete: true,
          isFallbackLocation: true,
        ),
      ],
      status: RouteModelStatus.partial,
      partialRouteWarning: 'Route incomplete',
    );
    h.scope.activeNavigationRoute = degraded;
    h.scope.onIndoorRequest =
        (req) => _indoorRoute('dest', req['floor'] ?? '0');

    h.startOutdoorAtEntrance();

    await h.corroborateEntry(tester);
    await tester.pump();
    await tester.pump();

    expect(h.scope.indoorRequests.length, 1,
        reason: 'a journey that does not reach the destination must refetch');
    expect(h.controller.indoorGuidanceUnavailable, isFalse);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('retarget resets the latch so the new session re-ensures '
      'guidance', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoorAtEntrance();
    var ensureCalls = 0;
    h.scope.onIndoorRequest = (req) {
      ensureCalls++;
      return _indoorRoute(req['dest']!, req['floor'] ?? '0');
    };

    await h.corroborateEntry(tester);
    await tester.pump();
    await tester.pump();
    expect(ensureCalls, 1);

    // Retarget installs a fresh session; the next handoff must re-ensure.
    await h.controller.retargetDestination(_poi('dest2', 'Room 105'));
    expect(h.controller.sessionForTest!.routeRevision, 0);

    // A later floor confirmation re-runs guidance for the new target.
    for (var i = 0; i < 8; i++) {
      h.native.emit(_wifi(floor: '2'));
    }
    await tester.pump();
    await tester.pump();
    expect(ensureCalls, greaterThanOrEqualTo(2));
    expect(h.scope.indoorRequests.last['dest'], 'dest2');

    // Burn the LP indoor-stale timer so the test ends clean.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('PHASE 10 / Matrix E: I→O→I double-handoff keeps identity and '
      'route through both boundaries', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoorAtEntrance();
    final sid = h.controller.sessionId!;

    // In: corroboration confirms ACTIVE_INDOOR.
    await h.corroborateEntry(tester);
    await tester.pump();
    await tester.pump();
    expect(h.scope.activeNavigationRoute, isNotNull);
    final routeAtIndoor = h.scope.activeNavigationRoute!;

    // Out: let the Wi-Fi belief go stale, then accumulate three good
    // outside confirmations.
    await tester.pump(const Duration(seconds: 11));
    for (var i = 0; i < NavigationConfig.exitConfirmationCount; i++) {
      h.provider.setGpsLocation(_gps(30.8560));
    }
    expect(h.controller.navigationState, NavigationState.exitingBuilding);
    // The confirming tick resolves the exit dwell.
    h.provider.setGpsLocation(_gps(30.8560));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    // INV-9: identity + route survive the exit boundary.
    expect(h.controller.sessionId, sid);
    expect(h.scope.activeNavigationRoute, same(routeAtIndoor));

    // Back in: approach preloads again and corroboration re-confirms —
    // WITHOUT a new session id.
    h.provider.setGpsLocation(_gps(30.86505));
    for (var i = 0; i < 6; i++) {
      h.native.emit(_wifi());
    }
    await tester.pump();
    expect(h.controller.buildingPreloadedForTest, isTrue,
        reason: 're-entry re-runs the residency preload');
    await h.corroborateEntry(tester);
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    expect(h.controller.sessionId, sid,
        reason: 'returning indoors mid-trip is the SAME session');

    await tester.pump(const Duration(seconds: 11));
  });
}
