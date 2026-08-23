import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/position_fix.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

class _FakeLocationService implements LocationService {
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

class _FakeNativePositioningService implements NativePositioningService {
  final _estimateController = StreamController<PositionEstimate>.broadcast();

  final loadedMaps = <List<String>>[];

  void emit(PositionEstimate estimate) => _estimateController.add(estimate);

  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async {
    loadedMaps.add([text, buid, floor]);
    return true;
  }

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => _estimateController.stream;
}

PositionEstimate _est({
  String buid = 'b1',
  String floor = '1',
  double lat = 30.86500,
  double lng = 29.58280,
  int matched = 5,
  int total = 8,
  double? bestDistance = 4.0,
  double? topKSpreadMeters = 6.0,
  String status = 'success',
}) {
  return PositionEstimate(
    latitude: status == 'success' ? lat : null,
    longitude: status == 'success' ? lng : null,
    buid: buid,
    floor: floor,
    matchedAps: matched,
    totalAps: total,
    durationMs: 12,
    timestamp: DateTime.now(),
    status: status,
    bestDistance: bestDistance,
    topKSpreadMeters: topKSpreadMeters,
  );
}

/// Enters indoor mode with [buid]/[floor] (3 consecutive qualifying estimates).
void _enterIndoor(
  _FakeNativePositioningService native, {
  String buid = 'b1',
  String floor = '1',
  double lat = 30.86500,
  double lng = 29.58280,
  double? bestDistance = 4.0,
}) {
  for (var i = 0; i < NavigationConfig.indoorEnterConfirmCount; i++) {
    native.emit(_est(
      buid: buid,
      floor: floor,
      lat: lat,
      lng: lng,
      bestDistance: bestDistance,
    ));
  }
}

/// Emits enough additional same-scope estimates to publish the confirmed
/// scope onto the canonical fix. Publication lags confirmation by one
/// accepted estimate (each fix is built with the previously confirmed pair),
/// so this emits scopeConfirmCount extra estimates: confirmation fires on the
/// first of them and the last one carries the identity.
void _confirmScope(
  _FakeNativePositioningService native, {
  String buid = 'b1',
  String floor = '1',
  double lat = 30.86500,
  double lng = 29.58280,
}) {
  for (var i = 0; i < NavigationConfig.scopeConfirmCount; i++) {
    native.emit(_est(buid: buid, floor: floor, lat: lat, lng: lng));
  }
}

void main() {
  late _FakeNativePositioningService native;
  late LocationProvider provider;

  setUp(() {
    native = _FakeNativePositioningService();
    provider = LocationProvider(
      locationService: _FakeLocationService(),
      nativePositioningService: native,
    );
  });

  tearDown(() {
    provider.dispose();
  });

  group('invalid / empty evidence is rejected safely', () {
    testWidgets('no_match, null-coords, zero-coord and sub-threshold estimates '
        'never produce an identity or a Wi-Fi belief in outdoor mode',
        (tester) async {
      final variants = [
        _est(status: 'no_match'),
        PositionEstimate(
          latitude: 0,
          longitude: 0,
          buid: 'b1',
          floor: '1',
          matchedAps: 5,
          totalAps: 8,
          durationMs: 12,
          timestamp: DateTime.now(),
          status: 'success',
        ),
        _est(matched: 0),
        _est(matched: 1),
        _est(matched: 2, total: 9), // ratio 0.22 < minMatchedRatio
        _est(buid: ''),
        _est(floor: ''),
      ];

      for (final v in variants) {
        native.emit(v);
        await tester.pump();
        expect(provider.positionSource, isNot(LocationSource.indoorWifi),
            reason: 'variant ${v.matchedAps}/${v.totalAps} "${v.buid}"');
        expect(provider.currentFix?.buildingId, isNull);
      }

      // Raw pass-through still reflects the newest observation.
      expect(provider.latestIndoorEstimate, same(variants.last));
    });

    testWidgets('a single invalid cycle inside indoor mode neither exits nor '
        'invents an identity', (tester) async {
      _enterIndoor(native);
      await tester.pump();
      expect(provider.positionSource, LocationSource.indoorWifi);

      native.emit(_est(status: 'no_match'));
      await tester.pump();

      expect(provider.positionSource, LocationSource.indoorWifi);
      expect(provider.currentFix!.source, PositionSource.wifi);
      expect(provider.currentFix!.buildingId, isNull);
    });
  });

  group('legacy payload compatibility', () {
    testWidgets('payloads without evidence fields parse and remain usable '
        'evidence', (tester) async {
      final legacy = PositionEstimate.fromMap({
        'latitude': 30.86500,
        'longitude': 29.58280,
        'buid': 'b1',
        'floor': '1',
        'matchedAps': 5,
        'totalAps': 8,
        'durationMs': 12,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'success',
      });

      expect(legacy.bestDistance, isNull);
      expect(legacy.topKSpreadMeters, isNull);
      expect(legacy.isValid, isTrue);

      for (var i = 0; i < 3; i++) {
        native.emit(legacy);
        await tester.pump();
      }

      expect(provider.positionSource, LocationSource.indoorWifi);

      // No basis -> conservative upper-bound accuracy.
      expect(provider.currentFix!.accuracy,
          NavigationConfig.wifiAccuracyMaxMeters);
    });

    testWidgets('string numerics and missing optional keys stay tolerant',
        (tester) async {
      final legacy = PositionEstimate.fromMap({
        'latitude': '30.86500',
        'longitude': '29.58280',
        'buid': 'b1',
        'floor': '1',
        'matchedAps': '5',
        'totalAps': '8',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'status': 'success',
      });

      expect(legacy.latitude, 30.86500);
      expect(legacy.matchedAps, 5);
      expect(legacy.isValid, isTrue);
    });
  });

  group('accuracy derivation treats infinite/absent evidence as no basis', () {
    testWidgets('bestDistance=infinity contributes nothing (no distance basis)',
        (tester) async {
      for (var i = 0; i < NavigationConfig.indoorEnterConfirmCount; i++) {
        native.emit(_est(
          bestDistance: double.infinity,
          topKSpreadMeters: null,
        ));
      }
      await tester.pump();
      final fix = provider.currentFix!;

      // No finite spread, no finite bestDistance -> conservative bound.
      expect(fix.accuracy, NavigationConfig.wifiAccuracyMaxMeters);
      expect(fix.accuracy.isFinite, isTrue);
      expect(fix.confidence.isFinite, isTrue);
      expect(fix.confidence.inRange0to1(), isTrue);
    });

    testWidgets('infinite bestDistance does not mask a valid finite spread',
        (tester) async {
      for (var i = 0; i < 3; i++) {
        native.emit(_est(bestDistance: double.infinity));
      }
      await tester.pump();

      expect(provider.currentFix!.accuracy, 6.0);
    });

    testWidgets('infinite topKSpreadMeters is ignored, finite bestDistance wins',
        (tester) async {
      for (var i = 0; i < 3; i++) {
        native.emit(
            _est(topKSpreadMeters: double.infinity, bestDistance: 10.0));
      }
      await tester.pump();

      expect(provider.currentFix!.accuracy, 10.0);
      expect(provider.currentFix!.confidence.isFinite, isTrue);
    });

    testWidgets('fully absent evidence falls back to the conservative bound',
        (tester) async {
      for (var i = 0; i < 3; i++) {
        native.emit(_est(bestDistance: null, topKSpreadMeters: null));
      }
      await tester.pump();

      expect(provider.currentFix!.accuracy,
          NavigationConfig.wifiAccuracyMaxMeters);
      expect(provider.currentFix!.confidence.isFinite, isTrue);
      expect(provider.currentFix!.confidence.inRange0to1(), isTrue);
    });
  });

  group('indoor entry hysteresis', () {
    testWidgets('fewer than indoorEnterConfirmCount qualifying estimates never '
        'enter indoor mode', (tester) async {
      native.emit(_est());
      await tester.pump();
      expect(provider.positionSource, isNot(LocationSource.indoorWifi));

      native.emit(_est());
      await tester.pump();
      expect(provider.positionSource, isNot(LocationSource.indoorWifi));
      expect(provider.currentFix, isNull);
    });

    testWidgets('the confirming estimate itself becomes the first believed fix',
        (tester) async {
      native.emit(_est(lat: 30.86501, lng: 29.58281));
      native.emit(_est(lat: 30.86502, lng: 29.58282));
      native.emit(_est(lat: 30.86503, lng: 29.58283));
      await tester.pump();

      expect(provider.positionSource, LocationSource.indoorWifi);
      final fix = provider.currentFix!;
      expect(fix.source, PositionSource.wifi);
      expect(fix.latitude, 30.86503);
      expect(fix.longitude, 29.58283);
      expect(fix.status, PositionFixStatus.fresh);
    });
  });

  group('scope confirmation', () {
    testWidgets('identity appears exactly after scopeConfirmCount consistent '
        'claims (published on the following accepted estimate)',
        (tester) async {
      // Claim streak = 1 at entry; identity must never appear before N.
      _enterIndoor(native); // claims 1..3? no: entry consumes 1 claim
      await tester.pump();
      expect(provider.currentFix!.hasScope, isFalse);

      native.emit(_est()); // streak = 2
      await tester.pump();
      expect(provider.currentFix!.hasScope, isFalse);

      native.emit(_est()); // streak = 3 -> confirmation fires internally
      await tester.pump();
      // The confirming fix was built with the previously confirmed pair, so
      // identity is still absent here - and selection never fills the gap.
      expect(provider.currentFix!.hasScope, isFalse);

      native.emit(_est()); // first accepted estimate after confirmation
      await tester.pump();
      final fix = provider.currentFix!;
      expect(fix.hasScope, isTrue);
      expect(fix.buildingId, 'b1');
      expect(fix.floor, '1');
    });

    testWidgets('winner identity comes only from evidence, and a different '
        'winning pair restarts the streak then switches atomically',
        (tester) async {
      _enterIndoor(native);
      _confirmScope(native);
      await tester.pump();
      expect(provider.currentFix!.buildingId, 'b1');

      // New winning pair: coordinates follow evidence immediately, identity
      // does NOT switch yet.
      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86600, lng: 29.58350));
      await tester.pump();
      var fix = provider.currentFix!;
      expect(fix.latitude, 30.86600);
      expect(fix.buildingId, 'b1');
      expect(fix.floor, '1');

      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86601, lng: 29.58351));
      await tester.pump();
      expect(provider.currentFix!.buildingId, 'b1'); // streak = 2

      // Interrupting pair resets the b2 streak...
      native.emit(_est(buid: 'b1', floor: '1', lat: 30.86500, lng: 29.58280));
      await tester.pump();
      expect(provider.currentFix!.buildingId, 'b1');

      // ...so b2 needs a fresh run of N consecutive claims.
      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86602, lng: 29.58352));
      await tester.pump();
      expect(provider.currentFix!.buildingId, 'b1');
      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86603, lng: 29.58353));
      await tester.pump();
      // Third consecutive b2 claim confirms internally, but the confirming
      // fix still publishes the previous pair.
      expect(provider.currentFix!.buildingId, 'b1');

      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86604, lng: 29.58354));
      await tester.pump();

      native.emit(
          _est(buid: 'b2', floor: '2', lat: 30.86605, lng: 29.58355));
      await tester.pump();
      fix = provider.currentFix!;
      expect(fix.buildingId, 'b2');
      expect(fix.floor, '2');
      expect(fix.latitude, 30.86605);
    });
  });

  group('outlier guard', () {
    testWidgets('same-scope jump beyond threshold holds the previous fix',
        (tester) async {
      const p1Lat = 30.86500, p1Lng = 29.58280;
      _enterIndoor(native, lat: p1Lat, lng: p1Lng);
      _confirmScope(native, lat: p1Lat, lng: p1Lng);
      await tester.pump();
      final before = provider.currentFix!;

      // ~111 m north, same winning map: implausible within one scan period.
      native.emit(_est(lat: p1Lat + 0.001, lng: p1Lng));
      await tester.pump();

      final held = provider.currentFix!;
      expect(held.status, PositionFixStatus.held);
      expect(held.latitude, before.latitude);
      expect(held.longitude, before.longitude);
      expect(held.accuracy, before.accuracy);
      expect(held.confidence, before.confidence);
      expect(held.buildingId, 'b1');
      expect(provider.latestIndoorEstimate!.latitude,
          closeTo(p1Lat + 0.001, 1e-9));

      // A plausible sample recovers immediately.
      native.emit(_est(lat: p1Lat, lng: p1Lng));
      await tester.pump();
      final recovered = provider.currentFix!;
      expect(recovered.status, PositionFixStatus.fresh);
      expect(recovered.latitude, p1Lat);
    });

    testWidgets('different-scope jumps are genuine transitions and bypass the '
        'guard', (tester) async {
      const p1Lat = 30.86500, p1Lng = 29.58280;
      _enterIndoor(native, lat: p1Lat, lng: p1Lng);
      _confirmScope(native, lat: p1Lat, lng: p1Lng);
      await tester.pump();

      // Different winning map ~111 m away: floors/maps overlap geographically,
      // only map identity disambiguates, so this is evidence - not an outlier.
      native.emit(
          _est(buid: 'b2', floor: '2', lat: p1Lat + 0.001, lng: p1Lng));
      await tester.pump();

      final fix = provider.currentFix!;
      expect(fix.status, PositionFixStatus.fresh);
      expect(fix.latitude, closeTo(p1Lat + 0.001, 1e-9));
      expect(fix.source, PositionSource.wifi);
    });

    testWidgets('three consecutive same-scope outliers exhaust the exit '
        'hysteresis', (tester) async {
      const p1Lat = 30.86500, p1Lng = 29.58280;
      _enterIndoor(native, lat: p1Lat, lng: p1Lng);
      _confirmScope(native, lat: p1Lat, lng: p1Lng);
      await tester.pump();

      native.emit(_est(lat: p1Lat + 0.001, lng: p1Lng));
      await tester.pump();
      native.emit(_est(lat: p1Lat + 0.002, lng: p1Lng));
      await tester.pump();
      expect(provider.positionSource, LocationSource.indoorWifi);

      native.emit(_est(lat: p1Lat + 0.003, lng: p1Lng));
      await tester.pump();
      expect(provider.positionSource, isNot(LocationSource.indoorWifi));
    });
  });

  group('indoor exit hysteresis', () {
    testWidgets('exits only after indoorExitStaleCycles consecutive bad cycles',
        (tester) async {
      _enterIndoor(native);
      _confirmScope(native);
      await tester.pump();

      native.emit(_est(status: 'no_match'));
      await tester.pump();
      native.emit(_est(status: 'no_match'));
      await tester.pump();
      expect(provider.positionSource, LocationSource.indoorWifi);

      native.emit(_est(status: 'no_match'));
      await tester.pump();
      expect(provider.positionSource, isNot(LocationSource.indoorWifi));
      expect(provider.currentFix, isNull);
    });

    testWidgets('GPS fixes never force an indoor exit on their own',
        (tester) async {
      _enterIndoor(native);
      _confirmScope(native);
      await tester.pump();

      provider.setGpsLocation(UserLocation(
        latitude: 30.86,
        longitude: 29.58,
        accuracy: 3.0,
        timestamp: DateTime.now(),
      ));
      await tester.pump();
      expect(provider.positionSource, LocationSource.indoorWifi);

      provider.setGpsLocation(UserLocation(
        latitude: 30.87,
        longitude: 29.59,
        accuracy: 40.0,
        timestamp: DateTime.now(),
      ));
      await tester.pump();
      expect(provider.positionSource, LocationSource.indoorWifi);
    });
  });

  group('rapid winner changes', () {
    testWidgets('alternating winners are deterministic and never fabricate '
        'identity', (tester) async {
      final seq = [
        _est(buid: 'b1', floor: '1', lat: 30.86500, lng: 29.58280),
        _est(buid: 'b2', floor: '2', lat: 30.86600, lng: 29.58350),
        _est(buid: 'b1', floor: '1', lat: 30.86501, lng: 29.58281),
        _est(buid: 'b2', floor: '2', lat: 30.86601, lng: 29.58351),
        _est(buid: 'b1', floor: '1', lat: 30.86502, lng: 29.58282),
        _est(buid: 'b2', floor: '2', lat: 30.86602, lng: 29.58352),
        _est(buid: 'b1', floor: '1', lat: 30.86503, lng: 29.58283),
      ];
      for (final e in seq) {
        native.emit(e);
        await tester.pump();
      }

      // Entry happened on the third qualifying estimate; belief tracks the
      // latest winner exactly; no pair reached N during alternation.
      expect(provider.positionSource, LocationSource.indoorWifi);
      expect(provider.currentFix!.latitude, 30.86503);
      expect(provider.currentFix!.hasScope, isFalse);

      // Once a pair stabilises, confirmation fires on the third consecutive
      // claim and publishes onto the following accepted estimate.
      native.emit(_est(buid: 'b1', floor: '1', lat: 30.86504, lng: 29.58284));
      await tester.pump();
      native.emit(_est(buid: 'b1', floor: '1', lat: 30.86505, lng: 29.58285));
      await tester.pump();
      expect(provider.currentFix!.buildingId, isNull); // confirmed at #3, not yet published

      native.emit(_est(buid: 'b1', floor: '1', lat: 30.86506, lng: 29.58286));
      await tester.pump();
      expect(provider.currentFix!.buildingId, 'b1');
      expect(provider.currentFix!.floor, '1');
    });
  });

  group('selection independence', () {
    testWidgets('identical evidence streams yield identical canonical results '
        'regardless of which maps were loaded into the service',
        (tester) async {
      // Two providers whose services record DIFFERENT residency loads -
      // standing in for different UI selection contexts.
      final nativeA = _FakeNativePositioningService();
      final providerA = LocationProvider(
        locationService: _FakeLocationService(),
        nativePositioningService: nativeA,
      );
      final nativeB = _FakeNativePositioningService();
      final providerB = LocationProvider(
        locationService: _FakeLocationService(),
        nativePositioningService: nativeB,
      );

      await nativeA.loadRadioMap('TEXT-A', 'selected-A', '9');
      await nativeB.loadRadioMap('TEXT-B', 'selected-B', '3');

      final stream = [
        _est(buid: 'w1', floor: '1', lat: 30.86500, lng: 29.58280),
        _est(buid: 'w1', floor: '1', lat: 30.86501, lng: 29.58281),
        _est(buid: 'w1', floor: '1', lat: 30.86502, lng: 29.58282),
        _est(buid: 'w1', floor: '1', lat: 30.86503, lng: 29.58283),
        _est(buid: 'w1', floor: '1', lat: 30.86504, lng: 29.58284),
        _est(buid: 'w1', floor: '1', lat: 30.86505, lng: 29.58285),
      ];
      for (final e in stream) {
        nativeA.emit(e);
        nativeB.emit(e);
      }
      await tester.pump();

      expect(nativeA.loadedMaps.first[1], 'selected-A');
      expect(nativeB.loadedMaps.first[1], 'selected-B');

      final fa = providerA.currentFix!;
      final fb = providerB.currentFix!;
      expect(fa.source, fb.source);
      expect(fa.latitude, fb.latitude);
      expect(fa.longitude, fb.longitude);
      expect(fa.buildingId, fb.buildingId);
      expect(fa.floor, fb.floor);
      expect(fa.status, fb.status);
      expect(fa.buildingId, 'w1');

      providerA.dispose();
      providerB.dispose();
      await tester.pump();
    });
  });
}

extension _ConfidenceCheck on double {
  bool inRange0to1() => this >= 0.0 && this <= 1.0;
}
