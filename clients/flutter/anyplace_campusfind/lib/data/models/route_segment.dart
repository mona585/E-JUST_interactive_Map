import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Types of route segments in a cross-building navigation journey.
///
/// Segments are always ordered: exitTransition → outdoorWalking →
/// entranceTransition → indoorRouting. Additional floorTransition segments
/// may appear within exit or entrance segments.
enum RouteSegmentType {
  /// Outdoor walking path between buildings (OSRM).
  outdoorWalking,

  /// Indoor routing within a single building (Anyplace API).
  indoorRouting,

  /// Floor transition within a building (elevator/stairs).
  floorTransition,

  /// Indoor route from user's position to building exit.
  exitTransition,

  /// Indoor route from destination building entrance to destination POI.
  entranceTransition,
}

/// A single leg of a multi-segment navigation journey.
///
/// Each segment contains a list of [LatLng] points, metadata about the
/// segment type, and optional fields for rendering and navigation.
class RouteSegment {
  /// The type of this segment.
  final RouteSegmentType type;

  /// Ordered list of points forming this segment's path.
  final List<LatLng> points;

  /// Floor number for indoor segments. Null for outdoor segments.
  final String? floorNumber;

  /// Building ID for indoor segments. Null for outdoor segments.
  final String? buildingId;

  /// PUID of the connector POI (elevator/stairs) at the transition point.
  /// Null if no connector is involved.
  final String? connectorPoiId;

  /// Human-readable instruction for this segment (e.g., "Take elevator to
  /// Floor 1", "Walk to Building B").
  final String? instruction;

  /// Total distance of this segment in meters.
  final double distance;

  /// Whether this segment could not be fully generated (API failure).
  /// Incomplete segments are shown with a warning and not used for
  /// active navigation.
  final bool isIncomplete;

  /// Whether this segment's endpoint is a building centroid fallback
  /// (not a real connector/entrance POI).
  final bool isFallbackLocation;

  const RouteSegment({
    required this.type,
    required this.points,
    this.floorNumber,
    this.buildingId,
    this.connectorPoiId,
    this.instruction,
    this.distance = 0.0,
    this.isIncomplete = false,
    this.isFallbackLocation = false,
  });

  /// Whether this segment has no points.
  bool get isEmpty => points.isEmpty;

  /// The first point of this segment, or null if empty.
  LatLng? get startPoint => points.isEmpty ? null : points.first;

  /// The last point of this segment, or null if empty.
  LatLng? get endPoint => points.isEmpty ? null : points.last;

  // ──────────────────────────────────────────────────────────────
  // Factory constructors
  // ──────────────────────────────────────────────────────────────

  /// Creates an outdoor walking segment.
  factory RouteSegment.outdoor({
    required List<LatLng> points,
    required String buildingId,
    String? instruction,
    double distance = 0.0,
    bool isIncomplete = false,
  }) {
    return RouteSegment(
      type: RouteSegmentType.outdoorWalking,
      points: points,
      buildingId: buildingId,
      instruction: instruction,
      distance: distance,
      isIncomplete: isIncomplete,
    );
  }

  /// Creates an indoor routing segment.
  factory RouteSegment.indoor({
    required List<LatLng> points,
    required String buildingId,
    required String floorNumber,
    String? connectorPoiId,
    String? instruction,
    double distance = 0.0,
    bool isIncomplete = false,
  }) {
    return RouteSegment(
      type: RouteSegmentType.indoorRouting,
      points: points,
      buildingId: buildingId,
      floorNumber: floorNumber,
      connectorPoiId: connectorPoiId,
      instruction: instruction,
      distance: distance,
      isIncomplete: isIncomplete,
    );
  }

  /// Creates an exit transition segment (indoor → outdoor from starting building).
  factory RouteSegment.exit({
    required List<LatLng> points,
    required String buildingId,
    required String floorNumber,
    String? connectorPoiId,
    String? instruction,
    double distance = 0.0,
    bool isIncomplete = false,
    bool isFallbackLocation = false,
  }) {
    return RouteSegment(
      type: RouteSegmentType.exitTransition,
      points: points,
      buildingId: buildingId,
      floorNumber: floorNumber,
      connectorPoiId: connectorPoiId,
      instruction: instruction,
      distance: distance,
      isIncomplete: isIncomplete,
      isFallbackLocation: isFallbackLocation,
    );
  }

  /// Creates an entrance transition segment (outdoor → indoor at destination).
  factory RouteSegment.entrance({
    required List<LatLng> points,
    required String buildingId,
    required String floorNumber,
    String? connectorPoiId,
    String? instruction,
    double distance = 0.0,
    bool isIncomplete = false,
    bool isFallbackLocation = false,
  }) {
    return RouteSegment(
      type: RouteSegmentType.entranceTransition,
      points: points,
      buildingId: buildingId,
      floorNumber: floorNumber,
      connectorPoiId: connectorPoiId,
      instruction: instruction,
      distance: distance,
      isIncomplete: isIncomplete,
      isFallbackLocation: isFallbackLocation,
    );
  }

  /// Creates a floor transition segment (elevator/stairs within a building).
  factory RouteSegment.floorTransition({
    required List<LatLng> points,
    required String buildingId,
    required String floorNumber,
    String? connectorPoiId,
    String? instruction,
    double distance = 0.0,
  }) {
    return RouteSegment(
      type: RouteSegmentType.floorTransition,
      points: points,
      buildingId: buildingId,
      floorNumber: floorNumber,
      connectorPoiId: connectorPoiId,
      instruction: instruction,
      distance: distance,
    );
  }

  /// Creates a centroid fallback segment when no entrance/exit POI exists.
  ///
  /// The [points] should contain two points: the start (user position or
  /// building centroid) and the end (building centroid or entrance location).
  /// The [isFallbackLocation] flag is automatically set to `true`.
  factory RouteSegment.fallback({
    required RouteSegmentType type,
    required List<LatLng> points,
    required String buildingId,
    String? floorNumber,
    String? instruction,
    double distance = 0.0,
    bool isIncomplete = false,
  }) {
    return RouteSegment(
      type: type,
      points: points,
      buildingId: buildingId,
      floorNumber: floorNumber,
      instruction: instruction,
      distance: distance,
      isIncomplete: isIncomplete,
      isFallbackLocation: true,
    );
  }

  @override
  String toString() =>
      'RouteSegment(${type.name}, points: ${points.length}, '
      'floor: $floorNumber, incomplete: $isIncomplete, '
      'fallback: $isFallbackLocation)';
}
