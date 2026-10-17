import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart' as provider;

import 'package:anyplace_campusfind/datasources/gps_location_service.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/providers/directions_provider.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/map_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/search_overlay_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/widgets/map_top_bar.dart';

// Regression coverage for the three targeted fixes:
//   1. the initial campus-overview camera is centered on the VERIFIED E-JUST
//      campus centroid (mean of the live buildings) rather than the geometric
//      center of the provided DMS bounding box;
//   2. the visible map search hint refers to buildings only;
//   3. the From field can select a building whose verified coordinates become
//      the ACTUAL outdoor routing origin (never a silent GPS fallback).

SpaceModel _space(String name, String buid, double lat, double lng) =>
    SpaceModel(
      buid: buid,
      name: name,
      latitude: lat,
      longitude: lng,
      spaceType: 'building',
    );

PoiModel _poi(String name, String puid, String buid) => PoiModel(
  puid: puid,
  buid: buid,
  floorNumber: '0',
  name: name,
  poisType: 'room',
  latitude: 30.8601,
  longitude: 29.5601,
);

/// Records the routing entry points [executeDirections] actually invokes,
/// including the custom-origin override threaded through from the From field.
class _RecordingSpaceViewModel extends SpaceViewModel {
  SpaceModel? routedBuilding;
  LatLng? buildingOrigin;
  PoiModel? navigatedPoi;
  LatLng? poiOrigin;

  @override
  Future<void> requestRouteToBuilding(
    SpaceModel targetSpace, {
    LatLng? originOverride,
  }) async {
    routedBuilding = targetSpace;
    buildingOrigin = originOverride;
  }

  @override
  Future<void> requestRouteToSelectedPoi({LatLng? originOverride}) async {
    poiOrigin = originOverride;
  }

  @override
  Future<bool> navigateToPoi(PoiModel targetPoi) async {
    navigatedPoi = targetPoi;
    return true;
  }
}

/// A [SpaceViewModel] with a pre-selected building, so `isCampusOverview`
/// reports false without touching the network / asset loaders.
class _SelectedSpaceViewModel extends _RecordingSpaceViewModel {
  _SelectedSpaceViewModel(this._selected);

  final SpaceModel _selected;

  @override
  SpaceModel? get selectedSpace => _selected;
}

void main() {
  group('initial campus-overview camera target', () {
    test('uses the SUPPLIED campus boundary rectangle, not the building '
        'centroid', () {
      final space = _RecordingSpaceViewModel();
      final location = LocationViewModel(locationService: GpsLocationService());
      final nav = NavigationViewModel(
        spaceProvider: space,
        locationProvider: location,
      );
      final vm = MapViewModel(
        spaceProvider: space,
        locationProvider: location,
        navigationController: nav,
      );

      // Overview (nothing selected, no active session).
      expect(vm.isCampusOverview, isTrue);

      // Authoritative target: the supplied boundary rectangle's centre.
      expect(vm.campusCenter.latitude, closeTo(30.8591015, 1e-6));
      expect(vm.campusCenter.longitude, closeTo(29.564043, 1e-6));
      expect(vm.initialCameraTarget.latitude, closeTo(30.8591015, 1e-6));
      expect(vm.initialCameraTarget.longitude, closeTo(29.564043, 1e-6));

      // It must NOT be the centroid of the (incomplete) live buildings.
      expect(
        vm.campusCenter.latitude,
        isNot(closeTo(SpaceViewModel.defaultCenter.latitude, 1e-5)),
      );
      expect(
        vm.campusCenter.longitude,
        isNot(closeTo(SpaceViewModel.defaultCenter.longitude, 1e-5)),
      );

      // Bounds ARE the supplied extrema (framing source, unchanged semantics).
      expect(vm.campusBounds.southwest.latitude, closeTo(30.855703, 1e-9));
      expect(vm.campusBounds.northeast.latitude, closeTo(30.862500, 1e-9));
      expect(vm.campusBounds.southwest.longitude, closeTo(29.560721, 1e-9));
      expect(vm.campusBounds.northeast.longitude, closeTo(29.567365, 1e-9));

      nav.dispose();
      location.dispose();
      space.dispose();
    });

    test('non-overview initial target is unchanged (selection wins)', () {
      final selected = _space('Selected Hall', 'b-sel', 30.8650, 29.5700);
      final space = _SelectedSpaceViewModel(selected);
      final location = LocationViewModel(locationService: GpsLocationService());
      final nav = NavigationViewModel(
        spaceProvider: space,
        locationProvider: location,
      );
      final vm = MapViewModel(
        spaceProvider: space,
        locationProvider: location,
        navigationController: nav,
      );

      expect(vm.isCampusOverview, isFalse);
      // Outside the overview the campus boundary centre is NOT used.
      expect(vm.initialCameraTarget.latitude, closeTo(30.8650, 1e-9));
      expect(vm.initialCameraTarget.longitude, closeTo(29.5700, 1e-9));

      nav.dispose();
      location.dispose();
      space.dispose();
    });
  });

  group('visible map search hint', () {
    testWidgets('refers to buildings only', (tester) async {
      final space = _RecordingSpaceViewModel();
      await tester.pumpWidget(
        ProviderScope(
          child: provider.ChangeNotifierProvider<SpaceViewModel>.value(
            value: space,
            child: const MaterialApp(home: Scaffold(body: MapTopBar())),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Search buildings…'), findsOneWidget);
      expect(find.textContaining('rooms'), findsNothing);
      expect(find.textContaining('services'), findsNothing);
    });
  });

  group('start-point building search scope', () {
    test('originResults carries buildings with their SpaceModel', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1', 30.86, 29.56)]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);
      final vm = SearchOverlayViewModel(searchService: service)..setQuery('lib');

      final results = vm.originResults;
      expect(results, isNotEmpty);
      expect(results.every((r) => r.entityType == 'space'), isTrue);
      expect(results.every((r) => r.space != null), isTrue);
      expect(results.any((r) => r.entityType == 'poi'), isFalse);
    });
  });

  group('executeDirections honours a custom building start point', () {
    test('building → building routes from the selected building coordinates',
        () async {
      final fake = _RecordingSpaceViewModel();
      final origin = _space('Origin Hall', 'b-origin', 30.8600, 29.5600);
      final destination = _space('Destination Hall', 'b-dest', 30.8650, 29.5700);

      await executeDirections(
        spaceProvider: fake,
        origin: TripEndpoint.space(origin),
        destination: TripEndpoint.space(destination),
      );

      expect(fake.routedBuilding?.buid, 'b-dest');
      expect(fake.buildingOrigin, isNotNull);
      expect(fake.buildingOrigin!.latitude, closeTo(30.8600, 1e-9));
      expect(fake.buildingOrigin!.longitude, closeTo(29.5600, 1e-9));
    });

    test('My Location origin leaves the route on the GPS origin', () async {
      final fake = _RecordingSpaceViewModel();
      final destination = _space('Destination Hall', 'b-dest', 30.8650, 29.5700);

      await executeDirections(
        spaceProvider: fake,
        origin: const TripEndpoint.myLocation(),
        destination: TripEndpoint.space(destination),
      );

      expect(fake.routedBuilding?.buid, 'b-dest');
      expect(fake.buildingOrigin, isNull);
    });

    test('building origin with a POI destination forwards the override',
        () async {
      final fake = _RecordingSpaceViewModel();
      final origin = _space('Origin Hall', 'b-origin', 30.8600, 29.5600);
      final poi = _poi('Lab', 'p1', 'b2');

      await executeDirections(
        spaceProvider: fake,
        origin: TripEndpoint.space(origin),
        destination: TripEndpoint.poi(poi),
      );

      expect(fake.navigatedPoi?.puid, 'p1');
      expect(fake.poiOrigin, isNotNull);
      expect(fake.poiOrigin!.latitude, closeTo(30.8600, 1e-9));
      expect(fake.poiOrigin!.longitude, closeTo(29.5600, 1e-9));
    });

    test('switching back to My Location clears the custom origin', () async {
      final fake = _RecordingSpaceViewModel();
      final poi = _poi('Lab', 'p1', 'b2');

      await executeDirections(
        spaceProvider: fake,
        origin: const TripEndpoint.myLocation(),
        destination: TripEndpoint.poi(poi),
      );

      expect(fake.navigatedPoi?.puid, 'p1');
      expect(fake.poiOrigin, isNull);
    });

    test('TripEndpoint.space exposes the building label and coordinates', () {
      final building = _space('Origin Hall', 'b-origin', 30.8600, 29.5600);
      final endpoint = TripEndpoint.space(building);
      expect(endpoint.isMyLocation, isFalse);
      expect(endpoint.isSpace, isTrue);
      expect(endpoint.isPoi, isFalse);
      expect(endpoint.label, 'Origin Hall');
      expect(endpoint.space!.latLng.latitude, closeTo(30.8600, 1e-9));
      expect(endpoint.space!.latLng.longitude, closeTo(29.5600, 1e-9));
    });
  });
}
