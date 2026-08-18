import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_segment.dart';

/// Status of a navigation route model.
enum RouteModelStatus {
  /// All segments generated successfully. Full active navigation enabled.
  ready,

  /// One or more segments failed. Show available segments with warning.
  /// Active navigation is DISABLED for partial routes.
  partial,

  /// No usable route could be generated.
  error,
}

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

  /// Ordered list of route segments for cross-building navigation.
  /// Empty for legacy routes that don't use the segment model.
  final List<RouteSegment> segments;

  /// Overall status of this route.
  final RouteModelStatus status;

  /// Warning message shown when [status] is [NavigationRouteStatus.partial].
  final String? partialRouteWarning;

  const NavigationRouteModel({
    required this.points,
    this.segments = const [],
    this.status = RouteModelStatus.ready,
    this.partialRouteWarning,
  });

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

  /// Creates a route from segments, generating flat points automatically.
  factory NavigationRouteModel.fromSegments({
    required List<RouteSegment> segments,
    required RouteModelStatus status,
    String? partialRouteWarning,
  }) {
    final allPoints = <NavigationRoutePoint>[];
    for (final seg in segments) {
      for (final pt in seg.points) {
        allPoints.add(NavigationRoutePoint(
          latitude: pt.latitude,
          longitude: pt.longitude,
          puid: seg.connectorPoiId ?? '__segment__',
          buid: seg.buildingId ?? '',
          floorNumber: seg.floorNumber ?? '',
          poisType: seg.type.name,
          isOutdoor: seg.type == RouteSegmentType.outdoorWalking,
        ));
      }
    }
    return NavigationRouteModel(
      points: allPoints,
      segments: segments,
      status: status,
      partialRouteWarning: partialRouteWarning,
    );
  }

  bool get hasPoints => points.isNotEmpty;
  bool get hasRenderablePath => points.length >= 2;

  /// Whether this route uses the segment model (cross-building navigation).
  bool get hasSegments => segments.isNotEmpty;

  /// Whether this is a partial route (some segments failed).
  bool get isPartial => status == RouteModelStatus.partial;

  /// Whether this route is fully navigable (ready status, has segments).
  bool get isFullyNavigable =>
      status == RouteModelStatus.ready && hasSegments;

  /// Reconstructs the flat point list from segments for backward compatibility.
  /// If no segments exist, returns the original [points] list.
  List<NavigationRoutePoint> get flatPoints {
    if (segments.isEmpty) return points;
    final result = <NavigationRoutePoint>[];
    for (final seg in segments) {
      for (final pt in seg.points) {
        result.add(NavigationRoutePoint(
          latitude: pt.latitude,
          longitude: pt.longitude,
          puid: seg.connectorPoiId ?? '__segment__',
          buid: seg.buildingId ?? '',
          floorNumber: seg.floorNumber ?? '',
          poisType: seg.type.name,
          isOutdoor: seg.type == RouteSegmentType.outdoorWalking,
        ));
      }
    }
    return result;
  }

  /// Total distance across all segments in meters.
  double get totalDistance =>
      segments.fold(0.0, (sum, seg) => sum + seg.distance);

  /// Estimated total duration in seconds (approximation: 1.4 m/s walking speed).
  double get estimatedDuration => totalDistance / 1.4;

  /// The current segment being navigated, or null if not started.
  RouteSegment? get currentSegment => null; // Set by NavigationController

  /// The next segment after the current one, or null.
  RouteSegment? get nextSegment => null; // Set by NavigationController

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
