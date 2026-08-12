// Phase 7.1 — CampusSelectionScreen loading, error, empty and retry states.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/campus.dart';
import 'package:anyplace_campusfind/providers/campus_provider.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/screens/campus_selection_screen.dart';
import 'package:anyplace_campusfind/services/api_service.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';

/// CampusLoader whose loadConfigured() can be scripted per call.
class _ScriptedCampusLoader implements CampusLoader {
  _ScriptedCampusLoader(this._script);

  final List<Future<List<Campus>> Function()> _script;
  int _calls = 0;

  @override
  Future<List<Campus>> loadConfigured({List<String>? cuids}) async {
    final fn = _script[_calls < _script.length ? _calls : _script.length - 1];
    _calls++;
    return fn();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final campus = Campus(
    cuid: 'c1',
    name: 'E-JUST',
    spaces: const [],
  );

  testWidgets('shows a retry screen after a failed load and recovers on retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      campusLoaderProvider.overrideWithValue(_ScriptedCampusLoader([
        () async => throw ApiException('network down'),
        () async => [campus],
      ])),
      cacheServiceProvider.overrideWithValue(CacheService()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CampusSelectionScreen(onSelected: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();

    // First call failed -> error state with Retry.
    expect(find.text('Could not load campuses'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    // Tap Retry -> second call succeeds.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Choose your campus'), findsOneWidget);
    expect(find.text('E-JUST'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('shows the empty state when no campuses are configured',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(overrides: [
      campusLoaderProvider
          .overrideWithValue(_ScriptedCampusLoader([() async => const []])),
      cacheServiceProvider.overrideWithValue(CacheService()),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CampusSelectionScreen(onSelected: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No campuses configured'), findsOneWidget);
  });
}
