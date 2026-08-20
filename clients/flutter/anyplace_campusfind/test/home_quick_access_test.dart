import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/data/models/quick_access_item.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/screens/home_screen.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();
  });

  SpaceModel space(String name) => SpaceModel(
        buid: 'buid_$name',
        name: name,
        latitude: 30.86,
        longitude: 29.56,
        spaceType: 'building',
      );

  Widget wrap(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: provider.ChangeNotifierProvider<SpaceProvider>.value(
        value: _FakeSpaceProvider(),
        child: const MaterialApp(home: _Harness()),
      ),
    );
  }

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  testWidgets('Quick Access renders compact horizontal cards from QuickAccessItem',
      (tester) async {
    await cache.toggleQuickAccessItem(QuickAccessItem.fromSpace(
      space('Library of Science'),
      addedAt: 1,
      category: 'library',
    ));
    await cache.toggleQuickAccessItem(QuickAccessItem.fromSpace(
      space('Blue hall Cafeteria'),
      addedAt: 2,
      category: 'cafeteria',
    ));

    await tester.pumpWidget(wrap(container()));
    await tester.pumpAndSettle();

    // Old compact horizontal layout: a single horizontally scrolling list.
    final horizontalLists = tester
        .widgetList<ListView>(find.byType(ListView))
        .where((l) => l.scrollDirection == Axis.horizontal)
        .toList();
    expect(horizontalLists.length, 1);

    // Cards keep the original 130-wide dimensions.
    final cardContainers = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 130)
        .toList();
    expect(cardContainers.length, 2);

    // Display snapshot data renders (works even without loaded entities).
    expect(find.text('Library of Science'), findsOneWidget);
    expect(find.text('Blue hall Cafeteria'), findsOneWidget);

    // No extra "Search" label/button next to the Quick Access title.
    expect(find.widgetWithText(TextButton, 'Search'), findsNothing);
  });

  testWidgets('Quick Access bookmark toggle removes an item and persists',
      (tester) async {
    await cache.toggleQuickAccessItem(QuickAccessItem.fromSpace(
      space('Library of Science'),
      addedAt: 1,
      category: 'library',
    ));

    await tester.pumpWidget(wrap(container()));
    await tester.pumpAndSettle();

    expect(find.text('Library of Science'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();

    // Removed from the persisted store and the UI (empty state shown).
    expect(await cache.getQuickAccessItems(), isEmpty);
    expect(find.text('Library of Science'), findsNothing);

    // Let the snackbar timer expire so the test ends cleanly.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('Quick Access items persist across app restarts',
      (tester) async {
    final item = QuickAccessItem.fromSpace(
      space('National Bank branch'),
      addedAt: 1,
      category: 'building',
    );
    await cache.toggleQuickAccessItem(item);

    await tester.pumpWidget(wrap(container()));
    await tester.pumpAndSettle();
    expect(find.text('National Bank branch'), findsOneWidget);

    // Simulate restart: a fresh CacheService over the same prefs.
    final restarted = CacheService();
    final items = await restarted.getQuickAccessItems();
    expect(items.length, 1);
    expect(items.first.name, 'National Bank branch');
    expect(items.first.category, 'building');
  });
}

/// Mirrors MainShell: wires cache-change notifications so Quick Access
/// toggles immediately refresh the Home screen.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    wireCacheNotifications(ref);
    return const HomeScreen();
  }
}

class _FakeSpaceProvider extends SpaceProvider {
  @override
  Future<void> loadSpaces({bool forceReload = false}) async {}

  @override
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {}

  @override
  Future<void> loadCustomRoutes() async {}
}