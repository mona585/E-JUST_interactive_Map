/// Parses rich metadata encoded in backend `description` fields.
///
/// The project convention (see docs/CAMPUSFIND_PLAN.md) encodes structured
/// data separated by `|`. Every segment falls back to a sensible default so
/// parsing is robust to free-text descriptions too.
///
/// POI example: `Dr. Elena Rostova | Associate Professor | CS Dept | Office 402, Floor 4 | Mon/Wed 2-3:30PM`
/// Space example: `Main Campus West Quad | Opened 2021 | Ramps & Elevators | Braille Signage`
class DescriptionParser {
  DescriptionParser(this.raw);

  final String? raw;

  static const _separator = '|';

  bool get isEmpty => raw == null || raw!.trim().isEmpty;

  /// All segments split on the delimiter, trimmed and stripped of empties.
  List<String> get segments {
    if (isEmpty) return const [];
    return raw!
        .split(_separator)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  String _segmentAt(int index) {
    final segs = segments;
    if (index >= segs.length) return '';
    return segs[index];
  }

  // ---- Professor (POI description) ----
  /// e.g. `Dr. Elena Rostova`
  String get professorName => _segmentAt(0);

  /// e.g. `Associate Professor`
  String get professorTitle => _segmentAt(1);

  /// e.g. `CS Dept`
  String get professorDepartment => _segmentAt(2);

  /// e.g. `Office 402, Floor 4`
  String get officeLocation => _segmentAt(3);

  /// e.g. `Mon/Wed 2-3:30PM`
  String get officeHours => _segmentAt(4);

  // ---- Building / Space (space description) ----
  /// All descriptive tags, e.g. `Ramps & Elevators`, `Braille Signage`.
  List<String> get facilityTags {
    final segs = segments;
    return segs.length > 2 ? segs.sublist(2) : const [];
  }

  bool get hasAccessibilityInfo => facilityTags.isNotEmpty;

  String get summary {
    if (isEmpty) return '';
    return segments.take(2).join(' · ');
  }
}
