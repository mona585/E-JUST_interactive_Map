import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/screens/profile_screen.dart';
import 'package:anyplace_campusfind/screens/search_screen.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Widget wrap() {
    return UncontrolledProviderScope(
      container: container,
      child: provider.ChangeNotifierProvider<SpaceProvider>.value(
        value: _FakeSpaceProvider(),
        child: const MaterialApp(home: MainShell()),
      ),
    );
  }

  Override loaderOverride(Future<BulkLoadResult> Function() loader) {
    return bulkLoaderProvider.overrideWithValue(
      _FakeBulkLoader(loader),
    );
  }

  testWidgets('tabs are always visible even while data loads', (tester) async {
    final completer = Completer<BulkLoadResult>();
    container = ProviderContainer(overrides: [
      loaderOverride(() => completer.future),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    completer.complete(const BulkLoadResult());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shows offline banner when data came from snapshot',
      (tester) async {
    container = ProviderContainer(overrides: [
      bulkLoadProvider.overrideWith(
          (ref) async => const BulkLoadResult(fromOffline: true)),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached campus data'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('bottom nav contains exactly Home and Map', (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.destinations.length, 2);

    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Map'),
      ),
      findsOneWidget,
    );

    // Search and Profile are NOT bottom-navigation destinations.
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Search'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Profile'),
      ),
      findsNothing,
    );
  });

  testWidgets('Home search bar opens the Search screen', (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search professors, rooms, halls...'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsOneWidget);
    expect(find.text('Search Directory'), findsOneWidget);
  });

  testWidgets('Home profile button opens the Profile screen', (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Clear Quick Access'), findsOneWidget);
  });
}

class _FakeBulkLoader implements BulkLoader {
  _FakeBulkLoader(this.loader);

  final Future<BulkLoadResult> Function() loader;

  @override
  Future<BulkLoadResult> load() => loader();
}

class _FakeSpaceProvider extends SpaceProvider {
  @override
  Future<void> loadSpaces({bool forceReload = false}) async {}

  @override
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {}

  @override
  Future<void> loadCustomRoutes() async {}
}
