// Smoke tests for the app shell (no campus selected -> campus selection).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App renders the campus selection screen on first launch',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: CampusFindApp()));
    await tester.pumpAndSettle();

    // No configured campuses -> the empty-state hint is shown.
    expect(find.text('Welcome to CampusFind'), findsOneWidget);
    expect(find.text('No campuses configured'), findsOneWidget);
  });
}
