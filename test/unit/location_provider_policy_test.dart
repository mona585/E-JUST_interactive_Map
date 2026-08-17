import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

class MockLocationService implements LocationService {
  UserLocation? fixedPosition;

  MockLocationService({this.fixedPosition});

  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> checkPermission() async => LocationPermissionStatus.granted;
  @override
  Future<LocationPermissionStatus> requestPermission() async => LocationPermissionStatus.granted;
  @override
  Future<UserLocation?> getCurrentPosition() async => fixedPosition;
  @override
  Stream<UserLocation> getPositionStream({int distanceFilter = 2}) =>
      const Stream.empty();
}

class MockNativePositioningService implements NativePositioningService {
  final StreamController<PositionEstimate> controller =
      StreamController<PositionEstimate>.broadcast();

  @override
  Stream<PositionEstimate> get positionStream => controller.stream;

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async => true;
  @override
  Future<bool> clearRadioMap() async => true;
  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  void emitEstimate(PositionEstimate estimate) {
    controller.add(estimate);
  }
}

void main() {
  final gpsPos = UserLocation(
    latitude: 35.1440,
    longitude: 33.4100,
    accuracy: 4.0,
    timestamp: DateTime.now(),
  );

  late MockLocationService mockGps;
  late MockNativePositioningService mockNative;
  late LocationProvider provider;

  setUp(() {
    mockGps = MockLocationService(fixedPosition: gpsPos);
    mockNative = MockNativePositioningService();
    provider = LocationProvider(
      locationService: mockGps,
      nativePositioningService: mockNative,
    );
  });

  tearDown(() {
    provider.dispose();
  });

  group('LocationProvider Position Policy', () {
    test('GPS fix sets position source to GPS initially', () async {
      await provider.requestAndCenter();

      expect(provider.positionSource, LocationSource.gps);
      expect(provider.currentLocation?.latitude, 35.1440);
      expect(provider.isIndoorWifiActive, isFalse);
    });

    test('Valid indoor estimate for active floor overrides GPS position', () async {
      await provider.requestAndCenter();
      expect(provider.positionSource, LocationSource.gps);

      // Select B7 / Floor 0
      provider.setActiveIndoorFloor('buid_B7', '0');

      // Emit valid native indoor estimate
      final validEst = PositionEstimate(
        latitude: 30.859418,
        longitude: 29.562789,
        buid: 'buid_B7',
        floor: '0',
        matchedAps: 6,
        totalAps: 12,
        durationMs: 10,
        timestamp: DateTime.now(),
        status: 'success',
      );
      mockNative.emitEstimate(validEst);
      await Future<void>.delayed(Duration.zero);

      expect(provider.positionSource, LocationSource.indoorWifi);
      expect(provider.isIndoorWifiActive, isTrue);
      expect(provider.currentLocation?.latitude, closeTo(30.859418, 0.000001));
      expect(provider.currentLocation?.longitude, closeTo(29.562789, 0.000001));
    });

    test('Indoor estimate for DIFFERENT floor/building is ignored and retains GPS',
        () async {
      await provider.requestAndCenter();

      // Active floor is B7 / Floor 0
      provider.setActiveIndoorFloor('buid_B7', '0');

      // Emit estimate for B7 / Floor 1 (mismatched floor)
      final mismatchedEst = PositionEstimate(
        latitude: 30.8599,
        longitude: 29.5630,
        buid: 'buid_B7',
        floor: '1',
        matchedAps: 8,
        totalAps: 12,
        durationMs: 10,
        timestamp: DateTime.now(),
        status: 'success',
      );
      mockNative.emitEstimate(mismatchedEst);
      await Future<void>.delayed(Duration.zero);

      // Position must remain GPS
      expect(provider.positionSource, LocationSource.gps);
      expect(provider.currentLocation?.latitude, 35.1440);
    });

    test('Clearing active floor immediately reverts position source to GPS',
        () async {
      await provider.requestAndCenter();
      provider.setActiveIndoorFloor('buid_B7', '0');

      final validEst = PositionEstimate(
        latitude: 30.859418,
        longitude: 29.562789,
        buid: 'buid_B7',
        floor: '0',
        matchedAps: 6,
        totalAps: 12,
        durationMs: 10,
        timestamp: DateTime.now(),
        status: 'success',
      );
      mockNative.emitEstimate(validEst);
      await Future<void>.delayed(Duration.zero);
      expect(provider.positionSource, LocationSource.indoorWifi);

      // Clear floor selection
      provider.setActiveIndoorFloor(null, null);

      expect(provider.positionSource, LocationSource.gps);
      expect(provider.isIndoorWifiActive, isFalse);
      expect(provider.currentLocation?.latitude, 35.1440);
    });

    test('Invalid native estimate (0 matched APs) is rejected and retains GPS',
        () async {
      await provider.requestAndCenter();
      provider.setActiveIndoorFloor('buid_B7', '0');

      final invalidEst = PositionEstimate(
        latitude: 30.859418,
        longitude: 29.562789,
        buid: 'buid_B7',
        floor: '0',
        matchedAps: 0, // Invalid 0 matched APs
        totalAps: 12,
        durationMs: 5,
        timestamp: DateTime.now(),
        status: 'no_match',
      );
      mockNative.emitEstimate(invalidEst);
      await Future<void>.delayed(Duration.zero);

      expect(provider.positionSource, LocationSource.gps);
      expect(provider.currentLocation?.latitude, 35.1440);
    });
  });
}
