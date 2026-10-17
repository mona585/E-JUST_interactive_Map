import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/config/map_config.dart';
import 'package:anyplace_campusfind/datasources/gps_location_service.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/views/main_shell.dart';

import 'helpers/fake_google_maps_platform.dart';

// Campus-overview camera regression coverage.
//
// The overview must be framed from the user-supplied campus BOUNDARY rectangle
// (centre ≈ 30.8591015, 29.564043) and must remain the FINAL camera after the
// bundled KMZ routes load. Historically it was overridden a frame or two later
// by `_centerOnCustomRoutesIfNeeded()`, which re-framed the map to the custom
// route BOUNDING-BOX centre at zoom 17.
//
// It must also open rotated 45° toward the north-east
// ([MapConfig.campusOverviewBearing], Google Maps bearing = degrees clockwise
// from north), and keep that bearing after the KMZ routes load.
//
// These tests drive the REAL widget tree with a fake Google Maps platform that
// actually fires `onMapCreated` and records every camera command.

/// Visible half-spans (degrees) of a camera at [targetLat]/[zoom] over a
/// [size]-pixel viewport — the standard Web-Mercator metres-per-pixel relation.
({double latHalf, double lngHalf}) _visibleHalfSpans(
  double targetLat,
  double zoom,
  Size size,
) {
  final cosLat = math.cos(targetLat * math.pi / 180);
  final metersPerPixel =
      156543.03392 * cosLat / math.pow(2, zoom).toDouble();
  final latHalf = (size.height * metersPerPixel) / 111320.0 / 2;
  final lngHalf = (size.width * metersPerPixel) / (111320.0 * cosLat) / 2;
  return (latHalf: latHalf, lngHalf: lngHalf);
}

class _NoSyncSpaceViewModel extends SpaceViewModel {
  @override
  Future<void> loadSpaces({bool forceReload = false}) async {}

  @override
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {}
}

Future<void> _pumpShell(WidgetTester tester, SpaceViewModel space) async {
  final location = LocationViewModel(locationService: GpsLocationService());
  final nav = NavigationViewModel(spaceProvider: space, locationProvider: location);
  addTearDown(() {
    nav.dispose();
    location.dispose();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [cacheServiceProvider.overrideWithValue(CacheService())],
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider<SpaceViewModel>.value(value: space),
          provider.ChangeNotifierProvider<LocationViewModel>.value(
            value: location,
          ),
          provider.ChangeNotifierProvider<NavigationViewModel>.value(
            value: nav,
          ),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the supplied campus-boundary overview is the authoritative FINAL camera',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final platform = RecordingGoogleMapsPlatform.install();
      final space = _NoSyncSpaceViewModel();

      const viewSize = Size(411, 866);
      tester.view.physicalSize = viewSize;
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = const FakeViewPadding(top: 44);
      addTearDown(tester.view.reset);

      await _pumpShell(tester, space);

      // ── 0. The FIRST frame (map creation) already opens rotated 45° toward
      // the north-east. Bearing is only delivered at creation via
      // MapWidgetConfiguration, so it is read from the recorded creation-time
      // camera, not from `cameraUpdates`.
      final initial = platform.initialCameraPosition;
      expect(
        initial,
        isNotNull,
        reason: 'GoogleMap.initialCameraPosition must reach the platform',
      );
      expect(MapConfig.campusOverviewBearing, 45.0);
      expect(initial!.bearing, 45.0);
      // Rotation only — the initial target is still the boundary centre, not a
      // positional offset.
      expect(
        initial.target.latitude,
        closeTo(ejustCampusBoundaryCenter.latitude, 1e-9),
      );
      expect(
        initial.target.longitude,
        closeTo(ejustCampusBoundaryCenter.longitude, 1e-9),
      );

      // ── 1. Exactly one camera move, targeting the SUPPLIED boundary centre.
      expect(platform.cameraUpdates.length, 1);
      final overview = platform.lastCameraPosition!;
      expect(
        overview.target.latitude,
        closeTo(ejustCampusBoundaryCenter.latitude, 1e-9),
      );
      expect(
        overview.target.longitude,
        closeTo(ejustCampusBoundaryCenter.longitude, 1e-9),
      );

      // …and the fitted overview keeps the same 45° rotation.
      expect(overview.bearing, MapConfig.campusOverviewBearing);
      expect(overview.bearing, 45.0);

      // …and NOT the centroid of the (incomplete) building registry.
      expect(
        overview.target.latitude,
        isNot(closeTo(SpaceViewModel.defaultCenter.latitude, 1e-4)),
      );
      expect(
        overview.target.longitude,
        isNot(closeTo(SpaceViewModel.defaultCenter.longitude, 1e-4)),
      );

      // ── 2. Framing still CONTAINS the supplied N/S/E/W extrema.
      final half = _visibleHalfSpans(
        overview.target.latitude,
        overview.zoom,
        viewSize,
      );
      expect(
        ejustCampusBounds.southwest.latitude,
        greaterThan(overview.target.latitude - half.latHalf),
        reason: 'supplied SOUTH extrema must be inside the overview',
      );
      expect(
        ejustCampusBounds.northeast.latitude,
        lessThan(overview.target.latitude + half.latHalf),
        reason: 'supplied NORTH extrema must be inside the overview',
      );
      expect(
        ejustCampusBounds.southwest.longitude,
        greaterThan(overview.target.longitude - half.lngHalf),
        reason: 'supplied WEST extrema must be inside the overview',
      );
      expect(
        ejustCampusBounds.northeast.longitude,
        lessThan(overview.target.longitude + half.lngHalf),
        reason: 'supplied EAST extrema must be inside the overview',
      );
      for (final point in ejustCampusBoundaryPoints) {
        expect(point.latitude,
            inInclusiveRange(overview.target.latitude - half.latHalf,
                overview.target.latitude + half.latHalf));
        expect(point.longitude,
            inInclusiveRange(overview.target.longitude - half.lngHalf,
                overview.target.longitude + half.lngHalf));
      }

      // ── 3. Appropriate overview zoom — never the zoom-17 route framing.
      expect(overview.zoom, lessThan(17.0));
      expect(overview.zoom, greaterThanOrEqualTo(13.0));

      // ── 4. Let the bundled custom KMZ routes finish loading (this is what
      // used to trigger the stale bounds-centre override).
      await space.loadCustomRoutes();
      await tester.pumpAndSettle(const Duration(milliseconds: 50));
      await tester.pumpAndSettle(const Duration(milliseconds: 50));

      expect(space.customRouteRepository.isLoaded, isTrue);
      expect(space.customRouteRepository.routes, isNotEmpty);

      // The overview remains authoritative — no later camera update at all.
      expect(
        platform.cameraUpdates.length,
        1,
        reason: 'no later camera update may override the campus overview fit',
      );
      final last = platform.lastCameraPosition!;
      expect(
        last.target.latitude,
        closeTo(ejustCampusBoundaryCenter.latitude, 1e-9),
      );
      expect(
        last.target.longitude,
        closeTo(ejustCampusBoundaryCenter.longitude, 1e-9),
      );
      expect(last.zoom, isNot(closeTo(17.0, 1e-6)));
      expect(last.zoom, lessThan(17.0));
      // KMZ loading must not reset the rotation either (the legacy pin was
      // north-up at zoom 17 — bearing 0.0).
      expect(
        last.bearing,
        45.0,
        reason: 'KMZ route load must not reset the 45° overview bearing',
      );
    },
  );
}
