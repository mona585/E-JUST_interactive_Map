import 'package:latlong2/latlong.dart';

/// Represents a space (building, vessel, etc.) in the Anyplace backend.
class SpaceModel {
  /// Unique identifier for the building/space (e.g. "building_3ae47293-69d1-45ec-96a3-f59f95a70705_1423000957534").
  final String buid;

  /// Display name of the building (e.g. "University of Cyprus").
  final String name;

  /// Latitude coordinate in WGS84 format.
  final double latitude;

  /// Longitude coordinate in WGS84 format.
  final double longitude;

  /// Optional description of the building / occupants.
  final String? description;

  /// Optional building short code (e.g. "ucy", "FST02").
  final String? bucode;

  /// Optional physical address.
  final String? address;

  /// Optional web URL.
  final String? url;

  /// Whether this building is publicly published.
  final bool isPublished;

  /// Type of space (e.g. "building", "vessel").
  final String spaceType;

  const SpaceModel({
    required this.buid,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.description,
    this.bucode,
    this.address,
    this.url,
    this.isPublished = true,
    this.spaceType = 'building',
  });

  /// LatLng coordinate helper for Flutter Map.
  LatLng get latLng => LatLng(latitude, longitude);

  /// Factory constructor to parse a [SpaceModel] from Anyplace JSON.
  factory SpaceModel.fromJson(Map<String, dynamic> json) {
    final buid = (json['buid'] ?? '').toString().trim();
    final name = (json['name'] ?? 'Unnamed Building').toString().trim();

    final latRaw = json['coordinates_lat'];
    final lonRaw = json['coordinates_lon'];

    final double lat = _parseDouble(latRaw);
    final double lon = _parseDouble(lonRaw);

    final description = json['description']?.toString().trim();
    final bucode = json['bucode']?.toString().trim();
    final address = json['address']?.toString().trim();
    final url = json['url']?.toString().trim();

    final isPublishedRaw = json['is_published'];
    final bool isPublished = isPublishedRaw == null
        ? true
        : (isPublishedRaw is bool
            ? isPublishedRaw
            : isPublishedRaw.toString().toLowerCase() == 'true');

    final spaceType = (json['space_type'] ?? 'building').toString().trim();

    return SpaceModel(
      buid: buid,
      name: name,
      latitude: lat,
      longitude: lon,
      description: description != null && description.isNotEmpty ? description : null,
      bucode: bucode != null && bucode.isNotEmpty ? bucode : null,
      address: address != null && address.isNotEmpty ? address : null,
      url: url != null && url.isNotEmpty ? url : null,
      isPublished: isPublished,
      spaceType: spaceType.isNotEmpty ? spaceType : 'building',
    );
  }

  /// Converts this [SpaceModel] to JSON.
  Map<String, dynamic> toJson() {
    return {
      'buid': buid,
      'name': name,
      'coordinates_lat': latitude.toString(),
      'coordinates_lon': longitude.toString(),
      if (description != null) 'description': description,
      if (bucode != null) 'bucode': bucode,
      if (address != null) 'address': address,
      if (url != null) 'url': url,
      'is_published': isPublished.toString(),
      'space_type': spaceType,
    };
  }

  /// Helper to safely parse numbers or strings into double coordinates.
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0.0;
    }
    return 0.0;
  }

  SpaceModel copyWith({
    String? buid,
    String? name,
    double? latitude,
    double? longitude,
    String? description,
    String? bucode,
    String? address,
    String? url,
    bool? isPublished,
    String? spaceType,
  }) {
    return SpaceModel(
      buid: buid ?? this.buid,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      description: description ?? this.description,
      bucode: bucode ?? this.bucode,
      address: address ?? this.address,
      url: url ?? this.url,
      isPublished: isPublished ?? this.isPublished,
      spaceType: spaceType ?? this.spaceType,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpaceModel &&
          runtimeType == other.runtimeType &&
          buid == other.buid &&
          name == other.name &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          bucode == other.bucode;

  @override
  int get hashCode =>
      buid.hashCode ^
      name.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      bucode.hashCode;

  @override
  String toString() {
    return 'SpaceModel(buid: $buid, name: $name, lat: $latitude, lon: $longitude, bucode: $bucode)';
  }
}
