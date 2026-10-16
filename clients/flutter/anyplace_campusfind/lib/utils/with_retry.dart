import 'package:flutter/foundation.dart';

/// Retries [fn] up to [maxRetries] times with exponential backoff.
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxRetries = 2,
  String label = '',
}) async {
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt < maxRetries) {
        final delaySec = 1 << attempt; // 1s, 2s, 4s...
        debugPrint(
          '$label attempt ${attempt + 1} failed ($e), retrying in ${delaySec}s...',
        );
        await Future.delayed(Duration(seconds: delaySec));
      } else {
        rethrow;
      }
    }
  }
  throw StateError('unreachable');
}