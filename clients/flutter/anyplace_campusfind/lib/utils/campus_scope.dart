import '../config/constants.dart';
import '../data/models/space_model.dart';

/// E-JUST GLOBAL SCOPE (post-Phase-9 adjustment).
///
/// CampusFind is single-campus: E-JUST is the implicit parent of every
/// browsing/search surface (buildings list, map markers, search index,
/// service scoping). This helper is the ONE place that decides whether an
/// entity belongs to that scope so the rule stays consistent everywhere.
///
/// Rule (data-driven, nothing invented client-side):
///  * If an entity carries a campus id (`cuid`) and it differs from
///    [AppConstants.primaryCampusCuid] → OUT of scope.
///  * Entities without a campus id are treated as in-scope, because on a
///    dedicated single-campus deployment every payload belongs to that
///    campus by definition. This keeps the app fully functional against an
///    E-JUST-only backend while still excluding foreign campuses when the
///    backend identifies them.
class CampusScope {
  CampusScope._();

  /// cuid of the global active campus (E-JUST).
  static String get cuid => AppConstants.primaryCampusCuid;

  /// Human-readable name of the global active campus (E-JUST).
  static String get displayName => AppConstants.primaryCampusName;

  /// Whether a campus id belongs to the active campus.
  static bool campusIdInScope(String? cuid) =>
      cuid == null || cuid.isEmpty || cuid == AppConstants.primaryCampusCuid;

  /// Whether a building belongs to the active campus.
  static bool spaceInScope(SpaceModel space) =>
      campusIdInScope(space.cuid);

  // POIs and floors are never filtered here: they are only ever loaded per
  // `buid`, i.e. for buildings that are already in scope, so ownership is
  // inherited structurally (see SpaceProvider.loadSpaces).

  /// Filters a fetched building list down to the active campus.
  static List<SpaceModel> filterSpaces(List<SpaceModel> spaces) =>
      spaces.where(spaceInScope).toList(growable: false);
}
