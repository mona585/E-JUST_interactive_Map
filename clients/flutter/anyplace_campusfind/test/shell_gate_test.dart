import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/datasources/gps_location_service.dart';
import 'package:anyplace_campusfind/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/providers/connectivity_provider.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/views/main_shell.dart';
import 'package:anyplace_campusfind/views/profile_screen.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/widgets/campus_content_panel.dart';

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
    final space = _FakeSpaceViewModel();
    final location = LocationViewModel(
      locationService: GpsLocationService(),
      nativePositioningService: MethodChannelNativePositioningService(),
    );
    final navController = NavigationViewModel(
      spaceProvider: space,
      locationProvider: location,
    );
    return UncontrolledProviderScope(
      container: container,
      child: provider.MultiProvider(
        providers: [
          provider.ChangeNotifierProvider<SpaceViewModel>.value(value: space),
          provider.ChangeNotifierProvider<LocationViewModel>.value(
            value: location,
          ),
          provider.ChangeNotifierProvider<NavigationViewModel>.value(
            value: navController,
          ),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
  }

  testWidgets('map-first shell renders immediately', (tester) async {
    container = ProviderContainer(
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    // No bottom tab bar in the map-first shell; the dynamic content area is
    // present from the first frame.
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(CampusContentPanel), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(CampusContentPanel), findsOneWidget);
  });

  testWidgets('shows offline banner when connectivity is lost', (tester) async {
    container = ProviderContainer(
      overrides: [
        isOnlineProvider.overrideWithValue(false),
        cacheServiceProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached campus data'), findsOneWidget);
  });

  testWidgets('map-first shell has no bottom navigation destinations', (
    tester,
  ) async {
    container = ProviderContainer(
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsNothing);

    // Profile is reachable via the top-bar avatar, never mounted by default.
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets('Top search bar opens the From/To search overlay', (
    tester,
  ) async {
    container = ProviderContainer(
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search buildings, rooms, services…'));
    await tester.pumpAndSettle();

    // Phase 2: the top bar opens the From/To overlay, not the directory.
    expect(find.text('Where to?'), findsOneWidget);
    expect(find.text('From'), findsOneWidget);
    expect(find.text('My Location'), findsOneWidget);
  });

  testWidgets('Top bar avatar opens the Profile screen', (tester) async {
    container = ProviderContainer(
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Clear Quick Access'), findsOneWidget);
  });
}

class _FakeSpaceViewModel extends SpaceViewModel {
  @override
  Future<void> loadSpaces({bool forceReload = false}) async {}

  @override
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {}

  @override
  Future<void> loadCustomRoutes() async {}
}
