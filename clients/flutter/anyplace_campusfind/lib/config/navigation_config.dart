/// Configurable constants for indoor navigation enhancement.
///
/// All thresholds are initial values to be tuned with real positioning data.
class NavigationConfig {
  NavigationConfig._();

  // -- Building entry (outdoor → indoor) --

  /// GPS distance (m) to building center to start pre-loading building data.
  static const double buildingPrepThreshold = 100.0;

  /// GPS distance (m) to building center to cancel pre-loading if user moves away.
  static const double buildingPrepCancelThreshold = 150.0;

  /// GPS distance (m) to entrance POI to trigger indoor transition.
  static const double entranceTransitionThreshold = 25.0;

  /// Fallback: GPS distance (m) to building center if no entrance POIs exist.
  static const double entranceFallbackThreshold = 30.0;

  // -- Building exit (indoor → outdoor) --

  /// GPS accuracy (m) threshold for outdoor-quality signal.
  static const double exitAccuracyThreshold = 15.0;

  /// Distance (m) from building center fallback for exit detection.
  static const double exitDistanceThreshold = 80.0;

  /// Number of consecutive GPS updates confirming exit.
  static const int exitConfirmationCount = 3;

  // -- Rerouting --

  /// Route deviation (m) before auto-reroute triggers.
  static const double deviationThreshold = 15.0;

  /// Minimum time (s) between reroute attempts.
  static const int rerouteCooldownSeconds = 15;

  /// Maximum retry attempts for failed reroute requests.
  static const int rerouteMaxRetries = 3;

  // -- Custom route matching --

  /// Maximum distance (m) from a custom route to consider the user "on-route".
  /// Used by NavigationController for custom-route-aware off-route detection.
  static const double customRouteOnThreshold = 30.0;

  /// Maximum snap distance (m) when matching GPS to custom route graph.
  static const double customRouteSnapThreshold = 50.0;

  /// Maximum distance (m) to bridge OSRM endpoint to custom route start/end.
  /// When the OSRM route endpoint or destination is within this distance
  /// of a custom route edge, they are considered connectable.
  static const double customRouteConnectionThreshold = 100.0;

  // -- Positioning stability --

  /// Duration (s) of the rolling window for stability detection.
  static const int stabilityWindowSeconds = 5;

  /// Minimum consecutive valid estimates to declare stable.
  static const int stabilityMinEstimates = 3;

  /// Maximum position delta (m) between consecutive estimates for stability.
  static const double stabilityMaxDelta = 15.0;

  /// Minimum matched WiFi APs for a valid indoor estimate.
  static const int stabilityMinMatchedAps = 2;

  // -- Camera --

  /// Camera zoom during indoor navigation follow mode.
  static const double indoorFollowZoom = 19.0;

  /// Camera zoom during outdoor navigation follow mode.
  static const double outdoorFollowZoom = 17.0;

  /// Camera padding (pixels) when framing the full route.
  static const double routeFramePadding = 60.0;

  /// Lower-third offset: user position at 2/3 from top (1/3 from bottom).
  static const double followLowerThirdFraction = 0.67;

  // -- Camera bearing --

  /// Minimum speed (m/s) to compute movement bearing (filters stationary GPS noise).
  static const double bearingSpeedThreshold = 0.5;

  /// Exponential moving average factor for bearing smoothing (0..1). Lower = smoother.
  static const double bearingSmoothingFactor = 0.25;

  /// Minimum time (ms) between bearing-driven camera updates (prevents jitter at high GPS rates).
  static const int bearingUpdateIntervalMs = 300;

  /// When standing still, hold the last bearing for this duration (ms) before resetting to 0.
  static const int bearingHoldDurationMs = 3000;

  // -- Floor transition --

  /// Distance (m) from connector POI to trigger floor pre-loading.
  static const double connectorProximityThreshold = 30.0;

  /// Message shown during positioning blackout between floors.
  static const String transitionBlackoutMessage = 'Moving to Floor';

  /// Suppression period (s) after a floor switch before reroute checks resume.
  static const int postFloorSwitchSuppressSeconds = 10;

  /// Maximum time (s) to wait for a floor transition to complete before aborting.
  static const int transitionTimeoutSeconds = 30;

  // -- Indoor stale timer --

  /// Seconds without a valid indoor estimate before it is cleared.
  static const int indoorStaleTimerSeconds = 10;
}
