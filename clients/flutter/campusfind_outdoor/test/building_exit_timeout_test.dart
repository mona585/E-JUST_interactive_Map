import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/floorplan_model.dart';
import 'package:anyplace_campusfind/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/models/navigation_state.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/position_estimate.dart';
import 'package:anyplace_campusfind/models/position_fix.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/repositories/custom_route_repository.dart';
import 'package:anyplace_campusfind/services/navigation_building_context_handler.dart';
import 'package:anyplace_campusfind/services/navigation_event_log.dart';
import 'package:anyplace_campusfind/services/navigation_pilot_port.dart';
import 'package:anyplace_campusfind/services/navigation_route_scope.dart';
import 'package:anyplace_campusfind/services/navigation_state_machine.dart';

// ---------------------------------------------------------------------------
// Focused behavioral tests for the building-exit timeout fix.
//
// The production flow can only enter EXITING_BUILDING from ACTIVE_INDOOR
// (checkBuildingExit gates on that state), and ACTIVE_INDOOR is only reachable
// via the building-exit timeout itself — an isolated cycle. These tests force
// the machine into EXITING_BUILDING via the public transition() seam and drive
// maintainDwell with a controllable clock, so the timeout target is verified
// deterministically without real-time delays.
// ---------------------------------------------------------------------------

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.8650,
      longitude: 29.5828,
    );



FloorplanModel _floorplanContainingBuilding() => FloorplanModel(
      buid: 'b1',
      floorNumber: '0',
      imagePath: '/tmp/floorplan.png',
      imageSizeBytes: 1024,
      // Real bounds tightly around the building center (30.8650, 29.5828).
      // A point at 30.8750 lies OUTSIDE these bounds.
      bottomLeftLat: 30.8640,
      bottomLeftLng: 29.5818,
      topRightLat: 30.8660,
      topRightLng: 29.5838,
    );

UserLocation _outsideFix({double accuracy = 8.0}) => UserLocation(
      latitude: 30.8750,
      longitude: 29.5828,
      accuracy: accuracy,
      timestamp: DateTime(2026),
    );

UserLocation _insideFix({double accuracy = 8.0}) => UserLocation(
      latitude: 30.8650,
      longitude: 29.5828,
      accuracy: accuracy,
      timestamp: DateTime(2026),
    );

class _FakePort implements NavigationPilotPort {
  _FakePort(this._now);

  DateTime Function() _now;
  PositionFix? fix;
  UserLocation? location;
  bool indoorWifiActive = false;

  set nowFn(DateTime Function() fn) {
    _now = fn;
  }

  @override
  PositionFix? get currentFix => fix;

  @override
  UserLocation? get currentLocation => location;

  @override
  UserLocation? get gpsLocation => location;

  @override
  PositionEstimate? get latestIndoorEstimate => null;

  @override
  bool get hasGpsFix => true;

  @override
  bool get isIndoorWifiActive => indoorWifiActive;

  @override
  bool get gpsDegraded => false;

  @override
  DateTime now() => _now();

  @override
  void notifyChanged() {}
}

class _FakeScope extends ChangeNotifier implements NavigationRouteScope {
  _FakeScope();

  FloorplanModel? floorplan;

  @override
  NavigationRouteModel? activeNavigationRoute;

  @override
  FloorModel? selectedFloor;

  @override
  SpaceModel? selectedSpace;

  @override
  List<FloorModel> floors = const [];

  @override
  List<PoiModel> pois = const [];

  @override
  bool get hasPois => false;

  @override
  FloorplanModel? get activeFloorplan => floorplan;

  @override
  CustomRouteRepository get customRouteRepository => CustomRouteRepository();

  @override
  void selectSpace(SpaceModel space) {}

  @override
  void selectFloor(FloorModel floor) {}

  @override
  void clearSelection() {}

  @override
  void selectFloorForNavigation(FloorModel floor) {}

  @override
  void selectSpaceForNavigation(SpaceModel space) {}

  @override
  void releaseIndoorContextForNavigation() {}

  @override
  void adoptNavigatedRoute(NavigationRouteModel route) {}

  @override
  void clearNavigationRoute() {}

  @override
  Future<bool> requestRouteForRetarget(PoiModel target) async => false;
}

/// Builds a real machine + handler, forces the machine into EXITING_BUILDING via
/// the public transition seam, and returns them plus the shared clock.
({NavigationStateMachine machine, NavigationBuildingContextHandler handler,
    _FakePort port, _FakeScope scope,
    DateTime Function() clock}) _build() {
  var now = DateTime(2026, 1, 1, 12, 0, 0);
  DateTime clock() => now;

  final port = _FakePort(clock);
  final scope = _FakeScope();
  final navEvent = NavigationEventLog(
    port: port,
    session: () => null,
    currentFloor: () => null,
  );
  final machine = NavigationStateMachine(
    now: clock,
    navEvent: navEvent,
  );
  final handler = NavigationBuildingContextHandler(
    scope: scope,
    port: port,
    machine: machine,
    navEvent: navEvent,
    destinationSpace: () => _building(),
    session: () => null,
    isCurrent: (_, _) => true,
    onPreloadFloor: (_) {},
    onReleaseIndoorForExit: () {},
  );

  // Drive the machine into EXITING_BUILDING via allowed edges.
  machine.transition(NavigationState.routePreview);
  machine.transition(NavigationState.activeOutdoor);
  machine.transition(NavigationState.enteringBuilding);
  machine.transition(NavigationState.activeIndoor);
  machine.transition(NavigationState.exitingBuilding);
  expect(machine.state, NavigationState.exitingBuilding);

  return (
    machine: machine,
    handler: handler,
    port: port,
    scope: scope,
    clock: () => now,
  );
}

void main() {
  group('building-exit timeout is Outdoor-only', () {
    testWidgets('timeout reaches activeOutdoor, never activeIndoor',
        (tester) async {
      final h = _build();
      h.port.location = _outsideFix(accuracy: 8.0);

      // Advance past the corroboration timeout.
      final advanced = h.clock().add(
        Duration(seconds: NavigationConfig.exitingCorroborationTimeoutSeconds + 5),
      );
      h.port.nowFn = () => advanced;

      h.handler.maintainDwell(null, _outsideFix());
      expect(h.machine.state, NavigationState.activeOutdoor);
      expect(h.machine.state, isNot(NavigationState.activeIndoor));
      await tester.pump();
    });

    testWidgets('poor GPS accuracy prevents confirmation (stays exitingBuilding)',
        (tester) async {
      final h = _build();
      // Poor accuracy (> exitAccuracyThreshold) and still inside the building
      // bounds → neither confirmation nor (yet) timeout.
      h.port.location = _insideFix(accuracy: 120.0);

      h.handler.maintainDwell(null, _insideFix(accuracy: 120.0));
      expect(h.machine.state, NavigationState.exitingBuilding);
      await tester.pump();
    });

    testWidgets('confirmed exit reaches activeOutdoor (floorplan bounds)',
        (tester) async {
      final h = _build();
      // Floorplan bounds tightly around the building; the fix is outside them.
      h.scope.floorplan = _floorplanContainingBuilding();
      h.port.location = _outsideFix(accuracy: 8.0);

      h.handler.maintainDwell(null, _outsideFix());
      expect(h.machine.state, NavigationState.activeOutdoor);
      expect(h.machine.state, isNot(NavigationState.activeIndoor));
      await tester.pump();
    });

    testWidgets('recovery: after timeout, improved GPS stays Outdoor',
        (tester) async {
      final h = _build();
      // First: timeout with poor GPS → activeOutdoor (the fix).
      h.port.location = _outsideFix(accuracy: 8.0);
      final advanced = h.clock().add(
        Duration(seconds: NavigationConfig.exitingCorroborationTimeoutSeconds + 5),
      );
      h.port.nowFn = () => advanced;
      h.handler.maintainDwell(null, _outsideFix());
      expect(h.machine.state, NavigationState.activeOutdoor);

      // Recovery: good GPS keeps the machine Outdoor; arrival still possible.
      h.port.location = _outsideFix(accuracy: 5.0);
      h.handler.maintainDwell(
        PositionFix(
          latitude: 30.8750,
          longitude: 29.5828,
          source: PositionSource.gps,
          accuracy: 5.0,
          confidence: 0.9,
          timestamp: h.clock(),
          status: PositionFixStatus.fresh,
        ),
        _outsideFix(accuracy: 5.0),
      );
      expect(h.machine.state, NavigationState.activeOutdoor);
      expect(h.machine.state, isNot(NavigationState.activeIndoor));
      await tester.pump();
    });
  });
}
