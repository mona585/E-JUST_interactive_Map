import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/models/floor_model.dart';
import 'package:anyplace_campusfind/models/poi_model.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/viewmodels/search_overlay_view_model.dart';

// CP-8: the additive `SpaceViewModel.requestRouteBetweenPois` wrapper and its
// POI-to-POI repository API were removed with indoor routing. The remaining
// coverage here is the search-suggestion behavior used by the directions UX.

SpaceModel _space(String name, String buid) => SpaceModel(
      buid: buid,
      name: name,
      latitude: 30.86,
      longitude: 29.56,
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

void main() {
  group('SearchService.query includeSpacesAndFloors flag', () {
    test('default keeps POI-only legacy behavior', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final legacy = service.query('lib');
      expect(legacy, isNotEmpty);
      expect(legacy.every((r) => r.entityType == 'poi'), isTrue);
    });

    test('opt-in flag includes building entries as suggestions', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final mixed = service.query('lib', includeSpacesAndFloors: true);
      expect(mixed.any((r) => r.entityType == 'space'), isTrue);
      expect(mixed.any((r) => r.entityType == 'poi'), isTrue);
    });
  });

  group('SearchService.query spacesOnly (outdoor-only scope)', () {
    test('returns buildings only — no rooms, floors, Indoor POIs', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addFloors('b1', [FloorModel(buid: 'b1', floorNumber: '1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final results = service.query('lib', spacesOnly: true);
      expect(results, isNotEmpty);
      expect(results.every((r) => r.entityType == 'space'), isTrue);
      expect(results.any((r) => r.entityType == 'floor'), isFalse);
      expect(results.any((r) => r.entityType == 'poi'), isFalse);
    });

    test('empty query returns buildings only under spacesOnly', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final results = service.query('', spacesOnly: true);
      expect(results.every((r) => r.entityType == 'space'), isTrue);
    });

    test('no building match yields empty results', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);

      expect(service.query('zzzz', spacesOnly: true), isEmpty);
    });
  });

  group('SearchOverlayViewModel destination scope (outdoor-only)', () {
    test('destinationResults returns buildings only', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addFloors('b1', [FloorModel(buid: 'b1', floorNumber: '1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);
      final vm = SearchOverlayViewModel(searchService: service)..setQuery('lib');

      final results = vm.destinationResults;
      expect(results, isNotEmpty);
      expect(results.every((r) => r.entityType == 'space'), isTrue);
      expect(results.any((r) => r.entityType == 'floor' || r.entityType == 'poi'),
          isFalse);
    });

    test('originResults returns buildings only (custom start-point picker)', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addFloors('b1', [FloorModel(buid: 'b1', floorNumber: '1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);
      final vm = SearchOverlayViewModel(searchService: service)..setQuery('lib');

      final results = vm.originResults;
      expect(results, isNotEmpty);
      expect(results.every((r) => r.entityType == 'space'), isTrue);
      expect(results.any((r) => r.entityType == 'poi'), isFalse);
      expect(results.any((r) => r.entityType == 'floor'), isFalse);
      // Building results carry the SpaceModel used to build a routing origin.
      expect(results.every((r) => r.space != null), isTrue);
    });

    test('empty/loading/no-results states remain correct', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      final vm = SearchOverlayViewModel(searchService: service);

      // Empty query still returns building suggestions.
      expect(vm.destinationResults.every((r) => r.entityType == 'space'), isTrue);
      // No match -> empty.
      vm.setQuery('zzzz');
      expect(vm.destinationResults, isEmpty);
      // Clear returns to building suggestions.
      vm.clearQuery();
      expect(vm.destinationResults.every((r) => r.entityType == 'space'), isTrue);
    });
  });
}
