import '../utils/parsing.dart';

/// Building (Space) entity as returned by the Anyplace backend.
///
/// Field names mirror `datasources/SCHEMA.scala` and the cleaned responses of
/// `MapSpaceController.public` / `MapCampusController.get`.
class Space {
  const Space({
    required this.buid,
    required this.name,
    required this.coordinatesLat,
    required this.coordinatesLon,
    required this.spaceType,
    this.description,
    this.url,
    this.address,
    this.bucode,
    this.isPublished,
  });

  final String buid;
  final String name;
  final double coordinatesLat;
  final double coordinatesLon;
  final String spaceType;
  final String? description;
  final String? url;
  final String? address;
  final String? bucode;
  final String? isPublished;

  factory Space.fromJson(Map<String, dynamic> json) {
    return Space(
      buid: json['buid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coordinatesLat: parseDouble(json['coordinates_lat']),
      coordinatesLon: parseDouble(json['coordinates_lon']),
      spaceType: json['space_type'] as String? ?? 'building',
      description: json['description'] as String?,
      url: json['url'] as String?,
      address: json['address'] as String?,
      bucode: json['bucode'] as String?,
      isPublished: json['is_published'] as String?,
    );
  }

  bool get isBuilding => spaceType == 'building';

  Map<String, dynamic> toJson() => {
        'buid': buid,
        'name': name,
        'coordinates_lat': coordinatesLat.toString(),
        'coordinates_lon': coordinatesLon.toString(),
        'space_type': spaceType,
        if (description != null) 'description': description,
        if (url != null) 'url': url,
        if (address != null) 'address': address,
        if (bucode != null) 'bucode': bucode,
        if (isPublished != null) 'is_published': isPublished,
      };
}
