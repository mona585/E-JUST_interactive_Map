// Smoke test: app opens directly to the main shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/providers/position_provider.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/services/positioning_service.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders the main shell on launch', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          bulkLoaderProvider.overrideWithValue(_FakeBulkLoader()),
          positioningServiceProvider.overrideWith(
            (ref) => PositioningService(
              api: ref.read(apiServiceProvider),
              gpsStreamBuilder: () => const Stream<LatLng>.empty(),
              wifiScanBuilder: () async => const [],
              permissionRequest: () async => false,
            ),
          ),
        ],
        child: const MaterialApp(home: MainShell()),
      ),
    );
    await tester.pumpAndSettle();

    // App opens directly to the tab shell — no campus selection screen.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });
}

class _FakeBulkLoader implements BulkLoader {
  @override
  Future<BulkLoadResult> load() async =>
      BulkLoadResult(campuses: const [], spaces: const []);
}
