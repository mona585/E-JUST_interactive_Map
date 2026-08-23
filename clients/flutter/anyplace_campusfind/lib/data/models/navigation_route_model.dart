import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'route_segment.dart';

/// Completeness of a composed [NavigationRouteModel].
///
/// Deliberately distinct from SpaceProvider's `NavigationRouteStatus`, which
/// tracks the route-fetch lifecycle (idle/loading/ready/unsupported/error).
/// This enum describes whether the model itself is fully usable: [ready]
/// enables active navigation, [partial] renders with a warning and disables
/// it, [error] carries nothing usable.
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

/// A full Anyplace navigation route.
///
/// Two complementary representations live here:
///  * [points] — the universal flat waypoint projection consumed by the
///    renderer and by the controller's floor-transition indices. Always
///    populated.
///  * [segments] — optional typed legs of a cross-building journey
///    ([RouteSegmentType]). Empty for legacy routes built directly from
///    server waypoints or hybrid merges; when built via
///    [NavigationRouteModel.fromSegments], [points] are derived from the
///    segments so the segments remain the single source of truth.
class NavigationRouteModel {
  final List<NavigationRoutePoint> points;

  /// Ordered list of route segments for cross-building navigation.
  /// Empty for legacy routes that don't use the segment model.
  final List<RouteSegment> segments;

  /// Overall status of this route.
  final RouteModelStatus status;

  /// Warning message shown when [status] is [RouteModelStatus.partial].
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

  /// Creates a route from segments, deriving the flat [points] projection.
  ///
  /// Generated points carry synthetic, globally-unique puids of the form
  /// `<segmentType>_<index>` and have no server identity. Real connector /
  /// entrance identity stays on the [RouteSegment] itself (e.g.
  /// [RouteSegment.connectorPoiId]).
  factory NavigationRouteModel.fromSegments({
    required List<RouteSegment> segments,
    required RouteModelStatus status,
    String? partialRouteWarning,
  }) {
    final allPoints = <NavigationRoutePoint>[];
    var pointIndex = 0;
    for (final seg in segments) {
      for (final pt in seg.points) {
        allPoints.add(NavigationRoutePoint(
          latitude: pt.latitude,
          longitude: pt.longitude,
          puid: '${seg.type.name}_$pointIndex',
          buid: seg.buildingId ?? '',
          floorNumber: seg.floorNumber ?? '',
          poisType: seg.type.name,
          isOutdoor: seg.type == RouteSegmentType.outdoorWalking,
        ));
        pointIndex++;
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

  /// The subset of polyline points that belong to [floorNumber].
  List<LatLng> polylinePointsForFloor(String floorNumber) {
    return points
        .where((p) => p.floorNumber == floorNumber)
        .map((p) => p.latLng)
        .toList();
  }
}
