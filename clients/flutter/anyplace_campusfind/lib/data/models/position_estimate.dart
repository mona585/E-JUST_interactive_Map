import 'package:latlong2/latlong.dart';

/// Represents a native indoor position estimate calculated from Wi-Fi fingerprinting.
class PositionEstimate {
  final double? latitude;
  final double? longitude;
  final String buid;
  final String floor;
  final int matchedAps;
  final int totalAps;
  final int durationMs;
  final DateTime timestamp;
  final String status;

  const PositionEstimate({
    this.latitude,
    this.longitude,
    required this.buid,
    required this.floor,
    required this.matchedAps,
    required this.totalAps,
    required this.durationMs,
    required this.timestamp,
    required this.status,
  });

  /// Factory constructor to deserialize from EventChannel JSON payload map.
  factory PositionEstimate.fromMap(Map<dynamic, dynamic> map) {
    double? parseDouble(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val);
      return null;
    }

    int parseInt(dynamic val, [int defaultValue = 0]) {
      if (val == null) return defaultValue;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val) ?? defaultValue;
      return defaultValue;
    }

    final tsVal = map['timestamp'];
    final timestamp = tsVal is num
        ? DateTime.fromMillisecondsSinceEpoch(tsVal.toInt())
        : DateTime.now();

    return PositionEstimate(
      latitude: parseDouble(map['latitude']),
      longitude: parseDouble(map['longitude']),
      buid: (map['buid'] ?? '').toString(),
      floor: (map['floor'] ?? '').toString(),
      matchedAps: parseInt(map['matchedAps']),
      totalAps: parseInt(map['totalAps']),
      durationMs: parseInt(map['durationMs']),
      timestamp: timestamp,
      status: (map['status'] ?? 'unknown').toString(),
    );
  }

  /// Whether this estimate contains valid, non-placeholder WGS84 coordinates.
  bool get isValid {
    if (status != 'success') return false;
    if (latitude == null || longitude == null) return false;
    if (!latitude!.isFinite || !longitude!.isFinite) return false;
    if (latitude == 0.0 && longitude == 0.0) return false;
    if (matchedAps <= 0) return false;
    return true;
  }

  /// Converts valid coordinates to LatLng for FlutterMap.
  LatLng? get latLng {
    if (!isValid) return null;
    return LatLng(latitude!, longitude!);
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'buid': buid,
      'floor': floor,
      'matchedAps': matchedAps,
      'totalAps': totalAps,
      'durationMs': durationMs,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status,
    };
  }

  @override
  String toString() {
    return 'PositionEstimate(buid: $buid, floor: $floor, matchedAps: $matchedAps/$totalAps, lat: $latitude, lon: $longitude, valid: $isValid)';
  }
}
