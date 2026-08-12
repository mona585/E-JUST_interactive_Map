/// App-wide constants not related to the backend API.
class AppConstants {
  AppConstants._();

  static const String appName = 'CampusFind';

  /// SharedPreferences keys.
  static const String prefCampusId = 'selected_campus_id';
  static const String prefRecentWaypoints = 'recent_waypoints';
  static const String prefHasCompletedOnboarding = 'onboarding_done';

  /// Outdoor tile source. Defaults to a Carto Positron fallback until the
  /// self-hosted tile server (Phase 0.6) is ready. See project plan.
  static const String outdoorTilesUrl =
      'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';

  /// Zoom level at which indoor POIs/floorplan are shown.
  static const double indoorZoomThreshold = 19;

  /// Campus cuids offered on first launch.
  ///
  /// The backend has no public "list campuses" endpoint, so campuses are
  /// enumerated here. Override at build time:
  ///   flutter run --dart-define=CAMPUS_IDS=cuid_a,cuid_b
  /// When empty, [CampusLoader] falls back to deriving a single default
  /// campus from all published buildings (`space/public`) so a stock build
  /// is usable out of the box (see [defaultCampusName]).
  static const String _campusIdsEnv =
      String.fromEnvironment('CAMPUS_IDS');

  static final List<String> configuredCampusIds = _parseCampusIds(_campusIdsEnv);

  /// Name of the auto-derived default campus shown when no [CAMPUS_IDS]
  /// were provided at build time. Override with `--dart-define=CAMPUS_NAME=...`.
  static const String defaultCampusName = String.fromEnvironment(
    'CAMPUS_NAME',
    defaultValue: 'E-JUST Campus',
  );

  /// Synthetic cuid used to persist the auto-derived default campus locally.
  /// It is only used to remember the first-launch selection, never sent to the
  /// backend as a real campus id.
  static const String defaultCampusCuid = 'ejust_campus';

  static List<String> _parseCampusIds(String raw) {
    if (raw.isEmpty) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Maximum markers shown before clustering kicks in.
  static const int clusterThreshold = 12;
}
