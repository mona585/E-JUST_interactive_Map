import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/navigation_config.dart';
import '../data/datasources/gps_location_service.dart';
import '../data/datasources/location_service.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/position_estimate.dart';
import '../data/models/position_fix.dart';
import '../data/models/user_location.dart';

/// Active source of effective user position.
enum LocationSource {
  /// Position provided by outdoor device GPS.
  gps,

  /// Position provided by native Kotlin Wi-Fi fingerprinting (KnnLocalizer).
  indoorWifi,

  /// No valid location estimate available.
  none,
}

/// Status of the device location provider lifecycle.
enum LocationStateStatus {
  initial,
  requesting,
  tracking,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  error,
}

/// Positioning stability state for indoor navigation.
enum PositioningStability {
  /// No valid indoor estimates available.
  unavailable,

  /// Receiving estimates but not yet stable (not enough consecutive valid ones).
  acquiring,

  /// Enough consecutive valid estimates to trust the position.
  stable,
}

/// Which evidence stream the unified arbiter currently believes.
///
/// Decided exclusively by measurement evidence (timeliness and quality of
/// native estimates vs availability of GPS) — never by UI selection,
/// destination, route, POI, or selected-floor context.
enum _ArbiterMode {
  /// GPS is the believed source; Wi-Fi evidence is only accumulating towards
  /// indoor-entry confirmation.
  outdoor,

  /// Fresh, qualifying Wi-Fi evidence is the believed source.
  indoor,
}

/// A single entry in the positioning stability rolling window.
class _StabilityEntry {
  final LatLng position;
  final DateTime timestamp;
  final int matchedAps;

  _StabilityEntry({
    required this.position,
    required this.timestamp,
    required this.matchedAps,
  });
}

/// Provider managing outdoor device GPS position, native indoor Wi-Fi position,
/// and arbitrating between them as a single unified positioning pipeline.
///
/// Arbitration contract (Phase 1):
/// - Native estimates are consumed as evidence only. An estimate's
///   `buid`/`floor` mean "this estimate was localized against that resident
///   RadioMap"; they become canonical user identity only after
///   [NavigationConfig.scopeConfirmCount] consecutive consistent winning
///   estimates.
/// - UI selection (building/floor/POI/route/destination) never influences
///   which evidence is believed nor the reported identity.
/// - There is no numerical GPS/Wi-Fi fusion: exactly one source is believed
///   at a time, switched with hysteresis.
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;
  final NativePositioningService _nativePositioningService;

  // -- Raw evidence streams (pass-through, never selection-gated) --
  UserLocation? _gpsLocation;
  PositionEstimate? _latestIndoorEstimate;

  // -- PHASE 5: GPS ingestion quality gate (INV-8 inputs, INV-11) --
  /// Most recent raw GPS sample regardless of gate outcome (INV-11: raw
  /// preservation; filtering is per-fix acceptance, not rate reduction).
  UserLocation? _lastRawGps;

  /// Diagnostics view of the untouched last raw GPS sample (INV-11).
  UserLocation? get lastRawGpsForDiagnostics => _lastRawGps;

  /// Last GPS sample that PASSED the quality gate.
  UserLocation? _lastAcceptedGps;

  /// Canonical-candidate fix built exclusively from accepted GPS samples.
  PositionFix? _gpsFix;

  /// Consecutive outlier samples accepted as real fast movement guard.
  int _gpsOutlierStreak = 0;

  /// Consecutive degraded (stale/rejected/poor/held) GPS samples.
  int _gpsDegradedStreak = 0;

  /// Whether the GPS feed is currently degraded for decision purposes:
  /// [NavigationConfig.gpsPausePoorTicks] consecutive poor/invalid/held
  /// fixes. Consumers (pause logic) must wait this out before acting.
  bool get gpsDegraded =>
      _gpsDegradedStreak >= NavigationConfig.gpsPausePoorTicks;

  // -- Unified arbiter state --
  _ArbiterMode _mode = _ArbiterMode.outdoor;

  /// Canonical output of the arbiter (single believed source per fix).
  PositionFix? _currentFix;

  /// Consecutive qualifying estimates while outdoor (indoor-entry hysteresis).
  int _indoorCandidateStreak = 0;

  /// Consecutive non-qualifying/outlier arrivals while indoor
  /// (indoor-exit hysteresis). Silence is handled by the stale timer.
  int _indoorBadCycleCount = 0;

  /// Building/floor claim under confirmation (estimate-level identity).
  String? _claimBuid;
  String? _claimFloor;
  int _claimStreak = 0;

  /// Canonically confirmed identity pair; null until
  /// [NavigationConfig.scopeConfirmCount] consistent claims succeed.
  String? _confirmedBuid;
  String? _confirmedFloor;

  /// Estimate-level identity of the last accepted Wi-Fi fix; used by the
  /// outlier guard to distinguish genuine map switches from noise.
  String? _lastAcceptedWifiBuid;
  String? _lastAcceptedWifiFloor;

  LocationStateStatus _status = LocationStateStatus.initial;
  String? _errorMessage;
  StreamSubscription<UserLocation>? _gpsSubscription;
  StreamSubscription<PositionEstimate>? _nativeSubscription;
  Timer? _indoorStaleTimer;
  int _indoorEstimateGeneration = 0;
  bool _isTracking = false;
  bool _isDisposed = false;

  // -- Positioning stability tracker --
  final List<_StabilityEntry> _stabilityWindow = [];
  PositioningStability _positioningStability = PositioningStability.unavailable;
  PositioningStability get positioningStability => _positioningStability;

  LocationProvider({
    LocationService? locationService,
    NativePositioningService? nativePositioningService,
  })  : _locationService = locationService ?? GpsLocationService(),
        _nativePositioningService =
            nativePositioningService ?? MethodChannelNativePositioningService() {
    _subscribeNativePositionStream();
  }

  /// Canonical immutable position fix produced by unified arbitration.
  ///
  /// Exactly one of GPS / Wi-Fi evidence is believed per fix. Building/floor
  /// identity is present only after claim confirmation; it is never inferred
  /// from UI selection context.
  PositionFix? get currentFix => _currentFix;

  /// Current effective user location (either Indoor Wi-Fi or Outdoor GPS).
  UserLocation? get currentLocation {
    final fix = _currentFix;
    if (fix == null) return null;
    return UserLocation(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      timestamp: fix.timestamp,
    );
  }

  /// Outdoor GPS location fix (raw pass-through).
  UserLocation? get gpsLocation => _gpsLocation;

  /// Latest raw native Wi-Fi indoor position estimate (pass-through).
  PositionEstimate? get latestIndoorEstimate => _latestIndoorEstimate;

  /// Active position source (`gps`, `indoorWifi`, or `none`).
  LocationSource get positionSource {
    final fix = _currentFix;
    if (fix == null) return LocationSource.none;
    return fix.source == PositionSource.wifi
        ? LocationSource.indoorWifi
        : LocationSource.gps;
  }

  /// Whether current effective position is driven by native Wi-Fi.
  bool get isIndoorWifiActive => positionSource == LocationSource.indoorWifi;

  /// Current lifecycle status of location provider.
  LocationStateStatus get status => _status;

  /// Human-readable error or warning message, if any.
  String? get errorMessage => _errorMessage;

  /// Whether active GPS stream tracking is running.
  bool get isTracking => _isTracking;

  /// Whether a valid user location fix is available.
  bool get hasLocation => _currentFix != null;

  void _subscribeNativePositionStream() {
    _nativeSubscription?.cancel();
    _nativeSubscription = _nativePositioningService.positionStream.listen(
      (estimate) {
        debugPrint(
          '[LocationProvider] Native position estimate received: $estimate',
        );
        _onNativeEstimate(estimate);
      },
      onError: (err) {
        debugPrint('[LocationProvider] Native position stream error: $err');
      },
    );
  }

  /// Unified evidence intake: records raw pass-through state, runs the mode
  /// state machine, then rebuilds the canonical fix.
  void _onNativeEstimate(PositionEstimate estimate) {
    if (_isDisposed) return;
    _latestIndoorEstimate = estimate;

    final qualifies = _qualifies(estimate);

    if (!estimate.isValid) {
      _cancelIndoorStaleTimer();
    } else {
      _scheduleIndoorStaleTimer();
    }

    switch (_mode) {
      case _ArbiterMode.outdoor:
        _handleOutdoorEvidence(estimate, qualifies);
        break;
      case _ArbiterMode.indoor:
        _handleIndoorEvidence(estimate, qualifies);
        break;
    }

    _feedStability(qualifies, estimate);
    _evaluateArbitration();
  }

  /// Whether an estimate counts as valid positioning evidence.
  ///
  /// Gates: native validity, a backing resident RadioMap (non-empty buid and
  /// floor), minimum matched APs, and — when totalAps is known — the minimum
  /// matched ratio. Estimates without a backing map carry no verifiable
  /// coordinates and are never qualifying evidence.
  bool _qualifies(PositionEstimate e) {
    if (!e.isValid) return false;
    if (e.buid.isEmpty || e.floor.isEmpty) return false;
    if (e.matchedAps < NavigationConfig.stabilityMinMatchedAps) return false;
    if (e.totalAps > 0 &&
        e.matchedAps / e.totalAps < NavigationConfig.minMatchedRatio) {
      return false;
    }
    return true;
  }

  // -- Mode state machine --

  /// Outdoor mode: only qualifying estimates accumulate towards indoor entry.
  /// GPS remains the believed source until [NavigationConfig.indoorEnterConfirmCount]
  /// consecutive qualifying estimates confirm indoor positioning.
  void _handleOutdoorEvidence(PositionEstimate estimate, bool qualifies) {
    if (!qualifies) {
      _indoorCandidateStreak = 0;
      return;
    }

    _indoorCandidateStreak++;
    if (_indoorCandidateStreak >= NavigationConfig.indoorEnterConfirmCount) {
      debugPrint(
        '[LocationProvider] Entering indoor positioning after '
        '$_indoorCandidateStreak consecutive qualifying estimates',
      );
      _mode = _ArbiterMode.indoor;
      _indoorCandidateStreak = 0;
      _indoorBadCycleCount = 0;
      _resetClaim();
      _acceptWifiEstimate(estimate);
    }
  }

  /// Indoor mode: accepted evidence maintains the fix and claim streak;
  /// non-qualifying or outlier evidence accumulates towards exit.
  void _handleIndoorEvidence(PositionEstimate estimate, bool qualifies) {
    if (qualifies) {
      if (_isOutlierJump(estimate)) {
        // Suspect sample: hold previous fix, break the claim streak, and
        // count this cycle as bad for exit hysteresis.
        debugPrint(
          '[LocationProvider] Outlier jump rejected '
          '(>${NavigationConfig.outlierJumpThresholdMeters}m within same scope); holding previous fix',
        );
        _holdWifiFix(estimate);
        _claimStreak = 0;
        _indoorBadCycleCount++;
      } else {
        _acceptWifiEstimate(estimate);
        _indoorBadCycleCount = 0;
      }

      if (_indoorBadCycleCount >= NavigationConfig.indoorExitStaleCycles) {
        _exitIndoorMode('consecutive low-quality/outlier cycles');
      }
      return;
    }

    _indoorBadCycleCount++;
    _claimStreak = 0;
    if (_indoorBadCycleCount >= NavigationConfig.indoorExitStaleCycles) {
      _exitIndoorMode('consecutive non-qualifying cycles');
    }
  }

  void _exitIndoorMode(String reason) {
    debugPrint('[LocationProvider] Exiting indoor positioning: $reason');
    _mode = _ArbiterMode.outdoor;
    _indoorCandidateStreak = 0;
    _indoorBadCycleCount = 0;
    _resetClaim();
    _resetStability();
    // Canonical fix falls back to GPS (or none) in _evaluateArbitration.
  }

  /// Whether a qualifying estimate is an implausible jump from the last
  /// accepted Wi-Fi fix.
  ///
  /// Only applies when the estimate claims the same resident map identity as
  /// the last accepted fix. A different winning (buid, floor) is genuine
  /// evidence — floors overlap geographically and only map identity can
  /// disambiguate them — so it bypasses the guard.
  bool _isOutlierJump(PositionEstimate e) {
    final fix = _currentFix;
    if (fix == null || fix.source != PositionSource.wifi) return false;
    if (e.buid != _lastAcceptedWifiBuid || e.floor != _lastAcceptedWifiFloor) {
      return false;
    }
    final distance = Geolocator.distanceBetween(
      fix.latitude,
      fix.longitude,
      e.latitude!,
      e.longitude!,
    );
    return distance > NavigationConfig.outlierJumpThresholdMeters;
  }

  /// Accepts a qualifying Wi-Fi estimate as the believed fix and advances the
  /// building/floor claim state machine.
  void _acceptWifiEstimate(PositionEstimate e) {
    _currentFix = PositionFix(
      latitude: e.latitude!,
      longitude: e.longitude!,
      source: PositionSource.wifi,
      buildingId: _confirmedBuid,
      floor: _confirmedFloor,
      accuracy: _deriveWifiAccuracy(e),
      confidence: _computeWifiConfidence(e),
      timestamp: e.timestamp,
      status: PositionFixStatus.fresh,
    );
    _lastAcceptedWifiBuid = e.buid;
    _lastAcceptedWifiFloor = e.floor;
    _advanceClaim(e.buid, e.floor);
  }

  /// Carries the previous fix forward with `held` status after an outlier.
  /// Coordinates/accuracy/confidence/scope are preserved unchanged.
  void _holdWifiFix(PositionEstimate observationTime) {
    final fix = _currentFix;
    if (fix == null) return;
    _currentFix = fix.copyWith(
      timestamp: observationTime.timestamp,
      status: PositionFixStatus.held,
    );
  }

  // -- Claim confirmation (N = NavigationConfig.scopeConfirmCount) --

  /// Advances the claim streak with an accepted estimate's identity pair.
  ///
  /// The pair becomes canonically confirmed only after
  /// [NavigationConfig.scopeConfirmCount] consecutive consistent claims; the
  /// confirmed pair then switches atomically when a different pair reaches N.
  void _advanceClaim(String buid, String floor) {
    if (_claimBuid == buid && _claimFloor == floor) {
      _claimStreak++;
    } else {
      _claimBuid = buid;
      _claimFloor = floor;
      _claimStreak = 1;
    }

    if (_claimStreak >= NavigationConfig.scopeConfirmCount &&
        (_confirmedBuid != buid || _confirmedFloor != floor)) {
      debugPrint('[LocationProvider] Scope confirmed: $buid / $floor');
      _confirmedBuid = buid;
      _confirmedFloor = floor;
    }
  }

  void _resetClaim() {
    _claimBuid = null;
    _claimFloor = null;
    _claimStreak = 0;
    _confirmedBuid = null;
    _confirmedFloor = null;
    _lastAcceptedWifiBuid = null;
    _lastAcceptedWifiFloor = null;
  }

  // -- Evidence-derived quality metrics --

  /// Derives Wi-Fi horizontal accuracy (meters) from KNN evidence:
  /// clamp(max(topKSpreadMeters, bestDistance), wifiAccuracyMinMeters,
  /// wifiAccuracyMaxMeters). Non-finite or absent fields contribute nothing;
  /// with no basis at all, the conservative upper bound is used.
  double _deriveWifiAccuracy(PositionEstimate e) {
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
  double _computeWifiConfidence(PositionEstimate e) {
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
    final stabilityScore =
        _positioningStability == PositioningStability.stable ? 1.0 : 0.4;

    return (0.45 * ratioScore + 0.25 * spreadScore + 0.30 * stabilityScore)
        .clamp(0.0, 1.0);
  }

  /// Deterministic GPS confidence mapping from reported accuracy.
  ///
  /// PHASE 5 bands: ≤5 m excellent; ≤ good high; anything accepted above
  /// the poor band is flagged low-confidence so decisions can ignore it.
  double _gpsConfidence(double accuracy) {
    if (accuracy <= 5.0) return 0.9;
    if (accuracy <= NavigationConfig.gpsGoodAccuracyMeters) return 0.7;
    return 0.25;
  }

  // ── PHASE 5: GPS ingestion gate ──────────────────────────────────────

  /// Single intake point for every raw GPS sample (stream, manual injection,
  /// initial centering). Applies staleness, accuracy-band and implied-speed
  /// gates BEFORE anything can become canonical; raw samples are always
  /// preserved on [_gpsLocation]/[_lastRawGps] (INV-11).
  void _ingestGps(UserLocation location) {
    _lastRawGps = location;
    _gpsLocation = location;
    final now = DateTime.now();

    // Staleness: a fix older than the window must never refresh the
    // canonical position; an existing fix is demoted to stale for display.
    final age = now.difference(location.timestamp);
    if (age.inSeconds > NavigationConfig.gpsStaleAfterSeconds) {
      debugPrint('[LocationProvider] GPS fix stale (${age.inSeconds}s) — '
          'not applied');
      _markDegraded();
      _demoteGpsFixToStale();
      return;
    }

    // Hard rejection band.
    if (location.accuracy > NavigationConfig.gpsRejectAccuracyMeters) {
      debugPrint('[LocationProvider] GPS fix rejected '
          '(accuracy ${location.accuracy.toStringAsFixed(0)}m)');
      _markDegraded();
      return;
    }

    // Implied-speed outlier: implausible displacement without good accuracy
    // is held for [gpsOutlierHoldTicks] ticks; a second consecutive outlier
    // is accepted as genuine fast movement.
    final prev = _lastAcceptedGps;
    if (prev != null) {
      final dtMs =
          location.timestamp.difference(prev.timestamp).inMilliseconds;
      if (dtMs > 0) {
        final dist = Geolocator.distanceBetween(
            prev.latitude, prev.longitude, location.latitude, location.longitude);
        final speed = dist / (dtMs / 1000.0);
        final newAccuracyIsGood =
            location.accuracy <= NavigationConfig.gpsGoodAccuracyMeters;
        if (speed > NavigationConfig.gpsMaxImpliedSpeedMps &&
            !newAccuracyIsGood) {
          _gpsOutlierStreak++;
          _markDegraded();
          if (_gpsOutlierStreak <= NavigationConfig.gpsOutlierHoldTicks) {
            debugPrint('[LocationProvider] GPS outlier held '
                '(${speed.toStringAsFixed(0)} m/s implied); holding previous fix');
            _holdGpsFix(location.timestamp);
            return;
          }
          debugPrint('[LocationProvider] GPS outlier streak accepted as real '
              'movement');
        }
      }
    }
    _gpsOutlierStreak = 0;

    // Accepted.
    _lastAcceptedGps = location;
    _gpsDegradedStreak = 0;
    _gpsFix = PositionFix(
      latitude: location.latitude,
      longitude: location.longitude,
      source: PositionSource.gps,
      accuracy: location.accuracy,
      confidence: _gpsConfidence(location.accuracy),
      timestamp: location.timestamp,
      status: PositionFixStatus.fresh,
    );
  }

  void _markDegraded() {
    _gpsDegradedStreak++;
  }

  void _holdGpsFix(DateTime observedAt) {
    final fix = _gpsFix;
    if (fix == null) return;
    _gpsFix = fix.copyWith(
      timestamp: observedAt,
      status: PositionFixStatus.held,
    );
  }

  void _demoteGpsFixToStale() {
    final fix = _gpsFix;
    if (fix == null || fix.status == PositionFixStatus.stale) return;
    _gpsFix = fix.copyWith(status: PositionFixStatus.stale);
  }

  // -- Canonical fix maintenance --

  /// Rebuilds the canonical fix from arbiter state. While indoor, the
  /// maintained Wi-Fi fix stands; otherwise the GPS gate output (or none)
  /// is believed.
  void _evaluateArbitration() {
    if (_isDisposed) return;
    if (!(_mode == _ArbiterMode.indoor && _currentFix != null)) {
      _currentFix = _gpsFix;
    }
    notifyListeners();
  }

  // -- Indoor stale timer --

  void _scheduleIndoorStaleTimer() {
    final estimate = _latestIndoorEstimate;
    if (estimate == null || !estimate.isValid) {
      _cancelIndoorStaleTimer();
      return;
    }

    _indoorStaleTimer?.cancel();
    final generation = ++_indoorEstimateGeneration;
    _indoorStaleTimer = Timer(
      Duration(seconds: NavigationConfig.indoorStaleTimerSeconds),
      () {
        if (_isDisposed || generation != _indoorEstimateGeneration) {
          return;
        }

        if (_latestIndoorEstimate == estimate) {
          debugPrint(
            '[LocationProvider] Indoor estimate expired after '
            '${NavigationConfig.indoorStaleTimerSeconds}s; clearing active Wi-Fi position',
          );
          _latestIndoorEstimate = null;
          if (_mode == _ArbiterMode.indoor) {
            _exitIndoorMode('stale estimate');
          }
          _evaluateArbitration();
        }
      },
    );
  }

  void _cancelIndoorStaleTimer() {
    _indoorStaleTimer?.cancel();
    _indoorStaleTimer = null;
  }

  // -- Positioning stability (scope-independent feed) --

  /// Feeds the rolling stability window from every qualifying estimate,
  /// regardless of which resident RadioMap produced it.
  void _feedStability(bool qualifies, PositionEstimate estimate) {
    if (!qualifies ||
        estimate.latitude == null ||
        estimate.longitude == null) {
      return;
    }

    _stabilityWindow.add(_StabilityEntry(
      position: LatLng(estimate.latitude!, estimate.longitude!),
      timestamp: estimate.timestamp,
      matchedAps: estimate.matchedAps,
    ));
    _evaluateStability();
  }

  /// Evaluates positioning stability based on a rolling window of indoor estimates.
  void _evaluateStability() {
    final now = DateTime.now();
    final windowDuration = Duration(seconds: NavigationConfig.stabilityWindowSeconds);

    // Evict entries older than the window
    _stabilityWindow.removeWhere(
      (e) => now.difference(e.timestamp) > windowDuration,
    );

    if (_stabilityWindow.length < NavigationConfig.stabilityMinEstimates) {
      _updateStability(PositioningStability.acquiring);
      return;
    }

    // Check matched APs threshold
    final hasMinAps = _stabilityWindow.every(
      (e) => e.matchedAps >= NavigationConfig.stabilityMinMatchedAps,
    );
    if (!hasMinAps) {
      _updateStability(PositioningStability.acquiring);
      return;
    }

    // Check position delta between consecutive entries
    // Distance calculation now uses Geolocator
    bool stable = true;
    for (var i = 1; i < _stabilityWindow.length; i++) {
      final delta = Geolocator.distanceBetween(_stabilityWindow[i - 1].position.latitude, _stabilityWindow[i - 1].position.longitude, _stabilityWindow[i].position.latitude, _stabilityWindow[i].position.longitude);
      if (delta > NavigationConfig.stabilityMaxDelta) {
        stable = false;
        break;
      }
    }

    _updateStability(
      stable ? PositioningStability.stable : PositioningStability.acquiring,
    );
  }

  void _updateStability(PositioningStability newStability) {
    if (_isDisposed || _positioningStability == newStability) return;
    _positioningStability = newStability;
    debugPrint('[LocationProvider] Positioning stability: $newStability');
    notifyListeners();
  }

  void _resetStability() {
    _stabilityWindow.clear();
    _updateStability(PositioningStability.unavailable);
  }

  /// Requests permission, acquires current GPS position, and begins live GPS tracking.
  Future<UserLocation?> requestAndCenter() async {
    debugPrint('[LocationProvider] requestAndCenter called');
    _status = LocationStateStatus.requesting;
    _errorMessage = null;
    notifyListeners();

    // 1. Check if location services are enabled
    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    debugPrint('[LocationProvider] Location service enabled: $serviceEnabled');
    if (!serviceEnabled) {
      _status = LocationStateStatus.serviceDisabled;
      _errorMessage = 'Location services are disabled. Please turn on GPS.';
      notifyListeners();
      return null;
    }

    // 2. Request permission
    final permStatus = await _locationService.requestPermission();
    debugPrint('[LocationProvider] Permission status: $permStatus');
    switch (permStatus) {
      case LocationPermissionStatus.denied:
        _status = LocationStateStatus.permissionDenied;
        _errorMessage = 'Location permission was denied.';
        notifyListeners();
        return null;
      case LocationPermissionStatus.deniedForever:
        _status = LocationStateStatus.permissionDeniedForever;
        _errorMessage =
            'Location permission permanently denied. Please enable in App Settings.';
        notifyListeners();
        return null;
      case LocationPermissionStatus.serviceDisabled:
        _status = LocationStateStatus.serviceDisabled;
        _errorMessage = 'Location services are disabled. Please turn on GPS.';
        notifyListeners();
        return null;
      case LocationPermissionStatus.granted:
        break;
    }

    // 3. Obtain current GPS position
    try {
      debugPrint('[LocationProvider] Calling getCurrentPosition...');
      final position = await _locationService.getCurrentPosition();
      debugPrint('[LocationProvider] getCurrentPosition returned: ${position != null ? "${position.latitude},${position.longitude}" : "null"}');
      if (position != null) {
        _ingestGps(position);
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        startTracking();
        _evaluateArbitration();
        return currentLocation;
      } else {
        _status = LocationStateStatus.error;
        _errorMessage = 'Unable to acquire GPS signal. Please try again.';
        notifyListeners();
        return null;
      }
    } catch (e) {
      debugPrint('[LocationProvider] getCurrentPosition error: $e');
      _status = LocationStateStatus.error;
      _errorMessage = 'Error acquiring GPS location: $e';
      notifyListeners();
      return null;
    }
  }

  /// Starts listening to real-time GPS location updates.
  void startTracking() {
    if (_isTracking) {
      debugPrint('[LocationProvider] startTracking already tracking, skip');
      return;
    }

    debugPrint('[LocationProvider] startTracking: subscribing to GPS stream');
    _gpsSubscription?.cancel();
    _isTracking = true;

    _gpsSubscription = _locationService.getPositionStream().listen(
      (location) {
        debugPrint('[LocationProvider] GPS update: ${location.latitude},${location.longitude}');
        if (_isDisposed) return;
        _ingestGps(location);
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        _evaluateArbitration();
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[LocationProvider] GPS stream error: $error');
        if (_isDisposed) return;
        _errorMessage = 'GPS tracking error: $error';
        notifyListeners();
      },
    );
  }

  /// Stops listening to GPS updates.
  void stopTracking() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Manually injects a GPS position (useful for unit testing).
  ///
  /// PHASE 5: routed through the same ingestion gate as the live stream, so
  /// tests exercise identical staleness/accuracy/outlier semantics.
  void setGpsLocation(UserLocation location) {
    _ingestGps(location);
    _evaluateArbitration();
  }

  /// Clears any transient error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _indoorStaleTimer?.cancel();
    _indoorStaleTimer = null;
    super.dispose();
  }
}
