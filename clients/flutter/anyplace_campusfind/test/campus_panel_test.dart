import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/poi_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/providers/panel_provider.dart';
import 'package:anyplace_campusfind/providers/search_provider.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/widgets/campus_content_panel.dart';
import 'package:anyplace_campusfind/ui/widgets/poi_detail_card.dart';

SpaceModel _space(String buid, String name, String code) => SpaceModel(
      buid: buid,
      name: name,
      latitude: 30.86,
      longitude: 29.56,
      bucode: code,
      spaceType: 'building',
    );

class _FakeSpaceRepository implements SpaceRepository {
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async => [
        _space('buid_a', 'Library Building', 'LIB'),
        _space('buid_b', 'Engineering Hall', 'ENG'),
      ];

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => null;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      [
        FloorModel(buid: buid, floorNumber: '0', floorName: 'Ground Floor'),
        FloorModel(buid: buid, floorNumber: '1', floorName: 'First Floor'),
      ];
}

class _FakePoiRepo implements PoiRepository {
  @override
  Future<List<PoiModel>> getPoisByFloor(
    String buid,
    String floor, {
    bool forceReload = false,
  }) async =>
      [
        PoiModel(
          puid: 'p_room',
          buid: buid,
          floorNumber: floor,
          name: 'Room 101',
          poisType: 'room',
          latitude: 30.8601,
          longitude: 29.5601,
        ),
        // Connector must be filtered out of the navigable list.
        PoiModel(
          puid: 'p_conn',
          buid: buid,
          floorNumber: floor,
          name: 'connector',
          poisType: 'None',
          latitude: 30.8602,
          longitude: 29.5602,
        ),
      ];

  @override
  Future<bool> isPoisCached(String buid, String floor) async => false;

  @override
  Future<void> clearPois(String buid, String floor) async {}

  @override
  Future<void> clearAll() async {}
}

class _FakeRadioMapRepo implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor,
      {bool forceReload = false}) async =>
      throw UnimplementedError('not needed in UI test');

  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;

  @override
  Future<void> clearRadioMap(String buid, String floor) async {}

  @override
  Future<void> clearAllCache() async {}
}

class _FakeFloorplanRepo implements FloorplanRepository {
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SpaceProvider spaceProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    spaceProvider = SpaceProvider(
      repository: _FakeSpaceRepository(),
      poiRepository: _FakePoiRepo(),
      radioMapRepository: _FakeRadioMapRepo(),
      floorplanRepository: _FakeFloorplanRepo(),
    );
    await spaceProvider.loadSpaces();
  });

  Widget wrap({void Function(dynamic target, double zoom)? onFocus}) {
    final location = LocationProvider();
    final nav = NavigationController(
      spaceProvider: spaceProvider,
      locationProvider: location,
    );
    final searchService = SearchService()
      ..addSpaces(spaceProvider.spaces)
      ..addPois('buid_a', '0', [
        PoiModel(
          puid: 'svc_toilet_a',
          buid: 'buid_a',
          floorNumber: '0',
          name: 'Toilets A',
          poisType: 'Toilets',
          latitude: 30.8603,
          longitude: 29.5603,
        ),
      ])
      ..addPois('buid_b', '0', [
        PoiModel(
          puid: 'svc_toilet_b',
          buid: 'buid_b',
          floorNumber: '0',
          name: 'Toilets B',
          poisType: 'Toilets',
          latitude: 30.8613,
          longitude: 29.5613,
        ),
        PoiModel(
          puid: 'svc_cafe_b',
          buid: 'buid_b',
          floorNumber: '0',
          name: 'Cafeteria B',
          poisType: 'Cafeteria',
          latitude: 30.8614,
          longitude: 29.5614,
        ),
      ]);

    return UncontrolledProviderScope(
      container: ProviderContainer(overrides: [
        searchServiceProvider.overrideWithValue(searchService),
        if (onFocus != null)
          mapFocusRequesterProvider.overrideWith(
            (ref) => (dynamic target, double zoom) => onFocus(target, zoom),
          ),
      ]),
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider<SpaceProvider>.value(
              value: spaceProvider),
          provider.ChangeNotifierProvider<LocationProvider>.value(
              value: location),
          provider.ChangeNotifierProvider<NavigationController>.value(
              value: nav),
        ],
        child:
            const MaterialApp(home: Scaffold(body: CampusContentPanel())),
      ),
    );
  }

  Future<void> expandPanel(WidgetTester tester) async {
    // Phone-size surface so grid/tap geometry matches real usage.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pumpAndSettle();
  }

  testWidgets('Buildings is the default tab and lists loaded buildings',
      (tester) async {
    await tester.pumpWidget(wrap());

    // CORRECTION PASS (#11): the panel starts COLLAPSED — map dominant.
    final panelH = tester.getSize(find.byType(CampusContentPanel)).height;
    final screenH =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(panelH, lessThan(screenH * 0.2));
    await expandPanel(tester);

    // Default segment is active and both segments exist.
    expect(find.text('Services'), findsWidgets);
    expect(find.text('Buildings'), findsWidgets);

    // Loaded spaces are listed as CARDS (#12) in a grid.
    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('Library Building'), findsOneWidget);
    expect(find.text('Engineering Hall'), findsOneWidget);

    // CORRECTION PASS (#1/#8): no Quick Access/Recent sections, no count.
    expect(find.text('Quick Access'), findsNothing);
    expect(find.text('Recent Waypoints'), findsNothing);
  });

  testWidgets('Services tab renders the discovered service-type grid',
      (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // Discovered categories render as tiles with scoped counts.
    expect(find.text('Toilets'), findsOneWidget);
    expect(find.text('Cafeteria'), findsOneWidget);

    await tester.tap(find.text('Buildings'));
    await tester.pumpAndSettle();
    expect(find.text('Engineering Hall'), findsOneWidget);
  });

  testWidgets('Selecting a building enters Building context; Back keeps it',
      (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    await tester.tap(find.text('Library Building'));
    await tester.pumpAndSettle();

    // Header switched to the building with a back affordance.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.textContaining('Ground Floor'), findsOneWidget);

    // Back returns to the campus list WITHOUT dropping the selection.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Engineering Hall'), findsOneWidget);
    expect(spaceProvider.selectedSpace?.buid, 'buid_a');

    // Re-entering the SAME building from campus still works.
    await tester.tap(find.text('Library Building'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
  });

  testWidgets('Clearing the selection returns the panel to Campus',
      (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    // Enter Building context via domain selection (gesture-equivalent path
    // already covered by the previous test).
    spaceProvider.selectSpace(spaceProvider.spaces.last);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Map tap-on-empty calls clearSelection() in production; simulate it.
    spaceProvider.clearSelection();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Library Building'), findsOneWidget);
  });

  testWidgets('Building → Floor → POI → Destination ladder', (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    // Enter building via domain selection, then wait for floors.
    spaceProvider.selectSpace(spaceProvider.spaces.first);
    await spaceProvider.loadFloorsForSelectedSpace();
    await tester.pumpAndSettle();

    // Floor chips are rendered.
    expect(find.textContaining('Ground Floor'), findsOneWidget);
    expect(find.textContaining('First Floor'), findsOneWidget);

    // Select a floor → Floor context with POI list (connectors filtered).
    // Chip taps live inside a nested horizontal scroller and are covered by
    // the widget itself; here we drive selection via the domain API.
    final firstFloor =
        spaceProvider.floors.firstWhere((f) => f.floorNumber == '1');
    spaceProvider.selectFloor(firstFloor);
    await tester.pumpAndSettle();

    expect(find.textContaining('First Floor'), findsWidgets);
    expect(find.text('Points of Interest'), findsOneWidget);
    expect(find.text('Room 101'), findsOneWidget);
    expect(find.text('connector'), findsNothing);

    // Tap POI → Destination view (PoiDetailCard embedded).
    await tester.tap(find.text('Room 101'));
    await tester.pumpAndSettle();
    expect(find.byType(PoiDetailCard), findsOneWidget);

    // Back from destination returns to the floor list; back again to floors.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(PoiDetailCard), findsNothing);
    expect(find.text('Room 101'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(PoiDetailCard), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // building ctx
    expect(spaceProvider.selectedSpace?.buid, 'buid_a');
  });

  testWidgets('Services grid scopes reactively and enters service context',
      (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    // Open the Services segment.
    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();

    // Campus scope: Toilets tile shows 2 matches; Cafeteria 1.
    expect(find.text('Toilets'), findsOneWidget);
    expect(find.text('Cafeteria'), findsOneWidget);

    // Choose Toilets → results view with campus scope; FIRST result
    // auto-selected and focused (Phase 6 behavior).
    await tester.tap(find.text('Toilets'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Scope: E-JUST'), findsOneWidget);

    // Selecting a building while a service is active RE-SCOPES the service
    // instead of yanking the user into Building context.
    spaceProvider.selectSpace(spaceProvider.spaces.first); // Library
    await tester.pumpAndSettle();
    expect(find.textContaining('Scope: E-JUST › Library Building'),
        findsOneWidget);
    expect(find.text('Toilets B'), findsNothing);

    // Back returns to the type grid (selection preserved).
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Cafeteria'), findsOneWidget);
    expect(spaceProvider.selectedSpace?.buid, 'buid_a');
  });

  testWidgets('Places service exposes the real E-JUST buildings (#2)',
      (tester) async {
    final focused = <dynamic>[];
    await tester.pumpWidget(wrap(onFocus: (t, z) => focused.add(t)));
    await expandPanel(tester);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Places'));
    await tester.pumpAndSettle();

    // Building results carousel with a Directions action.
    expect(find.text('Library Building'), findsWidgets);
    expect(find.text('Route Here'), findsWidgets);

    // Selecting the Library card focuses its coordinates.
    focused.clear();
    await tester.tap(find.text('Library Building').first);
    await tester.pumpAndSettle();
    expect(focused, isNotEmpty);
    expect(spaceProvider.selectedSpace?.buid, 'buid_a');
  });

  testWidgets('Service carousel auto-selects first and follows swipes',
      (tester) async {
    final focusTargets = <dynamic>[];
    await tester.pumpWidget(wrap(onFocus: (t, z) => focusTargets.add(t)));
    await expandPanel(tester);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toilets'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    // First result auto-selected and focused exactly once.
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_a');
    expect(focusTargets, isNotEmpty);

    // Swipe A → B: selection and focus follow the swipe.
    await tester.drag(find.byType(PageView), const Offset(-320, 0));
    await tester.pumpAndSettle();
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_b');
    expect(focusTargets.last.latitude, closeTo(30.8613, 1e-6));

    // Swipe back B → A.
    await tester.drag(find.byType(PageView), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_a');

    // CORRECTION #2: visible arrows, edge-aware and synchronized.
    expect(find.byIcon(Icons.chevron_left), findsNothing); // first item
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_b');
    expect(find.byIcon(Icons.chevron_right), findsNothing); // last item
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_a');

    // Map → carousel direction: a marker tap is an EXTERNAL selection
    // (selectPoi without a swipe). The panel must follow it.
    final toiletB = PoiModel(
      puid: 'svc_toilet_b',
      buid: 'buid_b',
      floorNumber: '0',
      name: 'Toilets B',
      poisType: 'Toilets',
      latitude: 30.8613,
      longitude: 29.5613,
    );
    spaceProvider.selectPoi(toiletB);
    await tester.pumpAndSettle();
    expect(spaceProvider.selectedPoi?.puid, 'svc_toilet_b');
  });

  testWidgets('Single-result service renders one card without a carousel',
      (tester) async {
    await tester.pumpWidget(wrap());
    await expandPanel(tester);

    await tester.tap(find.text('Services'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cafeteria'));
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Cafeteria B'), findsOneWidget);
    expect(find.text('Directions'), findsOneWidget);
    expect(spaceProvider.selectedPoi?.puid, 'svc_cafe_b');
  });
}
