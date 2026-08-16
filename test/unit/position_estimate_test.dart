import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';

void main() {
  group('PositionEstimate', () {
    test('parses valid native estimate map correctly', () {
      final map = {
        'latitude': 30.859418,
        'longitude': 29.562789,
        'buid': 'building_b8f4e123',
        'floor': '0',
        'matchedAps': 6,
        'totalAps': 12,
        'durationMs': 15,
        'timestamp': 1786543200000,
        'status': 'success',
      };

      final estimate = PositionEstimate.fromMap(map);

      expect(estimate.latitude, closeTo(30.859418, 0.000001));
      expect(estimate.longitude, closeTo(29.562789, 0.000001));
      expect(estimate.buid, 'building_b8f4e123');
      expect(estimate.floor, '0');
      expect(estimate.matchedAps, 6);
      expect(estimate.totalAps, 12);
      expect(estimate.durationMs, 15);
      expect(estimate.status, 'success');
      expect(estimate.isValid, isTrue);
      expect(estimate.latLng, isNotNull);
      expect(estimate.latLng!.latitude, closeTo(30.859418, 0.000001));
    });

    test('rejects (0.0, 0.0) coordinates as invalid', () {
      final map = {
        'latitude': 0.0,
        'longitude': 0.0,
        'buid': 'buid_1',
        'floor': '1',
        'matchedAps': 5,
        'status': 'success',
      };

      final estimate = PositionEstimate.fromMap(map);
      expect(estimate.isValid, isFalse);
      expect(estimate.latLng, isNull);
    });

    test('rejects estimate with 0 matched APs', () {
      final map = {
        'latitude': 30.8594,
        'longitude': 29.5627,
        'buid': 'buid_1',
        'floor': '1',
        'matchedAps': 0,
        'status': 'success',
      };

      final estimate = PositionEstimate.fromMap(map);
      expect(estimate.isValid, isFalse);
      expect(estimate.latLng, isNull);
    });

    test('rejects estimate with status != success', () {
      final map = {
        'latitude': 30.8594,
        'longitude': 29.5627,
        'buid': 'buid_1',
        'floor': '1',
        'matchedAps': 5,
        'status': 'no_match',
      };

      final estimate = PositionEstimate.fromMap(map);
      expect(estimate.isValid, isFalse);
      expect(estimate.latLng, isNull);
    });

    test('handles string-formatted numbers gracefully', () {
      final map = {
        'latitude': '35.1444',
        'longitude': '33.4105',
        'buid': 'buid_str',
        'floor': '2',
        'matchedAps': '4',
        'totalAps': '10',
        'durationMs': '8',
        'status': 'success',
      };

      final estimate = PositionEstimate.fromMap(map);
      expect(estimate.latitude, 35.1444);
      expect(estimate.longitude, 33.4105);
      expect(estimate.matchedAps, 4);
      expect(estimate.isValid, isTrue);
    });
  });
}
