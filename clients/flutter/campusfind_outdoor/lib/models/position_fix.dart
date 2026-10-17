import 'package:google_maps_flutter/google_maps_flutter.dart';

/// How the unified positioning arbiter sourced a [PositionFix].
enum PositionSource {
  /// Fix derived from GNSS/GPS readings.
  gps,

  /// Fix derived from WiFi fingerprinting against a resident RadioMap.
  wifi,
}

/// Lifecycle state of a [PositionFix] as judged by the arbiter.
enum PositionFixStatus {
  /// Freshly accepted from qualifying evidence.
  fresh,

  /// The newest raw evidence was rejected (quality gate or outlier guard);
  /// the previous accepted coordinates are carried forward unchanged.
  held,

  /// No qualifying evidence within the freshness window. Coordinates are kept
  /// for display only and must not drive navigation decisions.
  stale,
}

/// Canonical immutable output of the unified positioning pipeline.
///
/// A [PositionFix] is the single authoritative position object produced by
/// arbitration between GPS and WiFi evidence. Consumers must never reconstruct
/// position or building/floor identity from UI selection context; identity is
/// present here only after [NavigationConfig.scopeConfirmCount] consecutive
/// consistent winning estimates, otherwise [buildingId]/[floor] are null.
class PositionFix {
  /// WGS84 latitude (degrees). Always finite and within valid ranges.
  final double latitude;

  /// WGS84 longitude (degrees). Always finite and within valid ranges.
  final double longitude;

  /// Which evidence stream won arbitration for this fix.
  final PositionSource source;

  /// Canonically confirmed building id, or null while unconfirmed.
  ///
  /// Never inferred from user selection; populated only after a consistent
  /// winning-estimate streak of [NavigationConfig.scopeConfirmCount].
  final String? buildingId;

  /// Canonically confirmed floor name, or null while unconfirmed.
  ///
  /// Confirmed together with [buildingId] as one atomic identity pair.
  final String? floor;

  /// Estimated horizontal accuracy in meters (GPS reported accuracy, or WiFi
  /// accuracy clamped to
  /// [NavigationConfig.wifiAccuracyMinMeters]..[NavigationConfig.wifiAccuracyMaxMeters]).
  final double accuracy;

  /// Arbitration confidence in [0, 1], derived from match ratio, top-k spread
  /// and short-term stability of the winning evidence stream.
  final double confidence;

  /// Time at which the underlying evidence was observed.
  final DateTime timestamp;

  /// Arbiter lifecycle state of this fix.
  final PositionFixStatus status;

  const PositionFix({
    required this.latitude,
    required this.longitude,
    required this.source,
    this.buildingId,
    this.floor,
    required this.accuracy,
    required this.confidence,
    required this.timestamp,
    required this.status,
  })  : assert(latitude >= -90.0 && latitude <= 90.0),
        assert(longitude >= -180.0 && longitude <= 180.0),
        assert(accuracy >= 0.0),
        assert(confidence >= 0.0 && confidence <= 1.0);

  /// Whether the canonical building/floor identity is confirmed on this fix.
  bool get hasScope => buildingId != null && floor != null;

  /// Coordinates as [LatLng] for map consumption.
  LatLng get latLng => LatLng(latitude, longitude);

  /// Returns a copy with the given fields replaced.
  PositionFix copyWith({
    double? latitude,
    double? longitude,
    PositionSource? source,
    String? buildingId,
    String? floor,
    double? accuracy,
    double? confidence,
    DateTime? timestamp,
    PositionFixStatus? status,
  }) {
    return PositionFix(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      source: source ?? this.source,
      buildingId: buildingId ?? this.buildingId,
      floor: floor ?? this.floor,
      accuracy: accuracy ?? this.accuracy,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PositionFix &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.source == source &&
        other.buildingId == buildingId &&
        other.floor == floor &&
        other.accuracy == accuracy &&
        other.confidence == confidence &&
        other.timestamp == timestamp &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, source, buildingId,
      floor, accuracy, confidence, timestamp, status);

  @override
  String toString() {
    return 'PositionFix(${latitude.toStringAsFixed(6)}, '
        '${longitude.toStringAsFixed(6)}, source: $source, '
        'scope: ${hasScope ? '$buildingId/$floor' : 'unconfirmed'}, '
        'accuracy: ${accuracy.toStringAsFixed(1)}m, '
        'confidence: ${confidence.toStringAsFixed(2)}, status: $status)';
  }
}
