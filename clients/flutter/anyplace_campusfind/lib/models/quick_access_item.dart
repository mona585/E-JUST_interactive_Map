import 'poi_model.dart';
import 'space_model.dart';

/// A user-saved location shown in Quick Access on the Home screen.
///
/// Supports both building-level and POI-level entries. Each item stores a
/// display snapshot (name/category/subtitle) so the list can render even when
/// the underlying building/floor/POI is not currently loaded, plus the stable
/// navigation identifiers (buid/puid, and floorNumber for POIs) so tapping the
/// item can navigate to its real location regardless of the current selection.
class QuickAccessItem {
  /// Entity kind: 'building' | 'poi'.
  final String type;

  /// Stable identifier: the building `buid` (type 'building') or the POI
  /// `puid` (type 'poi').
  final String id;

  /// Display snapshot of the name (renders even when the entity is unloaded).
  final String name;

  /// [EntityCategory.name]-compatible key used to derive the icon/color via
  /// the existing CategoryDeriver. Derived from building/space or POI metadata.
  final String category;

  /// Secondary display line (building code/spaceType or POI type).
  final String subtitle;

  /// Epoch milliseconds when the item was added (order key for user items).
  final int addedAt;

  /// Parent building id for POI items; used for cross-building navigation.
  final String? buid;

  /// Floor number for POI items; used for cross-building navigation.
  final String? floorNumber;

  const QuickAccessItem({
    required this.type,
    required this.id,
    required this.name,
    required this.category,
    required this.subtitle,
    required this.addedAt,
    this.buid,
    this.floorNumber,
  });

  /// Unique key for deduplication across buildings and POIs.
  String get dedupeKey => '$type:$id';

  bool get isBuilding => type == 'building';
  bool get isPoi => type == 'poi';

  /// Whether the item carries enough navigation metadata to open the POI
  /// directly (migrated items may lack buid/floorNumber until resolved).
  bool get hasPoiNavigationIds => isPoi && buid != null && floorNumber != null;

  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'name': name,
        'category': category,
        'subtitle': subtitle,
        'addedAt': addedAt,
        if (buid != null) 'buid': buid,
        if (floorNumber != null) 'floorNumber': floorNumber,
      };

  factory QuickAccessItem.fromJson(Map<String, dynamic> json) {
    return QuickAccessItem(
      type: (json['type'] ?? 'building').toString(),
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      category: (json['category'] ?? 'building').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      buid: json['buid']?.toString(),
      floorNumber: json['floorNumber']?.toString(),
    );
  }

  /// Builds a building-level item from [SpaceModel] metadata.
  factory QuickAccessItem.fromSpace(
    SpaceModel space, {
    required int addedAt,
    required String category,
  }) {
    return QuickAccessItem(
      type: 'building',
      id: space.buid,
      name: space.name,
      category: category,
      subtitle: space.bucode != null && space.bucode!.isNotEmpty
          ? space.bucode!
          : space.spaceType,
      addedAt: addedAt,
    );
  }

  /// Builds a POI-level item from [PoiModel] metadata.
  factory QuickAccessItem.fromPoi(
    PoiModel poi, {
    required int addedAt,
    required String category,
  }) {
    return QuickAccessItem(
      type: 'poi',
      id: poi.puid,
      name: poi.name,
      category: category,
      subtitle: poi.poisType,
      addedAt: addedAt,
      buid: poi.buid,
      floorNumber: poi.floorNumber,
    );
  }

  /// Minimal POI item used when migrating a saved puid that cannot yet be
  /// resolved to full metadata. Preserved so it remains usable for later
  /// API-driven resolution.
  factory QuickAccessItem.minimalPoi(
    String puid, {
    required int addedAt,
  }) {
    return QuickAccessItem(
      type: 'poi',
      id: puid,
      name: puid,
      category: 'other',
      subtitle: 'Saved place',
      addedAt: addedAt,
    );
  }

  QuickAccessItem copyWith({
    String? type,
    String? id,
    String? name,
    String? category,
    String? subtitle,
    int? addedAt,
    String? buid,
    String? floorNumber,
  }) {
    return QuickAccessItem(
      type: type ?? this.type,
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      subtitle: subtitle ?? this.subtitle,
      addedAt: addedAt ?? this.addedAt,
      buid: buid ?? this.buid,
      floorNumber: floorNumber ?? this.floorNumber,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuickAccessItem &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          id == other.id;

  @override
  int get hashCode => Object.hash(type, id);

  @override
  String toString() =>
      'QuickAccessItem(type: $type, id: $id, name: $name, category: $category)';
}