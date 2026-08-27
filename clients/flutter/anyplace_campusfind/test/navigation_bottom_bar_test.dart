import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/ui/widgets/navigation_bottom_bar.dart';

void main() {
  testWidgets('compact navigation bar renders controls and fires callbacks',
      (tester) async {
    var expanded = false;
    var closed = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBottomBar(
          subtitle: 'Library · Floor 1',
          onClose: () => closed = true,
          onExpand: () => expanded = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Active indication + subtitle.
    expect(find.text('Navigation active'), findsOneWidget);
    expect(find.text('Library · Floor 1'), findsOneWidget);

    // Expand control re-opens the panel WITHOUT ending navigation.
    await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
    await tester.pump();
    expect(expanded, isTrue);
    expect(closed, isFalse);

    // Close control ends navigation via the existing termination flow.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('tapping the bar body expands the panel', (tester) async {
    var expanded = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBottomBar(
          onClose: () {},
          onExpand: () => expanded = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Navigation active'));
    await tester.pump();
    expect(expanded, isTrue);
  });
}
