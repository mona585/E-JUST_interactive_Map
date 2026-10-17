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
