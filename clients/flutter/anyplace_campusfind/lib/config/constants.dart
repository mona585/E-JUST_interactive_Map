/// App-wide constants not related to the backend API.
class AppConstants {
  AppConstants._();

  static const String appName = 'CampusFind';

  /// SharedPreferences keys.
  static const String prefCampusId = 'selected_campus_id';
  static const String prefRecentWaypoints = 'recent_waypoints';
  static const String prefHasCompletedOnboarding = 'onboarding_done';

  /// Google Maps API Key. Set via `--dart-define=MAPS_API_KEY=YOUR_KEY` or read from
  /// `.env.example` (`MAPS_API_KEY=YOUR_GOOGLE_MAPS_API_KEY`).
  static const String mapsApiKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'YOUR_GOOGLE_MAPS_API_KEY',
  );

  /// Outdoor tile source. Defaults to Google Maps; fallback to Carto Positron if key is
  /// not configured. See project plan.
  static String get outdoorTilesUrl {
    if (mapsApiKey != null && mapsApiKey.isNotEmpty &&
        mapsApiKey != 'YOUR_GOOGLE_MAPS_API_KEY') {
      return 'https://maps.googleapis.com/maps/api/staticmap?';
    }
    return 'https://a.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
  }

  /// Zoom level at which indoor POIs/floorplan are shown.
  static const double indoorZoomThreshold = 19;

  /// Zoom level when focusing on a specific building or GPS location.
  static const double focusedZoom = 17;

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

  /// Maximum markers shown before clustering kicks in.
  static const int clusterThreshold = 12;
}
