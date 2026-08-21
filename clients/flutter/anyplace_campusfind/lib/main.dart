import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:shared_preferences/shared_preferences.dart';

import 'config/constants.dart';
import 'config/theme.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';
import 'services/cache_service.dart';
import 'state/location_provider.dart';
import 'state/navigation_controller.dart';
import 'state/space_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('server_url');

  final locationProvider = LocationProvider();
  final cacheService = CacheService();
  final spaceProvider = SpaceProvider(
    cacheService: cacheService,
  );
  final navigationController = NavigationController(
    spaceProvider: spaceProvider,
    locationProvider: locationProvider,
  );

  runApp(
    provider.MultiProvider(
      providers: [
        provider.ChangeNotifierProvider.value(value: locationProvider),
        provider.ChangeNotifierProvider.value(value: spaceProvider),
        provider.ChangeNotifierProvider.value(value: navigationController),
      ],
      child: ProviderScope(
        overrides: [
          cacheServiceProvider.overrideWithValue(cacheService),
        ],
        child: const CampusFindApp(),
      ),
    ),
  );
}

class CampusFindApp extends StatelessWidget {
  const CampusFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RootRouter(),
    );
  }
}

class RootRouter extends ConsumerStatefulWidget {
  const RootRouter({super.key});

  @override
  ConsumerState<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends ConsumerState<RootRouter> {
  bool _restored = false;

  @override
  void initState() {
    super.initState();
    _restoreSelection();
  }

  Future<void> _restoreSelection() async {
    final saved = await ref.read(cacheServiceProvider).getSelectedCampusId();
    if (!mounted) return;
    if (saved != AppConstants.primaryCampusCuid) {
      await ref
          .read(cacheServiceProvider)
          .setSelectedCampusId(AppConstants.primaryCampusCuid);
    }
    ref.read(selectedCampusIdProvider.notifier).state =
        AppConstants.primaryCampusCuid;
    setState(() => _restored = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_restored) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return const MainShell();
  }
}
