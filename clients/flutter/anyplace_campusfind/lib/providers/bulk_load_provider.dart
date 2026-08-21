import 'package:flutter_riverpod/flutter_riverpod.dart';

final bulkLoadProvider = FutureProvider<BulkLoadResult>((ref) async {
  return const BulkLoadResult();
});

class BulkLoadResult {
  const BulkLoadResult({
    this.campuses = const [],
    this.spaces = const [],
    this.error,
    this.fromOffline = false,
  });

  final List<dynamic> campuses;
  final List<dynamic> spaces;
  final Object? error;
  final bool fromOffline;
}

class BulkLoader {
  Future<BulkLoadResult> load() async => const BulkLoadResult();
}

final bulkLoaderProvider = Provider<BulkLoader>((ref) => BulkLoader());
