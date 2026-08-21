import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

class FakeLocationService implements LocationService {
  bool serviceEnabled = true;
  LocationPermissionStatus permissionStatus = LocationPermissionStatus.granted;
  UserLocation? fixedPosition;
  final StreamController<UserLocation> _streamController =
      StreamController<UserLocation>.broadcast();

  FakeLocationService({this.fixedPosition});

  void emitLocation(UserLocation loc) {
    _streamController.add(loc);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permissionStatus;

  @override
  Future<LocationPermissionStatus> requestPermission() async => permissionStatus;

  @override
  Future<UserLocation?> getCurrentPosition() async => fixedPosition;

  @override
  Stream<UserLocation> getPositionStream({int distanceFilter = 2}) =>
      _streamController.stream;
}

void main() {
  final testLocation = UserLocation(
    latitude: 35.1444,
    longitude: 33.4105,
    accuracy: 5.0,
    timestamp: DateTime(2026, 8, 15, 12, 0, 0),
  );

  group('LocationProvider Unit Tests', () {
    test('initial state is correct', () {
      final service = FakeLocationService();
      final provider = LocationProvider(locationService: service);

      expect(provider.status, LocationStateStatus.initial);
      expect(provider.currentLocation, isNull);
      expect(provider.hasLocation, isFalse);
      expect(provider.isTracking, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('requestAndCenter succeeds when service enabled and permission granted',
        () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      final provider = LocationProvider(locationService: service);

      final result = await provider.requestAndCenter();

      expect(result, equals(testLocation));
      expect(provider.currentLocation, equals(testLocation));
      expect(provider.hasLocation, isTrue);
      expect(provider.status, LocationStateStatus.tracking);
      expect(provider.isTracking, isTrue);
      expect(provider.errorMessage, isNull);
    });

    test('requestAndCenter handles disabled location service gracefully',
        () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      service.serviceEnabled = false;
      final provider = LocationProvider(locationService: service);

      final result = await provider.requestAndCenter();

      expect(result, isNull);
      expect(provider.currentLocation, isNull);
      expect(provider.hasLocation, isFalse);
      expect(provider.status, LocationStateStatus.serviceDisabled);
      expect(provider.errorMessage, contains('Location services are disabled'));
    });

    test('requestAndCenter handles denied permission gracefully', () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      service.permissionStatus = LocationPermissionStatus.denied;
      final provider = LocationProvider(locationService: service);

      final result = await provider.requestAndCenter();

      expect(result, isNull);
      expect(provider.currentLocation, isNull);
      expect(provider.status, LocationStateStatus.permissionDenied);
      expect(provider.errorMessage, contains('Location permission was denied'));
    });

    test('requestAndCenter handles permanently denied permission gracefully',
        () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      service.permissionStatus = LocationPermissionStatus.deniedForever;
      final provider = LocationProvider(locationService: service);

      final result = await provider.requestAndCenter();

      expect(result, isNull);
      expect(provider.currentLocation, isNull);
      expect(provider.status, LocationStateStatus.permissionDeniedForever);
      expect(provider.errorMessage, contains('permanently denied'));
    });

    test('stream updates currentLocation and notifies listeners', () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      final provider = LocationProvider(locationService: service);

      await provider.requestAndCenter();
      expect(provider.currentLocation, equals(testLocation));

      final updatedLocation = UserLocation(
        latitude: 35.1450,
        longitude: 33.4110,
        accuracy: 3.0,
        timestamp: DateTime(2026, 8, 15, 12, 1, 0),
      );

      service.emitLocation(updatedLocation);
      await pumpEventQueue();

      expect(provider.currentLocation, equals(updatedLocation));
      expect(provider.status, LocationStateStatus.tracking);
    });

    test('stopTracking cancels active stream subscription', () async {
      final service = FakeLocationService(fixedPosition: testLocation);
      final provider = LocationProvider(locationService: service);

      await provider.requestAndCenter();
      expect(provider.isTracking, isTrue);

      provider.stopTracking();
      expect(provider.isTracking, isFalse);
    });
  });
}
