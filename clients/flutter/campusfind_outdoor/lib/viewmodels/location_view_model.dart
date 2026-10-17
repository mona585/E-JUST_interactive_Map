import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

import '../config/navigation_config.dart';
import '../datasources/location_service.dart';
import '../models/position_estimate.dart';
import '../models/position_fix.dart';
import '../models/user_location.dart';
import '../services/positioning_engine.dart';

/// Active source of effective user position.
enum LocationSource {
  /// Position provided by outdoor device GPS.
  gps,

  /// Position provided by native Kotlin Wi-Fi fingerprinting (KnnLocalizer).
  ///
  /// Outdoor-only build: retained for API compatibility with the shared
  /// navigation port; no reachable Outdoor runtime path can produce this
  /// source.
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

/// Provider managing the outdoor device GPS position for the Outdoor-only
/// build.
///
/// HISTORY: this class previously fused GPS with a native Wi-Fi indoor
/// positioning arbiter. The Indoor evidence pipeline (native positioning
/// service dependency, Gps/Wi-Fi mode state machine, building/floor claim
/// confirmation, indoor stale timer, positioning-stability window) has been
/// removed here: the canonical fix is now derived exclusively from the GPS
/// ingestion gate. The Wi-Fi engine therefore has no producer and is not part
/// of the Outdoor runtime graph.
///
/// The Indoor compatibility accessors ([latestIndoorEstimate],
/// [isIndoorWifiActive]) remain as inert constants so the shared navigation
/// port keeps compiling until the Indoor consumer surface is removed.
class LocationViewModel extends ChangeNotifier {
  final LocationService _locationService;

  // -- Raw GPS evidence (pass-through, never selection-gated) --
  UserLocation? _gpsLocation;

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

  /// Canonical output of the positioning pipeline (always the GPS gate output
  /// in this Outdoor-only build).
  PositionFix? _currentFix;

  LocationStateStatus _status = LocationStateStatus.initial;
  String? _errorMessage;
  StreamSubscription<UserLocation>? _gpsSubscription;
  bool _isTracking = false;
  bool _isDisposed = false;

  LocationViewModel({
    required LocationService locationService,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _locationService = locationService;

  /// Canonical immutable position fix produced by the GPS pipeline.
  PositionFix? get currentFix => _currentFix;

  /// Current effective user location (Outdoor GPS).
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

  /// Latest raw native Wi-Fi indoor position estimate.
  ///
  /// Outdoor-only build: always null — the Wi-Fi engine has no producer.
  PositionEstimate? get latestIndoorEstimate => null;

  /// Active position source (`gps` or `none`).
  ///
  /// Outdoor-only build: a fix is always GPS-sourced.
  LocationSource get positionSource {
    final fix = _currentFix;
    if (fix == null) return LocationSource.none;
    return LocationSource.gps;
  }

  /// Whether current effective position is driven by native Wi-Fi.
  ///
  /// Outdoor-only build: always false — the Wi-Fi engine has no producer.
  bool get isIndoorWifiActive => false;

  /// Current lifecycle status of location provider.
  LocationStateStatus get status => _status;

  /// Human-readable error or warning message, if any.
  String? get errorMessage => _errorMessage;

  /// Whether active GPS stream tracking is running.
  bool get isTracking => _isTracking;

  /// Whether a valid user location fix is available.
  bool get hasLocation => _currentFix != null;

  // -- Evidence-derived quality metrics --

  /// Deterministic GPS confidence mapping from reported accuracy.
  ///
  /// PHASE 5 bands: <=5 m excellent; <= good high; anything accepted above
  /// the poor band is flagged low-confidence so decisions can ignore it.
  double _gpsConfidence(double accuracy) =>
      PositioningEngine.gpsConfidence(accuracy);

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
      debugPrint(
        '[LocationViewModel] GPS fix stale (${age.inSeconds}s) — '
        'not applied',
      );
      _markDegraded();
      _demoteGpsFixToStale();
      return;
    }

    // Hard rejection band.
    if (location.accuracy > NavigationConfig.gpsRejectAccuracyMeters) {
      debugPrint(
        '[LocationViewModel] GPS fix rejected '
        '(accuracy ${location.accuracy.toStringAsFixed(0)}m)',
      );
      _markDegraded();
      return;
    }

    // Implied-speed outlier: implausible displacement without good accuracy
    // is held for [gpsOutlierHoldTicks] ticks; a second consecutive outlier
    // is accepted as genuine fast movement.
    final prev = _lastAcceptedGps;
    if (prev != null) {
      final dtMs = location.timestamp.difference(prev.timestamp).inMilliseconds;
      if (dtMs > 0) {
        final dist = Geolocator.distanceBetween(
          prev.latitude,
          prev.longitude,
          location.latitude,
          location.longitude,
        );
        final speed = dist / (dtMs / 1000.0);
        final newAccuracyIsGood =
            location.accuracy <= NavigationConfig.gpsGoodAccuracyMeters;
        if (speed > NavigationConfig.gpsMaxImpliedSpeedMps &&
            !newAccuracyIsGood) {
          _gpsOutlierStreak++;
          _markDegraded();
          if (_gpsOutlierStreak <= NavigationConfig.gpsOutlierHoldTicks) {
            debugPrint(
              '[LocationViewModel] GPS outlier held '
              '(${speed.toStringAsFixed(0)} m/s implied); holding previous fix',
            );
            _holdGpsFix(location.timestamp);
            return;
          }
          debugPrint(
            '[LocationViewModel] GPS outlier streak accepted as real '
            'movement',
          );
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

  /// Rebuilds the canonical fix from the GPS gate output.
  void _evaluateArbitration() {
    if (_isDisposed) return;
    _currentFix = _gpsFix;
    notifyListeners();
  }

  /// Requests permission, acquires current GPS position, and begins live GPS tracking.
  Future<UserLocation?> requestAndCenter() async {
    debugPrint('[LocationViewModel] requestAndCenter called');
    _status = LocationStateStatus.requesting;
    _errorMessage = null;
    notifyListeners();

    // 1. Check if location services are enabled
    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    debugPrint('[LocationViewModel] Location service enabled: $serviceEnabled');
    if (!serviceEnabled) {
      _status = LocationStateStatus.serviceDisabled;
      _errorMessage = 'Location services are disabled. Please turn on GPS.';
      notifyListeners();
      return null;
    }

    // 2. Request permission
    final permStatus = await _locationService.requestPermission();
    debugPrint('[LocationViewModel] Permission status: $permStatus');
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
      debugPrint('[LocationViewModel] Calling getCurrentPosition...');
      final position = await _locationService.getCurrentPosition();
      debugPrint(
        '[LocationViewModel] getCurrentPosition returned: ${position != null ? "${position.latitude},${position.longitude}" : "null"}',
      );
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
      debugPrint('[LocationViewModel] getCurrentPosition error: $e');
      _status = LocationStateStatus.error;
      _errorMessage = 'Error acquiring GPS location: $e';
      notifyListeners();
      return null;
    }
  }

  /// Starts listening to real-time GPS location updates.
  void startTracking() {
    if (_isTracking) {
      debugPrint('[LocationViewModel] startTracking already tracking, skip');
      return;
    }

    debugPrint('[LocationViewModel] startTracking: subscribing to GPS stream');
    _gpsSubscription?.cancel();
    _isTracking = true;

    _gpsSubscription = _locationService.getPositionStream().listen(
      (location) {
        debugPrint(
          '[LocationViewModel] GPS update: ${location.latitude},${location.longitude}',
        );
        if (_isDisposed) return;
        _ingestGps(location);
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        _evaluateArbitration();
        notifyListeners();
      },
      onError: (error) {
        debugPrint('[LocationViewModel] GPS stream error: $error');
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
    super.dispose();
  }
}
