import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/datasources/gps_location_service.dart';
import 'package:anyplace_campusfind/views/main_shell.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/viewmodels/location_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/navigation_view_model.dart';
import 'package:anyplace_campusfind/viewmodels/space_view_model.dart';
import 'package:anyplace_campusfind/widgets/campus_content_panel.dart';

import 'helpers/fake_google_maps_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(installFakeGoogleMapsPlatform);

  testWidgets('App renders the map-first shell on launch', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final space = _FakeSpaceViewModel();
    final location = LocationViewModel(
      locationService: GpsLocationService(),
    );
    final nav = NavigationViewModel(
      spaceProvider: space,
      locationProvider: location,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: const [],
        child: provider.MultiProvider(
          providers: [
            provider.ChangeNotifierProvider<SpaceViewModel>.value(value: space),
            provider.ChangeNotifierProvider<LocationViewModel>.value(
              value: location,
            ),
            provider.ChangeNotifierProvider<NavigationViewModel>.value(
              value: nav,
            ),
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
    expect(find.text('Search buildings…'), findsOneWidget);
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
