import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/config/api_config.dart';
import 'package:anyplace_campusfind/config/constants.dart';
import 'package:anyplace_campusfind/config/map_config.dart' show MapConfig;
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/views/map_screen.dart'
    show
        ejustCampusBounds,
        ejustCampusBoundaryCenter,
        ejustCampusBoundaryEast,
        ejustCampusBoundaryNorth,
        ejustCampusBoundaryPoints,
        ejustCampusBoundarySouth,
        ejustCampusBoundaryWest;

void main() {
  group('Server configuration (E-JUST backend migration)', () {
    test('default base URL is the E-JUST server', () {
      expect(ApiConfig.baseUrl, 'https://map.beout.ai');
      expect(ApiConfig.serverUrl, 'https://map.beout.ai');
    });

    test('E-JUST fallback center replaced the Cyprus centroid', () {
      // Mean of the six live buildings on map.beout.ai.
      expect(SpaceViewModel.defaultCenter.latitude, closeTo(30.859877, 1e-6));
      expect(SpaceViewModel.defaultCenter.longitude, closeTo(29.563241, 1e-6));
    });

    test('campus identity constants remain E-JUST', () {
      expect(AppConstants.primaryCampusCuid, 'ejust');
      expect(AppConstants.primaryCampusName, 'E-JUST');
    });

    test('E-JUST campus bounds are the SUPPLIED boundary extrema', () {
      // Cardinal boundary points supplied by the campus administration:
      //   North 30.862500, 29.561806   South 30.855703, 29.566940
      //   East  30.860705, 29.567365   West  30.858273, 29.560721
      expect(ejustCampusBounds.southwest.latitude, closeTo(30.855703, 1e-6));
      expect(ejustCampusBounds.southwest.longitude, closeTo(29.560721, 1e-6));
      expect(ejustCampusBounds.northeast.latitude, closeTo(30.862500, 1e-6));
      expect(ejustCampusBounds.northeast.longitude, closeTo(29.567365, 1e-6));

      // The bounds are exactly the bounding box of the four supplied points.
      for (final point in ejustCampusBoundaryPoints) {
        expect(ejustCampusBounds.contains(point), isTrue);
      }
      expect(ejustCampusBounds.southwest.latitude,
          closeTo(ejustCampusBoundarySouth.latitude, 1e-9));
      expect(ejustCampusBounds.northeast.latitude,
          closeTo(ejustCampusBoundaryNorth.latitude, 1e-9));
      expect(ejustCampusBounds.southwest.longitude,
          closeTo(ejustCampusBoundaryWest.longitude, 1e-9));
      expect(ejustCampusBounds.northeast.longitude,
          closeTo(ejustCampusBoundaryEast.longitude, 1e-9));
    });

    test('preliminary boundary-rectangle centre is the documented value', () {
      // Arithmetic midpoint of the supplied extrema — a bounding-box centre,
      // NOT a polygon centroid.
      expect(ejustCampusBoundaryCenter.latitude, closeTo(30.8591015, 1e-6));
      expect(ejustCampusBoundaryCenter.longitude, closeTo(29.564043, 1e-6));
    });

    test('campus-overview camera bearing is 45° clockwise from north', () {
      // Google Maps convention (`CameraPosition.bearing`): degrees measured
      // clockwise from north — 0.0 = camera points north (north-up), 90.0 =
      // camera points east. 45.0 therefore points the map north-east.
      expect(MapConfig.campusOverviewBearing, 45.0);
    });

    test('Quick Access defaults reference the new server buids only', () {
      final legacyBuids = {
        'building_163182b1-2875-46a0-a398-a722b83f4ede_1787170088312',
        'building_aa532328-faa2-406b-9b6e-2a4640e3cbe2_1787170286644',
        'building_5aee1ddd-3736-4100-977b-31fb3c3d2576_1787170410290',
        'building_6dc90d58-81fb-4f3c-ad29-43d825fb5b77_1787170194408',
        'building_638b4ab9-0f48-4c0f-8e9a-a9477b251259_1787170631136',
        'building_48c4eb03-8424-4b09-8563-13cfc1c720c9_1787170689278',
      };
      for (final d in AppConstants.kDefaultQuickAccessLocations) {
        expect(legacyBuids.contains(d.buid), isFalse,
            reason: '${d.label} still points at an old-backend buid');
      }
      // The six real entities from the map.beout.ai payload are covered.
      expect(AppConstants.kDefaultQuickAccessLocations.length, 6);
    });
  });

  group('Dataset epoch migration (CacheService)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('legacy device (user data present, no marker) → wipes and marks',
        () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefQuickAccess: '[{"type":"space","id":"old_buid",'
            '"name":"Old","subtitle":"","category":"building","addedAt":1}]',
        AppConstants.prefRecentWaypoints: ['old_puid'],
        'dataset_epoch': 'ucy-2025',
      });
      final cache = CacheService();

      final migrated = await cache.consumeDatasetEpochMigration();

      expect(migrated, isTrue);
      // Quick Access key REMOVED (not emptied) so first-run seeding re-runs
      // against the new server's dataset.
      expect(await cache.hasQuickAccessKey(), isFalse);
      expect(await cache.getRecentWaypoints(), isEmpty);
      expect(await cache.getDatasetEpoch(), AppConstants.datasetEpoch);
    });

    test('idempotent: second run is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheService();

      expect(await cache.consumeDatasetEpochMigration(), isTrue);
      await cache.addRecentWaypoint('new_puid');

      // Marker already current → user data written after migration survives.
      expect(await cache.consumeDatasetEpochMigration(), isFalse);
      expect(await cache.getRecentWaypoints(), ['new_puid']);
    });

    test('fresh install: marker written without touching unrelated keys',
        () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheService();

      expect(await cache.consumeDatasetEpochMigration(), isTrue);
      expect(await cache.getDatasetEpoch(), AppConstants.datasetEpoch);
      expect(await cache.getSelectedCampusId(), isNull); // untouched
    });
  });
}
