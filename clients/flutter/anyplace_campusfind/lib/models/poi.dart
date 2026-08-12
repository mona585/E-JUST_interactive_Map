import '../utils/parsing.dart';

/// POI (point of interest) as returned by `MapPoiController`.
class Poi {
  const Poi({
    required this.puid,
    required this.buid,
    required this.name,
    required this.coordinatesLat,
    required this.coordinatesLon,
    required this.floorNumber,
    this.description,
    this.floorName,
    this.url,
    this.image,
    this.poisType,
    this.isDoor,
    this.isBuildingEntrance,
    this.isPublished,
  });

  final String puid;
  final String buid;
  final String name;
  final double coordinatesLat;
  final double coordinatesLon;
  final String floorNumber;
  final String? description;
  final String? floorName;
  final String? url;
  final String? image;
  final String? poisType;
  final String? isDoor;
  final String? isBuildingEntrance;
  final String? isPublished;

  factory Poi.fromJson(Map<String, dynamic> json) {
    return Poi(
      puid: json['puid'] as String? ?? '',
      buid: json['buid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      coordinatesLat: parseDouble(json['coordinates_lat']),
      coordinatesLon: parseDouble(json['coordinates_lon']),
      floorNumber: json['floor_number'] as String? ?? '',
      description: json['description'] as String?,
      floorName: json['floor_name'] as String?,
      url: json['url'] as String?,
      image: json['image'] as String?,
      poisType: json['pois_type'] as String?,
      isDoor: json['is_door'] as String?,
      isBuildingEntrance: json['is_building_entrance'] as String?,
      isPublished: json['is_published'] as String?,
    );
  }

  bool get isEntrance => isBuildingEntrance == 'true';

  Map<String, dynamic> toJson() => {
        'puid': puid,
        'buid': buid,
        'name': name,
        'coordinates_lat': coordinatesLat.toString(),
        'coordinates_lon': coordinatesLon.toString(),
        'floor_number': floorNumber,
        if (description != null) 'description': description,
        if (floorName != null) 'floor_name': floorName,
        if (url != null) 'url': url,
        if (image != null) 'image': image,
        if (poisType != null) 'pois_type': poisType,
        if (isDoor != null) 'is_door': isDoor,
        if (isBuildingEntrance != null) 'is_building_entrance': isBuildingEntrance,
        if (isPublished != null) 'is_published': isPublished,
      };
}
