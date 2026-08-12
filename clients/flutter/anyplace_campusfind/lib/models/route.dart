import '../utils/parsing.dart';

/// A single point along a navigation route, as returned by
/// `NavigationController`. Field names mirror `NavResultPoint.toJson()`.
class RoutePoint {
  const RoutePoint({
    required this.lat,
    required this.lon,
    required this.puid,
    required this.buid,
    required this.floorNumber,
    this.poisType,
  });

  final double lat;
  final double lon;
  final String puid;
  final String buid;
  final String floorNumber;
  final String? poisType;

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      lat: parseDouble(json['lat']),
      lon: parseDouble(json['lon']),
      puid: json['puid'] as String? ?? '',
      buid: json['buid'] as String? ?? '',
      floorNumber: json['floor_number'] as String? ?? '',
      poisType: json['pois_type'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat.toString(),
        'lon': lon.toString(),
        'puid': puid,
        'buid': buid,
        'floor_number': floorNumber,
        if (poisType != null) 'pois_type': poisType,
      };
}

/// Result of `POST /api/navigation/route` and `/route/coordinates`.
class NavigationRoute {
  const NavigationRoute({required this.numOfPois, required this.pois});

  final int numOfPois;
  final List<RoutePoint> pois;

  factory NavigationRoute.fromJson(Map<String, dynamic> json) {
    return NavigationRoute(
      numOfPois: json['num_of_pois'] as int? ?? 0,
      pois: (json['pois'] as List<dynamic>? ?? const [])
          .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'num_of_pois': numOfPois,
        'pois': pois.map((p) => p.toJson()).toList(),
      };
}
