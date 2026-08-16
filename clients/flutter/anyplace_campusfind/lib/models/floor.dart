/// Floor entity as returned by `MapFloorController.all`.
///
/// `fuid` is `buid + "_" + floor_number` when not provided by the backend.
class Floor {
  const Floor({
    required this.fuid,
    required this.buid,
    required this.floorNumber,
    this.floorName,
    this.description,
    this.isPublished,
    this.bottomLeftLat,
    this.bottomLeftLng,
    this.topRightLat,
    this.topRightLng,
  });

  final String fuid;
  final String buid;
  final String floorNumber;
  final String? floorName;
  final String? description;
  final String? isPublished;

  /// Geographic bounds of the floorplan, when provided by the backend.
  /// Used by the map layer to position the floorplans64 overlay.
  final double? bottomLeftLat;
  final double? bottomLeftLng;
  final double? topRightLat;
  final double? topRightLng;

  factory Floor.fromJson(Map<String, dynamic> json) {
    final buid = json['buid'] as String? ?? '';
    final floorNumber = json['floor_number'] as String? ?? '';
    return Floor(
      fuid: json['fuid'] as String? ?? '${buid}_$floorNumber',
      buid: buid,
      floorNumber: floorNumber,
      floorName: json['floor_name'] as String?,
      description: json['description'] as String?,
      isPublished: json['is_published'] as String?,
      bottomLeftLat: _parseDouble(json['bottom_left_lat']),
      bottomLeftLng: _parseDouble(json['bottom_left_lng']),
      topRightLat: _parseDouble(json['top_right_lat']),
      topRightLng: _parseDouble(json['top_right_lng']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'fuid': fuid,
        'buid': buid,
        'floor_number': floorNumber,
        if (floorName != null) 'floor_name': floorName,
        if (description != null) 'description': description,
        if (isPublished != null) 'is_published': isPublished,
        if (bottomLeftLat != null) 'bottom_left_lat': bottomLeftLat.toString(),
        if (bottomLeftLng != null) 'bottom_left_lng': bottomLeftLng.toString(),
        if (topRightLat != null) 'top_right_lat': topRightLat.toString(),
        if (topRightLng != null) 'top_right_lng': topRightLng.toString(),
      };
}
