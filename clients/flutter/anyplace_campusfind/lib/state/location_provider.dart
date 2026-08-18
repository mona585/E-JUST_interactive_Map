import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/navigation_config.dart';
import '../data/datasources/gps_location_service.dart';
import '../data/datasources/location_service.dart';
import '../data/datasources/native_positioning_service.dart';
import '../data/models/position_estimate.dart';
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
/// and evaluating position source precedence.
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;
  final NativePositioningService _nativePositioningService;

  UserLocation? _gpsLocation;
  PositionEstimate? _latestIndoorEstimate;
  String? _activeIndoorBuid;
  String? _activeIndoorFloor;

  UserLocation? _currentLocation;
  LocationSource _positionSource = LocationSource.none;

  LocationStateStatus _status = LocationStateStatus.initial;
  String? _errorMessage;
  StreamSubscription<UserLocation>? _gpsSubscription;
  StreamSubscription<PositionEstimate>? _nativeSubscription;
  Timer? _indoorStaleTimer;
  int _indoorEstimateGeneration = 0;
  bool _isTracking = false;

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

  /// Current effective user location (either Indoor Wi-Fi or Outdoor GPS).
  UserLocation? get currentLocation => _currentLocation;

  /// Outdoor GPS location fix.
  UserLocation? get gpsLocation => _gpsLocation;

  /// Latest native Wi-Fi indoor position estimate.
  PositionEstimate? get latestIndoorEstimate => _latestIndoorEstimate;

  /// Active position source (`gps`, `indoorWifi`, or `none`).
  LocationSource get positionSource => _positionSource;

  /// Whether current effective position is driven by native Wi-Fi.
  bool get isIndoorWifiActive => _positionSource == LocationSource.indoorWifi;

  /// Current lifecycle status of location provider.
  LocationStateStatus get status => _status;

  /// Human-readable error or warning message, if any.
  String? get errorMessage => _errorMessage;

  /// Whether active GPS stream tracking is running.
  bool get isTracking => _isTracking;

  /// Whether a valid user location fix is available.
  bool get hasLocation => _currentLocation != null;

  void _subscribeNativePositionStream() {
    _nativeSubscription?.cancel();
    _nativeSubscription = _nativePositioningService.positionStream.listen(
      (estimate) {
        debugPrint(
          '[LocationProvider] Native position estimate received: $estimate',
        );
        _latestIndoorEstimate = estimate;

        // Feed stability window if estimate is valid and matches current floor
        if (estimate.isValid &&
            estimate.buid == _activeIndoorBuid &&
            estimate.floor == _activeIndoorFloor &&
            estimate.latitude != null &&
            estimate.longitude != null) {
          _stabilityWindow.add(_StabilityEntry(
            position: LatLng(estimate.latitude!, estimate.longitude!),
            timestamp: estimate.timestamp,
            matchedAps: estimate.matchedAps,
          ));
          _evaluateStability();
        }

        _scheduleIndoorStaleTimer();
        _evaluatePositionPolicy();
      },
      onError: (err) {
        debugPrint('[LocationProvider] Native position stream error: $err');
      },
    );
  }

  void _scheduleIndoorStaleTimer() {
    final estimate = _latestIndoorEstimate;
    if (estimate == null || !estimate.isValid) {
      _indoorStaleTimer?.cancel();
      _indoorStaleTimer = null;
      return;
    }

    _indoorStaleTimer?.cancel();
    final generation = ++_indoorEstimateGeneration;
    _indoorStaleTimer = Timer(const Duration(seconds: 10), () {
      if (generation != _indoorEstimateGeneration) {
        return;
      }

      if (_latestIndoorEstimate == estimate) {
        debugPrint(
          '[LocationProvider] Indoor estimate expired after 10s; clearing active Wi-Fi position',
        );
        _latestIndoorEstimate = null;
        _evaluatePositionPolicy();
      }
    });
  }

  /// Sets the currently active indoor building and floor scope.
  ///
  /// Must be called whenever the user selects or clears a floor.
  void setActiveIndoorFloor(String? buid, String? floor) {
    if (_activeIndoorBuid == buid && _activeIndoorFloor == floor) return;

    debugPrint(
      '[LocationProvider] setActiveIndoorFloor: ($buid, $floor) [was ($_activeIndoorBuid, $_activeIndoorFloor)]',
    );
    _activeIndoorBuid = buid;
    _activeIndoorFloor = floor;

    // Reset indoor estimate if floor changed or cleared
    if (buid == null || floor == null) {
      _latestIndoorEstimate = null;
      _indoorStaleTimer?.cancel();
      _indoorStaleTimer = null;
      _indoorEstimateGeneration++;
      _resetStability();
    } else {
      // Floor changed to a new value Ã¢â‚¬â€ reset stability for new floor
      _resetStability();
    }

    _evaluatePositionPolicy();
  }

  /// Evaluates position source precedence:
  ///
  /// 1. Indoor Wi-Fi wins IF valid estimate exists for current buid/floor AND < 10s old.
  /// 2. GPS fallback used otherwise.
  void _evaluatePositionPolicy() {
    final estimate = _latestIndoorEstimate;
    final isIndoorValid = estimate != null &&
        estimate.isValid &&
        estimate.buid == _activeIndoorBuid &&
        estimate.floor == _activeIndoorFloor;

    if (isIndoorValid) {
      _positionSource = LocationSource.indoorWifi;
      _currentLocation = UserLocation(
        latitude: estimate.latitude!,
        longitude: estimate.longitude!,
        accuracy: 3.0,
        timestamp: estimate.timestamp,
      );
    } else if (_gpsLocation != null) {
      _positionSource = LocationSource.gps;
      _currentLocation = _gpsLocation;
    } else {
      _positionSource = LocationSource.none;
      _currentLocation = null;
    }

    notifyListeners();
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
    if (_positioningStability == newStability) return;
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
    _status = LocationStateStatus.requesting;
    _errorMessage = null;
    notifyListeners();

    // 1. Check if location services are enabled
    final serviceEnabled = await _locationService.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _status = LocationStateStatus.serviceDisabled;
      _errorMessage = 'Location services are disabled. Please turn on GPS.';
      notifyListeners();
      return null;
    }

    // 2. Request permission
    final permStatus = await _locationService.requestPermission();
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
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        _gpsLocation = position;
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        startTracking();
        _evaluatePositionPolicy();
        return _currentLocation;
      } else {
        _status = LocationStateStatus.error;
        _errorMessage = 'Unable to acquire GPS signal. Please try again.';
        notifyListeners();
        return null;
      }
    } catch (e) {
      _status = LocationStateStatus.error;
      _errorMessage = 'Error acquiring GPS location: $e';
      notifyListeners();
      return null;
    }
  }

  /// Starts listening to real-time GPS location updates.
  void startTracking() {
    if (_isTracking) return;

    _gpsSubscription?.cancel();
    _isTracking = true;

    _gpsSubscription = _locationService.getPositionStream().listen(
      (location) {
        _gpsLocation = location;
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        _evaluatePositionPolicy();
      },
      onError: (error) {
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
  void setGpsLocation(UserLocation location) {
    _gpsLocation = location;
    _evaluatePositionPolicy();
  }

  /// Clears any transient error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _nativeSubscription?.cancel();
    _indoorStaleTimer?.cancel();
    super.dispose();
  }
}
