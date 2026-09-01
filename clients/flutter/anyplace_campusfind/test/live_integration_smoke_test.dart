// OPT-IN LIVE INTEGRATION SMOKE TEST.
//
// Hits the REAL backend (https://map.beout.ai) to catch contract drift
// (e.g. a changed response shape, a renamed field, a missing E-JUST campus).
// DISABLED by default so it never runs in normal CI or local `flutter test`.
// Enable explicitly with:
//
//   flutter test --dart-define=LIVE_SMOKE=true test/live_integration_smoke_test.dart
//
// Requires network access to the backend. This is intentionally kept out of
// the default unit-test path; the default CI path uses fakes (see the other
// test files). See CAMPUSFIND_PLAN.md Phase 8 (T8.3).

import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/api_config.dart';
import 'package:anyplace_campusfind/config/constants.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';

void main() {
  // Guard: skip unless explicitly enabled via --dart-define=LIVE_SMOKE=true.
  if (!const bool.fromEnvironment('LIVE_SMOKE', defaultValue: false)) {
    test('live integration smoke test (disabled — pass --dart-define=LIVE_SMOKE=true to run)',
        () {},
        skip: true);
    return;
  }

  group('Live integration smoke (${ApiConfig.serverUrl})', () {
    late AnyplaceApiClient client;

    setUp(() {
      client = AnyplaceApiClient();
    });

    test('space/public returns the hard-coded E-JUST campus and is non-empty',
        () async {
      final spaces = await client.fetchPublicSpaces();
      expect(spaces, isNotEmpty,
          reason: 'Backend returned no public spaces.');
      final ejust = spaces
          .where((s) => s.buid == AppConstants.primaryCampusCuid)
          .toList();
      expect(ejust, isNotEmpty,
          reason: 'Expected the hard-coded E-JUST campus '
              '(${AppConstants.primaryCampusCuid}) to be present.');
    });
  });
}
