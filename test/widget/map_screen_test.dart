import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:anyplace_campusfind/core/config/map_config.dart';
import 'package:anyplace_campusfind/core/theme/app_theme.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/location_service.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';
import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/floorplan_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/models/user_location.dart';
import 'package:anyplace_campusfind/data/repositories/floorplan_repository.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/location_provider.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/ui/screens/map_screen.dart';
import 'package:anyplace_campusfind/ui/widgets/building_detail_card.dart';
import 'package:anyplace_campusfind/ui/widgets/building_marker.dart';
import 'package:anyplace_campusfind/ui/widgets/building_search_sheet.dart';
import 'package:anyplace_campusfind/ui/widgets/user_location_marker.dart';

class FakeSpaceRepository implements SpaceRepository {
  final List<SpaceModel> fakeSpaces;
  final Map<String, List<FloorModel>> fakeFloors;

  FakeSpaceRepository(this.fakeSpaces, {this.fakeFloors = const {}});

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async {
    return fakeSpaces;
  }

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    final matches = fakeSpaces.where((s) => s.buid == buid);
    return matches.isNotEmpty ? matches.first : null;
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async {
    return fakeFloors[buid] ?? [];
  }
}

class FakeLocationService implements LocationService {
  bool serviceEnabled = true;
  LocationPermissionStatus permissionStatus = LocationPermissionStatus.granted;
  UserLocation? fixedPosition;
  final StreamController<UserLocation> _streamController =
      StreamController<UserLocation>.broadcast();

  FakeLocationService({this.fixedPosition});

  void emitLocation(UserLocation loc) {
    _streamController.add(loc);
  }

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async => permissionStatus;

  @override
  Future<LocationPermissionStatus> requestPermission() async => permissionStatus;

  @override
  Future<UserLocation?> getCurrentPosition() async => fixedPosition;

  @override
  Stream<UserLocation> getPositionStream({int distanceFilter = 2}) =>
      _streamController.stream;
}

class FakeRadioMapRepository implements RadioMapRepository {
  @override
  Future<String> getRadioMap(String buid, String floor, {bool forceReload = false}) async => '';
  @override
  Future<bool> isRadioMapCached(String buid, String floor) async => false;
  @override
  Future<void> clearRadioMap(String buid, String floor) async {}
  @override
  Future<void> clearAllCache() async {}
}

class FakeFloorplanRepository implements FloorplanRepository {
  final Map<String, FloorplanModel> floorplans;
  FakeFloorplanRepository({this.floorplans = const {}});

  @override
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata, {
    bool forceReload = false,
  }) async =>
      floorplans['$buid/$floor'];
  @override
  Future<bool> isFloorplanCached(String buid, String floor) async =>
      floorplans.containsKey('$buid/$floor');
  @override
  Future<void> clearFloorplan(String buid, String floor) async {}
  @override
  Future<void> clearAll() async {}
}

class FakeNativePositioningService implements NativePositioningService {
  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async => true;
  @override
  Future<bool> clearRadioMap() async => true;
  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async => null;
}

void main() {
  final testSpaces = [
    const SpaceModel(
      buid: 'building_test_123',
      name: 'Engineering Building',
      latitude: 35.1444,
      longitude: 33.4105,
      bucode: 'ENG01',
      description: 'Department of Computer Science',
      spaceType: 'building',
    ),
    const SpaceModel(
      buid: 'building_test_456',
      name: 'Science Library',
      latitude: 35.1450,
      longitude: 33.4110,
      bucode: 'LIB01',
      spaceType: 'building',
    ),
  ];

  final testFloors = {
    'building_test_123': [
      const FloorModel(
        buid: 'building_test_123',
        floorNumber: '0',
        floorName: 'Ground Floor',
      ),
      const FloorModel(
        buid: 'building_test_123',
        floorNumber: '1',
        floorName: 'First Floor',
      ),
    ],
    'building_test_456': [
      const FloorModel(
        buid: 'building_test_456',
        floorNumber: '0',
        floorName: 'Library Ground',
      ),
    ],
  };

  final testGpsLocation = UserLocation(
    latitude: 35.1440,
    longitude: 33.4100,
    accuracy: 4.0,
    timestamp: DateTime(2026, 8, 15, 12, 0, 0),
  );

  Widget createTestWidget({
    required SpaceRepository repository,
    FloorplanRepository? floorplanRepository,
    LocationService? locationService,
  }) {
    final locService = locationService ??
        FakeLocationService(fixedPosition: testGpsLocation);

    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<SpaceProvider>(
            create: (_) => SpaceProvider(
              repository: repository,
              radioMapRepository: FakeRadioMapRepository(),
              floorplanRepository:
                  floorplanRepository ?? FakeFloorplanRepository(),
              nativePositioningService: FakeNativePositioningService(),
            ),
          ),
          ChangeNotifierProvider<LocationProvider>(
            create: (_) => LocationProvider(locationService: locService),
          ),
        ],
        child: const MapScreen(),
      ),
    );
  }

  group('MapScreen Widget Tests', () {
    testWidgets('renders map with CARTO Voyager TileLayer and space count',
        (tester) async {
      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);

      await tester.pumpWidget(createTestWidget(repository: repo));
      await tester.pumpAndSettle();

      // Verify app title & building count
      expect(find.text('Anyplace'), findsOneWidget);
      expect(find.text('2 spaces mapped'), findsOneWidget);

      // Verify TileLayer URL is CARTO Voyager
      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.urlTemplate, equals(MapConfig.cartoVoyagerUrlTemplate));

      // Verify BuildingMarker widgets are present
      expect(find.byType(BuildingMarker), findsNWidgets(2));
    });

    testWidgets(
        'tapping a building marker displays BuildingDetailCard and allows selecting floors',
        (tester) async {
      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);

      await tester.pumpWidget(createTestWidget(repository: repo));
      await tester.pumpAndSettle();

      // Trigger onTap callback on first marker (Engineering Building)
      final firstMarker =
          tester.widget<BuildingMarker>(find.byType(BuildingMarker).first);
      firstMarker.onTap();
      await tester.pumpAndSettle();

      // Verify BuildingDetailCard is rendered
      expect(find.byType(BuildingDetailCard), findsOneWidget);
      expect(find.text('Engineering Building'), findsOneWidget);
      expect(find.text('building_test_123'), findsOneWidget);
      expect(find.text('ENG01'), findsOneWidget);

      // Verify Floors section is rendered with loaded floor chips
      expect(find.text('Floors'), findsOneWidget);
      expect(find.text('Ground Floor (Floor 0)'), findsOneWidget);
      expect(find.text('First Floor (Floor 1)'), findsOneWidget);

      // Tap on 'First Floor (Floor 1)' chip
      await tester.tap(find.text('First Floor (Floor 1)'));
      await tester.pumpAndSettle();

      // Verify selected floor indicator
      expect(find.text('Selected: Floor 1'), findsOneWidget);

      // Tap close button on detail card
      final closeButton = find.byIcon(Icons.close);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      // Verify detail card dismissed
      expect(find.byType(BuildingDetailCard), findsNothing);
    });

    testWidgets(
        'search button opens BuildingSearchSheet and selecting building updates selection and loads floors',
        (tester) async {
      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);

      await tester.pumpWidget(createTestWidget(repository: repo));
      await tester.pumpAndSettle();

      // Tap search button in MapControls
      final searchButton = find.byTooltip('Browse / Search Buildings');
      expect(searchButton, findsOneWidget);
      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      // Verify search sheet opened
      expect(find.byType(BuildingSearchSheet), findsOneWidget);
      expect(find.text('Anyplace Buildings (2)'), findsOneWidget);
      expect(find.text('Science Library'), findsOneWidget);

      // Tap second building in search list
      await tester.tap(find.text('Science Library'));
      await tester.pumpAndSettle();

      // Verify detail card for Science Library is displayed
      expect(find.byType(BuildingDetailCard), findsOneWidget);
      expect(find.text('Science Library'), findsOneWidget);
      expect(find.text('building_test_456'), findsOneWidget);
      expect(find.text('LIB01'), findsOneWidget);

      // Verify Science Library floors are loaded
      expect(find.text('Library Ground (Floor 0)'), findsOneWidget);
    });

    testWidgets(
        'tapping My Location button acquires GPS position and shows UserLocationMarker',
        (tester) async {
      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);
      final locService = FakeLocationService(fixedPosition: testGpsLocation);

      await tester.pumpWidget(
        createTestWidget(repository: repo, locationService: locService),
      );
      await tester.pumpAndSettle();

      // Initially, no UserLocationMarker is present
      expect(find.byType(UserLocationMarker), findsNothing);

      // Tap My Location button in controls
      final locationButton = find.byTooltip('My Location / Recenter View');
      expect(locationButton, findsOneWidget);
      await tester.tap(locationButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      // Verify UserLocationMarker is now rendered on map
      expect(find.byType(UserLocationMarker), findsOneWidget);
    });

    testWidgets(
        'tapping My Location when permission is denied displays SnackBar message',
        (tester) async {
      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);
      final locService = FakeLocationService();
      locService.permissionStatus = LocationPermissionStatus.denied;

      await tester.pumpWidget(
        createTestWidget(repository: repo, locationService: locService),
      );
      await tester.pumpAndSettle();

      // Tap My Location button
      final locationButton = find.byTooltip('My Location / Recenter View');
      await tester.tap(locationButton);
      await tester.pumpAndSettle();

      // Verify SnackBar with permission denied message appears
      expect(find.text('Location permission was denied.'), findsOneWidget);
      expect(find.byType(UserLocationMarker), findsNothing);
    });

    testWidgets(
        'displays error banner when repository fails and allows retry',
        (tester) async {
      int fetchCount = 0;
      final failingRepo = _ThrowingSpaceRepository(
        onFetch: () => fetchCount++,
        errorMessage: 'Connection refused',
      );

      await tester.pumpWidget(createTestWidget(repository: failingRepo));
      await tester.pumpAndSettle();

      // Verify error banner is visible
      expect(find.text('Connection refused'), findsOneWidget);
      expect(fetchCount, 1);

      // Tap retry button in error banner
      final retryButton = find.widgetWithText(TextButton, 'Retry');
      expect(retryButton, findsOneWidget);
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(fetchCount, 2);
    });

    testWidgets(
        'selecting a floor displays OverlayImageLayer with floorplan bounds',
        (tester) async {
      final sampleFloorplan = const FloorplanModel(
        buid: 'building_test_123',
        floorNumber: '1',
        imagePath: '/dev/null',
        bottomLeftLat: 35.1440,
        bottomLeftLng: 33.4100,
        topRightLat: 35.1450,
        topRightLng: 33.4110,
        isCached: true,
        imageSizeBytes: 50000,
      );

      final repo = FakeSpaceRepository(testSpaces, fakeFloors: testFloors);
      final floorplanRepo = FakeFloorplanRepository(
        floorplans: {'building_test_123/1': sampleFloorplan},
      );

      await tester.pumpWidget(createTestWidget(
        repository: repo,
        floorplanRepository: floorplanRepo,
      ));
      await tester.pumpAndSettle();

      // Tap on Engineering Building marker
      final firstMarker =
          tester.widget<BuildingMarker>(find.byType(BuildingMarker).first);
      firstMarker.onTap();
      await tester.pumpAndSettle();

      // Select Floor 1
      final floor1Chip = find.text('First Floor (Floor 1)');
      expect(floor1Chip, findsOneWidget);
      await tester.tap(floor1Chip);
      await tester.pumpAndSettle();

      // Verify OverlayImageLayer is rendered
      expect(find.byType(OverlayImageLayer), findsOneWidget);

      final overlayLayer =
          tester.widget<OverlayImageLayer>(find.byType(OverlayImageLayer));
      expect(overlayLayer.overlayImages.length, equals(1));
      final overlay = overlayLayer.overlayImages.first as OverlayImage;
      expect(
        overlay.bounds.southWest.latitude,
        equals(35.1440),
      );
      expect(
        overlay.bounds.northEast.latitude,
        equals(35.1450),
      );
    });
  });
}

class _ThrowingSpaceRepository implements SpaceRepository {
  final VoidCallback onFetch;
  final String errorMessage;

  _ThrowingSpaceRepository({
    required this.onFetch,
    required this.errorMessage,
  });

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async {
    onFetch();
    throw ApiException(errorMessage);
  }

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async {
    throw ApiException(errorMessage);
  }

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async {
    throw ApiException(errorMessage);
  }
}
