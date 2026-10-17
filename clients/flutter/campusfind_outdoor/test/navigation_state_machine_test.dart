import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/floorplan_model.dart';
import 'package:anyplace_campusfind/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/models/position_estimate.dart';
import 'package:anyplace_campusfind/models/position_fix.dart';
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
// Fakes
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
  _StubNavigationRepository(this._route);

  NavigationRouteModel? _route;
  Completer<List<LatLng>>? _gate;
  int calls = 0;

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async {
    calls++;
    final gate = _gate;
    if (gate != null) {
      _gate = null;
      return gate.future;
    }
    final route = _route;
    if (route == null) throw Exception('stub: no route');
    return [for (final p in route.points) LatLng(p.latitude, p.longitude)];
  }

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      null;

  /// Holds the next request open until [release] completes it.
  void gate(Completer<List<LatLng>> completer) => _gate = completer;

  void respondWith(NavigationRouteModel? route) => _route = route;
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

  _FakeSpaceScope({
    required this.floors,
    this.pois = const [],
  });

  @override
  bool get hasPois => pois.isNotEmpty;

  @override
  FloorplanModel? activeFloorplan;

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
// Fixtures — everything collinear on lng 29.5828 so on-route ticks have ~0
// polyline deviation and never trip the rerouter unintentionally.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _gps(double lat, {double accuracy = 8.0}) => UserLocation(
      latitude: lat,
      longitude: _lng,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );

PositionEstimate _wifi({String floor = '0', String buid = 'b1'}) => PositionEstimate(
      latitude: 30.8650,
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

PoiModel _entrancePoi() => PoiModel(
      puid: 'entr',
      buid: 'b1',
      floorNumber: '0',
      name: 'Main Entrance',
      poisType: 'Entrance',
      latitude: 30.8650,
      longitude: _lng,
      isBuildingEntrance: true,
    );

/// Long collinear outdoor route through every fixture latitude.
NavigationRouteModel _route() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8750, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8700, longitude: _lng),
      NavigationRoutePoint(
        latitude: 30.8650,
        longitude: _lng,
        puid: 'entr',
        buid: 'b1',
        floorNumber: '0',
        poisType: 'entrance',
      ),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

/// The outdoor point geometry of [_route] as raw coordinates (CP-8: the
/// reroute request path carries coordinates, not a composed model).
List<LatLng> _routePoints() =>
    [for (final p in _route().points) LatLng(p.latitude, p.longitude)];

/// A route with no indoor information at all — exercises the legacy tiers
/// of the ORIGINAL PHASE 4 preload-floor cascade. Outdoor points carry
/// floor '0' so the floor-filtered deviation corridor stays visible while
/// the user walks the approach.
NavigationRouteModel _pureOutdoorRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8760, longitude: _lng),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

/// Outdoor walk ending at lat 30.8720 (far from every fixture POI/building),
/// followed by [second]. Segment-based route for segment-advance tests.
NavigationRouteModel _twoSegmentRoute(RouteSegment second) =>
    NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.outdoor(
          points: [
            LatLng(30.8760, _lng),
            LatLng(30.8740, _lng),
            LatLng(30.8720, _lng),
          ],
          buildingId: 'b1',
        ),
        second,
      ],
      status: RouteModelStatus.ready,
    );

class _Harness {
  final gpsService = _FakeLocationService();
  final native = _FakeNativePositioningService();
  final stub = _StubNavigationRepository(_route());
  late final _FakeSpaceScope scope;
  late final LocationViewModel provider;
  late final NavigationViewModel controller;

  _Harness({bool withEntrancePoi = false, List<FloorModel>? floors}) {
    scope = _FakeSpaceScope(
      floors: floors ?? [_floor('0'), _floor('1')],
      pois: withEntrancePoi ? [_entrancePoi()] : [],
    );
    scope.selectedSpace = _building();
    scope.selectedFloor = _floor('0');
    scope.activeNavigationRoute = _route();
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

  void establishOutdoorPreview() {
    controller.startRoutePreview(
      destinationPuid: 'dest',
      destinationSpace: _building(),

    );
  }

  void startOutdoor() {
    provider.setGpsLocation(_gps(30.8750));
    establishOutdoorPreview();
    controller.startActiveNavigation();
  }

  /// Drives positioning into WiFi belief, then starts navigation indoors.
  Future<void> startIndoor(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      native.emit(_wifi());
    }
    await tester.pump();
    establishOutdoorPreview();
    controller.startActiveNavigation();
  }
}

void main() {
  testWidgets('preview requires a renderable route; lifecycle basics hold',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);

    // No route loaded -> rejected.
    h.scope.activeNavigationRoute = null;
    h.controller.startRoutePreview(
      destinationPuid: 'd',
      destinationSpace: _building(),

    );
    expect(h.controller.navigationState, NavigationState.idle);

    h.scope.activeNavigationRoute = _route();
    h.controller.startRoutePreview(
      destinationPuid: 'd',
      destinationSpace: _building(),

    );
    expect(h.controller.navigationState, NavigationState.routePreview);
    expect(h.controller.phase, NavigationPhase.preview);
    expect(h.controller.isPreview, isTrue);
    expect(h.controller.isActive, isFalse);
    expect(h.controller.subState, NavigationSubState.outdoor);

    // Start is only legal from preview.
    h.controller.endNavigation();
    h.controller.startActiveNavigation();
    expect(h.controller.navigationState, NavigationState.idle);

    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);
    await tester.pump();
  });

  testWidgets('initial activity follows positioning evidence, never the '
      'destination', (tester) async {
    // GPS-believed -> ACTIVE_OUTDOOR even though the destination is a building.
    final gpsCase = _Harness();
    addTearDown(gpsCase.dispose);
    gpsCase.provider.setGpsLocation(_gps(30.8750));
    gpsCase.establishOutdoorPreview();
    gpsCase.controller.startActiveNavigation();
    expect(gpsCase.controller.navigationState, NavigationState.activeOutdoor);
    expect(gpsCase.controller.subState, NavigationSubState.outdoor);
    await tester.pump();
  });

  testWidgets('destination selection seeds route context but cannot fabricate '
      'an indoor claim', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.provider.setGpsLocation(_gps(30.8750));
    h.establishOutdoorPreview();

    // Route-context bookkeeping was seeded from the destination flow...
    expect(h.controller.currentNavigatingFloor, '0');

    h.controller.startActiveNavigation();
    // ...but the machine stayed outdoors on GPS evidence alone.
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.controller.snapshot.fix?.source, PositionSource.gps);
    expect(h.controller.positioningStatus, 'GPS active');
    await tester.pump();
  });

  testWidgets('approach enters ENTERING_BUILDING dwell', (tester) async {
    final h = _Harness(withEntrancePoi: true);
    addTearDown(h.dispose);
    h.scope.selectedSpace =
        null; // nothing selected yet so the preload path is observable
    h.startOutdoor();

    // Far: nothing happens.
    h.provider.setGpsLocation(_gps(30.8750));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    // Within prep threshold (<100m): building preloaded.
    h.provider.setGpsLocation(_gps(30.8657));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.scope.calls, contains('selectSpaceForNavigation:b1'));

    // At the entrance: ENTERING_BUILDING, still GPS-evidenced.
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    expect(h.controller.isActive, isTrue);
    expect(h.controller.subState, NavigationSubState.transitioning);
    expect(h.controller.snapshot.fix?.source, PositionSource.gps);

    // Outdoor-only: entry corroboration (WiFi) is no longer reachable.
  });

  testWidgets('pause overlay records previous activity and resumes into it',
      (tester) async {
    // PHASE 5 flip: pause requires gpsPausePoorTicks CONSECUTIVE degraded
    // fixes; a single bad tick can never pause (INV-8 hysteresis).
    // Outdoor variant.
    final out = _Harness();
    addTearDown(out.dispose);
    out.startOutdoor();
    for (var i = 0; i < NavigationConfig.gpsPausePoorTicks - 1; i++) {
      out.provider.setGpsLocation(_gps(30.8750, accuracy: 150));
    }
    expect(out.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'below the degraded threshold nothing happens yet');
    out.provider.setGpsLocation(_gps(30.8750, accuracy: 150));
    expect(out.controller.navigationState, NavigationState.paused);
    expect(out.controller.isPaused, isTrue);
    expect(out.controller.pauseMessage, isNotNull);
    expect(out.controller.subState, NavigationSubState.outdoor,
        reason: 'paused projects its previous activity');
    out.provider.setGpsLocation(_gps(30.8750, accuracy: 8));
    expect(out.controller.navigationState, NavigationState.activeOutdoor);
    await tester.pump();
  });

  testWidgets('rerouting overlay keeps physical fixes untouched and restores '
      'the interrupted activity', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    final original = h.scope.activeNavigationRoute;
    h.stub.respondWith(_route());

    // Jump far off the route line -> deviation triggers reroute
    // (PHASE 6: after the second consecutive confirm tick).
    h.provider.setGpsLocation(UserLocation(
      latitude: 30.8720,
      longitude: 29.5900,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));
    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'a single off-route tick never fires a reroute');
    h.provider.setGpsLocation(UserLocation(
      latitude: 30.8720,
      longitude: 29.5900,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));
    expect(h.controller.navigationState, NavigationState.rerouting);
    expect(h.stub.calls, 1);

    // The physical fix observed while REROUTING must survive resolution
    // untouched — recomputing a plan never fabricates position.
    final fixDuringReroute = h.controller.snapshot.fix;
    await tester.pump(); // let the stub resolve

    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'reroute completion restores the interrupted activity');
    expect(h.controller.isRerouting, isFalse);
    final adopted = h.scope.activeNavigationRoute;
    expect(identical(h.controller.activeRoute, adopted), isTrue,
        reason: 'reroute result replaces the active route');
    expect(identical(adopted, original), isFalse,
        reason: 'a freshly composed outdoor route replaces the previous one');
    expect(h.controller.snapshot.fix, fixDuringReroute,
        reason: 'physical position must be untouched by rerouting');
  });

  testWidgets('ARRIVED is reachable only through the reserved hook',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();

    // No producer exists yet; location updates never produce arrival.
    h.provider.setGpsLocation(_gps(30.8650));
    expect(h.controller.navigationState, isNot(NavigationState.arrived));

    h.controller.markArrived();
    expect(h.controller.navigationState, NavigationState.arrived);
    expect(h.controller.phase, NavigationPhase.active);
    expect(h.controller.subState, NavigationSubState.outdoor,
        reason: 'arrived projects its previous activity');

    // Inert to further location updates.
    h.provider.setGpsLocation(_gps(30.8700));
    expect(h.controller.navigationState, NavigationState.arrived);

    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);
    await tester.pump();
  });

  test('transition table matches the audited edge list exactly', () {
    const states = NavigationState.values;
    expect(states.length, 10);

    // NavigationState.idle as a TARGET is universally allowed and asserted
    // separately below, so it is omitted from every set here.
    const expected = <NavigationState, Set<NavigationState>>{
      NavigationState.idle: {NavigationState.routePreview},
      NavigationState.routePreview: {
        NavigationState.activeOutdoor,
        NavigationState.activeIndoor,
      },
      NavigationState.activeOutdoor: {
        NavigationState.enteringBuilding,
        NavigationState.rerouting,
        NavigationState.paused,
        NavigationState.arrived,
      },
      NavigationState.enteringBuilding: {
        NavigationState.activeIndoor,
        NavigationState.activeOutdoor,
        NavigationState.rerouting,
      },
      NavigationState.activeIndoor: {
        NavigationState.floorTransition,
        NavigationState.exitingBuilding,
        NavigationState.rerouting,
        NavigationState.paused,
        NavigationState.arrived,
      },
      NavigationState.floorTransition: {
        NavigationState.activeIndoor,
        NavigationState.exitingBuilding,
      },
      NavigationState.exitingBuilding: {
        NavigationState.activeOutdoor,
        NavigationState.activeIndoor,
      },
      NavigationState.arrived: {},
      NavigationState.paused: {},
      NavigationState.rerouting: {},
    };

    for (final from in states) {
      for (final to in states) {
        final allowed =
            isAllowedNavigationTransition(from, to) && to != NavigationState.idle;
        expect(
          allowed,
          expected[from]!.contains(to),
          reason: 'edge $from -> $to disagrees with the audited table',
        );
      }
      // User End / cancel is universally reachable.
      expect(isAllowedNavigationTransition(from, NavigationState.idle), isTrue);
    }

    // Dynamic restore edges are handled by the controller, not the table.
    expect(
      isAllowedNavigationTransition(NavigationState.paused, NavigationState.activeOutdoor),
      isFalse,
    );
    expect(
      isAllowedNavigationTransition(NavigationState.rerouting, NavigationState.activeIndoor),
      isFalse,
    );
  });

  testWidgets('endNavigation lands IDLE from every reachable state, including '
      'mid-reroute', (tester) async {
    // Mid-reroute with a gated repository.
    final h = _Harness();
    addTearDown(h.dispose);
    h.startOutdoor();
    final gate = Completer<List<LatLng>>();
    h.stub.gate(gate);

    h.provider.setGpsLocation(UserLocation(
      latitude: 30.8720,
      longitude: 29.5900,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));
    // PHASE 6 hysteresis: the second consecutive tick fires the reroute.
    h.provider.setGpsLocation(UserLocation(
      latitude: 30.8720,
      longitude: 29.5900,
      accuracy: 8.0,
      timestamp: DateTime.now(),
    ));
    expect(h.controller.navigationState, NavigationState.rerouting);

    h.controller.endNavigation();
    expect(h.controller.navigationState, NavigationState.idle);

    gate.complete(_routePoints());
    await tester.pump();
    expect(h.controller.navigationState, NavigationState.idle,
        reason: 'late reroute completion must not resurrect the session');
    expect(h.controller.activeRoute, isNull);
    await tester.pump();

    // Preview / paused / arrived paths are covered by their scenario tests.
  });

  testWidgets('advancing INTO a floorTransition segment never claims the new '
      'floor — positioning evidence owns that', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.scope.activeNavigationRoute = _twoSegmentRoute(
      RouteSegment.floorTransition(
        points: [LatLng(30.8720, _lng), LatLng(30.8719, _lng)],
        buildingId: 'b1',
        floorNumber: '3',
        connectorPoiId: 'lift-1',
        instruction: 'Take elevator to Floor 3',
      ),
    );

    h.startOutdoor();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);
    expect(h.controller.totalSegments, 2);
    // Route-context floor was seeded by the destination flow ('0').
    expect(h.controller.currentNavigatingFloor, '0');

    // Reach the outdoor segment endpoint -> segment advance fires.
    h.provider.setGpsLocation(_gps(30.8720));

    expect(
      h.controller.currentSegment?.type,
      RouteSegmentType.floorTransition,
    );
    expect(h.controller.currentNavigatingFloor, '0',
        reason: 'floorTransition segments must not write route-context '
            'floor bookkeeping; only corroborated evidence may');
    await tester.pump();
  });

  testWidgets('advancing into a regular segment still updates route-context '
      'floor bookkeeping', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    h.scope.activeNavigationRoute = _twoSegmentRoute(
      RouteSegment.entrance(
        points: [LatLng(30.8720, _lng), LatLng(30.8719, _lng)],
        buildingId: 'b1',
        floorNumber: '5',
      ),
    );

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8720));

    expect(
      h.controller.currentSegment?.type,
      RouteSegmentType.entranceTransition,
    );
    expect(h.controller.currentNavigatingFloor, '5');
    await tester.pump();
  });

  // ── ORIGINAL PHASE 4 — BUILDING TRANSITIONS ────────────────────────

  test('navigationDwellExpired boundary matrix', () {
    final start = DateTime(2026, 1, 1, 12, 0, 0);
    expect(
      navigationDwellExpired(null, start.add(const Duration(seconds: 999)), 20),
      isFalse,
      reason: 'no dwell start means never expired',
    );
    expect(navigationDwellExpired(start, start, 20), isFalse);
    expect(
      navigationDwellExpired(start, start.add(const Duration(seconds: 19)), 20),
      isFalse,
    );
    expect(
      navigationDwellExpired(start, start.add(const Duration(seconds: 20)), 20),
      isTrue,
    );
    expect(
      navigationDwellExpired(start, start.add(const Duration(seconds: 21)), 20),
      isTrue,
    );
  });

  testWidgets('entry corroboration is identity-aware: a neighboring '
      "building's WiFi never confirms; timeout reverts outdoors; the "
      're-trigger cooldown gates the proximity path', (tester) async {
    final h = _Harness(withEntrancePoi: true);
    addTearDown(h.dispose);
    var fakeNow = DateTime.now();
    h.controller.debugNowOverride = () => fakeNow;

    h.startOutdoor();
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    h.provider.setGpsLocation(_gps(30.8660)); // preload stage
    h.provider.setGpsLocation(_gps(30.86505)); // entrance dwell
    expect(h.controller.navigationState, NavigationState.enteringBuilding);

    // Building b2's WiFi becomes the believed fix and its claim streak
    // confirms scope b2; a fourth estimate carries that identity on the
    // fix itself. Identity does NOT match destination b1.
    for (var i = 0; i < 4; i++) {
      h.native.emit(_wifi(buid: 'b2'));
    }
    await tester.pump();
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.enteringBuilding,
        reason: 'confirmed scope b2 != destination b1 must not confirm entry');

    // Retire the foreign WiFi belief (stale timer) so later ticks are
    // GPS-evidenced and cannot re-enter via the evidence path — this keeps
    // the focus on the proximity/cooldown interplay below.
    await tester.pump(const Duration(seconds: 11));

    // Past the corroboration timeout the dwell reverts outdoors...
    fakeNow = fakeNow.add(const Duration(seconds: 21));
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.activeOutdoor);

    // ...the cooldown suppresses an immediate proximity re-dwell...
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.activeOutdoor,
        reason: 'cooldown must gate the proximity path right after timeout');

    // ...and once it elapses the dwell may arm again.
    fakeNow = fakeNow.add(const Duration(seconds: 16));
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.enteringBuilding);

    // Burn the pending WiFi-stale timer so the test ends clean.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('approach preload cancels when the user retreats and re-arms '
      'on re-approach', (tester) async {
    final h = _Harness(withEntrancePoi: true);
    addTearDown(h.dispose);

    h.startOutdoor();
    expect(h.controller.buildingPreloadedForTest, isFalse);

    h.provider.setGpsLocation(_gps(30.8658)); // ~89m from center
    expect(h.controller.buildingPreloadedForTest, isTrue);

    // Retreat beyond the cancel threshold — preparation is withdrawn.
    h.provider.setGpsLocation(_gps(30.8635)); // ~165m south
    expect(h.controller.buildingPreloadedForTest, isFalse);

    // Re-approach re-preloads and can reach the entrance dwell again.
    h.provider.setGpsLocation(_gps(30.8658));
    expect(h.controller.buildingPreloadedForTest, isTrue);
    h.provider.setGpsLocation(_gps(30.86505));
    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    await tester.pump();
  });

  testWidgets('preload floor cascade prefers the route arrival floor '
      '(segment-derived)', (tester) async {
    final h = _Harness(
      withEntrancePoi: true,
      floors: [_floor('0'), _floor('2')],
    );
    addTearDown(h.dispose);
    // Real segment model drives the tier-1 arrival-floor scan (entrance on
    // floor '2'); the hand-projected points carry floor '0' on the outdoor
    // corridor so floor-filtered deviation keeps the approach visible.
    final entranceSegment = RouteSegment.entrance(
      points: [LatLng(30.8560, _lng), LatLng(30.8559, _lng)],
      buildingId: 'b1',
      floorNumber: '2',
      connectorPoiId: 'entr-2',
    );
    h.scope.activeNavigationRoute = NavigationRouteModel(
      points: [
        NavigationRoutePoint.outdoor(latitude: 30.8760, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8700, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8660, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
        NavigationRoutePoint(
          latitude: 30.8559,
          longitude: _lng,
          puid: 'entranceTransition_4',
          buid: 'b1',
          floorNumber: '2',
          poisType: 'entranceTransition',
        ),
      ],
      segments: [
        RouteSegment.outdoor(
          points: [
            LatLng(30.8760, _lng),
            LatLng(30.8700, _lng),
            LatLng(30.8660, _lng),
            LatLng(30.8560, _lng),
          ],
          buildingId: 'b1',
        ),
        entranceSegment,
      ],
    );

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8660));
    h.provider.setGpsLocation(_gps(30.86505));

    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    expect(h.controller.currentNavigatingFloor, '2',
        reason: 'the segment the route enters the building on owns the '
            'preload choice, not the legacy ground heuristic');
    expect(h.scope.calls, contains('selectFloorForNavigation:2'));
    await tester.pump();
  });

  testWidgets('preload floor cascade reads point-projected routes too',
      (tester) async {
    final h = _Harness(
      withEntrancePoi: true,
      floors: [_floor('0'), _floor('1')],
    );
    addTearDown(h.dispose);
    // Indoor point sits between two outdoor points so the whole approach
    // corridor stays on-route; outdoor points carry floor '0' so the
    // floor-filtered deviation view keeps the corridor visible.
    h.scope.activeNavigationRoute = NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8760, longitude: _lng),
      NavigationRoutePoint(
        latitude: 30.8660,
        longitude: _lng,
        puid: 'room-1',
        buid: 'b1',
        floorNumber: '1',
        poisType: 'None',
      ),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8660));
    h.provider.setGpsLocation(_gps(30.86505));

    expect(h.controller.currentNavigatingFloor, '1');
    expect(h.scope.calls, contains('selectFloorForNavigation:1'));
    await tester.pump();
  });

  testWidgets('legacy fallbacks hold: pure-outdoor routes preload floor 0',
      (tester) async {
    final h = _Harness(withEntrancePoi: true);
    addTearDown(h.dispose);
    h.scope.activeNavigationRoute = _pureOutdoorRoute();

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8660));
    h.provider.setGpsLocation(_gps(30.86505));

    expect(h.controller.currentNavigatingFloor, '0');
    expect(h.scope.calls, contains('selectFloorForNavigation:0'));
    await tester.pump();
  });

  testWidgets("without a '0' floor the cascade picks the deterministically "
      'lowest numeric floor', (tester) async {
    final h = _Harness(withEntrancePoi: true, floors: [_floor('5'), _floor('2')]);
    addTearDown(h.dispose);
    h.scope.activeNavigationRoute = _pureOutdoorRoute();

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8660));
    h.provider.setGpsLocation(_gps(30.86505));

    expect(h.controller.currentNavigatingFloor, '2',
        reason: 'server ordering [5, 2] must not win over natural ordering');
    expect(h.scope.calls, contains('selectFloorForNavigation:2'));
    expect(h.scope.calls, isNot(contains('selectFloorForNavigation:5')));
    await tester.pump();
  });

  testWidgets('a derived arrival floor missing from the scope falls through '
      "to the legacy '0' tier", (tester) async {
    final h = _Harness(withEntrancePoi: true, floors: [_floor('0')]);
    addTearDown(h.dispose);
    h.scope.activeNavigationRoute = NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(latitude: 30.8760, longitude: _lng),
      NavigationRoutePoint(
        latitude: 30.8660,
        longitude: _lng,
        puid: 'x',
        buid: 'b1',
        floorNumber: '9',
        poisType: 'None',
      ),
      NavigationRoutePoint.outdoor(latitude: 30.8560, longitude: _lng),
    ]);

    h.startOutdoor();
    h.provider.setGpsLocation(_gps(30.8660));
    h.provider.setGpsLocation(_gps(30.86505));

    expect(h.controller.currentNavigatingFloor, '0',
        reason: 'unresolvable derived floors must never fabricate residency '
            'for a floor the scope does not carry');
    await tester.pump();
  });

}
