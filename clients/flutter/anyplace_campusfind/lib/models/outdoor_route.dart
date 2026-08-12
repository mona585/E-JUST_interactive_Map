import 'package:latlong2/latlong.dart';

/// A decoded OSRM (Open Source Routing Machine) driving route.
class OutdoorRoute {
  const OutdoorRoute({required this.points, this.distance, this.duration});

  /// Decoded geometry coordinates, in travel order.
  final List<LatLng> points;

  /// Route distance in metres (when reported by OSRM).
  final double? distance;

  /// Route duration in seconds (when reported by OSRM).
  final double? duration;

  bool get isEmpty => points.isEmpty;
}
