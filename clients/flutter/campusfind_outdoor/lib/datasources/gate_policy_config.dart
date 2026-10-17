import 'dart:convert';

import 'package:flutter/services.dart';

/// Parsed campus gate routing policy, loaded from `gate_policy.json`.
///
/// This is POLICY only (which gate is preferred and which are disabled), keyed
/// by gate id. Gate ids/names/coordinates still come from
/// `university gates.kmz`; this file never contains coordinates — only ids.
class GatePolicyConfig {
  /// Immutable parsed policy loaded from the bundled asset.
  const GatePolicyConfig({required this.preferredGateId, required this.disabledGateIds});

  /// The gate id that should be preferred for outside→campus routing,
  /// or null when no preference is configured.
  final String? preferredGateId;

  /// Ids of gates disabled by policy (never routed to).
  final Set<String> disabledGateIds;
}

/// Loads the gate routing policy from the bundled `gate_policy.json` asset
/// and parses it into a [GatePolicyConfig].
///
/// Uses standard JSON parsing (`dart:convert`); no additional dependencies.
///
/// Throws a [FormatException] (or rethrows asset load errors) if the file is
/// missing or malformed, so callers can surface a clear startup failure.
class GatePolicyConfigLoader {
  /// Bundled asset with the gate routing policy.
  static const String assetPath = 'assets/config/gate_policy.json';

  const GatePolicyConfigLoader();

  /// Reads [assetPath] and parses it.
  ///
  /// [parse] is injectable for tests so parsing can be unit-tested without
  /// the asset bundle.
  Future<GatePolicyConfig> load({
    Future<String> Function(String path)? loadString,
    GatePolicyConfig Function(String json)? parse,
  }) async {
    final read = loadString ?? _readAsset;
    final toConfig = parse ?? decode;
    final raw = await read(assetPath);
    return toConfig(raw);
  }

  static Future<String> _readAsset(String path) => rootBundle.loadString(path);

  /// Parses a raw JSON config string into a [GatePolicyConfig].
  ///
  /// Expects:
  /// ```json
  /// { "preferredGateId": "G2", "disabledGateIds": ["G1", "G3", "G4"] }
  /// ```
  /// Both keys are optional. `disabledGateIds` may be absent/empty. This
  /// deliberately never reads or validates gate coordinates — only ids.
  static GatePolicyConfig decode(String json) {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('gate policy must be a JSON object');
    }

    final String? preferredGateId = decoded['preferredGateId'] as String?;

    final Object? disabledRaw = decoded['disabledGateIds'];
    final Set<String> disabledGateIds = <String>{};
    if (disabledRaw != null) {
      if (disabledRaw is! List) {
        throw const FormatException('disabledGateIds must be a JSON array');
      }
      for (final entry in disabledRaw) {
        if (entry is! String) {
          throw const FormatException(
              'disabledGateIds entries must be strings');
        }
        disabledGateIds.add(entry);
      }
    }

    return GatePolicyConfig(
      preferredGateId: preferredGateId,
      disabledGateIds: disabledGateIds,
    );
  }
}
