import 'package:latlong2/latlong.dart';

/// A single Anyplace navigation waypoint returned by the routing API.
class NavigationRoutePoint {
  final double latitude;
  final double longitude;
  final String puid;
  final String buid;
  final String floorNumber;
  final String poisType;

  const NavigationRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.puid,
    required this.buid,
    required this.floorNumber,
    required this.poisType,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  factory NavigationRoutePoint.fromJson(Map<String, dynamic> json) {
    double parseRequiredDouble(String fieldName) {
      final value = json[fieldName];
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      throw FormatException('Invalid route point coordinate for "$fieldName".');
    }

    String parseRequiredString(String fieldName) {
      final value = json[fieldName]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
      throw FormatException('Invalid route point field "$fieldName".');
    }

    return NavigationRoutePoint(
      latitude: parseRequiredDouble('lat'),
      longitude: parseRequiredDouble('lon'),
      puid: parseRequiredString('puid'),
      buid: parseRequiredString('buid'),
      floorNumber: parseRequiredString('floor_number'),
      poisType: json['pois_type']?.toString().trim().isNotEmpty == true
          ? json['pois_type'].toString().trim()
          : 'None',
    );
  }
}

/// A full Anyplace navigation route polyline composed of waypoint POIs.
class NavigationRouteModel {
  final List<NavigationRoutePoint> points;

  const NavigationRouteModel({required this.points});

  factory NavigationRouteModel.fromJson(Map<String, dynamic> json) {
    final poisList = json['pois'];
    if (poisList is! List) {
      throw const FormatException(
        'Navigation route payload is missing a valid "pois" list.',
      );
    }

    final routePoints = <NavigationRoutePoint>[];
    for (final item in poisList) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException(
          'Navigation route contains an invalid route point.',
        );
      }
      routePoints.add(NavigationRoutePoint.fromJson(item));
    }

    if (routePoints.length < 2) {
      throw const FormatException(
        'Navigation route must contain at least two valid points.',
      );
    }

    return NavigationRouteModel(points: routePoints);
  }

  bool get hasPoints => points.isNotEmpty;
  bool get hasRenderablePath => points.length >= 2;

  List<LatLng> get polylinePoints =>
      points.map((point) => point.latLng).toList();
}
