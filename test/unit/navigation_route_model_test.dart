import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';

void main() {
  group('NavigationRouteModel parsing', () {
    test('NavigationRoutePoint.fromJson rejects invalid coordinates', () {
      expect(
        () => NavigationRoutePoint.fromJson({
          'lat': 'not-a-number',
          'lon': '33.4105',
          'puid': 'poi_start',
          'buid': 'buid_123',
          'floor_number': '1',
          'pois_type': 'None',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('NavigationRouteModel.fromJson rejects routes with fewer than two points', () {
      expect(
        () => NavigationRouteModel.fromJson({
          'pois': [
            {
              'lat': '35.1444',
              'lon': '33.4105',
              'puid': 'poi_start',
              'buid': 'buid_123',
              'floor_number': '1',
              'pois_type': 'None',
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
