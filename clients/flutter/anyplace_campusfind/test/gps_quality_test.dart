import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/position_fix.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

// ---------------------------------------------------------------------------
// PHASE 5 — Outdoor GPS Quality Pipeline (INV-8 inputs, INV-11)
// ---------------------------------------------------------------------------

UserLocation _gps(
  double lat, {
  double accuracy = 8.0,
  DateTime? at,
  double lng = 29.5828,
}) =>
    UserLocation(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      timestamp: at ?? DateTime.now(),
    );

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
  @override
  Stream<PositionEstimate> get positionStream => const Stream.empty();
}

LocationProvider _provider() => LocationProvider(
      locationService: _GpsService(),
      nativePositioningService: _Native(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('stale fixes never become canonical; the previous fix is '
      'demoted to stale for display', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);

    p.setGpsLocation(_gps(30.8700));
    expect(p.currentFix?.source, PositionSource.gps);
    expect(p.currentFix?.status, PositionFixStatus.fresh);

    // A fix stamped 30 s in the past must not move the canonical position.
    p.setGpsLocation(_gps(30.9000,
        at: DateTime.now().subtract(const Duration(seconds: 30))));
    expect(p.currentFix!.latitude, 30.8700,
        reason: 'stale fix did not refresh canonical position');
    expect(p.gpsLocation!.latitude, 30.9000,
        reason: 'INV-11: raw sample is still preserved');

    // The demotion surfaces through status.
    final fresh = _gps(30.8701);
    p.setGpsLocation(fresh);
    expect(p.currentFix!.status, PositionFixStatus.fresh);
  });

  testWidgets('accuracy bands: reject band ignored, poor band accepted but '
      'low-confidence', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);

    // Above the reject band: entirely ignored.
    p.setGpsLocation(_gps(30.9000, accuracy: 80));
    expect(p.currentFix, isNull);
    expect(p.gpsLocation!.latitude, 30.9000, reason: 'raw preserved');

    // Poor band (poor < acc <= reject): accepted, flagged low-confidence.
    p.setGpsLocation(_gps(30.8900, accuracy: 40));
    expect(p.currentFix, isNotNull);
    expect(p.currentFix!.latitude, 30.8900);
    expect(p.currentFix!.confidence, lessThan(0.5),
        reason: 'poor-band fixes carry low confidence for decisions');
    expect(p.currentFix!.status, PositionFixStatus.fresh);

    // Good band returns high confidence.
    p.setGpsLocation(_gps(30.8899, accuracy: 10));
    expect(p.currentFix!.confidence, 0.7);
  });

  testWidgets('implied-speed outlier holds once, then accepts real fast '
      'movement', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);

    var t = DateTime.now();
    p.setGpsLocation(_gps(30.8700, accuracy: 8, at: t));

    // 1.1 km "jump" within ~1 s with non-good accuracy -> outlier.
    t = t.add(const Duration(milliseconds: 50));
    p.setGpsLocation(_gps(30.8600, accuracy: 40, at: t));
    expect(p.currentFix!.latitude, 30.8700,
        reason: 'outlier held: previous fix carried forward');
    expect(p.currentFix!.status, PositionFixStatus.held);

    // Second consecutive outlier: genuine fast movement is accepted.
    t = t.add(const Duration(milliseconds: 50));
    p.setGpsLocation(_gps(30.8500, accuracy: 40, at: t));
    expect(p.currentFix!.latitude, 30.8500);
    expect(p.currentFix!.status, PositionFixStatus.fresh);

    // Good-accuracy jumps are never treated as outliers.
    t = t.add(const Duration(milliseconds: 50));
    p.setGpsLocation(_gps(30.9950, accuracy: 8, at: t));
    expect(p.currentFix!.latitude, 30.9950);
  });

  testWidgets('degraded streak drives the pause contract signal', (tester) async {
    final p = _provider();
    addTearDown(p.dispose);

    p.setGpsLocation(_gps(30.8700, accuracy: 8));
    expect(p.gpsDegraded, isFalse);

    for (var i = 0; i < NavigationConfig.gpsPausePoorTicks - 1; i++) {
      p.setGpsLocation(_gps(30.8700, accuracy: 80));
      expect(p.gpsDegraded, isFalse,
          reason: 'below threshold nothing may act on degradation');
    }
    p.setGpsLocation(_gps(30.8700, accuracy: 80));
    expect(p.gpsDegraded, isTrue);

    // A single good fix clears the streak immediately.
    p.setGpsLocation(_gps(30.8701, accuracy: 8));
    expect(p.gpsDegraded, isFalse);
  });
}
