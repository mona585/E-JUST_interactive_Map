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
  });

  final String fuid;
  final String buid;
  final String floorNumber;
  final String? floorName;
  final String? description;
  final String? isPublished;

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
    );
  }

  Map<String, dynamic> toJson() => {
        'fuid': fuid,
        'buid': buid,
        'floor_number': floorNumber,
        if (floorName != null) 'floor_name': floorName,
        if (description != null) 'description': description,
        if (isPublished != null) 'is_published': isPublished,
      };
}
