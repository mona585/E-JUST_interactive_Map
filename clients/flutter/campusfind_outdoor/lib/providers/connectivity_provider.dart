import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Live connectivity state.
///
/// `onConnectivityChanged` resets the `none` element to an empty list on some
/// platforms, so we treat "no non-none result" as offline.
final connectivityStreamProvider =
    StreamProvider<List<ConnectivityResult>>((ref) {
  return Connectivity().onConnectivityChanged;
});

/// Convenience synchronous view of [connectivityStreamProvider]: true when at
/// least one interface is available. Errors/loading are treated as online so
/// the UI never shows a spurious offline banner.
final isOnlineProvider = Provider<bool>((ref) {
  final state = ref.watch(connectivityStreamProvider);
  return state.when(
    data: (list) => list.any((e) => e != ConnectivityResult.none),
    loading: () => true,
    error: (_, __) => true,
  );
});
