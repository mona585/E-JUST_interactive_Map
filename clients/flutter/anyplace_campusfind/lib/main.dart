import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/constants.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = ProviderContainer();
  final cache = container.read(cacheServiceProvider);
  final savedCampus = await cache.getSelectedCampusId();
  if (savedCampus != null) {
    container.read(selectedCampusIdProvider.notifier).state = savedCampus;
  }
  runApp(UncontrolledProviderScope(
    container: container,
    child: const CampusFindApp(),
  ));
}

class CampusFindApp extends StatelessWidget {
  const CampusFindApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const RootRouter(),
    );
  }
}
