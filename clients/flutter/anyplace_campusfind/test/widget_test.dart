import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders the main shell on launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bulkLoaderProvider.overrideWithValue(_FakeBulkLoader()),
        ],
        child: provider.ChangeNotifierProvider<SpaceProvider>.value(
          value: _FakeSpaceProvider(),
          child: const MaterialApp(home: MainShell()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
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
