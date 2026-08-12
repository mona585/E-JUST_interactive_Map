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
}
