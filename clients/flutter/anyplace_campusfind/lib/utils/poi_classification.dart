import '../data/models/poi_model.dart';

/// Classifies POIs using the real Anyplace API classification rules.
///
/// Source of truth: `Poi.scala` (server constants), `PoiController.js`
/// (Architect dropdown), `SCHEMA.scala` (field definitions), and the
/// Flutter client's own filtering logic in `space_provider.dart` and
/// `navigation_controller.dart`.
///
/// The `pois_type` field is free-form — there is no backend validation.
/// The Architect UI recommends Title Case values (`"Elevator"`, `"Stair"`,
/// `"Entrance"`), but the server constants use lowercase (`"elevator"`,
/// `"stair"`). All matching uses **case-insensitive substring** checks.
class PoiClassification {
  PoiClassification._();

  // ──────────────────────────────────────────────────────────────
  // Connector (floor-transition POI)
  // ──────────────────────────────────────────────────────────────

  /// A connector is a special POI that represents a floor-transition point
  /// (stair/elevator landing). In the Anyplace data model, connectors are
  /// POIs with `pois_type` set to the sentinel value `"None"` (capital N).
  ///
  /// Source: `Poi.scala:46` (`POIS_TYPE_NONE = "None"`),
  ///         `PoiController.js:1291` (created with `pois_type: "None"`),
  ///         `MongodbDatasource.scala:633-637` (filtered out of building queries).
  static bool isConnector(PoiModel poi) => poi.poisType == 'None';

  // ──────────────────────────────────────────────────────────────
  // Entrance
  // ──────────────────────────────────────────────────────────────

  /// An entrance is detected by two independent signals (OR logic):
  /// 1. Boolean flag: `is_building_entrance == true`
  /// 2. Type string: `pois_type` contains `"entrance"` (case-insensitive)
  ///
  /// Source: `space_provider.dart:661-663`,
  ///         `navigation_controller.dart:556-557`,
  ///         `Poi.scala:55` (`fIsBuildingEntrance`).
  static bool isEntrance(PoiModel poi) =>
      poi.isBuildingEntrance ||
      poi.poisType.toLowerCase().contains('entrance');

  // ──────────────────────────────────────────────────────────────
  // Elevator
  // ──────────────────────────────────────────────────────────────

  /// Elevator detection via case-insensitive substring of `pois_type`.
  ///
  /// Source: `Poi.scala:47` (`POIS_TYPE_ELEVATOR = "elevator"`),
  ///         `category_deriver.dart:147`.
  static bool isElevator(PoiModel poi) =>
      poi.poisType.toLowerCase().contains('elevator');

  // ──────────────────────────────────────────────────────────────
  // Stairs / Staircase
  // ──────────────────────────────────────────────────────────────

  /// Stairs detection via case-insensitive substring of `pois_type`.
  /// Matches both `"stairs"` and `"staircase"`.
  ///
  /// Source: `Poi.scala:48` (`POIS_TYPE_STAIR = "stair"`),
  ///         `category_deriver.dart:150`.
  static bool isStairs(PoiModel poi) {
    final t = poi.poisType.toLowerCase();
    return t.contains('stairs') || t.contains('staircase');
  }

  // ──────────────────────────────────────────────────────────────
  // Door
  // ──────────────────────────────────────────────────────────────

  /// Door detection via boolean flag or case-insensitive substring.
  ///
  /// Source: `poi_marker.dart:38-41`, `SCHEMA.scala:56` (`fIsDoor`).
  static bool isDoor(PoiModel poi) =>
      poi.isDoor || poi.poisType.toLowerCase().contains('door');

  // ──────────────────────────────────────────────────────────────
  // Floor transition (composite)
  // ──────────────────────────────────────────────────────────────

  /// A floor-transition POI is any POI that connects different floors:
  /// connector (`"None"`), elevator, or stairs.
  ///
  /// Used by `CrossBuildingRouter` to identify candidate exit/entrance POIs
  /// for cross-building navigation.
  static bool isFloorTransition(PoiModel poi) =>
      isConnector(poi) || isElevator(poi) || isStairs(poi);

  // ──────────────────────────────────────────────────────────────
  // Convenience filters
  // ──────────────────────────────────────────────────────────────

  /// Returns entrance POIs from [pois] that are on the ground floor
  /// (floor number `"0"` or the first floor if no `"0"` exists).
  static List<PoiModel> getGroundFloorEntrances(
    List<PoiModel> pois,
    String buildingBuid,
  ) {
    return pois.where((p) {
      if (p.buid != buildingBuid) return false;
      if (!isEntrance(p)) return false;
      return p.floorNumber == '0' || p.floorNumber == 'G';
    }).toList();
  }

  /// Returns connector/floor-transition POIs from [pois] on the given floor.
  static List<PoiModel> getFloorConnectors(
    List<PoiModel> pois,
    String floorNumber,
  ) {
    return pois.where((p) {
      if (p.floorNumber != floorNumber) return false;
      return isFloorTransition(p);
    }).toList();
  }

  /// Returns all floor-transition POIs in the given building.
  static List<PoiModel> getBuildingFloorTransitions(
    List<PoiModel> pois,
    String buildingBuid,
  ) {
    return pois.where((p) {
      if (p.buid != buildingBuid) return false;
      return isFloorTransition(p);
    }).toList();
  }

  /// Returns all entrance POIs in the given building.
  static List<PoiModel> getBuildingEntrances(
    List<PoiModel> pois,
    String buildingBuid,
  ) {
    return pois.where((p) {
      if (p.buid != buildingBuid) return false;
      return isEntrance(p);
    }).toList();
  }
}
