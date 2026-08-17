import 'dart:typed_data';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Data model representing an acquired geographic floorplan image for a building floor.
class FloorplanModel {
  final String buid;
  final String floorNumber;
  final String imagePath;
  final Uint8List? imageBytes;
  final double bottomLeftLat;
  final double bottomLeftLng;
  final double topRightLat;
  final double topRightLng;
  final bool isCached;
  final int imageSizeBytes;

  const FloorplanModel({
    required this.buid,
    required this.floorNumber,
    required this.imagePath,
    this.imageBytes,
    required this.bottomLeftLat,
    required this.bottomLeftLng,
    required this.topRightLat,
    required this.topRightLng,
    this.isCached = false,
    this.imageSizeBytes = 0,
  });

  /// Geographic bounding box for overlay positioning on FlutterMap.
  LatLngBounds get bounds => LatLngBounds(
        LatLng(bottomLeftLat, bottomLeftLng),
        LatLng(topRightLat, topRightLng),
      );

  /// Center coordinate of the floorplan.
  LatLng get center => LatLng(
        (bottomLeftLat + topRightLat) / 2.0,
        (bottomLeftLng + topRightLng) / 2.0,
      );

  /// Whether the floorplan has valid non-zero bounding box coordinates.
  bool get hasValidBounds =>
      bottomLeftLat != 0.0 &&
      bottomLeftLng != 0.0 &&
      topRightLat != 0.0 &&
      topRightLng != 0.0 &&
      bottomLeftLat < topRightLat;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FloorplanModel &&
          runtimeType == other.runtimeType &&
          buid == other.buid &&
          floorNumber == other.floorNumber &&
          imagePath == other.imagePath;

  @override
  int get hashCode =>
      buid.hashCode ^ floorNumber.hashCode ^ imagePath.hashCode;

  @override
  String toString() =>
      'FloorplanModel(buid: $buid, floor: $floorNumber, size: $imageSizeBytes bytes, cached: $isCached)';
}
