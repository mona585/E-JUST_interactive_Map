import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/providers/directions_provider.dart';
import 'package:anyplace_campusfind/providers/search_provider.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/views/search_overlay.dart';

// BUG 1 regression coverage: this exercises the REAL rendered interaction path
// (SearchOverlay widget + tap + text entry), not just the ViewModel. The bug
// was that the only text input inside the origin picker was DISABLED while
// `pickingFrom` was true, so tapping the From / My Location field entered a
// mode with no usable search field.

SpaceModel _space(String name, String buid, double lat, double lng) =>
    SpaceModel(
      buid: buid,
      name: name,
      latitude: lat,
      longitude: lng,
      spaceType: 'building',
    );

class _NoopSpaceViewModel extends SpaceViewModel {}

Widget _host(SearchService service, SpaceViewModel space) {
  return ProviderScope(
    overrides: [searchServiceProvider.overrideWithValue(service)],
    child: provider.ChangeNotifierProvider<SpaceViewModel>.value(
      value: space,
      child: const MaterialApp(home: SearchOverlay()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  SearchService populatedService() {
    final service = SearchService();
    service.addSpaces([
      _space('Library Building', 'b1', 30.8600, 29.5600),
      _space('Engineering Building', 'b2', 30.8610, 29.5610),
    ]);
    return service;
  }

  testWidgets('tapping the From / My Location field opens a usable origin '
      'picker (enabled search field that accepts text)', (tester) async {
    final space = _NoopSpaceViewModel();
    await tester.pumpWidget(_host(populatedService(), space));
    await tester.pumpAndSettle();

    // The From row shows My Location by default.
    expect(find.text('From'), findsOneWidget);
    expect(find.text('My Location'), findsOneWidget);

    // Tap the REAL From field ("My Location" box).
    await tester.tap(find.text('My Location'));
    await tester.pumpAndSettle();

    // Pick mode is visibly active.
    expect(find.text('Choose origin'), findsOneWidget);
    expect(find.text('Use current device location'), findsOneWidget);

    // The origin picker must expose a USABLE (enabled) search field.
    final fieldFinder = find.byType(TextField);
    expect(fieldFinder, findsOneWidget);
    final field = tester.widget<TextField>(fieldFinder);
    expect(
      field.enabled,
      isNot(false),
      reason: 'the origin search field must be enabled while picking an origin',
    );

    // …and it must actually accept text and filter to campus buildings.
    await tester.enterText(fieldFinder, 'eng');
    await tester.pumpAndSettle();
    expect(find.text('Engineering Building'), findsOneWidget);
    expect(find.text('Library Building'), findsNothing);
  });

  testWidgets('selecting a building sets it as the origin and clears pick mode',
      (tester) async {
    final space = _NoopSpaceViewModel();
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [searchServiceProvider.overrideWithValue(populatedService())],
        child: provider.ChangeNotifierProvider<SpaceViewModel>.value(
          value: space,
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SearchOverlay();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Location'));
    await tester.pumpAndSettle();
    expect(find.text('Choose origin'), findsOneWidget);

    await tester.tap(find.text('Library Building').last);
    await tester.pumpAndSettle();

    // Pick mode closed and the From row now shows the chosen building.
    expect(find.text('Choose origin'), findsNothing);
    final fromColumn = find
        .ancestor(of: find.text('From'), matching: find.byType(Column))
        .first;
    expect(
      find.descendant(
        of: fromColumn,
        matching: find.text('Library Building'),
      ),
      findsOneWidget,
    );
    expect(capturedRef.read(directionOriginProvider).isMyLocation, isFalse);
    expect(
      capturedRef.read(directionOriginProvider).space?.buid,
      'b1',
    );
  });

  testWidgets('cancelling the picker preserves My Location and returning to '
      'My Location works', (tester) async {
    final space = _NoopSpaceViewModel();
    await tester.pumpWidget(_host(populatedService(), space));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Location'));
    await tester.pumpAndSettle();
    expect(find.text('Choose origin'), findsOneWidget);

    // Cancel preserves the previous (My Location) origin.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Choose origin'), findsNothing);
    expect(find.text('My Location'), findsOneWidget);
  });
}
