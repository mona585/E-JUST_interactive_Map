import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/theme.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/position_estimate.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';

// ---------------------------------------------------------------------------
// FAILURE #2 regression — SAME-BUILDING indoor navigation.
//
// A user already inside the destination building who requests a room in the
// SAME building must receive the segmented indoorRouting representation
// (the unified indoor navigation style), NOT the legacy rendering path —
// even though CrossBuildingRouter.composeRoute is deliberately skipped for
// the same-building scenario.
//
// Geometry is never fabricated: the wrapped segments carry the server route's
// exact coordinates and per-point floors.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

UserLocation _indoorFix() => UserLocation(
      latitude: 30.8605,
      longitude: _lng,
      accuracy: 12.0,
      timestamp: DateTime.now(),
    );

SpaceModel _building() => SpaceModel(
      buid: 'b1',
      name: 'Building One',
      latitude: 30.86,
      longitude: _lng,
    );

FloorModel _floor0() => FloorModel(buid: 'b1', floorNumber: '0');

PoiModel _room() => PoiModel(
      puid: 'room-104',
      buid: 'b1',
      floorNumber: '0',
      name: 'Room 104',
      poisType: 'room',
      latitude: 30.8595,
      longitude: _lng,
    );

List<PoiModel> _floorPois() => [
      PoiModel(
        puid: 'entr-1',
        buid: 'b1',
        floorNumber: '0',
        name: 'Main Entrance',
        poisType: 'Entrance',
        latitude: 30.8600,
        longitude: _lng,
        isBuildingEntrance: true,
      ),
      PoiModel(
        puid: 'conn-1',
        buid: 'b1',
        floorNumber: '0',
        name: 'Hallway node',
        poisType: 'None',
        latitude: 30.8599,
        longitude: _lng,
      ),
      _room(),
    ];

/// The legacy shape Strategy 1/2 historically committed verbatim: raw server
/// waypoints with real puids and per-point floors, no segment metadata.
NavigationRouteModel _legacyIndoorRoute() => NavigationRouteModel(points: [
      NavigationRoutePoint(
          latitude: 30.8602,
          longitude: _lng,
          puid: 'conn-1',
          buid: 'b1',
          floorNumber: '0',
          poisType: 'None'),
      NavigationRoutePoint(
          latitude: 30.8597,
          longitude: _lng,
          puid: 'conn-2',
          buid: 'b1',
          floorNumber: '0',
          poisType: 'None'),
      NavigationRoutePoint(
          latitude: 30.8595,
          longitude: _lng,
          puid: 'room-104',
          buid: 'b1',
          floorNumber: '0',
          poisType: 'room'),
    ]);

class _FakeGpsService implements LocationService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.granted;
  @override
  Future<UserLocation?> getCurrentPosition() async => _indoorFix();
  @override
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3}) =>
      const Stream.empty();
}

class _FakeSpaceRepository implements SpaceRepository {
  final spaces = [_building()];
  final floors = [_floor0()];

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      spaces;

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      spaces.where((s) => s.buid == buid).firstOrNull;

  @override
  Future<List<FloorModel>> getFloorsByBuid(String buid,
          {bool forceReload = false}) async =>
      floors;
}

class _FakePoiRepository implements PoiRepository {
  @override
  Future<List<PoiModel>> getPoisByFloor(String buid, String floor,
          {bool forceReload = false}) async =>
      _floorPois();

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor,
          {bool forceReload = false}) async =>
      '';

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
  }) async =>
      null;

  @override
  Future<bool> isFloorplanCached(String buid, String floor) async => false;

  @override
  Future<void> clearFloorplan(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _RecordingNavRepo implements NavigationRepository {
  NavigationRouteModel? servedFromCoords;
  NavigationRouteModel? servedBetweenPois;
  bool throwOnCoords = false;
  final coordCalls = <String?>[];

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async {
    if (servedBetweenPois == null) {
      throw ApiException('no route found', statusCode: 400);
    }
    return servedBetweenPois!;
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    String? floorNumber,
    required String destinationPuid,
  }) async {
    coordCalls.add(floorNumber);
    if (throwOnCoords || servedFromCoords == null) {
      throw ApiException('Navigation is not supported on your floor.',
          statusCode: 400);
    }
    return servedFromCoords!;
  }
}

class _FakeNativePositioningService implements NativePositioningService {
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
  Stream<PositionEstimate> get positionStream => const Stream.empty();
}

Future<SpaceProvider> _seededProvider(_RecordingNavRepo navRepo,
    {required LocationProvider locationProvider}) async {
  final provider = SpaceProvider(
    repository: _FakeSpaceRepository(),
    poiRepository: _FakePoiRepository(),
    radioMapRepository: _FakeRadioMapRepository(),
    floorplanRepository: _FakeFloorplanRepository(),
    navigationRepository: navRepo,
    nativePositioningService: _FakeNativePositioningService(),
  );
  provider.setLocationProvider(locationProvider);
  locationProvider.setGpsLocation(_indoorFix());

  await provider.loadSpaces();
  provider.selectSpace(provider.spaces.first);
  await provider.loadFloorsForSelectedSpace();
  provider.selectFloor(provider.floors.first);
  await provider.loadPoisForSelectedFloor();
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CASE B / Strategy 1: same-building Route Here commits a '
      'segmented indoorRouting route with untouched geometry and the '
      'unified indoor style', (tester) async {
    final navRepo = _RecordingNavRepo()..servedFromCoords = _legacyIndoorRoute();
    final locationProvider = LocationProvider(
      locationService: _FakeGpsService(),
      nativePositioningService: _FakeNativePositioningService(),
    );
    final provider =
        await _seededProvider(navRepo, locationProvider: locationProvider);
    addTearDown(() {
      provider.dispose();
      locationProvider.dispose();
    });

    provider.selectPoi(_room());
    await provider.requestRouteToSelectedPoi();

    expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
    final route = provider.activeNavigationRoute!;
    expect(route.hasSegments, isTrue,
        reason: 'same-building indoor routes must leave the legacy path');

    final seg = route.segments.single;
    expect(seg.type, RouteSegmentType.indoorRouting);
    expect(seg.buildingId, 'b1');
    expect(seg.floorNumber, '0');
    // Geometry verbatim: every server coordinate survives the wrap.
    expect(route.polylinePoints, _legacyIndoorRoute().polylinePoints);
    // Per-point floors preserved truthfully.
    expect(
        route.points.map((p) => p.floorNumber).toList(), ['0', '0', '0']);
    // Status semantics unchanged.
    expect(route.status, RouteModelStatus.ready);

    // Rendering: exactly one spec, in the intended indoor style — identical
    // to the cross-building destination leg's style.
    final specs = routePolylineSpecs(
        route: route, displayedFloor: '0', indoorEmphasis: true);
    expect(specs.length, 1);
    expect(specs.single.id, 'route_segment_0');
    expect(specs.single.color, AppTheme.primary.withValues(alpha: 0.85));
    expect(specs.single.width, 6);
    expect(specs.single.patterns ?? const [], isEmpty);

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('CASE B / Strategy 2 fallback: when coordinate routing is '
      'unsupported, POI-to-POI results commit the same representation',
      (tester) async {
    final navRepo = _RecordingNavRepo()
      ..throwOnCoords = true
      ..servedBetweenPois = _legacyIndoorRoute();
    final locationProvider = LocationProvider(
      locationService: _FakeGpsService(),
      nativePositioningService: _FakeNativePositioningService(),
    );
    final provider =
        await _seededProvider(navRepo, locationProvider: locationProvider);
    addTearDown(() {
      provider.dispose();
      locationProvider.dispose();
    });

    provider.selectPoi(_room());
    await provider.requestRouteToSelectedPoi();

    expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
    final route = provider.activeNavigationRoute!;
    expect(route.hasSegments, isTrue);
    expect(route.segments.single.type, RouteSegmentType.indoorRouting);
    expect(route.polylinePoints, _legacyIndoorRoute().polylinePoints);

    await tester.pump(const Duration(seconds: 11));
  });
}
