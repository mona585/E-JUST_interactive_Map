import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/cross_building_router.dart';

// FORENSIC REMEDIATION REGRESSION TESTS
// Findings: NAV-002 (exit door = candidates.first, no scoring) and
// NAV-003 (connector-chain fallback silently substituting the entrance for
// unresolvable/cross-floor targets).

SpaceModel _space(String buid) =>
    SpaceModel(buid: buid, name: buid, latitude: 30.0, longitude: 29.0);

PoiModel _poi(String puid, double lat,
        {String type = 'Entrance', bool entranceFlag = false}) =>
    PoiModel(
      puid: puid,
      buid: 'bExit',
      floorNumber: '0',
      name: puid,
      poisType: type,
      latitude: lat,
      longitude: 29.0,
      isBuildingEntrance: entranceFlag,
    );

CrossBuildingRouter _router(Map<String, List<PoiModel>> poisByBuid) {
  return CrossBuildingRouter(
    isPositionInBuilding: (_, _) => false,
    loadPois: (buid, floorNumber) async => poisByBuid[buid] ?? const [],
    loadFloorNumbers: (buid) async => ['0'],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NAV-002: exit selector returns the NEAREST ground entrance, not the '
      'first in load order', () async {
    final near = _poi('door_near', 30.0005, entranceFlag: true);
    final far = _poi('door_far', 30.0090, entranceFlag: true);
    final router = _router({
      'bExit': [far, near], // far door listed first
    });

    final picked = await router.selectExitPoiForTest(
      _space('bExit'),
      userLocation: const LatLng(30.0001, 29.0001),
    );

    expect(picked, isNotNull);
    expect(picked!.puid, 'door_near');
  });

  test('NAV-003: connector-chain returns null when the target puid is not on '
      'the entrance floor (no silent entrance substitution)', () async {
    final entrance =
        _poi('door_main', 30.0005, type: 'Entrance', entranceFlag: true);
    final c1 = _poi('conn_1', 30.0008, type: 'None');
    final c2 = _poi('conn_2', 30.0012, type: 'None');
    final router = _router({
      'bExit': [entrance, c1, c2],
    });

    final result = await router.routeViaConnectorsForTest(
      entrancePoi: entrance,
      targetPuid: 'poi_on_other_floor',
      targetSpace: _space('bExit'),
    );

    expect(result, isNull,
        reason:
            'unresolvable targets must fall through to the flagged incomplete '
            'fallback instead of a complete-marked degenerate loop');
  });
}
