import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Data model representing an indoor Point of Interest (POI) from the Anyplace backend.
class PoiModel {
  final String puid;
  final String buid;
  final String floorNumber;
  final String? floorName;
  final String name;
  final String? description;
  final String poisType;
  final double latitude;
  final double longitude;
  final bool isBuildingEntrance;
  final bool isDoor;
  final bool isPublished;
  final String? imageUrl;
  
  /// Optional last-modified timestamp from the Anyplace backend (ISO 8601 string).
  /// Used for cache validation / revalidation. When present, the value is
  /// provided by the backend and should not be hardcoded or fabricated.
  final String? lastModified;

  const PoiModel({
    required this.puid,
    required this.buid,
    required this.floorNumber,
    this.floorName,
    required this.name,
    this.description,
    required this.poisType,
    required this.latitude,
    required this.longitude,
    this.isBuildingEntrance = false,
    this.isDoor = false,
    this.isPublished = true,
    this.imageUrl,
    this.lastModified,
  });

  /// [LatLng] coordinates for positioning on FlutterMap.
  LatLng get latLng => LatLng(latitude, longitude);

  /// Safe JSON deserialization factory supporting both string and numeric types from Anyplace API.
  factory PoiModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
      return defaultValue;
    }

    bool parseBool(dynamic value, [bool defaultValue = false]) {
      if (value == null) return defaultValue;
      if (value is bool) return value;
      if (value is String) {
        final lower = value.trim().toLowerCase();
        if (lower == 'true' || lower == '1' || lower == 'yes') return true;
        if (lower == 'false' || lower == '0' || lower == 'no') return false;
      }
      if (value is num) return value != 0;
      return defaultValue;
    }

    return PoiModel(
      puid: json['puid']?.toString().trim() ?? '',
      buid: json['buid']?.toString().trim() ?? '',
      floorNumber: json['floor_number']?.toString().trim() ?? '',
      floorName: json['floor_name']?.toString().trim(),
      name: json['name']?.toString().trim() ?? 'POI',
      description: json['description']?.toString().trim(),
      poisType: json['pois_type']?.toString().trim() ?? 'Other',
      latitude: parseDouble(json['coordinates_lat']),
      longitude: parseDouble(json['coordinates_lon']),
      isBuildingEntrance: parseBool(json['is_building_entrance']),
      isDoor: parseBool(json['is_door']),
      isPublished: parseBool(json['is_published'], true),
      imageUrl: json['image']?.toString().trim(),
      lastModified: json['last_modified'] != null && json['last_modified'].toString().trim().isNotEmpty
          ? json['last_modified'].toString().trim()
          : null,
    );
  }

  /// Converts this [PoiModel] into a JSON map for storage and caching.
  Map<String, dynamic> toJson() => {
        'puid': puid,
        'buid': buid,
        'floor_number': floorNumber,
        if (floorName != null) 'floor_name': floorName,
        'name': name,
        if (description != null) 'description': description,
        'pois_type': poisType,
        'coordinates_lat': latitude.toString(),
        'coordinates_lon': longitude.toString(),
        'is_building_entrance': isBuildingEntrance ? 'true' : 'false',
        'is_door': isDoor ? 'true' : 'false',
        'is_published': isPublished ? 'true' : 'false',
        if (imageUrl != null) 'image': imageUrl,
        if (lastModified != null) 'last_modified': lastModified,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PoiModel &&
          runtimeType == other.runtimeType &&
          puid == other.puid &&
          lastModified == other.lastModified;

  @override
  int get hashCode {
    final code = lastModified?.hashCode ?? 0;
    return puid.hashCode ^ code;
  }

  @override
  String toString() =>
      'PoiModel(puid: $puid, name: $name, type: $poisType, lat: $latitude, lon: $longitude)';
}
