import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';
import 'package:anyplace_campusfind/ui/widgets/arrival_banner.dart';
import 'package:anyplace_campusfind/ui/widgets/navigation_status_bar.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ---------------------------------------------------------------------------
// ORIGINAL PHASE 7 — UI exposure.
//
// Pure-projection tests: every widget consumes the existing Phase 1–6 public
// APIs as-is (canonical state machine, segment model, held-position cache,
// arrival state). No navigation behavior lives here.
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
    selectedFloor = null;
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
// Fixtures — collinear on lng 29.5828.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

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
  double lat = 30.8650,
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

/// Flat segmentless route ending at 30.8560.
NavigationRouteModel _route() => NavigationRouteModel(points: [
      NavigationRoutePoint.outdoor(
          latitude: 30.8750, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8700, longitude: _lng, buid: 'b1', floorNumber: '0'),
      NavigationRoutePoint.outdoor(
          latitude: 30.8560, longitude: _lng, buid: 'b1', floorNumber: '0'),
    ]);

/// Two-segment route carrying instructions; explicit points keep every
/// waypoint on floor '0' so the deviation filter sees the walker on-route.
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
          instruction: 'Walk north on campus road',
        ),
        RouteSegment.indoor(
          points: [LatLng(30.8720, _lng), LatLng(30.8700, _lng)],
          buildingId: 'b1',
          floorNumber: '0',
          instruction: 'Enter Building One and take the corridor',
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
    scope = _FakeSpaceScope(floors: [_floor('0'), _floor('1')], pois: pois);
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

  Future<void> emitWifi(WidgetTester tester, {double lat = 30.86500}) async {
    native.emit(_wifi(lat: lat));
    await tester.pump();
  }

  /// Burns the pending indoor-stale timer so the test ends clean
  /// (suite convention).
  Future<void> burnStaleTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
  }

  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<NavigationController>.value(
              value: controller),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Future<void> pumpStatusBar(WidgetTester tester) async {
    await tester.pumpWidget(wrap(const NavigationStatusBar()));
  }

  Future<void> pumpBanner(WidgetTester tester, VoidCallback onDone) async {
    await tester.pumpWidget(wrap(ArrivalBanner(onDone: () {
      onDone();
      controller.endNavigation();
    })));
  }
}

void main() {
  group('display-location projection (Phase 5 held position)', () {
    test('returns the held position while a floor transition holds', () {
      final held =
          UserLocation(latitude: 30.8655, longitude: 29.5828, timestamp: DateTime.now());
      final live =
          UserLocation(latitude: 31.9999, longitude: 29.9999, timestamp: DateTime.now());
      final display = displayLocationFor(
        holdFloorTransition: true,
        heldPosition: held,
        currentLocation: live,
      );
      expect(identical(display, held), isTrue);
    });

    test('passes the live location through outside transitions', () {
      final live =
          UserLocation(latitude: 30.8700, longitude: 29.5828, timestamp: DateTime.now());
      final display = displayLocationFor(
        holdFloorTransition: false,
        heldPosition: null,
        currentLocation: live,
      );
      expect(identical(display, live), isTrue);
    });

    test('falls back to the live location when no position was cached', () {
      final live =
          UserLocation(latitude: 30.8700, longitude: 29.5828, timestamp: DateTime.now());
      final display = displayLocationFor(
        holdFloorTransition: true,
        heldPosition: null,
        currentLocation: live,
      );
      expect(identical(display, live), isTrue);
    });
  });

  testWidgets('banner is hidden during ordinary activities', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpBanner(tester, () {});
    expect(find.byKey(const ValueKey('arrival_banner')), findsNothing);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'banner appears on ARRIVED with the destination name; Done ends the '
      'session exactly like End', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    var doneCount = 0;
    await h.startOutdoor(tester);

    h.controller.markArrived();
    await h.pumpBanner(tester, () => doneCount++);
    await tester.pump();

    expect(find.text('Arrived at Building One'), findsOneWidget);
    expect(h.controller.navigationState, NavigationState.arrived);

    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(doneCount, 1);
    expect(h.controller.navigationState, NavigationState.idle);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'banner stays mounted while ARRIVED persists; further updates are '
      'inert', (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    h.controller.markArrived();
    await h.pumpBanner(tester, () {});

    // Far-away GPS updates must not unmount the banner or leave ARRIVED.
    h.provider.setGpsLocation(_gps(30.9000));
    await tester.pump();
    expect(find.byKey(const ValueKey('arrival_banner')), findsOneWidget);
    expect(h.controller.navigationState, NavigationState.arrived);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'status bar keeps the verbatim source line outdoors and indoors',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpStatusBar(tester);
    expect(find.text('GPS active'), findsOneWidget);
    // Switch to indoor evidence: belief flips mid-stream, scope confirms,
    // then building-entry corroboration completes. Keep emitting until the
    // canonical machine reports activeIndoor, then let the UI catch up.
    for (var i = 0;
        i < 10 &&
            h.controller.navigationState != NavigationState.activeIndoor;
        i++) {
      await h.emitWifi(tester);
    }
    expect(h.controller.navigationState, NavigationState.activeIndoor);
    await tester.pump();
    await tester.pump();
    expect(find.text('Indoor \u2022 Floor 0'), findsOneWidget);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'status bar exposes ARRIVED with the dedicated label and icon',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    h.controller.markArrived();
    await h.pumpStatusBar(tester);

    expect(find.text('Arrived at Building One'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'status bar exposes PAUSED with the pause message and warning icon',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpStatusBar(tester);

    h.provider.setGpsLocation(_gps(30.8700, accuracy: 120));
    await tester.pump();

    expect(h.controller.isPaused, isTrue);
    expect(find.text('GPS signal weak \u2014 waiting for better signal'),
        findsOneWidget);
    expect(find.byIcon(Icons.gps_off), findsOneWidget);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'status bar exposes ENTERING_BUILDING dwell instead of raw source',
      (tester) async {
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
    final h = _Harness(pois: [entrancePoi, _poi()]);
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpStatusBar(tester);

    h.provider.setGpsLocation(_gps(30.8657));
    await tester.pump();
    h.provider.setGpsLocation(_gps(30.86505));
    await tester.pump();

    expect(h.controller.navigationState, NavigationState.enteringBuilding);
    expect(find.text('Entering building\u2026'), findsOneWidget);
    await h.burnStaleTimer(tester);
  });

  testWidgets(
      'instruction strip renders the current segment instruction and i/n '
      'progress, and follows segment advancement', (tester) async {
    final h = _Harness(route: _twoSegmentRoute());
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpStatusBar(tester);

    expect(find.text('Walk north on campus road'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    // Reach the first segment's endpoint (10 m rule) -> advance to 2/2.
    h.provider.setGpsLocation(_gps(30.87395));
    await tester.pump();

    expect(find.text('Enter Building One and take the corridor'),
        findsOneWidget);
    expect(find.text('2/2'), findsOneWidget);
    await h.burnStaleTimer(tester);
  });

  testWidgets('instruction strip renders nothing without segments',
      (tester) async {
    final h = _Harness();
    addTearDown(h.dispose);
    await h.startOutdoor(tester);
    await h.pumpStatusBar(tester);

    final strip = find.byKey(const ValueKey('navigation_instruction_strip'));
    expect(strip, findsNothing);
  });
}
