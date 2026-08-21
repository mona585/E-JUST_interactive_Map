import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';

void main() {
  group('UserLocation Model Tests', () {
    final testTimestamp = DateTime(2026, 8, 15, 12, 0, 0);

    test('creates UserLocation and extracts LatLng correctly', () {
      final loc = UserLocation(
        latitude: 35.1444,
        longitude: 33.4105,
        accuracy: 4.5,
        altitude: 120.0,
        heading: 90.0,
        speed: 1.2,
        timestamp: testTimestamp,
      );

      expect(loc.latitude, 35.1444);
      expect(loc.longitude, 33.4105);
      expect(loc.accuracy, 4.5);
      expect(loc.altitude, 120.0);
      expect(loc.heading, 90.0);
      expect(loc.speed, 1.2);
      expect(loc.timestamp, testTimestamp);
      expect(loc.latLng, equals(const LatLng(35.1444, 33.4105)));
    });

    test('supports value equality and hash code', () {
      final loc1 = UserLocation(
        latitude: 31.2001,
        longitude: 29.9187,
        accuracy: 5.0,
        timestamp: testTimestamp,
      );

      final loc2 = UserLocation(
        latitude: 31.2001,
        longitude: 29.9187,
        accuracy: 5.0,
        timestamp: testTimestamp,
      );

      final loc3 = UserLocation(
        latitude: 30.0444,
        longitude: 31.2357,
        accuracy: 10.0,
        timestamp: testTimestamp,
      );

      expect(loc1, equals(loc2));
      expect(loc1.hashCode, equals(loc2.hashCode));
      expect(loc1, isNot(equals(loc3)));
    });

    test('toString formats latitude, longitude, and accuracy cleanly', () {
      final loc = UserLocation(
        latitude: 35.1444,
        longitude: 33.4105,
        accuracy: 3.2,
        heading: 45.0,
        timestamp: testTimestamp,
      );

      expect(
        loc.toString(),
        'UserLocation(lat: 35.1444, lng: 33.4105, acc: 3.2m, heading: 45.0°)',
      );
    });
  });
}
