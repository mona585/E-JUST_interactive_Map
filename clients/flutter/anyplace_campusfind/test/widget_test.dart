// Basic smoke test for the CampusFind app shell.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/main.dart';

void main() {
  testWidgets('App renders the map preview shell', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: CampusFindApp()));

    expect(find.text('CampusFind Map'), findsOneWidget);
  });
}
