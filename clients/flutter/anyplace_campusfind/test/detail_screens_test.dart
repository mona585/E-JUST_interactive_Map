import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/floor.dart';
import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/providers/search_provider.dart';
import 'package:anyplace_campusfind/screens/building_detail_screen.dart';
import 'package:anyplace_campusfind/screens/detail_navigation.dart';
import 'package:anyplace_campusfind/screens/professor_profile_screen.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/utils/category_deriver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  final building = Space(
    buid: 'building_1',
    name: 'Engineering Building',
    coordinatesLat: 30.8,
    coordinatesLon: 29.5,
    spaceType: 'building',
    description: 'Main Campus West | Opened 2021 | Ramps & Elevators | Braille Signage',
  );

  final professor = Poi(
    puid: 'poi_prof',
    buid: 'building_1',
    name: 'Dr. Ahmed',
    coordinatesLat: 30.8001,
    coordinatesLon: 29.5001,
    floorNumber: '0',
    description:
        'Dr. Ahmed | Associate Professor | ECE Dept | Office 402, Floor 4 | Mon/Wed 2-3:30PM',
  );

  final cafe = Poi(
    puid: 'poi_cafe',
    buid: 'building_1',
    name: 'Main Cafeteria',
    coordinatesLat: 30.8002,
    coordinatesLon: 29.5002,
    floorNumber: '0',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService()
      ..setSpaces([building])
      ..setFloors('building_1', [
        Floor(
          fuid: 'building_1_0',
          buid: 'building_1',
          floorNumber: '0',
          floorName: 'Ground Floor',
        ),
      ])
      ..setPois('building_1', [professor, cafe]);

    container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);
  });

  Widget wrap(Widget child) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: child),
    );
  }

  testWidgets('building detail renders metadata, floors and facilities',
      (tester) async {
    await tester.pumpWidget(wrap(BuildingDetailScreen(space: building)));

    expect(find.text('Engineering Building'), findsWidgets);
    expect(find.text('Main Campus West · Opened 2021'), findsOneWidget);
    expect(find.text('Ground Floor'), findsOneWidget);
    expect(find.text('Ramps & Elevators'), findsOneWidget);
    expect(find.text('Braille Signage'), findsOneWidget);
  });

  testWidgets('building detail room search filters POIs', (tester) async {
    await tester.pumpWidget(wrap(BuildingDetailScreen(space: building)));

    await tester.enterText(find.byType(TextField), 'cafeteria');
    await tester.pumpAndSettle();

    expect(find.text('Main Cafeteria'), findsOneWidget);
    expect(find.text('Dr. Ahmed'), findsNothing);
  });

  testWidgets('professor profile parses name/title/dept/office/hours',
      (tester) async {
    await tester.pumpWidget(
      wrap(ProfessorProfileScreen(poi: professor)),
    );

    expect(find.text('Dr. Ahmed'), findsOneWidget);
    expect(find.text('Associate Professor'), findsOneWidget);
    expect(find.text('ECE Dept'), findsOneWidget);
    expect(find.text('Office 402, Floor 4'), findsOneWidget);
    expect(find.text('Mon/Wed 2-3:30PM'), findsOneWidget);
    expect(find.text('Engineering Building'), findsOneWidget);
  });

  testWidgets('openSearchResult pushes professor profile for professor POIs',
      (tester) async {
    WidgetRef? capturedRef;
    await tester.pumpWidget(wrap(Consumer(
      builder: (context, ref, child) {
        capturedRef = ref;
        return const Scaffold(body: SizedBox());
      },
    )));
    final context = tester.element(find.byType(Scaffold));

    openSearchResult(
      context,
      capturedRef!,
      SearchResult(category: EntityCategory.professor, poi: professor),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProfessorProfileScreen), findsOneWidget);
    expect(find.byType(BuildingDetailScreen), findsNothing);
  });

  testWidgets('openSearchResult pushes building detail for buildings',
      (tester) async {
    WidgetRef? capturedRef;
    await tester.pumpWidget(wrap(Consumer(
      builder: (context, ref, child) {
        capturedRef = ref;
        return const Scaffold(body: SizedBox());
      },
    )));
    final context = tester.element(find.byType(Scaffold));

    openSearchResult(
      context,
      capturedRef!,
      SearchResult(category: EntityCategory.building, space: building),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BuildingDetailScreen), findsOneWidget);
  });
}
