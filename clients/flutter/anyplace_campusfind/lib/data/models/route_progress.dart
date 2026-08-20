import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'custom_route_model.dart';

/// Tracks the user's progress along a custom route during active navigation.
///
/// Updated on each GPS fix by comparing the user's position to the route graph.
/// Used by [NavigationController] for progress display, off-route detection,
/// and rerouting decisions.
class RouteProgress {
  /// The custom route being navigated.
  final CustomRoute route;

  /// Index of the current edge (segment between two vertices) on the route.
  final int currentEdgeIndex;

  /// Parametric position along the current edge [0.0, 1.0].
  /// 0.0 = at the from-vertex, 1.0 = at the to-vertex.
  final double edgeProgress;

  /// Snapped position on the route closest to the user's GPS.
  final LatLng snappedPosition;

  /// Perpendicular distance from GPS to the snapped position (meters).
  final double distanceFromRoute;

  /// Total distance traveled along the route from the start (meters).
  final double distanceTraveled;

  /// Total remaining distance to the route end (meters).
  final double distanceRemaining;

  /// Total route length in meters.
  final double totalRouteLength;

  /// Whether the user is currently on-route (within threshold).
  final bool isOnRoute;

  const RouteProgress({
    required this.route,
    required this.currentEdgeIndex,
    required this.edgeProgress,
    required this.snappedPosition,
    required this.distanceFromRoute,
    required this.distanceTraveled,
    required this.distanceRemaining,
    required this.totalRouteLength,
    required this.isOnRoute,
  });

  /// Fraction of the route completed [0.0, 1.0].
  double get progressFraction =>
      totalRouteLength > 0 ? (distanceTraveled / totalRouteLength).clamp(0.0, 1.0) : 0.0;

  /// Percentage of route completed (0–100).
  int get progressPercent => (progressFraction * 100).round();

  @override
  String toString() =>
      'RouteProgress(edge: $currentEdgeIndex, '
      't: ${edgeProgress.toStringAsFixed(2)}, '
      'dist: ${distanceFromRoute.toStringAsFixed(1)}m, '
      ' traveled: ${distanceTraveled.toStringAsFixed(0)}m/'
      '${totalRouteLength.toStringAsFixed(0)}m, '
      'onRoute: $isOnRoute)';
}
