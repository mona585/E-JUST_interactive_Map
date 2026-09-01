import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/data/models/position_fix.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

// FORENSIC REMEDIATION REGRESSION TEST
// Finding: POS-003 / X-4 — GPS stream SILENCE left a `fresh` fix believed
// forever because staleness was evaluated only when a new sample arrived.
// The watchdog converts silence age into degraded ticks + stale demotion.

UserLocation _good(DateTime at) => UserLocation(
      latitude: 30.0,
      longitude: 29.0,
      accuracy: 5,
      timestamp: at,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('POS-003: silence windows convert into degraded ticks and demote the '
      'canonical fix to stale', () {
    final lp = LocationProvider();
    addTearDown(lp.dispose);

    final t0 = DateTime(2026, 8, 24, 12, 0, 0);
    lp.setGpsLocation(_good(t0));
    lp.startTracking(); // arms the real watchdog; evaluation driven manually

    expect(lp.gpsDegraded, isFalse);
    expect(lp.currentFix!.status, PositionFixStatus.fresh);

    // Watchdog firings at one-staleness-window intervals of total silence.
    for (var i = 1; i <= NavigationConfig.gpsPausePoorTicks; i++) {
      lp.debugEvaluateGpsSilenceForTest(
          t0.add(Duration(seconds: NavigationConfig.gpsStaleAfterSeconds * i)));
    }

    expect(lp.gpsDegraded, isTrue,
        reason: 'gpsPausePoorTicks silence windows must reach the PAUSED '
            'signal consumers already honor');
    expect(lp.currentFix!.status, PositionFixStatus.stale);
    // Coordinates are preserved for display — only status degrades.
    expect(lp.currentFix!.latitude, 30.0);
  });

  test('POS-003: a fresh accepted sample resets the silence accounting', () {
    final lp = LocationProvider();
    addTearDown(lp.dispose);

    final t0 = DateTime(2026, 8, 24, 12, 0, 0);
    lp.startTracking();
    lp.setGpsLocation(_good(t0));

    lp.debugEvaluateGpsSilenceForTest(t0
        .add(const Duration(seconds: NavigationConfig.gpsStaleAfterSeconds)));
    expect(lp.gpsDegradedStreakForTest, 1);

    lp.setGpsLocation(_good(t0.add(const Duration(
        seconds: NavigationConfig.gpsStaleAfterSeconds + 1))));
    expect(lp.gpsDegradedStreakForTest, 0);
    expect(lp.currentFix!.status, PositionFixStatus.fresh);
  });
}
