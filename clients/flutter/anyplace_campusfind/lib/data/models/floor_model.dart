/// Data model representing a floor in an Anyplace building/space.
class FloorModel implements Comparable<FloorModel> {
  /// The parent building's unique identifier (e.g. `building_...`).
  final String buid;

  /// The floor number as assigned by Anyplace (e.g. `"0"`, `"1"`, `"-1"`).
  final String floorNumber;

  /// Human-readable floor name (e.g. `"Ground Floor"`, `"Basement"`, `"Level 2"`).
  final String floorName;

  /// Floor description, if available.
  final String description;

  /// The floor's unique identifier (`<buid>_<floor_number>`).
  final String fuid;

  /// Whether the floor has been published in the Anyplace backend.
  final bool isPublished;

  /// Latitude of bottom-left corner of the floorplan, if available.
  final double? bottomLeftLat;

  /// Longitude of bottom-left corner of the floorplan, if available.
  final double? bottomLeftLng;

  /// Latitude of top-right corner of the floorplan, if available.
  final double? topRightLat;

  /// Longitude of top-right corner of the floorplan, if available.
  final double? topRightLng;

  const FloorModel({
    required this.buid,
    required this.floorNumber,
    this.floorName = '',
    this.description = '',
    this.fuid = '',
    this.isPublished = true,
    this.bottomLeftLat,
    this.bottomLeftLng,
    this.topRightLat,
    this.topRightLng,
  });

  /// Integer value of [floorNumber] for natural numeric sorting.
  int get numericFloor => int.tryParse(floorNumber) ?? 0;

  /// Formatted user-friendly display name.
  String get displayName {
    if (floorName.isNotEmpty &&
        floorName != floorNumber &&
        floorName != '-' &&
        floorName.toLowerCase() != 'null') {
      return '$floorName (Floor $floorNumber)';
    }
    return 'Floor $floorNumber';
  }

  /// Compact floor badge label (e.g. `"F0"`, `"F1"`, `"B1"`).
  String get badgeLabel {
    final num = numericFloor;
    if (num < 0) {
      return 'B${num.abs()}';
    }
    return 'F$num';
  }

  /// Parses a [FloorModel] from Anyplace backend JSON.
  factory FloorModel.fromJson(Map<String, dynamic> json) {
    final rawFloorNum = json['floor_number'] ?? json['floor'] ?? '0';
    final floorNumStr = rawFloorNum.toString().trim();

    final rawFloorName = json['floor_name']?.toString().trim() ?? '';
    final rawDesc = json['description']?.toString().trim() ?? '';
    final rawFuid = json['fuid']?.toString().trim() ?? '';
    final rawBuid = json['buid']?.toString().trim() ?? '';
    final rawPublished = json['is_published'];

    bool published = true;
    if (rawPublished is bool) {
      published = rawPublished;
    } else if (rawPublished is String) {
      published = rawPublished.toLowerCase() == 'true';
    }

    return FloorModel(
      buid: rawBuid,
      floorNumber: floorNumStr,
      floorName: rawFloorName,
      description: rawDesc,
      fuid: rawFuid.isNotEmpty ? rawFuid : '${rawBuid}_$floorNumStr',
      isPublished: published,
      bottomLeftLat: _parseDouble(json['bottom_left_lat']),
      bottomLeftLng: _parseDouble(json['bottom_left_lng']),
      topRightLat: _parseDouble(json['top_right_lat']),
      topRightLng: _parseDouble(json['top_right_lng']),
    );
  }

  /// Serializes to JSON.
  Map<String, dynamic> toJson() {
    return {
      'buid': buid,
      'floor_number': floorNumber,
      'floor_name': floorName,
      'description': description,
      'fuid': fuid,
      'is_published': isPublished.toString(),
      if (bottomLeftLat != null) 'bottom_left_lat': bottomLeftLat.toString(),
      if (bottomLeftLng != null) 'bottom_left_lng': bottomLeftLng.toString(),
      if (topRightLat != null) 'top_right_lat': topRightLat.toString(),
      if (topRightLng != null) 'top_right_lng': topRightLng.toString(),
    };
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  @override
  int compareTo(FloorModel other) {
    final numCompare = numericFloor.compareTo(other.numericFloor);
    if (numCompare != 0) return numCompare;
    return floorNumber.compareTo(other.floorNumber);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FloorModel &&
          runtimeType == other.runtimeType &&
          buid == other.buid &&
          floorNumber == other.floorNumber;

  @override
  int get hashCode => buid.hashCode ^ floorNumber.hashCode;

  @override
  String toString() =>
      'FloorModel(buid: $buid, floor: $floorNumber, name: $floorName)';
}
