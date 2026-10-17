import '../config/navigation_config.dart';
import '../models/position_estimate.dart';

/// Pure positioning scoring rules — deterministic, no live state.
///
/// Extracted from `LocationViewModel` so arbitration can delegate every
/// deterministic computation here while keeping evidence/arbitration
/// orchestration and notifications in the view model.
class PositioningEngine {
  /// Derived Wi-Fi fix accuracy in meters from a fingerprint estimate.
  ///
  /// Uses the top-k spread (tight clusters → lower accuracy) and the best
  /// match distance; the best known basis wins. With no basis at all, the
  /// conservative upper bound is used. The result is clamped into the
  /// configured band (wifiAccuracyMinMeters .. wifiAccuracyMaxMeters).
  static double deriveWifiAccuracy(PositionEstimate e) {
    var basis = -1.0;
    final spread = e.topKSpreadMeters;
    if (spread != null && spread.isFinite && spread > 0) {
      basis = spread;
    }
    final best = e.bestDistance;
    if (best != null && best.isFinite && best > basis) {
      basis = best;
    }
    if (basis < 0) {
      basis = NavigationConfig.wifiAccuracyMaxMeters;
    }
    return basis.clamp(
      NavigationConfig.wifiAccuracyMinMeters,
      NavigationConfig.wifiAccuracyMaxMeters,
    );
  }

  /// Computes arbitration confidence in [0, 1] from match ratio, top-k
  /// fingerprint spread, and short-term stability of the evidence window.
  static double computeWifiConfidence(
    PositionEstimate e, {
    required bool stable,
  }) {
    // Match-ratio component saturating at 50% matched APs. When totalAps is
    // unknown, take the neutral midpoint.
    final ratio = e.totalAps > 0 ? e.matchedAps / e.totalAps : 0.5;
    final ratioScore = (ratio / 0.5).clamp(0.0, 1.0);

    // Spread component: tight fingerprint clusters score higher; unknown
    // spread is neutral.
    var spreadScore = 0.5;
    final spread = e.topKSpreadMeters;
    if (spread != null && spread.isFinite && spread > 0) {
      final normalized =
          ((spread - NavigationConfig.wifiAccuracyMinMeters) /
                  (NavigationConfig.wifiAccuracyMaxMeters -
                      NavigationConfig.wifiAccuracyMinMeters))
              .clamp(0.0, 1.0);
      spreadScore = 1.0 - normalized;
    }

    // Stability component: agreement of the recent evidence window.
    final stabilityScore = stable ? 1.0 : 0.4;

    return (0.45 * ratioScore + 0.25 * spreadScore + 0.30 * stabilityScore)
        .clamp(0.0, 1.0);
  }

  /// Deterministic GPS confidence mapping from reported accuracy.
  ///
  /// PHASE 5 bands: <=5 m excellent; <= good high; anything accepted above
  /// the poor band is flagged low-confidence so decisions can ignore it.
  static double gpsConfidence(double accuracy) {
    if (accuracy <= 5.0) return 0.9;
    if (accuracy <= NavigationConfig.gpsGoodAccuracyMeters) return 0.7;
    return 0.25;
  }
}
