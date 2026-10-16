import 'dart:typed_data';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
  /// Optional last-modified timestamp from the cache (ISO 8601 string).
  /// Used for cache validation / revalidation.
  final String? lastModified;

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
    this.lastModified,
  });

  FloorplanModel copyWith({
    String? buid,
    String? floorNumber,
    String? imagePath,
    Uint8List? imageBytes,
    double? bottomLeftLat,
    double? bottomLeftLng,
    double? topRightLat,
    double? topRightLng,
    bool? isCached,
    int? imageSizeBytes,
    String? lastModified,
  }) {
    return FloorplanModel(
      buid: buid ?? this.buid,
      floorNumber: floorNumber ?? this.floorNumber,
      imagePath: imagePath ?? this.imagePath,
      imageBytes: imageBytes ?? this.imageBytes,
      bottomLeftLat: bottomLeftLat ?? this.bottomLeftLat,
      bottomLeftLng: bottomLeftLng ?? this.bottomLeftLng,
      topRightLat: topRightLat ?? this.topRightLat,
      topRightLng: topRightLng ?? this.topRightLng,
      isCached: isCached ?? this.isCached,
      imageSizeBytes: imageSizeBytes ?? this.imageSizeBytes,
      lastModified: lastModified ?? this.lastModified,
    );
  }

  /// Geographic bounding box for overlay positioning on FlutterMap.
  LatLngBounds get bounds => LatLngBounds(
        southwest: LatLng(bottomLeftLat, bottomLeftLng),
        northeast: LatLng(topRightLat, topRightLng),
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
          imagePath == other.imagePath &&
          lastModified == other.lastModified;

  @override
  int get hashCode {
    final code = lastModified?.hashCode ?? 0;
    return buid.hashCode ^ floorNumber.hashCode ^ imagePath.hashCode ^ code;
  }

  @override
  String toString() =>
      'FloorplanModel(buid: $buid, floor: $floorNumber, size: $imageSizeBytes bytes, cached: $isCached)';
}