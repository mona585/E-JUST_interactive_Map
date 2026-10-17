import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/datasources/location_service.dart';
import 'package:anyplace_campusfind/models/campus_asset_status.dart';
import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/route_segment.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/models/user_location.dart';
import 'package:anyplace_campusfind/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/repositories/space_repository.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ---------------------------------------------------------------------------
// CP-8 — SAME-BUILDING behavior under OUTDOOR-ONLY routing.
//
// Indoor routing has been removed: a request for a room in the building the
// user is already inside can only be honoured as an OUTDOOR leg that ends at
// the building's entrance. There is no interior leg anymore, so:
//
//  * when the user is effectively AT that building's entrance (the resolved
//    origin and destination entrances coincide), the request is refused with a
//    truthful message — never a fabricated interior route;
//  * when the building exposes a distinct destination entrance, the composed
//    journey is a single OUTDOOR segment between the two entrances — every
//    point is an outdoor (GPS) waypoint and NO indoor segment exists.
//
// The floor carries REAL server-style bounds so the canonical BuildingContainment
// service (which classifies UNKNOWN geometry as OUTSIDE, never fabricating
// "inside") recognizes the fix as being inside the building.
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

// Ground floor with real bounds that contain both the building center
// (30.86, _lng) and _indoorFix() (30.8605, _lng).
FloorModel _floor0() => FloorModel(
      buid: 'b1',
      floorNumber: '0',
      bottomLeftLat: 30.8580,
      bottomLeftLng: 29.5810,
      topRightLat: 30.8620,
      topRightLng: 29.5845,
    );

PoiModel _room() => PoiModel(
      puid: 'room-104',
      buid: 'b1',
      floorNumber: '0',
      name: 'Room 104',
      poisType: 'room',
      latitude: 30.8595,
      longitude: _lng,
    );

PoiModel _entrance(String puid, String name, double lat) => PoiModel(
      puid: puid,
      buid: 'b1',
      floorNumber: '0',
      name: name,
      poisType: 'Entrance',
      latitude: lat,
      longitude: _lng,
      isBuildingEntrance: true,
    );

/// A single entrance at 30.8600 — the user (30.8605) is right next to it.
List<PoiModel> _singleEntrancePois() => [
      _entrance('entr-1', 'Main Entrance', 30.8600),
      _room(),
    ];

/// Two entrances: entr-1 is nearest the user's fix, entr-2 is farther.
List<PoiModel> _twoEntrancePois() => [
      _entrance('entr-1', 'North Entrance', 30.8600),
      _entrance('entr-2', 'South Entrance', 30.8618),
      _room(),
    ];

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
  _FakePoiRepository(this.pois);

  final List<PoiModel> pois;

  @override
  Future<List<PoiModel>> getPoisByFloor(String buid, String floor,
          {bool forceReload = false}) async =>
      pois;

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

/// Outdoor-only navigation double (CP-8). Serves raw coordinate results for
/// the reroute path and optional OSRM metadata used by entrance selection and
/// the outdoor segment cascade. No indoor routing methods exist to stub.
class _RecordingNavRepo implements NavigationRepository {
  _RecordingNavRepo({this.metadata, this.outdoorPoints = const []});

  final OsrmRouteResult? Function(double toLat, double toLon)? metadata;
  final List<LatLng> outdoorPoints;

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      outdoorPoints;

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) async =>
      metadata?.call(toLat, toLon);
}

Future<SpaceViewModel> _seededProvider(
  _RecordingNavRepo navRepo, {
  required LocationViewModel locationProvider,
  required List<PoiModel> pois,
}) async {
  final provider = SpaceViewModel(
    repository: _FakeSpaceRepository(),
    poiRepository: _FakePoiRepository(pois),
    navigationRepository: navRepo,
  );
  provider.setLocationViewModel(locationProvider);
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

  testWidgets('same-building request at the destination entrance is refused '
      'with the truthful message and no fabricated interior route',
      (tester) async {
    final navRepo = _RecordingNavRepo();
    final locationProvider = LocationViewModel(
      locationService: _FakeGpsService(),
    );
    final provider = await _seededProvider(
      navRepo,
      locationProvider: locationProvider,
      pois: _singleEntrancePois(),
    );
    addTearDown(() {
      provider.dispose();
      locationProvider.dispose();
    });

    provider.selectPoi(_room());
    await provider.requestRouteToSelectedPoi();

    expect(provider.navigationRouteStatus, NavigationRouteStatus.error);
    expect(provider.activeNavigationRoute, isNull,
        reason: 'no honest outdoor route exists — nothing is committed');
    expect(provider.hasActiveNavigationRoute, isFalse);
    expect(
      provider.navigationRouteErrorMessage,
      contains('already at the Building One entrance'),
      reason: 'the failure must name the entrance policy honestly',
    );

    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('same-building request to a DISTINCT entrance composes an '
      'entrance-to-entrance OUTDOOR-only segment', (tester) async {
    final navRepo = _RecordingNavRepo(
      outdoorPoints: const [LatLng(30.8600, _lng), LatLng(30.8618, _lng)],
      metadata: (toLat, toLon) {
        if ((toLat - 30.8618).abs() < 1e-6) {
          return const OsrmRouteResult(
            points: [LatLng(30.8600, _lng), LatLng(30.8618, _lng)],
            distanceMeters: 50,
            durationSeconds: 40,
            finalBearingDegrees: 0,
          );
        }
        return const OsrmRouteResult(
          points: [LatLng(30.8600, _lng), LatLng(30.8600, _lng)],
          distanceMeters: 300,
          durationSeconds: 240,
          finalBearingDegrees: 0,
        );
      },
    );
    final locationProvider = LocationViewModel(
      locationService: _FakeGpsService(),
    );
    final provider = await _seededProvider(
      navRepo,
      locationProvider: locationProvider,
      pois: _twoEntrancePois(),
    );
    addTearDown(() {
      provider.dispose();
      locationProvider.dispose();
    });

    provider.selectPoi(_room());
    await provider.requestRouteToSelectedPoi();

    expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
    final route = provider.activeNavigationRoute!;
    expect(route.hasSegments, isTrue,
        reason: 'outdoor-only composition still uses the segment model');

    // A single OUTDOOR leg between the two entrances — no indoor segment.
    expect(route.segments.single.type, RouteSegmentType.outdoorWalking);
    expect(route.segments.single.buildingId, 'b1');
    expect(
      route.segments.every((s) => s.type != RouteSegmentType.indoorRouting),
      isTrue,
      reason: 'CP-8: indoor routing is gone; no indoor segment may appear',
    );
    expect(route.hasIndoorSegment, isFalse);

    // Every rendered point is an outdoor (identity-free) waypoint.
    expect(route.points, isNotEmpty);
    expect(route.points.every((p) => p.isOutdoor), isTrue,
        reason: 'all geometry is outdoor GPS waypoints');
    expect(route.indoorPolylinePoints, isEmpty);
    expect(route.outdoorPolylinePoints.length, greaterThanOrEqualTo(2));

    // Geometry runs from the origin entrance to the destination entrance.
    expect(route.outdoorPolylinePoints.first,
        const LatLng(30.8600, _lng));
    expect(route.outdoorPolylinePoints.last,
        const LatLng(30.8618, _lng));

    await tester.pump(const Duration(seconds: 11));
  });
}
