import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/constants.dart';
import 'config/theme.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';
import 'screens/campus_selection_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: CampusFindApp()));
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

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCampusId = ref.watch(selectedCampusIdProvider);
    if (selectedCampusId == null) {
      return CampusSelectionScreen(onSelected: (cuid) {
        ref.read(selectedCampusIdProvider.notifier).state = cuid;
      });
    }
    return const MainShell();
  }
}