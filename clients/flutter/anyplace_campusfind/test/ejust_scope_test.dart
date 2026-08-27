import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';
import 'package:anyplace_campusfind/utils/campus_scope.dart';

SpaceModel _space(String buid, String name, {String? cuid}) =>
    SpaceModel(
      buid: buid,
      name: name,
      latitude: 30.86,
      longitude: 29.56,
      spaceType: 'building',
      cuid: cuid,
    );

class _Repo implements SpaceRepository {
  _Repo(this.spaces);

  final List<SpaceModel> spaces;

  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) =>
      Future.value(spaces);

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async => null;

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      const [];
}

void main() {
  group('CampusScope (E-JUST global scope)', () {
    test('keeps entities without a campus id (single-campus backends)', () {
      expect(CampusScope.spaceInScope(_space('b1', 'A')), isTrue);
    });

    test('keeps entities owned by the active campus', () {
      expect(
        CampusScope.spaceInScope(_space('b2', 'B', cuid: 'ejust')),
        isTrue,
      );
    });

    test('excludes entities owned by a foreign campus', () {
      expect(
        CampusScope.spaceInScope(_space('b3', 'C', cuid: 'ucy')),
        isFalse,
      );
    });

    test('filterSpaces applies the rule to a whole payload', () {
      final filtered = CampusScope.filterSpaces([
        _space('b1', 'A'),
        _space('b2', 'B', cuid: 'ejust'),
        _space('b3', 'C', cuid: 'ucy'),
      ]);
      expect(filtered.map((s) => s.buid), ['b1', 'b2']);
    });
  });

  group('SpaceModel.cuid parsing', () {
    test('parses cuid when present and normalizes blanks to null', () {
      final withId = SpaceModel.fromJson({
        'buid': 'b1',
        'name': 'A',
        'coordinates_lat': 30.86,
        'coordinates_lon': 29.56,
        'cuid': 'ejust',
      });
      expect(withId.cuid, 'ejust');

      final blank = SpaceModel.fromJson({
        'buid': 'b2',
        'name': 'B',
        'cuid': '   ',
      });
      expect(blank.cuid, isNull);
    });

    test('toJson round-trips cuid', () {
      final s = _space('b1', 'A', cuid: 'ejust');
      expect(s.toJson()['cuid'], 'ejust');
    });
  });

  group('SpaceProvider.loadSpaces E-JUST filtering', () {
    test('exposes only in-scope buildings downstream', () async {
      final provider = SpaceProvider(
        repository: _Repo([
          _space('ej_1', 'EJUST Library', cuid: 'ejust'),
          _space('other_9', 'Foreign Hall', cuid: 'some_other_campus'),
          _space('legacy_1', 'Legacy Wing'), // no cuid → in scope
        ]),
      );
      await provider.loadSpaces();

      expect(provider.spaces.map((s) => s.buid), ['ej_1', 'legacy_1']);
    });
  });
}
