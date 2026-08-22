import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
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
    debugPrint('[GpsLocationService] getCurrentPosition: permission=$status');
    if (status != LocationPermissionStatus.granted) {
      return null;
    }

    try {
      debugPrint('[GpsLocationService] Calling Geolocator.getCurrentPosition...');
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      debugPrint('[GpsLocationService] Got position: ${position.latitude},${position.longitude}');
      return _toUserLocation(position);
    } catch (e) {
      debugPrint('[GpsLocationService] getCurrentPosition failed: $e');
      // Fall back to last known position if current position times out
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        debugPrint('[GpsLocationService] Last known: ${lastKnown != null ? "${lastKnown.latitude},${lastKnown.longitude}" : "null"}');
        if (lastKnown != null) {
          return _toUserLocation(lastKnown);
        }
      } catch (e2) {
        debugPrint('[GpsLocationService] getLastKnownPosition also failed: $e2');
      }
      return null;
    }
  }

  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) {
    // Navigation-grade settings: deliver meaningful fixes as soon as the OS
    // produces them, with a 500 ms minimum interval on Android so the
    // provider — not a tight loop — controls fix frequency.
    //
    // Platform limitation: geolocator's Dart API types distanceFilter as int,
    // so sub-meter filters (e.g. 0.3 m) cannot be expressed directly. A value
    // < 1 is mapped to 0, which disables the displacement gate on Android and
    // lets the fused provider + interval decide when a new fix is meaningful.
    final effectiveFilter =
        distanceFilter < 1 ? 0 : distanceFilter.round();

    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: effectiveFilter,
            intervalDuration: const Duration(milliseconds: 500),
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: effectiveFilter,
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
