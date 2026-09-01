import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/campus_gate.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SpaceProvider gate state', () {
    test('campusGates is empty before custom routes are loaded', () {
      final provider = SpaceProvider();
      expect(provider.campusGates, isEmpty);
      expect(provider.hasSelectedGate, isFalse);
    });

    test('loadCustomRoutes loads the real 4 gates and applies policy', () async {
      final provider = SpaceProvider();
      await provider.loadCustomRoutes();

      final gates = provider.campusGates;
      // Visibility is independent of the routing policy: ALL gates render,
      // including policy-disabled ones. G2 stays the preferred entry gate but
      // every gate remains selectable.
      expect(gates.length, 4);
      expect(gates.map((g) => g.id), containsAll(['G1', 'G2', 'G3', 'G4']));

      // Coordinates come from the KMZ, not literals — G2 must be the real gate.
      final g2 = gates.firstWhere((g) => g.id == 'G2');
      expect(g2.latitude, closeTo(30.8617536, 1e-6));
      expect(g2.longitude, closeTo(29.5669269, 1e-6));
    });

    test('campusGates getter is unmodifiable', () async {
      final provider = SpaceProvider();
      await provider.loadCustomRoutes();
      expect(
        () => provider.campusGates.clear(),
        throwsUnsupportedError,
      );
    });

    test('selectGate / clearSelectedGate drive selection state', () {
      final provider = SpaceProvider();
      final gate = CampusGate(
        id: 'G2',
        name: 'G2',
        latitude: 30.8617536,
        longitude: 29.5669269,
        enabled: true,
      );

      expect(provider.hasSelectedGate, isFalse);
      provider.selectGate(gate);
      expect(provider.hasSelectedGate, isTrue);
      expect(provider.selectedGate?.id, 'G2');

      provider.clearSelectedGate();
      expect(provider.hasSelectedGate, isFalse);
      expect(provider.selectedGate, isNull);
    });

    test('selecting a gate clears an indoor POI selection', () {
      final provider = SpaceProvider();
      provider.selectPoi(PoiModel(
        puid: 'p1',
        buid: 'b1',
        floorNumber: '0',
        name: 'Room',
        description: 'Room',
        poisType: 'room',
        latitude: 30.86,
        longitude: 29.56,
      ));
      expect(provider.hasSelectedPoi, isTrue);

      provider.selectGate(CampusGate(
        id: 'G2',
        name: 'G2',
        latitude: 30.8617536,
        longitude: 29.5669269,
        enabled: true,
      ));
      expect(provider.hasSelectedPoi, isFalse, reason: 'gate selection clears POI');
      expect(provider.selectedGate?.id, 'G2');
    });

    test('selecting a POI clears a gate selection', () {
      final provider = SpaceProvider();
      provider.selectGate(CampusGate(
        id: 'G2',
        name: 'G2',
        latitude: 30.8617536,
        longitude: 29.5669269,
        enabled: true,
      ));
      expect(provider.selectedGate?.id, 'G2');

      provider.selectPoi(PoiModel(
        puid: 'p1',
        buid: 'b1',
        floorNumber: '0',
        name: 'Room',
        description: 'Room',
        poisType: 'room',
        latitude: 30.86,
        longitude: 29.56,
      ));
      expect(provider.selectedGate, isNull, reason: 'POI selection clears gate');
      expect(provider.selectedPoi?.puid, 'p1');
    });

    test('requestRouteToGate fails cleanly when GPS location is unavailable',
        () async {
      final provider = SpaceProvider();
      // No location provider is set → current location is null.
      final gate = CampusGate(
        id: 'G2',
        name: 'G2',
        latitude: 30.8617536,
        longitude: 29.5669269,
        enabled: true,
      );

      final ok = await provider.requestRouteToGate(gate);
      expect(ok, isFalse);
      expect(provider.navigationRouteStatus, NavigationRouteStatus.error);
      expect(provider.navigationRouteErrorMessage, isNotNull);
      expect(provider.hasActiveNavigationRoute, isFalse);
    });

    test('no GPS error does not depend on gate policy', () async {
      final provider = SpaceProvider();
      // Even a policy-disabled gate (G1) fails the same way: the missing-GPS
      // guard runs before any gate-specific logic, and routing never consults
      // the policy for manual gate destinations.
      final g1 = CampusGate(
        id: 'G1',
        name: 'G1',
        latitude: 30.8626633,
        longitude: 29.5613399,
        enabled: false,
      );
      final ok = await provider.requestRouteToGate(g1);
      expect(ok, isFalse);
      expect(provider.navigationRouteStatus, NavigationRouteStatus.error);
    });
  });
}
