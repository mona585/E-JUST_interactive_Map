import 'dart:math' show max, min;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// E-JUST campus boundary — AUTHORITATIVE reference for the initial /
/// campus-overview framing.
///
/// The four approximate cardinal boundary points were supplied by the campus
/// administration from Google Maps:
///
///   North  30°51'45.0"N 29°33'42.5"E  →  30.862500, 29.561806
///   South                             →  30.855703, 29.566940
///   East                              →  30.860705, 29.567365
///   West                              →  30.858273, 29.560721
///
/// These SUPERSEDE the previously hand-transcribed DMS corners. The campus
/// building registry is still incomplete, so a centroid computed from the
/// currently registered buildings is explicitly NOT a reliable campus
/// reference; these boundary points are independent of the building dataset.
const LatLng ejustCampusBoundaryNorth = LatLng(30.862500, 29.561806);
const LatLng ejustCampusBoundarySouth = LatLng(30.855703, 29.566940);
const LatLng ejustCampusBoundaryEast = LatLng(30.860705, 29.567365);
const LatLng ejustCampusBoundaryWest = LatLng(30.858273, 29.560721);

/// The four supplied cardinal boundary points, as a single collection.
const List<LatLng> ejustCampusBoundaryPoints = <LatLng>[
  ejustCampusBoundaryNorth,
  ejustCampusBoundarySouth,
  ejustCampusBoundaryEast,
  ejustCampusBoundaryWest,
];

/// Axis-aligned bounding rectangle of [ejustCampusBoundaryPoints], derived
/// from the supplied points so the extrema can never drift from the reference
/// coordinates. Extrema: S 30.855703, N 30.862500, W 29.560721, E 29.567365.
///
/// Used ONLY to fit the initial / campus-overview camera viewport. Never drawn.
final LatLngBounds ejustCampusBounds = LatLngBounds(
  southwest: LatLng(
    ejustCampusBoundaryPoints.map((p) => p.latitude).reduce(min),
    ejustCampusBoundaryPoints.map((p) => p.longitude).reduce(min),
  ),
  northeast: LatLng(
    ejustCampusBoundaryPoints.map((p) => p.latitude).reduce(max),
    ejustCampusBoundaryPoints.map((p) => p.longitude).reduce(max),
  ),
);

/// Centre of the supplied BOUNDING RECTANGLE: the arithmetic midpoint of its
/// south/north and west/east extrema — `30.8591015, 29.564043`.
///
/// This is a bounding-box centre, NOT a polygon centroid of the campus
/// footprint (the four supplied points are cardinal extrema, not a traced
/// outline), so it approximates — rather than exactly equals — the visual
/// campus centre.
final LatLng ejustCampusBoundaryCenter = LatLng(
  (ejustCampusBounds.southwest.latitude +
          ejustCampusBounds.northeast.latitude) /
      2,
  (ejustCampusBounds.southwest.longitude +
          ejustCampusBounds.northeast.longitude) /
      2,
);


/// Map-related configuration constants.
class MapConfig {
  MapConfig._();

  static const MapType mapType = MapType.hybrid;

  static const double defaultZoom = 16.0;

  /// Initial / campus-overview camera bearing, in degrees measured CLOCKWISE
  /// FROM NORTH (the Google Maps convention — `CameraPosition.bearing`: `0.0`
  /// means the camera points north, north-up; `90.0` means it points east).
  ///
  /// `45.0` therefore rotates the camera 45° toward the north-east. This is a
  /// pure camera ROTATION: the target ([ejustCampusBoundaryCenter]), the
  /// boundary bounds ([ejustCampusBounds]) and the bounds-derived zoom are all
  /// unchanged. Non-overview cameras keep the legacy north-up (0.0) bearing.
  static const double campusOverviewBearing = 45.0;

  static const double focusedZoom = 18.0;
  static const double indoorFloorplanZoom = 19.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 19.0;

  static const String userAgentPackageName = 'eg.edu.ejust.anyplace.navigator';
}
