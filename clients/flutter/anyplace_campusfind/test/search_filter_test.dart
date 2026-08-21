import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/providers/search_provider.dart';
import 'package:anyplace_campusfind/screens/search_screen.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/utils/category_deriver.dart';

SearchService _seedService() {
  final service = SearchService();

  final b1 = const SpaceModel(
    buid: 'buid_b7', name: 'Building B7',
    latitude: 35.1, longitude: 33.4, spaceType: 'building',
  );
  final b2 = const SpaceModel(
    buid: 'buid_b3', name: 'Building B3',
    latitude: 35.1, longitude: 33.4, spaceType: 'building',
  );
  final b3 = const SpaceModel(
    buid: 'buid_lib', name: 'Library',
    latitude: 35.1, longitude: 33.4, spaceType: 'library',
  );

  service.addSpaces([b1, b2, b3]);

  service.addFloors('buid_b7', [
    FloorModel(buid: 'buid_b7', floorNumber: '0', floorName: 'B7 - Ground'),
    FloorModel(buid: 'buid_b7', floorNumber: '1', floorName: 'B7 - First'),
  ]);

  service.addFloors('buid_b3', [
    FloorModel(buid: 'buid_b3', floorNumber: '0', floorName: 'B3 - Ground'),
  ]);

  service.addFloors('buid_lib', [
    FloorModel(buid: 'buid_lib', floorNumber: '0', floorName: 'Lib - Ground'),
  ]);

  service.addPois('buid_b7', '0', [
    PoiModel(
      puid: 'poi_b7_elev_1', buid: 'buid_b7', floorNumber: '0',
      name: 'Elevator B7', poisType: 'Elevator',
      latitude: 35.1, longitude: 33.4,
    ),
    PoiModel(
      puid: 'poi_b7_toilet_1', buid: 'buid_b7', floorNumber: '0',
      name: 'Toilet B7', poisType: 'Toilet',
      latitude: 35.1, longitude: 33.4,
    ),
    PoiModel(
      puid: 'poi_b7_entrance_1', buid: 'buid_b7', floorNumber: '0',
      name: 'Entrance B7', poisType: 'Entrance',
      latitude: 35.1, longitude: 33.4,
    ),
  ]);

  service.addPois('buid_b3', '0', [
    PoiModel(
      puid: 'poi_b3_elev_1', buid: 'buid_b3', floorNumber: '0',
      name: 'Elevator B3', poisType: 'Elevator',
      latitude: 35.1, longitude: 33.4,
    ),
    PoiModel(
      puid: 'poi_b3_stairs_1', buid: 'buid_b3', floorNumber: '0',
      name: 'Stairs B3', poisType: 'Stairs',
      latitude: 35.1, longitude: 33.4,
    ),
  ]);

  service.addPois('buid_lib', '0', [
    PoiModel(
      puid: 'poi_lib_room_1', buid: 'buid_lib', floorNumber: '0',
      name: 'Reading Room', poisType: 'Room',
      latitude: 35.1, longitude: 33.4,
    ),
  ]);

  return service;
}

Widget _buildTestWidget(SearchService service) {
  return ProviderScope(
    overrides: [
      searchServiceProvider.overrideWithValue(service),
    ],
    child: const MaterialApp(home: SearchScreen()),
  );
}

void main() {
  group('SearchService query – POI-only results', () {
    test('returns only POIs, never buildings or floors', () {
      final service = _seedService();
      final results = service.query('');
      expect(results.length, 6);
      for (final r in results) {
        expect(r.entityType, 'poi');
        expect(r.poi, isNotNull);
        expect(r.space, isNull);
        expect(r.floor, isNull);
      }
    });

    test('buildings are indexed but excluded from query results', () {
      final service = _seedService();
      expect(service.itemCount, greaterThan(6));
      final results = service.query('');
      final names = results.map((r) => r.name).toSet();
      expect(names, isNot(contains('Building B7')));
      expect(names, isNot(contains('Building B3')));
      expect(names, isNot(contains('Library')));
    });

    test('floors are indexed but excluded from query results', () {
      final service = _seedService();
      final results = service.query('');
      final names = results.map((r) => r.name).toSet();
      expect(names, isNot(contains('B7 - Ground (Floor 0)')));
    });

    test('returns POIs across all buildings', () {
      final service = _seedService();
      final results = service.query('');
      final buids = results.map((r) => r.poi!.buid).toSet();
      expect(buids, containsAll(['buid_b7', 'buid_b3', 'buid_lib']));
    });
  });

  group('SearchService query – building filter', () {
    test('filters POIs by buid_b7 only', () {
      final service = _seedService();
      final results = service.query('', buid: 'buid_b7');
      expect(results.length, 3);
      for (final r in results) {
        expect(r.poi!.buid, 'buid_b7');
      }
    });

    test('returns empty when buid has no POIs', () {
      final service = _seedService();
      final results = service.query('', buid: 'nonexistent_buid');
      expect(results, isEmpty);
    });

    test('building filter still works via discoverBuids', () {
      final service = _seedService();
      final buids = service.discoverBuids();
      expect(buids.map((b) => b.buid), containsAll(['buid_b7', 'buid_b3', 'buid_lib']));
    });
  });

  group('SearchService query – POI type filter', () {
    test('filters by elevator category', () {
      final service = _seedService();
      final results = service.query('', category: EntityCategory.elevator);
      expect(results.length, 2);
      for (final r in results) {
        expect(r.category, EntityCategory.elevator);
      }
    });

    test('filters by stairs category', () {
      final service = _seedService();
      final results = service.query('', category: EntityCategory.stairs);
      expect(results.length, 1);
      expect(results.first.name, 'Stairs B3');
    });
  });

  group('SearchService query – combined building + POI type', () {
    test('elevators in B7 only', () {
      final service = _seedService();
      final results = service.query(
        '',
        buid: 'buid_b7',
        category: EntityCategory.elevator,
      );
      expect(results.length, 1);
      expect(results.first.name, 'Elevator B7');
    });

    test('elevators in B3', () {
      final service = _seedService();
      final results = service.query(
        '',
        buid: 'buid_b3',
        category: EntityCategory.elevator,
      );
      expect(results.length, 1);
      expect(results.first.name, 'Elevator B3');
    });

    test('stairs in B7 returns empty (no stairs there)', () {
      final service = _seedService();
      final results = service.query(
        '',
        buid: 'buid_b7',
        category: EntityCategory.stairs,
      );
      expect(results, isEmpty);
    });
  });

  group('SearchService query – search text + filters', () {
    test('text query + building filter', () {
      final service = _seedService();
      final results = service.query('elevator', buid: 'buid_b7');
      expect(results.length, 1);
      expect(results.first.name, 'Elevator B7');
    });

    test('text query + category filter', () {
      final service = _seedService();
      final results = service.query('stairs', category: EntityCategory.stairs);
      expect(results.length, 1);
      expect(results.first.name, 'Stairs B3');
    });

    test('text query + both filters', () {
      final service = _seedService();
      final results = service.query(
        'elevator',
        buid: 'buid_b3',
        category: EntityCategory.elevator,
      );
      expect(results.length, 1);
      expect(results.first.name, 'Elevator B3');
    });
  });

  group('SearchService query – clearing filters', () {
    test('clearing buid restores all building POIs', () {
      final service = _seedService();
      final filtered = service.query('', buid: 'buid_b7');
      final unfiltered = service.query('', buid: null);
      expect(unfiltered.length, greaterThan(filtered.length));
    });

    test('clearing category restores all types', () {
      final service = _seedService();
      final filtered = service.query('', category: EntityCategory.elevator);
      final unfiltered = service.query('', category: null);
      expect(unfiltered.length, greaterThan(filtered.length));
    });

    test('clearing both filters restores everything', () {
      final service = _seedService();
      final filtered = service.query(
        '',
        buid: 'buid_b7',
        category: EntityCategory.elevator,
      );
      final unfiltered = service.query('');
      expect(unfiltered.length, greaterThan(filtered.length));
    });
  });

  group('discoverBuids', () {
    test('returns human-readable names, not buid values', () {
      final service = _seedService();
      final buids = service.discoverBuids();
      final names = buids.map((b) => b.name).toList();
      expect(names, contains('Building B7'));
      expect(names, contains('Building B3'));
      expect(names, contains('Library'));
      for (final b in buids) {
        expect(b.buid, isNot(b.name));
      }
    });

    test('returns sorted by name', () {
      final service = _seedService();
      final buids = service.discoverBuids();
      final names = buids.map((b) => b.name).toList();
      final sorted = List<String>.from(names)..sort();
      expect(names, sorted);
    });
  });

  group('discoverCategoriesFromIndex', () {
    test('returns only POI categories present in the index', () {
      final service = _seedService();
      final categories = service.discoverCategoriesFromIndex();
      final labels = categories.map((c) => c.label).toList();
      expect(labels, contains('Elevator'));
      expect(labels, contains('Toilets'));
      expect(labels, contains('Entrance'));
      expect(labels, contains('Stairs'));
      expect(labels, contains('Room'));
    });

    test('excludes other and floor categories', () {
      final service = _seedService();
      final categories = service.discoverCategoriesFromIndex();
      expect(categories, isNot(contains(EntityCategory.other)));
      expect(categories, isNot(contains(EntityCategory.floor)));
    });

    test('returns sorted by label', () {
      final service = _seedService();
      final categories = service.discoverCategoriesFromIndex();
      final labels = categories.map((c) => c.label).toList();
      final sorted = List<String>.from(labels)..sort();
      expect(labels, sorted);
    });
  });

  group('SearchScreen widget – filter sheet', () {
    testWidgets('filter button is visible beside search field', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
    });

    testWidgets('tapping Filters opens bottom sheet with expected content', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Narrow results by building and POI type.'), findsOneWidget);
      expect(find.text('All buildings'), findsOneWidget);
      final sheetListView = find.byType(ListView).last;
      await tester.drag(sheetListView, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('All types'), findsOneWidget);
    });

    testWidgets('filter sheet shows building names (human-readable)', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Building B7'), findsWidgets);
      expect(find.text('Building B3'), findsWidgets);
      expect(find.text('Library'), findsWidgets);
    });

    testWidgets('filter sheet does not overflow on small screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      final sheetListView = find.byType(ListView).last;
      await tester.drag(sheetListView, const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('apply button closes sheet and updates results', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Building B7').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('clear button (X icon) resets filters', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Building B7').last);
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.close), findsWidgets);
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      expect(find.text('1'), findsNothing);
    });

    testWidgets('search bar and filter button are side by side', (tester) async {
      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();

      final row = find.byType(Row).first;
      expect(row, findsOneWidget);
      final rowWidget = row.evaluate().first.widget as Row;
      expect(rowWidget.children.length, greaterThanOrEqualTo(2));
    });

    testWidgets('search bar and filter button do not overflow on small screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_buildTestWidget(_seedService()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('B7 appears first after All buildings in filter sheet', (tester) async {
      final service = SearchService();
      service.addSpaces([
        const SpaceModel(buid: 'buid_aaa', name: 'AAA Building', latitude: 35.1, longitude: 33.4),
        const SpaceModel(
          buid: 'building_b8f4e123-d58f-45b7-9942-4492b198c9e4_1786536183663',
          name: 'B7', latitude: 35.1, longitude: 33.4,
        ),
        const SpaceModel(buid: 'buid_zzz', name: 'ZZZ Building', latitude: 35.1, longitude: 33.4),
      ]);

      await tester.pumpWidget(_buildTestWidget(service));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();

      final allBuildingsFinder = find.text('All buildings');
      final b7Finder = find.text('B7');

      expect(allBuildingsFinder, findsOneWidget);
      expect(b7Finder, findsOneWidget);

      final allBuildingsBox = allBuildingsFinder.evaluate().first.renderObject as RenderBox;
      final b7Box = b7Finder.evaluate().first.renderObject as RenderBox;
      expect(b7Box.localToGlobal(Offset.zero).dy, greaterThan(allBuildingsBox.localToGlobal(Offset.zero).dy));

      final aaaFinder = find.text('AAA Building');
      expect(aaaFinder, findsOneWidget);
      final aaaBox = aaaFinder.evaluate().first.renderObject as RenderBox;
      expect(aaaBox.localToGlobal(Offset.zero).dy, greaterThan(b7Box.localToGlobal(Offset.zero).dy));
    });
  });
}
