import '../models/poi.dart';
import '../models/space.dart';

/// POI/entity categories derived client-side from names and descriptions.
///
/// The set of categories is discovered dynamically from backend data, not
/// hardcoded — new categories appear automatically as data changes.
enum EntityCategory {
  professor,
  cafeteria,
  library,
  lab,
  building,
  other;

  String get label {
    switch (this) {
      case EntityCategory.professor:
        return 'Professors';
      case EntityCategory.cafeteria:
        return 'Cafeterias';
      case EntityCategory.library:
        return 'Library';
      case EntityCategory.lab:
        return 'Labs';
      case EntityCategory.building:
        return 'Buildings';
      case EntityCategory.other:
        return 'Other';
    }
  }
}

/// Derives a category for a POI based on the signals defined in the project
/// plan (professor titles, cafeteria/dining, library, lab/laboratory).
class CategoryDeriver {
  static EntityCategory derivePoi(Poi poi) {
    final text =
        '${poi.name} ${poi.description ?? ''}'.toLowerCase();

    if (poi.name.contains('Prof.') ||
        poi.name.contains('Dr.') ||
        text.contains('professor')) {
      return EntityCategory.professor;
    }
    if (text.contains('cafeteria') || text.contains('dining')) {
      return EntityCategory.cafeteria;
    }
    if (text.contains('library')) {
      return EntityCategory.library;
    }
    if (text.contains('lab') || text.contains('laboratory')) {
      return EntityCategory.lab;
    }
    return EntityCategory.other;
  }

  static EntityCategory deriveSpace(Space space) {
    if (space.spaceType == 'building') return EntityCategory.building;
    return EntityCategory.other;
  }

  /// The distinct categories present in the given POIs, in canonical order.
  static List<EntityCategory> discoverCategories(List<Poi> pois) {
    final seen = <EntityCategory>{};
    for (final poi in pois) {
      seen.add(derivePoi(poi));
    }
    return EntityCategory.values
        .where((c) => seen.contains(c))
        .toList();
  }
}
