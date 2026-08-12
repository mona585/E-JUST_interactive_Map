import 'dart:math';

import '../models/poi.dart';
import '../models/space.dart';

/// Haversine distance calculations between geographic coordinates.
class DistanceCalculator {
  DistanceCalculator._();

  static const double _earthRadiusMeters = 6371000.0;

  /// Great-circle distance in meters between two lat/lon points.
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double distanceToSpace(double lat, double lon, Space space) =>
      haversineMeters(lat, lon, space.coordinatesLat, space.coordinatesLon);

  static double distanceToPoi(double lat, double lon, Poi poi) =>
      haversineMeters(lat, lon, poi.coordinatesLat, poi.coordinatesLon);

  /// Nearest [Space] to a location, or null when [spaces] is empty.
  static Space? nearestSpace(double lat, double lon, List<Space> spaces) {
    Space? best;
    var bestDistance = double.infinity;
    for (final space in spaces) {
      final d = distanceToSpace(lat, lon, space);
      if (d < bestDistance) {
        bestDistance = d;
        best = space;
      }
    }
    return best;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
