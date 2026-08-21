import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../models/user_location.dart';
import 'location_service.dart';

/// Concrete implementation of [LocationService] using Android/iOS GPS via [Geolocator].
class GpsLocationService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    try {
      final permission = await Geolocator.checkPermission();
      return _mapPermission(permission);
    } catch (_) {
      return LocationPermissionStatus.denied;
    }
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      return LocationPermissionStatus.serviceDisabled;
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return _mapPermission(permission);
    } catch (_) {
      return LocationPermissionStatus.denied;
    }
  }

  @override
  Future<UserLocation?> getCurrentPosition() async {
    final status = await checkPermission();
    if (status != LocationPermissionStatus.granted) {
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return _toUserLocation(position);
    } catch (_) {
      // Fall back to last known position if current position times out
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          return _toUserLocation(lastKnown);
        }
      } catch (_) {}
      return null;
    }
  }

  @override
  Stream<UserLocation> getPositionStream({int distanceFilter = 2}) {
    final locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings)
        .map(_toUserLocation);
  }

  LocationPermissionStatus _mapPermission(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionStatus.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionStatus.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionStatus.denied;
    }
  }

  UserLocation _toUserLocation(Position pos) {
    return UserLocation(
      latitude: pos.latitude,
      longitude: pos.longitude,
      accuracy: pos.accuracy,
      altitude: pos.altitude,
      heading: pos.heading,
      speed: pos.speed,
      timestamp: pos.timestamp,
    );
  }
}
