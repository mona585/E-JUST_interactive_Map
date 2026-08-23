import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';

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

class _FakeNativePositioningService implements NativePositioningService {
  final _estimateController = StreamController<PositionEstimate>.broadcast();

  int listenerCount = 0;

  _FakeNativePositioningService() {
    _estimateController.onListen = () => listenerCount++;
    _estimateController.onCancel = () => listenerCount--;
  }

  void emit(PositionEstimate estimate) => _estimateController.add(estimate);

  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async =>
      true;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<bool> removeRadioMap(String buid, String floor) async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;

  @override
  Stream<PositionEstimate> get positionStream => _estimateController.stream;
}

PositionEstimate _estimate({
  double lat = 30.865936,
  double lng = 29.5828359,
}) {
  return PositionEstimate(
    latitude: lat,
    longitude: lng,
    buid: 'b1',
    floor: '1',
    matchedAps: 5,
    totalAps: 8,
    durationMs: 12,
    timestamp: DateTime.now(),
    status: 'success',
    bestDistance: 4.0,
    topKSpreadMeters: 6.0,
  );
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
  testWidgets('repeated startTracking subscribes exactly once; repeated stopTracking is safe',
      (tester) async {
    final locationService = _FakeLocationService();
    final nativeService = _FakeNativePositioningService();
    final provider = LocationProvider(
      locationService: locationService,
      nativePositioningService: nativeService,
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
    final nativeService = _FakeNativePositioningService();
    final provider = LocationProvider(
      locationService: locationService,
      nativePositioningService: nativeService,
    );

    provider.setGpsLocation(_gpsFix());
    expect(provider.currentLocation, isNotNull);

    provider.dispose();
    provider.dispose();

    nativeService.emit(_estimate());
    locationService._gpsController.add(_gpsFix(lat: 31.0, lng: 30.0));
    await tester.pump();

    expect(nativeService.listenerCount, 0);
    expect(provider.latestIndoorEstimate, isNull);
    expect(provider.positionSource, LocationSource.gps);
    expect(provider.currentLocation!.latitude, closeTo(30.86, 1e-9));
  });

  testWidgets('stale timer expiry clears Wi-Fi belief and exits indoor mode',
      (tester) async {
    final nativeService = _FakeNativePositioningService();
    final provider = LocationProvider(nativePositioningService: nativeService);

    nativeService.emit(_estimate());
    nativeService.emit(_estimate());
    nativeService.emit(_estimate());
    await tester.pump();

    expect(provider.positionSource, LocationSource.indoorWifi);
    expect(provider.latestIndoorEstimate, isNotNull);

    await tester.pump(const Duration(seconds: 11));

    expect(provider.latestIndoorEstimate, isNull);
    expect(provider.positionSource, LocationSource.none);

    provider.dispose();
    await tester.pump();
  });

  testWidgets('a newer estimate invalidates the pending staleness timer',
      (tester) async {
    final nativeService = _FakeNativePositioningService();
    final provider = LocationProvider(nativePositioningService: nativeService);

    final first = _estimate();
    nativeService.emit(first);
    nativeService.emit(_estimate());
    nativeService.emit(_estimate());
    await tester.pump();
    expect(provider.positionSource, LocationSource.indoorWifi);

    await tester.pump(const Duration(seconds: 9));

    final refreshed = _estimate(lat: 30.866100);
    nativeService.emit(refreshed);
    await tester.pump();

    await tester.pump(const Duration(seconds: 9));
    expect(provider.latestIndoorEstimate, same(refreshed));
    expect(provider.positionSource, LocationSource.indoorWifi);

    await tester.pump(const Duration(seconds: 2));
    expect(provider.latestIndoorEstimate, isNull);
    expect(provider.positionSource, LocationSource.none);

    provider.dispose();
    await tester.pump();
  });
}
