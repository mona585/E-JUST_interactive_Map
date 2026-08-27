import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/navigation_controller.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/widgets/campus_content_panel.dart';

import 'helpers/fake_google_maps_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeGoogleMapsPlatform);

  testWidgets('App renders the map-first shell on launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final space = _FakeSpaceProvider();
    final location = LocationProvider();
    final nav = NavigationController(
      spaceProvider: space,
      locationProvider: location,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bulkLoaderProvider.overrideWithValue(_FakeBulkLoader()),
        ],
        child: provider.MultiProvider(
          providers: [
            provider.ChangeNotifierProvider<SpaceProvider>.value(value: space),
            provider.ChangeNotifierProvider<LocationProvider>.value(
                value: location),
            provider.ChangeNotifierProvider<NavigationController>.value(
                value: nav),
          ],
          child: const MaterialApp(home: MainShell()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Map-first shell: no bottom tab bar anymore.
    expect(find.byType(NavigationBar), findsNothing);

    // The single dynamic content area is present at launch.
    expect(find.byType(CampusContentPanel), findsOneWidget);

    // Campus context shows the Buildings section and the top search bar.
    expect(find.text('Buildings'), findsWidgets);
    expect(find.text('Search buildings, rooms, services…'), findsOneWidget);
  });
}

class _FakeBulkLoader implements BulkLoader {
  @override
  Future<BulkLoadResult> load() async => const BulkLoadResult();
}

class _FakeSpaceProvider extends SpaceProvider {
  @override
  Future<void> loadSpaces({bool forceReload = false}) async {}

  @override
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {}

  @override
  Future<void> loadCustomRoutes() async {}
}
