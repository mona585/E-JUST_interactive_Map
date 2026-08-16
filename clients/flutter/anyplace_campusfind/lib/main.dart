import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/constants.dart';
import 'config/theme.dart';
import 'providers/providers.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The app's backend is a fixed build-time constant; a previously persisted
  // server_url must never override it. Drop any stale value left by older
  // builds so the app always talks to the public Anyplace backend.
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('server_url');
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

  /// Ensures the single primary (UCY) campus is selected. CampusFind is
  /// single-campus by design — there is no campus picker and no user decision.
  /// A stale persisted value is normalised to the primary campus.
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