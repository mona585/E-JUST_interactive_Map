import 'space.dart';

/// Campus (building set) as returned by `MapCampusController.get`.
///
/// The backend response strips `buids`/`owner_id`/`_id`/`_schema`/`cuid`/
/// `description` and adds a `spaces` array of Space objects.
class Campus {
  const Campus({
    required this.cuid,
    required this.name,
    this.greeklish,
    this.spaces = const [],
  });

  final String cuid;
  final String name;
  final String? greeklish;
  final List<Space> spaces;

  factory Campus.fromJson(Map<String, dynamic> json) {
    return Campus(
      // cuid is stripped from the response by design; callers pass it in via
      // the request. Fall back to any present value for robustness.
      cuid: json['cuid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      greeklish: json['greeklish'] as String?,
      spaces: (json['spaces'] as List<dynamic>? ?? const [])
          .map((e) => Space.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'cuid': cuid,
        'name': name,
        if (greeklish != null) 'greeklish': greeklish,
        'spaces': spaces.map((s) => s.toJson()).toList(),
      };
}
