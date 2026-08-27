import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/data/models/floor_model.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/poi_model.dart';
import 'package:anyplace_campusfind/data/models/space_model.dart';
import 'package:anyplace_campusfind/data/repositories/navigation_repository.dart';
import 'package:anyplace_campusfind/data/repositories/space_repository.dart';
import 'package:anyplace_campusfind/services/search_service.dart';
import 'package:anyplace_campusfind/state/space_provider.dart';

SpaceModel _space(String name, String buid) => SpaceModel(
      buid: buid,
      name: name,
      latitude: 30.86,
      longitude: 29.56,
      spaceType: 'building',
    );

PoiModel _poi(String name, String puid, String buid) => PoiModel(
      puid: puid,
      buid: buid,
      floorNumber: '0',
      name: name,
      poisType: 'room',
      latitude: 30.8601,
      longitude: 29.5601,
    );

class _FakeSpaceRepository implements SpaceRepository {
  @override
  Future<List<SpaceModel>> getPublicSpaces({bool forceReload = false}) async =>
      [_space('Library Building', 'buid_lib')];

  @override
  Future<SpaceModel?> getSpaceByBuid(String buid) async =>
      _space('Library Building', 'buid_lib');

  @override
  Future<List<FloorModel>> getFloorsByBuid(
    String buid, {
    bool forceReload = false,
  }) async =>
      const [];
}

class _FakeNavigationRepository implements NavigationRepository {
  _FakeNavigationRepository(this.route);

  final NavigationRouteModel route;
  int betweenPoisCalls = 0;

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) async {
    betweenPoisCalls++;
    return route;
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    String? floorNumber,
    required String destinationPuid,
  }) async =>
      throw UnimplementedError('not used by requestRouteBetweenPois');
}

void main() {
  group('SearchService.query includeSpacesAndFloors flag', () {
    test('default keeps POI-only legacy behavior', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final legacy = service.query('lib');
      expect(legacy, isNotEmpty);
      expect(legacy.every((r) => r.entityType == 'poi'), isTrue);
    });

    test('opt-in flag includes building entries as suggestions', () {
      final service = SearchService();
      service.addSpaces([_space('Library Building', 'b1')]);
      service.addPois('b1', '0', [_poi('Lib corner desk', 'p1', 'b1')]);

      final mixed = service.query('lib', includeSpacesAndFloors: true);
      expect(mixed.any((r) => r.entityType == 'space'), isTrue);
      expect(mixed.any((r) => r.entityType == 'poi'), isTrue);
    });
  });

  group('SpaceProvider.requestRouteBetweenPois (additive wrapper)', () {
    test('wraps the existing POI-to-POI repository API and readies the store',
        () async {
      final navRepo = _FakeNavigationRepository(
        NavigationRouteModel(
          points: const [
            NavigationRoutePoint(
              latitude: 30.8601,
              longitude: 29.5601,
              puid: 'p_origin',
              buid: 'buid_lib',
              floorNumber: '0',
              poisType: 'room',
            ),
            NavigationRoutePoint(
              latitude: 30.8602,
              longitude: 29.5602,
              puid: 'p_target',
              buid: 'buid_lib',
              floorNumber: '0',
              poisType: 'room',
            ),
          ],
        ),
      );
      final provider = SpaceProvider(
        repository: _FakeSpaceRepository(),
        navigationRepository: navRepo,
      );
      await provider.loadSpaces();

      final origin = _poi('Origin room', 'p_origin', 'buid_lib');
      final target = _poi('Target room', 'p_target', 'buid_lib');

      final ok = await provider.requestRouteBetweenPois(origin, target);

      expect(ok, isTrue);
      expect(navRepo.betweenPoisCalls, 1);
      expect(provider.navigationRouteStatus, NavigationRouteStatus.ready);
      expect(provider.hasActiveNavigationRoute, isTrue);
      expect(provider.selectedPoi?.puid, 'p_target');
      expect(provider.selectedSpace?.buid, 'buid_lib');
    });

    test('unsupported (non-renderable) route maps to unsupported status',
        () async {
      final navRepo = _FakeNavigationRepository(
        const NavigationRouteModel(points: []),
      );
      final provider = SpaceProvider(
        repository: _FakeSpaceRepository(),
        navigationRepository: navRepo,
      );
      await provider.loadSpaces();

      final ok = await provider.requestRouteBetweenPois(
        _poi('Origin', 'p_origin', 'buid_lib'),
        _poi('Target', 'p_target', 'buid_lib'),
      );

      expect(ok, isFalse);
      expect(provider.navigationRouteStatus, NavigationRouteStatus.unsupported);
      expect(provider.hasActiveNavigationRoute, isFalse);
    });
  });
}
