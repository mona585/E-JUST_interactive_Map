/// A verified E-JUST Quick Access default location.
///
/// [`buid`] is the actual Anyplace API entity identifier for a building,
/// resolved against the live backend dataset — never invented. [`name`] is the
/// entity name as published in that dataset (used for reporting only, not for
/// matching). [`label`] is the user-facing default name shown in the app.
class DefaultQuickAccessLocation {
  const DefaultQuickAccessLocation({
    required this.label,
    required this.name,
    required this.buid,
  });

  final String label;
  final String name;
  final String buid;
}

/// App-wide constants not related to the backend API.
class AppConstants {
  AppConstants._();

  static const String appName = 'CampusFind';

  /// SharedPreferences keys.
  static const String prefCampusId = 'selected_campus_id';
  static const String prefRecentWaypoints = 'recent_waypoints';
  static const String prefSavedPois = 'saved_pois';
  static const String prefQuickAccess = 'quick_access';
  static const String prefHasCompletedOnboarding = 'onboarding_done';

  /// Predefined Quick Access locations seeded on first launch.
  ///
  /// Each entry identifies a VERIFIED E-JUST entity resolved against the live
  /// Anyplace backend dataset (`space/public` on ap.cs.ucy.ac.cy:44). The
  /// `buid` values are the actual API entity identifiers observed in that
  /// dataset, NOT invented identifiers, and no coordinates are hardcoded.
  ///
  /// On first launch only, each default is resolved by its real `buid` against
  /// the spaces already loaded by the application. Only entities present in the
  /// loaded dataset are seeded (from their live `SpaceModel`, so identity is
  /// always the actual API entity). A default whose buid is not present in the
  /// loaded data is REPORTED and skipped — never substituted with a similarly
  /// named location. These defaults are never re-injected once the Quick Access
  /// preference key exists.
  static const List<DefaultQuickAccessLocation> kDefaultQuickAccessLocations = [
    DefaultQuickAccessLocation(
      label: 'Library',
      name: 'Library',
      buid: 'building_163182b1-2875-46a0-a398-a722b83f4ede_1787170088312',
    ),
    DefaultQuickAccessLocation(
      label: 'Blue Hall Cafeteria',
      name: 'Blue hall Cafeteria',
      buid: 'building_aa532328-faa2-406b-9b6e-2a4640e3cbe2_1787170286644',
    ),
    DefaultQuickAccessLocation(
      label: 'Stationery / Sales Library',
      name: 'Stationery shop',
      buid: 'building_5aee1ddd-3736-4100-977b-31fb3c3d2576_1787170410290',
    ),
    DefaultQuickAccessLocation(
      label: 'Bank',
      name: 'National Bank branch',
      buid: 'building_6dc90d58-81fb-4f3c-ad29-43d825fb5b77_1787170194408',
    ),
    DefaultQuickAccessLocation(
      label: 'Food Court',
      name: 'Food court',
      buid: 'building_638b4ab9-0f48-4c0f-8e9a-a9477b251259_1787170631136',
    ),
    DefaultQuickAccessLocation(
      label: 'Student Affairs',
      name: 'Student Affairs',
      buid: 'building_48c4eb03-8424-4b09-8563-13cfc1c720c9_1787170689278',
    ),
  ];

  /// Default floor number probed when a building has no floor list (the
  /// public backend returns no floors for most UCY buildings).
  static const String probeFloorNumber = '0';

  /// CampusFind ships with exactly ONE primary campus: the University of
  /// Cyprus (UCY) campus on the public Anyplace backend (`ap.cs.ucy.ac.cy`).
  ///
  /// CampusFind is single-campus by design — there is no campus picker and no
  /// runtime selection. The campus CUID (`ucy`) matches the official Anyplace
  /// campus entry (see https://anyplace.cs.ucy.ac.cy/viewer/?cuid=ucy).
  ///
  /// WARNING: the live backend has no public "list campuses" endpoint and
  /// rejects `campus/get` at the load balancer, so building data is loaded
  /// from the `space/public` endpoint (all published buildings), exactly like
  /// the pre-merge working CampusFind version.
  static const String primaryCampusCuid = 'ucy';

  /// Display name of the single primary campus.
  static const String primaryCampusName = 'University of Cyprus';

  /// CAMPUS_IDS is no longer required (or consumed) — CampusFind is single-
  /// campus. Kept as an empty default so any stray `--dart-define=CAMPUS_IDS`
  /// never accidentally enables multi-campus behavior.
  static const String _campusIdsEnv =
      String.fromEnvironment('CAMPUS_IDS');

  static final List<String> configuredCampusIds = _parseCampusIds(_campusIdsEnv);

  /// Name used for the primary campus dataset. Always the UCY campus.
  static const String defaultCampusName = primaryCampusName;

  /// cuid used to persist the single primary campus selection locally.
  static const String defaultCampusCuid = primaryCampusCuid;

  static List<String> _parseCampusIds(String raw) {
    if (raw.isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
