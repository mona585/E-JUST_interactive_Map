import '../utils/parsing.dart';

/// Result of `POST /api/position/estimate` — estimated user coordinates.
class PositionEstimate {
  const PositionEstimate({required this.lat, required this.long});

  final double lat;
  final double long;

  factory PositionEstimate.fromJson(Map<String, dynamic> json) {
    return PositionEstimate(
      lat: parseDouble(json['lat']),
      long: parseDouble(json['long']),
    );
  }

  /// True when the backend returned no usable fix (`"0 0"`).
  bool get hasFix => lat != 0.0 || long != 0.0;

  Map<String, dynamic> toJson() => {'lat': lat.toString(), 'long': long.toString()};
}
