import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/datasources/anyplace_api_client.dart';
import 'data/datasources/floorplan_cache.dart';
import 'data/datasources/gps_location_service.dart';
import 'data/datasources/native_positioning_service.dart';
import 'data/datasources/radiomap_cache.dart';
import 'data/repositories/floorplan_repository.dart';
import 'data/repositories/radiomap_repository.dart';
import 'data/repositories/space_repository.dart';
import 'state/location_provider.dart';
import 'state/space_provider.dart';
import 'ui/screens/map_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final apiClient = AnyplaceApiClient();
  final repository = AnyplaceSpaceRepository(apiClient: apiClient);
  final radiomapCache = RadioMapCache();
  final radioMapRepository = AnyplaceRadioMapRepository(
    apiClient: apiClient,
    cache: radiomapCache,
  );
  final floorplanCache = FloorplanCache();
  final floorplanRepository = AnyplaceFloorplanRepository(
    apiClient: apiClient,
    cache: floorplanCache,
  );
  final nativePositioningService = MethodChannelNativePositioningService();
  final locationService = GpsLocationService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SpaceProvider>(
          create: (_) => SpaceProvider(
            repository: repository,
            radioMapRepository: radioMapRepository,
            floorplanRepository: floorplanRepository,
            nativePositioningService: nativePositioningService,
          ),
        ),
        ChangeNotifierProvider<LocationProvider>(
          create: (_) => LocationProvider(locationService: locationService),
        ),
      ],
      child: const AnyplaceCampusFindApp(),
    ),
  );
}

/// Root Application Widget for Anyplace CampusFind.
class AnyplaceCampusFindApp extends StatelessWidget {
  const AnyplaceCampusFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anyplace CampusFind',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MapScreen(),
    );
  }
}
