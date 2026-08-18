import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single Anyplace navigation waypoint returned by the routing API.
class NavigationRoutePoint {
  final double latitude;
  final double longitude;
  final String puid;
  final String buid;
  final String floorNumber;
  final String poisType;
  final bool isOutdoor;

  const NavigationRoutePoint({
    required this.latitude,
    required this.longitude,
    required this.puid,
    required this.buid,
    required this.floorNumber,
    required this.poisType,
    this.isOutdoor = false,
  });

  LatLng get latLng => LatLng(latitude, longitude);

  /// Synthetic outdoor waypoint (GPS position, not from Anyplace graph).
  factory NavigationRoutePoint.outdoor({
    required double latitude,
    required double longitude,
    required String buid,
    required String floorNumber,
  }) {
    return NavigationRoutePoint(
      latitude: latitude,
      longitude: longitude,
      puid: '__outdoor__',
      buid: buid,
      floorNumber: floorNumber,
      poisType: 'outdoor',
      isOutdoor: true,
    );
  }

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

  /// Creates a hybrid route: outdoor segment (GPS â†’ entrance) + indoor segment (POI-to-POI).
  ///
  /// [outdoorPoints] are the GPS waypoints leading to the building entrance.
  /// [indoorRoute] is the Anyplace POI-to-POI route inside the building.
  /// The entrance point is shared between both segments.
  factory NavigationRouteModel.hybrid({
    required List<NavigationRoutePoint> outdoorPoints,
    NavigationRouteModel? indoorRoute,
  }) {
    final merged = <NavigationRoutePoint>[...outdoorPoints];
    if (indoorRoute != null && indoorRoute.hasPoints) {
      for (final p in indoorRoute.points) {
        if (merged.isEmpty || merged.last.puid != p.puid) {
          merged.add(p);
        }
      }
    }
    return NavigationRouteModel(points: merged);
  }

  /// Whether this route contains any outdoor (GPS) waypoints.
  bool get hasOutdoorSegment => points.any((p) => p.isOutdoor);

  /// The subset of points that are outdoor (GPS) waypoints.
  List<LatLng> get outdoorPolylinePoints => points
      .where((p) => p.isOutdoor)
      .map((p) => p.latLng)
      .toList();

  /// The subset of points that are indoor (Anyplace graph) waypoints.
  List<LatLng> get indoorPolylinePoints => points
      .where((p) => !p.isOutdoor)
      .map((p) => p.latLng)
      .toList();

  /// Whether there is a separate indoor segment to render.
  bool get hasIndoorSegment => points.where((p) => !p.isOutdoor).length >= 2;

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
        continue;
      }
      try {
        routePoints.add(NavigationRoutePoint.fromJson(item));
      } on FormatException {
        // Skip invalid points instead of failing the whole route
        continue;
      }
    }

    return NavigationRouteModel(points: routePoints);
  }

  bool get hasPoints => points.isNotEmpty;
  bool get hasRenderablePath => points.length >= 2;

  List<LatLng> get polylinePoints =>
      points.map((point) => point.latLng).toList();

  /// Indices where the floor number changes between consecutive points.
  ///
  /// Each entry is the index of the point BEFORE the floor change (the
  /// connector POI on the current floor). The next point is on a different floor.
  List<int> get floorTransitionIndices {
    final indices = <int>[];
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i].floorNumber != points[i + 1].floorNumber) {
        indices.add(i);
      }
    }
    return indices;
  }

  /// Whether this route crosses one or more floors.
  bool get hasFloorTransitions => floorTransitionIndices.isNotEmpty;

  /// The route points grouped by floor number (preserving order within each floor).
  Map<String, List<NavigationRoutePoint>> get segmentsByFloor {
    final map = <String, List<NavigationRoutePoint>>{};
    for (final point in points) {
      map.putIfAbsent(point.floorNumber, () => []).add(point);
    }
    return map;
  }

  /// Floor numbers this route passes through, in order of first appearance.
  List<String> get floorsInOrder {
    final seen = <String>{};
    final floors = <String>[];
    for (final point in points) {
      if (seen.add(point.floorNumber)) {
        floors.add(point.floorNumber);
      }
    }
    return floors;
  }

  /// Connector points where the floor changes.
  ///
  /// Uses [poisType] when available (Stair/Elevator), falls back to
  /// floor-number-change detection.
  List<NavigationRoutePoint> get connectorPoints {
    return [
      for (final idx in floorTransitionIndices) points[idx],
    ];
  }

  /// Returns the next floor the route transitions to from [currentFloor],
  /// or null if the route stays on the current floor.
  String? nextFloorFrom(String currentFloor) {
    for (final idx in floorTransitionIndices) {
      if (points[idx].floorNumber == currentFloor) {
        return points[idx + 1].floorNumber;
      }
    }
    return null;
  }

  /// The subset of polyline points that belong to [floorNumber].
  List<LatLng> polylinePointsForFloor(String floorNumber) {
    return points
        .where((p) => p.floorNumber == floorNumber)
        .map((p) => p.latLng)
        .toList();
  }
}
