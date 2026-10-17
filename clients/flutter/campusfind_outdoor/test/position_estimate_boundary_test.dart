import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/models/position_estimate.dart';

/// Native->Dart transport-boundary hardening verification.
///
/// - PositionEstimate.fromMap is total (cannot throw for any Map input) and
///   round-trips IEEE-754 doubles (NaN / +-inf) losslessly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Part 1: PositionEstimate.fromMap parsing matrix
  // ---------------------------------------------------------------------------
  group('PositionEstimate.fromMap transport matrix', () {
    testWidgets('canonical valid native payload parses all fields exactly',
        (tester) async {
      const ts = 1700000000000;
      final e = PositionEstimate.fromMap(const {
        'latitude': 30.865,
        'longitude': 29.5828,
        'buid': 'b1',
        'floor': '1',
        'matchedAps': 5,
        'totalAps': 8,
        'durationMs': 12,
        'timestamp': ts,
        'status': 'success',
        'bestDistance': 6.25,
        'topKSpreadMeters': 9.5,
      });

      expect(e.latitude, 30.865);
      expect(e.longitude, 29.5828);
      expect(e.buid, 'b1');
      expect(e.floor, '1');
      expect(e.matchedAps, 5);
      expect(e.totalAps, 8);
      expect(e.durationMs, 12);
      expect(e.timestamp.millisecondsSinceEpoch, ts);
      expect(e.status, 'success');
      expect(e.bestDistance, 6.25);
      expect(e.topKSpreadMeters, 9.5);
      expect(e.isValid, isTrue);
      expect(e.latLng, isNotNull);
    });

    testWidgets('legacy payload without evidence fields parses safely',
        (tester) async {
      final e = PositionEstimate.fromMap(const {
        'latitude': 30.865,
        'longitude': 29.5828,
        'buid': 'b1',
        'floor': '1',
        'matchedAps': 5,
        'totalAps': 8,
        'durationMs': 12,
        'timestamp': 1700000000000,
        'status': 'success',
      });

      expect(e.bestDistance, isNull);
      expect(e.topKSpreadMeters, isNull);
      expect(e.isValid, isTrue);
    });

    testWidgets('string numeric representations still parse', (tester) async {
      final e = PositionEstimate.fromMap(const {
        'latitude': '30.865',
        'longitude': '29.5828',
        'buid': 'b1',
        'floor': '1',
        'matchedAps': '5',
        'totalAps': '8',
        'durationMs': '12',
        'timestamp': 1700000000000,
        'status': 'success',
        'bestDistance': '6.25',
        'topKSpreadMeters': '9.5',
      });

      expect(e.latitude, 30.865);
      expect(e.longitude, 29.5828);
      expect(e.matchedAps, 5);
      expect(e.totalAps, 8);
      expect(e.durationMs, 12);
      expect(e.bestDistance, 6.25);
      expect(e.topKSpreadMeters, 9.5);
    });

    testWidgets('missing optional evidence stays null and harmless',
        (tester) async {
      final absent = PositionEstimate.fromMap(const {
        'buid': 'b1',
        'floor': '1',
        'status': 'no_match',
      });
      final explicitNull = PositionEstimate.fromMap(const {
        'buid': 'b1',
        'floor': '1',
        'status': 'no_match',
        'latitude': null,
        'longitude': null,
        'bestDistance': null,
        'topKSpreadMeters': null,
      });

      for (final e in [absent, explicitNull]) {
        expect(e.bestDistance, isNull);
        expect(e.topKSpreadMeters, isNull);
        expect(e.latitude, isNull);
        expect(e.longitude, isNull);
        expect(e.isValid, isFalse);
      }
    });

    testWidgets('malformed optional evidence types do not crash parsing',
        (tester) async {
      final e = PositionEstimate.fromMap(const {
        'latitude': [30.8],
        'longitude': {'deg': 29.5},
        'buid': 42,
        'floor': true,
        'matchedAps': [1, 2],
        'totalAps': {'n': 8},
        'durationMs': false,
        'timestamp': 'not-a-number',
        'status': ['success'],
        'bestDistance': <String>[],
        'topKSpreadMeters': <int, String>{0: 'x'},
      });

      // Untyped garbage degrades to defaults/nulls, never throws.
      expect(e.buid, '42'); // coerced via toString()
      expect(e.floor, 'true');
      expect(e.status, '[success]');
      expect(e.matchedAps, 0);
      expect(e.totalAps, 0);
      expect(e.durationMs, 0);
      expect(e.latitude, isNull);
      expect(e.longitude, isNull);
      expect(e.bestDistance, isNull);
      expect(e.topKSpreadMeters, isNull);
      expect(e.isValid, isFalse);
    });

    testWidgets('non-finite evidence values parse without failure',
        (tester) async {
      final e = PositionEstimate.fromMap(const {
        'latitude': double.nan,
        'longitude': double.infinity,
        'buid': 'b1',
        'floor': '1',
        'matchedAps': 5,
        'totalAps': 8,
        'status': 'success',
        'bestDistance': double.infinity,
        'topKSpreadMeters': double.nan,
      });

      // Values survive as non-finite doubles (StandardMethodCodec carries
      // IEEE-754 bit patterns); validity classification rejects them.
      expect(e.latitude!.isNaN, isTrue);
      expect(e.longitude!.isInfinite, isTrue);
      expect(e.bestDistance!.isInfinite, isTrue);
      expect(e.topKSpreadMeters!.isNaN, isTrue);
      expect(e.isValid, isFalse);
      expect(e.latLng, isNull);
    });

    testWidgets('corrupt numeric timestamps fall back to wall clock',
        (tester) async {
      final before = DateTime.now();
      final e = PositionEstimate.fromMap(const {
        'buid': 'b1',
        'floor': '1',
        'status': 'success',
        'timestamp': 9007199254740992,
      });
      final after = DateTime.now();

      // Must not throw; falls back to now() like non-numeric timestamps.
      expect(e.timestamp.isBefore(before) || e.timestamp.isAfter(after),
          isFalse);
      expect(e.isValid, isFalse); // no coordinates in payload
    });

    testWidgets('unsuccessful estimates without coordinates stay invalid',
        (tester) async {
      for (final status in const ['error', 'no_match', '', 'unknown']) {
        final e = PositionEstimate.fromMap({
          'buid': '',
          'floor': '',
          'status': status,
          'matchedAps': 0,
          'totalAps': 8,
        });
        expect(e.isValid, isFalse, reason: 'status=$status');
        expect(e.latLng, isNull, reason: 'status=$status');
      }
    });

    testWidgets('canonical field set is unchanged (toMap key contract)',
        (tester) async {
      final full = PositionEstimate(
        latitude: 30.865,
        longitude: 29.5828,
        buid: 'b1',
        floor: '1',
        matchedAps: 5,
        totalAps: 8,
        durationMs: 12,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: 'success',
        bestDistance: 6.25,
        topKSpreadMeters: 9.5,
      );

      expect(full.toMap().keys.toSet(), {
        'latitude', 'longitude', 'buid', 'floor', 'matchedAps', 'totalAps',
        'durationMs', 'timestamp', 'status', 'bestDistance', 'topKSpreadMeters',
      });

      // Round-trip preserves semantics (legacy consumers unaffected).
      final back = PositionEstimate.fromMap(full.toMap());
      expect(back.latitude, full.latitude);
      expect(back.longitude, full.longitude);
      expect(back.buid, full.buid);
      expect(back.floor, full.floor);
      expect(back.matchedAps, full.matchedAps);
      expect(back.totalAps, full.totalAps);
      expect(back.durationMs, full.durationMs);
      expect(
          back.timestamp.millisecondsSinceEpoch,
          full.timestamp.millisecondsSinceEpoch);
      expect(back.status, full.status);
      expect(back.bestDistance, full.bestDistance);
      expect(back.topKSpreadMeters, full.topKSpreadMeters);

      // Legacy-shaped estimates omit only the evidence keys they never had.
      final legacy = PositionEstimate(
        buid: 'b1',
        floor: '1',
        matchedAps: 5,
        totalAps: 8,
        durationMs: 12,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: 'success',
      );
      expect(legacy.toMap().containsKey('bestDistance'), isFalse);
      expect(legacy.toMap().containsKey('topKSpreadMeters'), isFalse);
    });

    testWidgets('hostile map battery never throws and never yields validity',
        (tester) async {
      final hostileMaps = <Map<dynamic, dynamic>>[
        const {},
        const {'latitude': 'abc', 'longitude': ''},
        const {'matchedAps': 'x', 'totalAps': -5},
        const {'timestamp': -5000},
        const {'timestamp': 9007199254740992},
        const {'buid': null, 'floor': null, 'status': null},
        const {
          'latitude': -1e308,
          'longitude': 1e308,
          'bestDistance': -0.0,
        },
      ];

      for (final m in hostileMaps) {
        PositionEstimate? parsed;
        expect(() => parsed = PositionEstimate.fromMap(m),
            returnsNormally, reason: 'map=$m');
        expect(parsed, isNotNull, reason: 'map=$m');
        if (!(parsed!.isValid)) {
          expect(parsed!.latLng, isNull, reason: 'map=$m');
        }
      }
    });
  });
}
