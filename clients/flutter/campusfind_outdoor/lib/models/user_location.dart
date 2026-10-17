import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Represents a geographic position obtained from the device GPS.
class UserLocation {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double heading;
  final double speed;
  final DateTime timestamp;

  const UserLocation({
    required this.latitude,
    required this.longitude,
    this.accuracy = 0.0,
    this.altitude = 0.0,
    this.heading = 0.0,
    this.speed = 0.0,
    required this.timestamp,
  });

  /// Returns a [LatLng] point compatible with FlutterMap.
  LatLng get latLng => LatLng(latitude, longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserLocation &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          accuracy == other.accuracy &&
          altitude == other.altitude &&
          heading == other.heading &&
          speed == other.speed &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      latitude.hashCode ^
      longitude.hashCode ^
      accuracy.hashCode ^
      altitude.hashCode ^
      heading.hashCode ^
      speed.hashCode ^
      timestamp.hashCode;

  @override
  String toString() {
    return 'UserLocation(lat: $latitude, lng: $longitude, acc: ${accuracy.toStringAsFixed(1)}m, heading: ${heading.toStringAsFixed(1)}Â°)';
  }
}
