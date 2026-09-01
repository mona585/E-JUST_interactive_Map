import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../datasources/kmz_loader.dart';
import '../models/campus_gate.dart';

/// Loads and exposes the campus gate data, and owns the preferred-gate policy.
///
/// ## Data vs. Policy separation
///
/// * **DATA** — gate ids, names, and coordinates are read ONLY from the
///   bundled `university gates.kmz` asset (the Google My Maps export). They
///   are never hardcoded in this class or anywhere in the routing code.
/// * **POLICY** — which gate is *preferred* and which are *disabled* is
///   decided here via ids/flags, never via coordinates. By default all KMZ
///   gates are enabled and `preferredGate()` falls back to the first enabled
///   gate in KMZ order; later policies (direction-based, priority, multiple
///   preferred gates) can extend this without touching the routing algorithm.
class CampusGateRepository {
  /// Bundled KMZ asset with the authoritative gate Points.
  static const String _kmzAssetPath = 'assets/config/university gates.kmz';

  /// Gates loaded from the KMZ, in KMZ document order.
  List<CampusGate> _gates = const [];

  /// Id of the configured preferred gate (policy, not coordinates).
  String? _preferredGateId;

  /// Ids of gates disabled by policy (policy, not coordinates).
  Set<String> _disabledGateIds = const {};

  /// Whether the KMZ has been loaded.
  bool _isLoaded = false;

  /// Human-readable reason a preferred gate could not be resolved.
  String? _resolutionMessage;

  /// A KML feature filter for tests / future data sources (Point gates).
  static bool _isPointGate(KmlFeature f) => f.isPoint;

  /// All gates loaded from the KMZ (unmodifiable).
  List<CampusGate> get gates => List.unmodifiable(_gates);

  /// The configured preferred gate id (policy), if any.
  String? get preferredGateId => _preferredGateId;

  /// Whether the KMZ gate data has been loaded.
  bool get isLoaded => _isLoaded;

  /// Default constructor backed by the bundled KMZ asset.
  CampusGateRepository();

  /// Visible-for-testing constructor: seeds gates directly, bypassing the
  /// KMZ asset. Also lets a policy (preferred id / disabled ids) be supplied.
  @visibleForTesting
  CampusGateRepository.seeded({
    required List<CampusGate> gates,
    String? preferredGateId,
    Set<String> disabledGateIds = const {},
  }) {
    _gates = List.of(gates);
    _preferredGateId = preferredGateId;
    _disabledGateIds = Set.of(disabledGateIds);
    _isLoaded = true;
  }

  /// Configures the preferred-gate policy (ids only, never coordinates).
  ///
  /// Safe to call before or after [load]. Unknown/disabled ids cause
  /// [preferredGate] to fall back to the first enabled gate.
  void setPreferredGatePolicy({String? preferredGateId, Set<String>? disabledGateIds}) {
    if (preferredGateId != null) _preferredGateId = preferredGateId;
    if (disabledGateIds != null) _disabledGateIds = Set.of(disabledGateIds);
  }

  /// Loads gates from the bundled `university gates.kmz` asset.
  ///
  /// Reuses the same KMZ parsing pipeline as the campus-road repository
  /// ([KmzLoader.parseKmzBytes]): each Point Placemark becomes a gate whose
  /// name and coordinates come directly from the KML. Safe to call many
  /// times (no-op once loaded).
  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final data = await rootBundle.load(_kmzAssetPath);
      final bytes = data.buffer.asUint8List();
      final features = KmzLoader.parseKmzBytes(bytes);

      final gates = <CampusGate>[];
      for (final f in features) {
        if (!_isPointGate(f)) continue;
        final gate = CampusGate.fromKmlFeature(f);
        if (gate != null) gates.add(gate);
      }

      _gates = gates;
      _isLoaded = true;
      debugPrint(
        '[CampusGateRepository] Loaded ${_gates.length} gates from KMZ, '
        'preferred=${_preferredGateId ?? "none"}',
      );
    } catch (e) {
      debugPrint('[CampusGateRepository] Failed to load gates: $e');
      _gates = const [];
      _isLoaded = false;
    }
  }

  /// Loads gates from raw KMZ bytes (for tests or manual loading), applying
  /// the current policy flags. Marks the repository loaded.
  @visibleForTesting
  void loadFromBytes(List<int> kmzBytes) {
    final features = KmzLoader.parseKmzBytes(Uint8List.fromList(kmzBytes));
    final gates = <CampusGate>[];
    for (final f in features) {
      if (!_isPointGate(f)) continue;
      final gate = CampusGate.fromKmlFeature(f);
      if (gate != null) gates.add(gate);
    }
    _gates = gates;
    _isLoaded = true;
  }

  /// POLICY: returns the preferred gate to use for outside→campus routing.
  ///
  /// Rules (all policy-driven via ids/flags; coordinates come from the KMZ):
  ///  1. If no gates are loaded, returns null (callers use endpoint fallback).
  ///  2. The preferred gate is the one whose [CampusGate.id] equals the
  ///     configured `preferredGateId`, provided it exists AND is enabled.
  ///  3. If the configured id is missing or disabled, fall back to the first
  ///     enabled gate in KMZ order.
  ///  4. If no enabled gate exists, returns null.
  ///
  /// This intentionally does NOT pick the nearest gate; preference is a
  /// policy decision so direction/priority/multiple-gate rules can be added
  /// later without changing the routing algorithm.
  CampusGate? preferredGate() {
    _resolutionMessage = null;
    if (!_isLoaded || _gates.isEmpty) {
      _resolutionMessage = 'no gate data loaded';
      return null;
    }

    CampusGate? disabledEffective(CampusGate g) =>
        g.enabled && !_disabledGateIds.contains(g.id) ? g : null;

    // Rule 2: exact preferred id match, must be enabled.
    if (_preferredGateId != null) {
      for (final gate in _gates) {
        if (gate.id == _preferredGateId) {
          final effective = disabledEffective(gate);
          if (effective != null) {
            debugPrint(
              '[CampusGateRepository] preferred gate resolved: ${gate.id}',
            );
            return effective;
          }
          _resolutionMessage =
              'preferred gate "$_preferredGateId" is disabled';
          break;
        }
      }
      _resolutionMessage ??=
          'preferred gate "$_preferredGateId" not found in data';
    }

    // Rule 3: first enabled gate (KMZ order) as fallback.
    for (final gate in _gates) {
      final effective = disabledEffective(gate);
      if (effective != null) {
        debugPrint(
          '[CampusGateRepository] no usable preferred id; falling back to '
          'first enabled gate: ${gate.id}',
        );
        return effective;
      }
    }

    // Rule 4: no enabled gates.
    _resolutionMessage = 'no enabled gates configured';
    return null;
  }

  /// The last resolution diagnostic (mainly for tests/debugging).
  String? get resolutionMessage => _resolutionMessage;
}
