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
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/widgets/campus_content_panel.dart';

import 'helpers/fake_google_maps_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    installFakeGoogleMapsPlatform();
    cache = CacheService();
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Widget wrap() {
    final space = _FakeSpaceProvider();
    final location = LocationProvider();
    final navController = NavigationController(
      spaceProvider: space,
      locationProvider: location,
    );
    return UncontrolledProviderScope(
      container: container,
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider<SpaceProvider>.value(value: space),
          provider.ChangeNotifierProvider<LocationProvider>.value(
              value: location),
          provider.ChangeNotifierProvider<NavigationController>.value(
              value: navController),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
  }

  Override loaderOverride(Future<BulkLoadResult> Function() loader) {
    return bulkLoaderProvider.overrideWithValue(
      _FakeBulkLoader(loader),
    );
  }

  testWidgets('map-first shell renders immediately while data loads',
      (tester) async {
    final completer = Completer<BulkLoadResult>();
    container = ProviderContainer(overrides: [
      loaderOverride(() => completer.future),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    // No bottom tab bar in the map-first shell; the dynamic content area is
    // present from the first frame.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(CampusContentPanel), findsOneWidget);

    completer.complete(const BulkLoadResult());
    await tester.pumpAndSettle();
    expect(find.byType(CampusContentPanel), findsOneWidget);
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
  });

  testWidgets('map-first shell has no bottom navigation destinations',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);

    // Profile is reachable via the top-bar avatar, never mounted by default.
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('Top search bar opens the From/To search overlay',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search buildings, rooms, services…'));
    await tester.pumpAndSettle();

    // Phase 2: the top bar opens the From/To overlay, not the directory.
    expect(find.byType(SearchScreen), findsNothing);
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('My Location'), findsOneWidget);
  });

  testWidgets('Top bar avatar opens the Profile screen', (tester) async {
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
