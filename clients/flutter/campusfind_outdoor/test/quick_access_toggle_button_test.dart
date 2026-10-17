import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/quick_access_item.dart';
import 'package:anyplace_campusfind/models/space_model.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/widgets/quick_access_toggle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Quick AccessToggleButton toggles bookmark state and persists',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final cache = CacheService();
    final item = QuickAccessItem.fromSpace(
      const SpaceModel(
        buid: 'buid_library',
        name: 'Library',
        latitude: 35.1,
        longitude: 33.4,
        spaceType: 'library',
      ),
      addedAt: 1,
      category: 'library',
    );

    final container = ProviderContainer(overrides: [
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: _Harness(item: item)),
      ),
    );
    await tester.pumpAndSettle();

    // Unsaved initially.
    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    // Tapping saves the item and persists it.
    await tester.tap(find.byType(QuickAccessToggleButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(await cache.isQuickAccessItem(item.type, item.id), isTrue);

    // Tapping again removes it.
    await tester.tap(find.byType(QuickAccessToggleButton));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsNothing);
    expect(await cache.isQuickAccessItem(item.type, item.id), isFalse);

    // Let any snackbar timer expire so the test ends cleanly.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}

/// Mirrors MainShell: wires cache-change notifications so the toggle button
/// re-evaluates its saved state immediately after a tap.
class _Harness extends ConsumerWidget {
  const _Harness({required this.item});

  final QuickAccessItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    wireCacheNotifications(ref);
    return Scaffold(body: QuickAccessToggleButton(itemBuilder: () => item));
  }
}