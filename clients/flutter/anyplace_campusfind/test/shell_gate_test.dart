import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService();
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  Widget wrap() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainShell()),
    );
  }

  Override loaderOverride(Future<BulkLoadResult> Function() loader) {
    return bulkLoaderProvider.overrideWithValue(
      _FakeBulkLoader(loader),
    );
  }

  testWidgets('tabs are always visible even while data loads', (tester) async {
    final completer = Completer<BulkLoadResult>();
    container = ProviderContainer(overrides: [
      loaderOverride(() => completer.future),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    completer.complete(const BulkLoadResult());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shows offline banner when data came from snapshot',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult(fromOffline: true)),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached campus data'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('bottom nav switches between Home, Search, Saved, Profile',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async => const BulkLoadResult()),
      cacheServiceProvider.overrideWithValue(cache),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
  });
}

class _FakeBulkLoader implements BulkLoader {
  _FakeBulkLoader(this.loader);

  final Future<BulkLoadResult> Function() loader;

  @override
  Future<BulkLoadResult> load() => loader();
}
