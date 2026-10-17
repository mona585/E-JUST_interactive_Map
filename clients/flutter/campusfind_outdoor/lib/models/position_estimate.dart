import 'package:google_maps_flutter/google_maps_flutter.dart';

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

  /// RSS-space distance of the closest matched fingerprint on the winning map.
  /// Null when the platform payload predates the evidence fields or when
  /// nothing was localized. May be infinite for degenerate native results.
  final double? bestDistance;

  /// Maximum pairwise great-circle spread (meters) among the k selected
  /// fingerprints of the winning map. Null when not provided.
  final double? topKSpreadMeters;

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
    this.bestDistance,
    this.topKSpreadMeters,
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
    DateTime timestamp;
    if (tsVal is num) {
      try {
        timestamp = DateTime.fromMillisecondsSinceEpoch(tsVal.toInt());
      } on ArgumentError {
        // Corrupt/out-of-range numeric timestamp: same fallback semantics as
        // a non-numeric one - never crash the positioning stream.
        timestamp = DateTime.now();
      }
    } else {
      timestamp = DateTime.now();
    }

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
      bestDistance: parseDouble(map['bestDistance']),
      topKSpreadMeters: parseDouble(map['topKSpreadMeters']),
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
      if (bestDistance != null) 'bestDistance': bestDistance,
      if (topKSpreadMeters != null) 'topKSpreadMeters': topKSpreadMeters,
    };
  }

  @override
  String toString() {
    return 'PositionEstimate(buid: $buid, floor: $floor, matchedAps: $matchedAps/$totalAps, lat: $latitude, lon: $longitude, valid: $isValid)';
  }
}
