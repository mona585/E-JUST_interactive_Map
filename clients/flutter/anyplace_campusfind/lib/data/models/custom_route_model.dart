import 'dart:math' show cos, sin, atan2, pi, sqrt;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// A single parsed outdoor walking route from a KMZ/KML file.
///
/// Each route is a named polyline with an ordered list of [LatLng] vertices.
/// Routes may intersect at junction vertices (detected by proximity).
class CustomRoute {
  /// Human-readable route name (from KML `<name>` tag).
  final String name;

  /// Ordered list of vertices forming the route polyline.
  final List<LatLng> vertices;

  /// Index of the first vertex in the merged [CustomRouteGraph] vertex list.
  /// Set by the graph builder; -1 if not yet assigned.
  final int graphStartIndex;

  /// Index of the last vertex in the merged graph.
  final int graphEndIndex;

  const CustomRoute({
    required this.name,
    required this.vertices,
    this.graphStartIndex = -1,
    this.graphEndIndex = -1,
  });

  /// Total geodesic length of this route in meters.
  double get lengthMeters {
    double total = 0;
    for (var i = 0; i < vertices.length - 1; i++) {
      total += _haversine(vertices[i], vertices[i + 1]);
    }
    return total;
  }

  bool get hasPoints => vertices.isNotEmpty;
  int get vertexCount => vertices.length;

  /// Returns a copy with updated graph indices.
  CustomRoute copyWith({
    int? graphStartIndex,
    int? graphEndIndex,
  }) {
    return CustomRoute(
      name: name,
      vertices: vertices,
      graphStartIndex: graphStartIndex ?? this.graphStartIndex,
      graphEndIndex: graphEndIndex ?? this.graphEndIndex,
    );
  }

  @override
  String toString() =>
      'CustomRoute($name, ${vertices.length} verts, ${lengthMeters.toStringAsFixed(0)}m)';

  /// Haversine distance in meters between two [LatLng] points.
  static double _haversine(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);

    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
}
