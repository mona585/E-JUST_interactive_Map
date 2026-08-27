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

  /// SharedPreferences key storing the dataset epoch this device's local
  /// data (Quick Access, Recent Waypoints, disk caches) belongs to.
  static const String prefDatasetEpoch = 'dataset_epoch';

  /// SERVER MIGRATION epoch marker. When the stored epoch differs from this
  /// value, startup performs a ONE-TIME silent migration: Quick Access and
  /// Recent Waypoints are cleared (their buids/puids belonged to the old
  /// backend) and the disk caches are purged via
  /// `SpaceProvider.purgeDatasetCaches()`. Quick Access then re-seeds from
  /// [kDefaultQuickAccessLocations] against the new server's real dataset.
  ///
  /// Bump this constant whenever the backend identity changes again.
  static const String datasetEpoch = 'beout-2026-08';

  /// Predefined Quick Access locations seeded on first launch.
  ///
  /// Each entry identifies a VERIFIED E-JUST entity resolved against the
  /// live E-JUST backend (`map.beout.ai`, post-migration). The `buid`
  /// values are the actual API entity identifiers returned by that
  /// server's `/api/mapping/space/public` payload — NOT invented — and no
  /// coordinates are hardcoded.
  ///
  /// On first launch only, each default is resolved by its real `buid`
  /// against the spaces already loaded by the application. Only entities
  /// present in the loaded dataset are seeded. A default whose buid is not
  /// present is REPORTED and skipped — never substituted.
  ///
  /// SERVER MIGRATION NOTE: the previous UCY-backend buids no longer exist
  /// on map.beout.ai; this list was re-pointed to the new server's real
  /// entities during the backend migration (Stationery shop dropped — the
  /// entity does not exist on the new server; B7 and the Administrative
  /// Building added).
  static const List<DefaultQuickAccessLocation> kDefaultQuickAccessLocations = [
    DefaultQuickAccessLocation(
      label: 'Library',
      name: 'E-JUST Library',
      buid: 'building_39d12406-5167-4ab6-b01e-1ec5f60e9c48_1787691620141',
    ),
    DefaultQuickAccessLocation(
      label: 'Blue Hall Cafeteria',
      name: 'E-JUST Blue Hall',
      buid: 'building_90580bbe-a411-47a1-8486-57578e35ffb7_1787691406039',
    ),
    DefaultQuickAccessLocation(
      label: 'Food Court',
      name: 'Food court',
      buid: 'building_0cee133d-7afc-4c23-8c01-efc53afb33ed_1787691448415',
    ),
    DefaultQuickAccessLocation(
      label: 'Bank',
      name: 'National Bank branch',
      buid: 'building_d475fb95-a1cb-4d4e-b473-dbc1fedf31a5_1787691464505',
    ),
    DefaultQuickAccessLocation(
      label: 'B7',
      name: 'B7',
      buid: 'building_98c4def5-553d-452a-baf2-da184f7b19ee_1787690379788',
    ),
    DefaultQuickAccessLocation(
      label: 'Administrative Building',
      name: 'E-JUST Administrative Building',
      buid: 'building_818fac74-6005-4877-bb70-89e307716914_1787691595861',
    ),
  ];

  /// Default floor number probed when a building has no floor list.
  static const String probeFloorNumber = '0';

  /// CampusFind ships with exactly ONE primary campus: **E-JUST**.
  ///
  /// CampusFind is single-campus by design — there is no campus picker and no
  /// runtime selection. E-JUST is the implicit GLOBAL browsing scope: every
  /// building / floor / POI / service / search result shown by the app is
  /// scoped to this campus (see `utils/campus_scope.dart`).
  ///
  /// Both values are overridable at build time without code changes:
  ///   --dart-define=CAMPUS_CUID=... --dart-define=CAMPUS_NAME=...
  ///
  /// NOTE on the upstream dataset: the public Anyplace backend historically
  /// served the UCY campus (`ap.cs.ucy.ac.cy`, cuid `ucy`). The E-JUST fork
  /// targets the E-JUST deployment whose spaces belong to the E-JUST campus;
  /// when space payloads carry a campus id (`cuid`), entities outside
  /// [primaryCampusCuid] are filtered out at load time. Entities that do not
  /// carry any campus id (single-campus deployments) are treated as in-scope,
  /// which keeps the app working against an E-JUST-only backend unchanged.
  static const String primaryCampusCuid = String.fromEnvironment(
    'CAMPUS_CUID',
    defaultValue: 'ejust',
  );

  /// Display name of the single primary campus.
  static const String primaryCampusName = String.fromEnvironment(
    'CAMPUS_NAME',
    defaultValue: 'E-JUST',
  );

  /// CAMPUS_IDS is no longer required (or consumed) — CampusFind is single-
  /// campus. Kept as an empty default so any stray `--dart-define=CAMPUS_IDS`
  /// never accidentally enables multi-campus behavior.
  static const String _campusIdsEnv =
      String.fromEnvironment('CAMPUS_IDS');

  static final List<String> configuredCampusIds = _parseCampusIds(_campusIdsEnv);

  /// Name used for the primary campus dataset. Always the primary campus.
  static const String defaultCampusName = primaryCampusName;

  /// cuid used to persist the single primary campus selection locally.
  static const String defaultCampusCuid = primaryCampusCuid;

  static List<String> _parseCampusIds(String raw) {
    if (raw.isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
