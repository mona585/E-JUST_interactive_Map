import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

class _FakeSpaceRepository implements SpaceRepository {
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      const [];

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => null;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async => const [];
}

class _FakePoiRepository implements PoiRepository {
  final List<PoiModel> pois;

  _FakePoiRepository(this.pois);

  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async => pois;

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeNavigationRepository implements NavigationRepository {
  NavigationRouteModel routeToReturn = const NavigationRouteModel(points: []);

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async => routeToReturn;

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
  }) async => routeToReturn;
}

class _FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async => '';

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class _FakeFloorplanRepository implements FloorplanRepository {
  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async => null;

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;

  @override
  Future<void> clearFloorplan(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeNativePositioningService implements NativePositioningService {
  final controller = StreamController<PositionEstimate>.broadcast();

  @override
  Stream<PositionEstimate> get positionStream => controller.stream;

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async =>
      true;

  @override
  Future<bool> clearRadioMap() async => true;

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

class _FakeLocationService implements LocationService {
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
  Stream<UserLocation> getPositionStream({int distanceFilter = 2}) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const selectedSpace = SpaceModel(
    buid: 'buid_1',
    name: 'Building One',
    latitude: 35.1,
    longitude: 33.1,
  );
  const selectedFloor = FloorModel(
    buid: 'buid_1',
    floorNumber: '1',
    floorName: 'First',
  );
  const selectedPoi = PoiModel(
    puid: 'poi_1',
    buid: 'buid_1',
    floorNumber: '1',
    name: 'Lab 101',
    poisType: 'Room',
    latitude: 35.1002,
    longitude: 33.1002,
  );

  group('SpaceProvider navigation', () {
    late _FakeNativePositioningService nativeService;
    late LocationProvider locationProvider;
    late _FakeNavigationRepository navigationRepository;
    late SpaceProvider provider;

    setUp(() {
      nativeService = _FakeNativePositioningService();
      locationProvider = LocationProvider(
        locationService: _FakeLocationService(),
        nativePositioningService: nativeService,
      );
      navigationRepository = _FakeNavigationRepository()
        ..routeToReturn = const NavigationRouteModel(
          points: [
            NavigationRoutePoint(
              latitude: 35.1000,
              longitude: 33.1000,
              puid: 'start',
              buid: 'buid_1',
              floorNumber: '1',
              poisType: 'None',
            ),
            NavigationRoutePoint(
              latitude: 35.1002,
              longitude: 33.1002,
              puid: 'poi_1',
              buid: 'buid_1',
              floorNumber: '1',
              poisType: 'Room',
            ),
          ],
        );
      provider = SpaceProvider(
        repository: _FakeSpaceRepository(),
        radioMapRepository: _FakeRadioMapRepository(),
        floorplanRepository: _FakeFloorplanRepository(),
        poiRepository: _FakePoiRepository(const [selectedPoi]),
        navigationRepository: navigationRepository,
        nativePositioningService: nativeService,
        locationProvider: locationProvider,
      );
      provider.selectSpace(selectedSpace);
      provider.selectFloor(selectedFloor);
      provider.selectPoi(selectedPoi);
    });

    test(
      'requestRouteToSelectedPoi succeeds with an active indoor estimate',
      () async {
        locationProvider.setGpsLocation(
          UserLocation(
            latitude: 35.1000,
            longitude: 33.1000,
            timestamp: DateTime(2026, 8, 16, 12),
          ),
        );
        locationProvider.setActiveIndoorFloor('buid_1', '1');
        nativeService.controller.add(
          PositionEstimate(
            latitude: 35.1000,
            longitude: 33.1000,
            buid: 'buid_1',
            floor: '1',
            matchedAps: 6,
            totalAps: 8,
            durationMs: 10,
            timestamp: DateTime(2026, 8, 16, 12),
            status: 'success',
          ),
        );
        await pumpEventQueue();

        await provider.requestRouteToSelectedPoi();

        expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
        expect(provider.hasActiveNavigationRoute, isTrue);
        expect(provider.activeNavigationRoute?.points.length, 2);
      },
    );

    test(
      'requestRouteToSelectedPoi succeeds with GPS fallback when indoor Wi-Fi is inactive',
      () async {
        locationProvider.setGpsLocation(
          UserLocation(
            latitude: 35.1000,
            longitude: 33.1000,
            timestamp: DateTime(2026, 8, 16, 12),
          ),
        );

        await provider.requestRouteToSelectedPoi();

        expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
        expect(provider.hasActiveNavigationRoute, isTrue);
        expect(provider.activeNavigationRoute?.points.length, 2);
      },
    );

  });
}
