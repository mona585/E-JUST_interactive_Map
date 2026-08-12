// Shell no longer gates on bulk load — tabs are always visible.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/providers/bulk_load_provider.dart';
import 'package:anyplace_campusfind/providers/providers.dart';
import 'package:anyplace_campusfind/providers/position_provider.dart';
import 'package:anyplace_campusfind/screens/main_shell.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/positioning_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late CacheService cache;

  final building = Space(
    buid: 'b1',
    name: 'Main Building',
    coordinatesLat: 30.85,
    coordinatesLon: 29.59,
    spaceType: 'building',
  );

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

  Override positioningOverride() {
    return positioningServiceProvider.overrideWith(
      (ref) => PositioningService(
        api: ref.read(apiServiceProvider),
        gpsStreamBuilder: () => const Stream<LatLng>.empty(),
        wifiScanBuilder: () async => const [],
        permissionRequest: () async => false,
      ),
    );
  }

  Override positioningGrantedOverride() {
    return positioningServiceProvider.overrideWith(
      (ref) => PositioningService(
        api: ref.read(apiServiceProvider),
        gpsStreamBuilder: () => const Stream<LatLng>.empty(),
        wifiScanBuilder: () async => const [],
        permissionRequest: () async => true,
      ),
    );
  }

  testWidgets('tabs are always visible even while data loads', (tester) async {
    final completer = Completer<BulkLoadResult>();
    container = ProviderContainer(overrides: [
      loaderOverride(() => completer.future),
      cacheServiceProvider.overrideWithValue(cache),
      positioningOverride(),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    // Tabs and nav bar should be visible immediately.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    completer.complete(
        BulkLoadResult(campuses: const [], spaces: [building]));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('shows offline banner when data came from snapshot',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async =>
          BulkLoadResult(campuses: const [], spaces: [building], fromOffline: true)),
      cacheServiceProvider.overrideWithValue(cache),
      positioningOverride(),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Offline — showing cached campus data'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('position tracking starts only while the Map tab is active',
      (tester) async {
    container = ProviderContainer(overrides: [
      loaderOverride(() async =>
          BulkLoadResult(campuses: const [], spaces: [building])),
      cacheServiceProvider.overrideWithValue(cache),
      positioningGrantedOverride(),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    Finder mapDestination() => find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Map'),
        );

    expect(container.read(positionStateProvider).isActive, isFalse);

    await tester.tap(mapDestination());
    await tester.pumpAndSettle();
    expect(container.read(positionStateProvider).isActive, isTrue);

    await tester.tap(find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Home'),
    ));
    await tester.pumpAndSettle();
    expect(container.read(positionStateProvider).isActive, isFalse);
  });
}

class _FakeBulkLoader implements BulkLoader {
  _FakeBulkLoader(this.loader);

  final Future<BulkLoadResult> Function() loader;

  @override
  Future<BulkLoadResult> load() => loader();
}
