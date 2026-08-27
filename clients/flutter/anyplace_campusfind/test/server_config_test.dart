import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/config/api_config.dart';
import 'package:anyplace_campusfind/config/constants.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/screens/map_screen.dart'
    show ejustCampusBounds;

void main() {
  group('Server configuration (E-JUST backend migration)', () {
    test('default base URL is the E-JUST server', () {
      expect(ApiConfig.baseUrl, 'https://map.beout.ai');
      expect(ApiConfig.serverUrl, 'https://map.beout.ai');
    });

    test('E-JUST fallback center replaced the Cyprus centroid', () {
      // Mean of the six live buildings on map.beout.ai.
      expect(SpaceProvider.defaultCenter.latitude, closeTo(30.859877, 1e-6));
      expect(SpaceProvider.defaultCenter.longitude, closeTo(29.563241, 1e-6));
    });

    test('campus identity constants remain E-JUST', () {
      expect(AppConstants.primaryCampusCuid, 'ejust');
      expect(AppConstants.primaryCampusName, 'E-JUST');
    });

    test('E-JUST campus bounds match the provided DMS corners', () {
      // 30°51'45.2"N 29°33'41.8"E / 30°51'26.4"N 29°33'40.9"E
      // 30°51'37.2"N 29°34'03.8"E / 30°51'19.7"N 29°33'59.1"E
      expect(ejustCampusBounds.southwest.latitude,
          closeTo(30 + 51 / 60 + 19.7 / 3600, 1e-6));
      expect(ejustCampusBounds.southwest.longitude,
          closeTo(29 + 33 / 60 + 40.9 / 3600, 1e-6));
      expect(ejustCampusBounds.northeast.latitude,
          closeTo(30 + 51 / 60 + 45.2 / 3600, 1e-6));
      expect(ejustCampusBounds.northeast.longitude,
          closeTo(29 + 34 / 60 + 3.8 / 3600, 1e-6));
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
