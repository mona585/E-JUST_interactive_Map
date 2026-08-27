import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/services/service_query.dart';
import 'package:anyplace_campusfind/utils/category_deriver.dart';

PoiModel _poi(String puid, String buid, String floor, String type) =>
    PoiModel(
      puid: puid,
      buid: buid,
      floorNumber: floor,
      name: 'poi_$puid',
      poisType: type,
      latitude: 1,
      longitude: 1,
    );

final fixture = <PoiModel>[
  _poi('toilet_a0', 'A', '0', 'Toilets'),
  _poi('toilet_a1', 'A', '1', 'Toilet'), // matches toilets bucket
  _poi('toilet_b0', 'B', '0', 'Toilets'),
  _poi('cafe_b0', 'B', '0', 'Cafeteria'),
  _poi('conn', 'A', '0', 'None'), // connector — excluded
  _poi('door', 'B', '0', 'Door'), // door — excluded
];

void main() {
  group('queryScopedServices', () {
    test('campus scope returns all matching non-connector/door POIs',
        () {
      final r = queryScopedServices(
        category: EntityCategory.toilets,
        campusIndexPois: fixture,
      );
      expect(r.map((p) => p.puid), containsAll(['toilet_a0', 'toilet_a1']));
      expect(r.length, 3);
    });

    test('building scope restricts to buid', () {
      final r = queryScopedServices(
        category: EntityCategory.toilets,
        campusIndexPois: fixture,
        buildingBuid: 'A',
      );
      expect(r.map((p) => p.buid), everyElement('A'));
      expect(r.length, 2);
    });

    test('floor scope restricts to buid+floor', () {
      final r = queryScopedServices(
        category: EntityCategory.toilets,
        campusIndexPois: fixture,
        buildingBuid: 'A',
        floorNumber: '1',
      );
      expect(r.map((p) => p.puid), ['toilet_a1']);
    });

    test('connectors and doors never surface as services', () {
      final r = queryScopedServices(
        category: EntityCategory.other,
        campusIndexPois: fixture,
      );
      // conn/door map to buckets but are excluded by rule.
      expect(r.any((p) => p.puid == 'conn' || p.puid == 'door'), isFalse);
    });
  });

  group('serviceScopeLabel', () {
    test('labels all three scopes with the global E-JUST parent', () {
      expect(serviceScopeLabel(buildingName: null, floorDisplayName: null),
          'E-JUST');
      expect(
          serviceScopeLabel(
              buildingName: 'Library Building', floorDisplayName: null),
          'E-JUST › Library Building');
      expect(
        serviceScopeLabel(
            buildingName: 'Library Building',
            floorDisplayName: 'Ground Floor (Floor 0)'),
        'E-JUST › Library Building · Floor Ground Floor (Floor 0)',
      );
    });
  });
}
