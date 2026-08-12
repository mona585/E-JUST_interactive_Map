/// Result of `POST /api/position/estimate` — estimated user coordinates.
class PositionEstimate {
  const PositionEstimate({required this.lat, required this.long});

  final double lat;
  final double long;

  factory PositionEstimate.fromJson(Map<String, dynamic> json) {
    return PositionEstimate(
      lat: _parseDouble(json['lat']),
      long: _parseDouble(json['long']),
    );
  }

  static double _parseDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  /// True when the backend returned no usable fix (`"0 0"`).
  bool get hasFix => lat != 0.0 || long != 0.0;

  Map<String, dynamic> toJson() => {'lat': lat.toString(), 'long': long.toString()};
}
