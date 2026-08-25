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
  ///
  /// PHASE 7 / INV-7: an outdoor point is IDENTITY-FREE. It carries no
  /// building id and no floor — the parameters that used to stamp the
  /// destination's identity onto GPS waypoints were a metadata lie and have
  /// been removed.
  factory NavigationRoutePoint.outdoor({
    required double latitude,
    required double longitude,
  }) {
    return NavigationRoutePoint(
      latitude: latitude,
      longitude: longitude,
      puid: '__outdoor__',
      buid: '',
      floorNumber: '',
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

    final puid = parseRequiredString('puid');
    final poisType = json['pois_type']?.toString().trim().isNotEmpty == true
        ? json['pois_type'].toString().trim()
        : 'None';
    // PHASE 7 / INV-7: server-derived points derive outdoor-ness from their
    // own markers instead of defaulting to false forever.
    final isOutdoor = poisType.toLowerCase() == 'outdoor' || puid == '__outdoor__';

    return NavigationRoutePoint(
      latitude: parseRequiredDouble('lat'),
      longitude: parseRequiredDouble('lon'),
      puid: puid,
      buid: parseRequiredString('buid'),
      floorNumber: parseRequiredString('floor_number'),
      poisType: poisType,
      isOutdoor: isOutdoor,
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
      // PHASE 7 / INV-7: outdoorWalking segments project IDENTITY-FREE
      // points — the segment-level buildingId is journey context for
      // instructions, never a claim about the GPS waypoint itself.
      final isOutdoorSeg = seg.type == RouteSegmentType.outdoorWalking;
      // Per-point truthful floors win over the segment-level floor whenever
      // they were provided and aligned; otherwise the flattened segment
      // floor applies exactly as before.
      final hasAlignedFloors =
          seg.pointFloors.length == seg.points.length;
      for (var i = 0; i < seg.points.length; i++) {
        final pt = seg.points[i];
        String floorNumber;
        if (isOutdoorSeg) {
          floorNumber = '';
        } else if (hasAlignedFloors && seg.pointFloors[i].isNotEmpty) {
          floorNumber = seg.pointFloors[i];
        } else {
          floorNumber = seg.floorNumber ?? '';
        }
        allPoints.add(NavigationRoutePoint(
          latitude: pt.latitude,
          longitude: pt.longitude,
          puid: '${seg.type.name}_$pointIndex',
          buid: isOutdoorSeg ? '' : (seg.buildingId ?? ''),
          floorNumber: floorNumber,
          poisType: isOutdoorSeg ? 'outdoor' : seg.type.name,
          isOutdoor: isOutdoorSeg,
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

  /// Wraps a PURELY-INDOOR legacy route into the segmented representation so
  /// it renders through the same indoorRouting projection as composed
  /// cross-building journeys.
  ///
  /// This is a representation change ONLY:
  ///  * geometry ([points] coordinates) is carried over verbatim;
  ///  * per-point floors are preserved via [RouteSegment.pointFloors];
  ///  * [status] / [partialRouteWarning] pass through unchanged;
  ///  * routes that already have segments, are not renderable, or contain
  ///    any outdoor waypoint are returned as-is (they either need no wrap or
  ///    belong to a different rendering path).
  NavigationRouteModel toSegmentedIndoor({
    String? fallbackBuildingId,
    String? instruction,
  }) {
    if (hasSegments || !hasRenderablePath || hasOutdoorSegment) return this;
    String? buid;
    String? floor;
    final pointFloors = <String>[];
    for (final p in points) {
      if (buid == null && p.buid.isNotEmpty) buid = p.buid;
      if (floor == null && p.floorNumber.isNotEmpty) floor = p.floorNumber;
      pointFloors.add(p.floorNumber);
    }
    return NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.indoor(
          points: polylinePoints,
          buildingId: buid ?? fallbackBuildingId ?? '',
          floorNumber: floor ?? '',
          pointFloors: pointFloors,
          instruction: instruction,
        ),
      ],
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
  /// PHASE 7 / INV-7: only changes between two NON-EMPTY floors count as
  /// floor transitions. An empty floor marks an entrance/exit boundary
  /// (outdoor leg meeting indoor leg) — those boundaries are already
  /// represented by segment types and must never fabricate a "transition"
  /// (the old ''↔'0' phantom).
  List<int> get floorTransitionIndices {
    final indices = <int>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i].floorNumber;
      final b = points[i + 1].floorNumber;
      if (a.isEmpty || b.isEmpty) continue;
      if (a != b) indices.add(i);
    }
    return indices;
  }

  /// Indices of points that act as entrance/exit markers (poiType based).
  ///
  /// Convenience for rendering connectors at journey boundaries without
  /// treating them as floor transitions.
  List<int> get entranceExitIndices {
    final indices = <int>[];
    for (var i = 0; i < points.length; i++) {
      final t = points[i].poisType.toLowerCase();
      if (t.contains('entrance') || t.contains('exit')) {
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
