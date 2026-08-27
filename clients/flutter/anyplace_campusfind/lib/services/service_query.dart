import '../config/constants.dart';
import '../data/models/poi_model.dart';
import '../utils/category_deriver.dart';
import '../utils/poi_classification.dart';

/// Scope of a service query (UI/UX REDESIGN PHASE 5).
enum ServiceScope { campus, building, floor }

/// Pure, side-effect-free service scoping over ALREADY-LOADED data.
///
/// A "service" is an [EntityCategory] of POI (Toilets, Cafeteria, Library…).
/// No repository/API access happens here: callers pass whatever is currently
/// indexed (the startup bulk-load progressively fills it), so results grow as
/// sync progresses — exactly like directory search today.
///
/// Exclusions mirror every navigable list in the app: connectors
/// (`pois_type == "None"`) and doors are never services.
List<PoiModel> queryScopedServices({
  required EntityCategory category,
  required Iterable<PoiModel> campusIndexPois,
  String? buildingBuid,
  String? floorNumber,
}) {
  var matches = campusIndexPois.where((poi) =>
      !PoiClassification.isConnector(poi) &&
      !PoiClassification.isDoor(poi) &&
      CategoryDeriver.fromPoiType(poi.poisType) == category);

  if (buildingBuid != null) {
    matches = matches.where((p) => p.buid == buildingBuid);
  }
  if (floorNumber != null) {
    matches = matches.where((p) => p.floorNumber == floorNumber);
  }
  return matches.toList(growable: false);
}

/// Human-readable label for the current scope. The global parent is always
/// the active campus (E-JUST); building/floor narrow it further.
String serviceScopeLabel({
  required String? buildingName,
  required String? floorDisplayName,
}) {
  if (buildingName == null) {
    return AppConstants.primaryCampusName;
  }
  final floorSuffix =
      floorDisplayName != null ? ' · Floor $floorDisplayName' : '';
  return '${AppConstants.primaryCampusName} › $buildingName$floorSuffix';
}
