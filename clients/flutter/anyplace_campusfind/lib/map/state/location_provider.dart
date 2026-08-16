import 'dart:async';
import 'package:flutter/foundation.dart';

import '../data/gps_location_service.dart';
import '../data/location_service.dart';
import '../models/user_location.dart';

/// Status of the device GPS location provider.
enum LocationStateStatus {
  /// Initial state before any location request.
  initial,

  /// Location is being requested/resolved.
  requesting,

  /// Actively receiving GPS location updates.
  tracking,

  /// Location permission was denied by the user.
  permissionDenied,

  /// Location permission was permanently denied.
  permissionDeniedForever,

  /// Device GPS hardware / location services are turned off.
  serviceDisabled,

  /// An error occurred while acquiring location.
  error,
}

/// Provider managing outdoor device GPS position and real-time tracking stream.
class LocationProvider extends ChangeNotifier {
  final LocationService _locationService;

  UserLocation? _currentLocation;
  LocationStateStatus _status = LocationStateStatus.initial;
  String? _errorMessage;
  StreamSubscription<UserLocation>? _positionSubscription;
  bool _isTracking = false;

  LocationProvider({LocationService? locationService})
      : _locationService = locationService ?? GpsLocationService();

  /// Current user GPS location.
  UserLocation? get currentLocation => _currentLocation;

  /// Current lifecycle status of location provider.
  LocationStateStatus get status => _status;

  /// Human-readable error or warning message, if any.
  String? get errorMessage => _errorMessage;

  /// Whether active stream tracking is running.
  bool get isTracking => _isTracking;

  /// Whether a valid GPS location fix has been acquired.
  bool get hasLocation => _currentLocation != null;

  /// Requests permission, acquires current GPS position, and begins live tracking.
  ///
  /// Returns the acquired [UserLocation], or `null` if permission was denied or
  /// GPS is unavailable.
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

    // 3. Obtain current position
    try {
      final position = await _locationService.getCurrentPosition();
      if (position != null) {
        _currentLocation = position;
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        startTracking();
        notifyListeners();
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

    _positionSubscription?.cancel();
    _isTracking = true;

    _positionSubscription = _locationService.getPositionStream().listen(
      (location) {
        _currentLocation = location;
        _status = LocationStateStatus.tracking;
        _errorMessage = null;
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'GPS tracking error: $error';
        notifyListeners();
      },
    );
  }

  /// Stops listening to GPS updates.
  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Clears any transient error message.
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }
}