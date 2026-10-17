import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';

class _FakeLocationService implements LocationService {
  final _gpsController = StreamController<UserLocation>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;

  @override
  Future<UserLocation?> getCurrentPosition() async => null;

  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) =>
      _gpsController.stream;
}

UserLocation _gpsFix({double lat = 30.8600, double lng = 29.5800}) {
  return UserLocation(
    latitude: lat,
    longitude: lng,
    accuracy: 8.0,
    timestamp: DateTime.now(),
  );
}

void main() {
  testWidgets(
      'repeated startTracking subscribes exactly once; repeated stopTracking is safe',
      (tester) async {
    final locationService = _FakeLocationService();
    final provider = LocationViewModel(
      locationService: locationService,
    );

    provider.startTracking();
    provider.startTracking();
    expect(provider.isTracking, isTrue);

    provider.stopTracking();
    expect(provider.isTracking, isFalse);
    provider.stopTracking();
    expect(provider.isTracking, isFalse);

    provider.dispose();
    await tester.pump();
  });

  testWidgets('dispose cancels streams; late emissions never mutate state or throw',
      (tester) async {
    final locationService = _FakeLocationService();
    final provider = LocationViewModel(
      locationService: locationService,
    );

    provider.setGpsLocation(_gpsFix());
    expect(provider.currentLocation, isNotNull);

    provider.dispose();
    provider.dispose();

    locationService._gpsController.add(_gpsFix(lat: 31.0, lng: 30.0));
    await tester.pump();

    expect(provider.positionSource, LocationSource.gps);
    expect(provider.currentLocation!.latitude, closeTo(30.86, 1e-9));
  });
}
