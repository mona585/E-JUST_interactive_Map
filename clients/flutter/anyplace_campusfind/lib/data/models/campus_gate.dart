import '../datasources/kmz_loader.dart';

/// A configured entry/exit point on the campus perimeter.
///
/// Gate metadata is DATA, not policy: this model carries only the facts
/// (id, name, coordinates, enabled flag). The routing policy that decides
/// which gate to use lives in the gate repository/policy layer, never here.
///
/// Gate facts (id, name, coordinates) come from the authoritative
/// `university gates.kmz` (Google My Maps export) — never from hardcoded
/// values in code. The `enabled` flag is a policy toggle applied on top of
/// the KMZ data; it does not originate from the KMZ.
class CampusGate {
  /// Stable unique identifier for the gate.
  ///
  /// Derived from the KMZ Placemark `<name>` (e.g. "G1", "G2"), which is
  /// unique per gate in the source file.
  final String id;

  /// Human-readable name from the KMZ (e.g. "G1", "Main Gate").
  final String name;

  /// Latitude of the gate (from the KMZ Point).
  final double latitude;

  /// Longitude of the gate (from the KMZ Point).
  final double longitude;

  /// Whether this gate is currently usable for routing.
  ///
  /// This is a POLICY flag (default true); the KMZ does not declare it.
  /// Disabled gates are ignored by the policy and never selected.
  final bool enabled;

  const CampusGate({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.enabled = true,
  });

  /// Builds a gate from a parsed KMZ Point feature.
  ///
  /// The [KmlFeature] must be a `Point` feature (isPoint == true) so the
  /// coordinate list is a single [LatLng]. The gate id and name both come
  /// from the Placemark `<name>`; coordinates come from the KML
  /// `<coordinates>` Point (already normalised to lat/lon by the loader).
  ///
  /// Returns null if the feature is not a single-point Point feature.
  static CampusGate? fromKmlFeature(KmlFeature feature) {
    if (!feature.isPoint || feature.coordinates.isEmpty) return null;
    final name = feature.name.trim();
    if (name.isEmpty) return null;
    final pos = feature.coordinates.first;
    return CampusGate(
      id: name,
      name: name,
      latitude: pos.latitude,
      longitude: pos.longitude,
    );
  }

  /// Returns a copy with an updated [enabled] flag (policy-only change).
  CampusGate copyWithEnabled(bool enabled) => CampusGate(
        id: id,
        name: name,
        latitude: latitude,
        longitude: longitude,
        enabled: enabled,
      );

  @override
  String toString() =>
      'CampusGate($id, $name, $latitude,$longitude, enabled: $enabled)';
}
