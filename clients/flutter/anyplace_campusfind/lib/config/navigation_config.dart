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

  // -- Unified positioning arbitration --

  /// Maximum number of building/floor RadioMaps simultaneously resident in the
  /// native positioning engine (LRU-evicted on overflow).
  ///
  /// DOCUMENTATION ONLY — the enforced constant lives in the native engine
  /// ([RESIDENT_MAP_LIMIT] in
  /// `android/app/src/main/kotlin/eg/edu/ejust/anyplace_campusfind/positioning/PositioningEngine.kt`),
  /// which is the single source of truth. Dart code must not branch on this
  /// value; changing it requires changing the native constant.
  static const int residentMapLimit = 4;

  /// Consecutive valid indoor estimates required before the arbiter enters
  /// indoor positioning mode (Wi-Fi becomes the believed source).
  static const int indoorEnterConfirmCount = 3;

  /// Consecutive low-quality indoor estimate cycles required before the
  /// arbiter exits indoor positioning mode (guards against transient WiFi
  /// dropouts). Hard staleness is additionally governed by
  /// [indoorStaleTimerSeconds].
  static const int indoorExitStaleCycles = 3;

  /// Minimum fraction of observed APs that must match a resident RadioMap for
  /// its estimate to count as valid positioning evidence.
  static const double minMatchedRatio = 0.25;

  /// Distance (m) between a new winning indoor estimate and the last accepted
  /// indoor fix above which the new estimate is treated as an outlier and the
  /// previous fix is held.
  static const double outlierJumpThresholdMeters = 30.0;

  /// Consecutive consistent winning (buildingId, floor) pairs required before
  /// the arbiter confirms that identity canonically. Until confirmed, the fix
  /// carries no building/floor identity: selection context must never fill it.
  static const int scopeConfirmCount = 3;

  /// Lower clamp bound (m) for Wi-Fi accuracy derived from KNN evidence
  /// (max(topKSpreadMeters, bestDistance)).
  static const double wifiAccuracyMinMeters = 2.0;

  /// Upper clamp bound (m) for Wi-Fi accuracy derived from KNN evidence.
  static const double wifiAccuracyMaxMeters = 30.0;

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

  /// Minimum speed (m/s) to accept a movement-derived bearing (filters GPS noise).
  static const double bearingSpeedThreshold = 0.2;

  /// Minimum movement (m) since the last bearing sample to accept a
  /// movement-derived bearing. Deliberately small so indoor turns are detected.
  static const double bearingMinMovementMeters = 0.15;

  /// Exponential moving average factor for heading smoothing (0..1).
  /// Higher = faster convergence to new headings.
  static const double bearingSmoothingFactor = 0.6;

  /// Minimum time (ms) between heading-driven camera updates (prevents jitter at high event rates).
  static const int bearingUpdateIntervalMs = 200;

  /// When standing still, hold the last heading for this duration (ms) before resetting to 0.
  static const int bearingHoldDurationMs = 1000;

  /// Age (ms) after which a device compass reading is considered stale and the
  /// movement-derived bearing fallback takes over.
  static const int compassStaleMs = 2000;

  // -- Camera follow gating --

  /// Minimum user movement (m) from the last applied camera target before a new
  /// follow animation is issued.
  static const double cameraMoveThresholdMeters = 0.3;

  /// Minimum heading change (degrees) from the last applied camera bearing before
  /// a new rotation animation is issued.
  static const double cameraBearingThresholdDegrees = 1.5;

  // -- Floor transition --

  /// Distance (m) from connector POI to trigger floor pre-loading.
  static const double connectorProximityThreshold = 30.0;

  /// Message shown during positioning blackout between floors.
  static const String transitionBlackoutMessage = 'Moving to Floor';

  /// Suppression period (s) after a floor switch before reroute checks resume.
  static const int postFloorSwitchSuppressSeconds = 10;

  /// Maximum time (s) to wait for a floor transition to complete before aborting.
  static const int transitionTimeoutSeconds = 30;

  /// Maximum number of floor-transition lifecycle events retained for
  /// observers (oldest dropped). (ORIGINAL PHASE 5 — Floor Transitions.)
  static const int floorTransitionEventHistoryLimit = 8;

  // -- Arrival --

  /// Distance (m) from the resolved destination anchor within which a
  /// positioning tick qualifies as an arrival candidate.
  /// (ORIGINAL PHASE 6 — Arrival.)
  static const double arrivalProximityThresholdMeters = 15.0;

  /// Consecutive qualifying ticks required before arrival is confirmed.
  /// Proximity alone is never proof. (ORIGINAL PHASE 6 — Arrival.)
  static const int arrivalConfirmationCount = 2;

  // -- Building entry dwell --

  /// How long (s) the ENTERING_BUILDING state waits for Wi-Fi corroboration
  /// before reverting to ACTIVE_OUTDOOR. (ORIGINAL PHASE 2 — State Machine.)
  static const int enteringCorroborationTimeoutSeconds = 20;

  /// Cool-down (s) after a TIMED-OUT entrance dwell before the proximity
  /// path may trigger ENTERING_BUILDING again. Prevents a doorstep loiterer
  /// from cycling in and out of the dwell every timeout period.
  /// Evidence-driven belief flips are never suppressed.
  /// (ORIGINAL PHASE 4 — Building Transitions.)
  static const int entryRetriggerCooldownSeconds = 15;

  /// How long (s) the EXITING_BUILDING state waits for a confirming GPS tick
  /// before reverting to ACTIVE_INDOOR — the safe default is to remain
  /// indoors rather than fabricate an exit from silence.
  /// (ORIGINAL PHASE 4 — Building Transitions.)
  static const int exitingCorroborationTimeoutSeconds = 20;

  // -- Indoor stale timer --

  /// Seconds without a valid indoor estimate before it is cleared.
  static const int indoorStaleTimerSeconds = 10;
}
