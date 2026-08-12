import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anyplace_campusfind/models/floor.dart';
import 'package:anyplace_campusfind/models/outdoor_route.dart';
import 'package:anyplace_campusfind/models/poi.dart';
import 'package:anyplace_campusfind/models/route.dart';
import 'package:anyplace_campusfind/models/space.dart';
import 'package:anyplace_campusfind/providers/route_provider.dart';
import 'package:anyplace_campusfind/services/api_service.dart';
import 'package:anyplace_campusfind/services/cache_service.dart';
import 'package:anyplace_campusfind/services/outdoor_routing_service.dart';

class _FakeApi extends ApiService {
  final Map<String, NavigationRoute> _routes = {};
  NavigationRoute? lastRouteFromCoords;

  void stubRoute(String fromPuid, String toPuid, NavigationRoute route) {
    _routes['$fromPuid|$toPuid'] = route;
  }

  @override
  Future<NavigationRoute> fetchNavigationRoute(
    String puidFrom,
    String puidTo,
  ) async {
    final route = _routes['$puidFrom|$puidTo'];
    if (route == null) {
      throw ApiException('no route');
    }
    return route;
  }

  @override
  Future<NavigationRoute> fetchNavigationRouteFromCoords({
    required double coordinatesLat,
    required double coordinatesLon,
    required String floorNumber,
    required String poisTo,
  }) async {
    lastRouteFromCoords = NavigationRoute(
      numOfPois: 1,
      pois: [
        RoutePoint(
          lat: coordinatesLat,
          lon: coordinatesLon,
          puid: 'coord',
          buid: '',
          floorNumber: floorNumber,
        ),
        RoutePoint(
          lat: 0,
          lon: 0,
          puid: poisTo,
          buid: '',
          floorNumber: floorNumber,
        ),
      ],
    );
    return lastRouteFromCoords!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CacheService cache;
  late _FakeApi api;

  final building = Space(
    buid: 'b1',
    name: 'Engineering Building',
    coordinatesLat: 30.8,
    coordinatesLon: 29.5,
    spaceType: 'building',
  );

  final entrance = Poi(
    puid: 'entrance_1',
    buid: 'b1',
    name: 'Main Entrance',
    coordinatesLat: 30.8001,
    coordinatesLon: 29.5001,
    floorNumber: '0',
    isBuildingEntrance: 'true',
  );

  final office = Poi(
    puid: 'office_1',
    buid: 'b1',
    name: 'Office 402',
    coordinatesLat: 30.8002,
    coordinatesLon: 29.5002,
    floorNumber: '3',
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = CacheService()
      ..setSpaces([building])
      ..setFloors('b1', [
        Floor(fuid: 'b1_0', buid: 'b1', floorNumber: '0'),
        Floor(fuid: 'b1_3', buid: 'b1', floorNumber: '3'),
      ])
      ..setPois('b1', [entrance, office]);
    api = _FakeApi();
  });

  group('OutdoorRoutingService', () {
    test('parses OSRM GeoJSON route', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': {
                  'coordinates': [
                    [29.5001, 30.8001],
                    [29.50015, 30.80015],
                    [29.5002, 30.8002],
                  ],
                },
                'distance': 25.4,
                'duration': 4.2,
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = OutdoorRoutingService(client: client);
      final route = await service.route(
        const LatLng(30.8001, 29.5001),
        const LatLng(30.8002, 29.5002),
      );

      expect(route, isA<OutdoorRoute>());
      expect(route.points, hasLength(3));
      expect(route.points.first.latitude, 30.8001);
      expect(route.points.first.longitude, 29.5001);
      expect(route.distance, 25.4);
    });

    test('throws on non-Ok status', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 'NoRoute', 'message': 'no path'}),
          200,
        );
      });

      final service = OutdoorRoutingService(client: client);
      expect(
        () => service.route(
          const LatLng(30.8, 29.5),
          const LatLng(30.8002, 29.5002),
        ),
        throwsA(isA<OutdoorRoutingException>()),
      );
    });

    test('throws on HTTP error', () async {
      final client = MockClient((request) async {
        return http.Response('boom', 500);
      });

      final service = OutdoorRoutingService(client: client);
      expect(
        () => service.route(
          const LatLng(30.8, 29.5),
          const LatLng(30.8002, 29.5002),
        ),
        throwsA(isA<OutdoorRoutingException>()),
      );
    });
  });

  group('RouteNotifier', () {
    OutdoorRoutingService osrm() {
      return OutdoorRoutingService(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': {
                    'coordinates': [
                      [29.5, 30.8],
                      [29.5001, 30.8001],
                    ],
                  },
                  'distance': 100.0,
                  'duration': 12.0,
                },
              ],
            }),
            200,
          );
        }),
      );
    }

    OutdoorRoutingService failingOsrm() {
      return OutdoorRoutingService(
        client: MockClient((request) async {
          return http.Response('boom', 500);
        }),
      );
    }

    RouteNotifier notifier({
      OutdoorRoutingService? outdoor,
    }) {
      return RouteNotifier(api, outdoor ?? osrm(), cache);
    }

    test('combined route: indoor via entrance + outdoor via OSRM', () async {
      api.stubRoute('entrance_1', 'office_1', NavigationRoute(
        numOfPois: 2,
        pois: [
          RoutePoint(
            lat: 30.8001,
            lon: 29.5001,
            puid: 'entrance_1',
            buid: 'b1',
            floorNumber: '0',
          ),
          RoutePoint(
            lat: 30.8002,
            lon: 29.5002,
            puid: 'office_1',
            buid: 'b1',
            floorNumber: '3',
          ),
        ],
      ));

      final n = notifier();
      await n.navigateToPoi(
        office,
        from: const LatLng(30.799, 29.499),
      );

      final state = n.state;
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.destination?.puid, 'office_1');
      // Indoor route split by floor.
      expect(state.indoorPointsByFloor['0'], hasLength(1));
      expect(state.indoorPointsByFloor['3'], hasLength(1));
      // Outdoor leg comes from OSRM.
      expect(state.hasOutdoor, isTrue);
      expect(state.outdoorPoints, hasLength(2));
      expect(state.outdoorFallback, isFalse);
      expect(state.noEntranceFallback, isFalse);
    });

    test('outdoor straight-line fallback when OSRM fails', () async {
      api.stubRoute('entrance_1', 'office_1', NavigationRoute(
        numOfPois: 2,
        pois: const [],
      ));

      final n = notifier(outdoor: failingOsrm());
      await n.navigateToPoi(
        office,
        from: const LatLng(30.799, 29.499),
      );

      expect(n.state.outdoorFallback, isTrue);
      expect(n.state.hasOutdoor, isTrue);
      expect(n.state.outdoorPoints, hasLength(2));
    });

    test('no entrance POI: uses building center via route/coordinates', () async {
      final cacheNoEntrance = CacheService()
        ..setSpaces([building])
        ..setFloors('b1', [
          Floor(fuid: 'b1_3', buid: 'b1', floorNumber: '3'),
        ])
        ..setPois('b1', [office]);
      final n = RouteNotifier(api, osrm(), cacheNoEntrance);

      await n.navigateToPoi(
        office,
        from: const LatLng(30.799, 29.499),
      );

      expect(n.state.noEntranceFallback, isTrue);
      expect(api.lastRouteFromCoords, isNotNull);
      expect(n.state.indoorPointsByFloor['3'], hasLength(2));
    });

    test('error state when indoor route fails', () async {
      final n = notifier(); // no stub for entrance_1 -> office_1

      await n.navigateToPoi(office, from: const LatLng(30.799, 29.499));

      expect(n.state.error, isNotNull);
      expect(n.state.isActive, isFalse);
    });

    test('navigateToBuilding is outdoor-only', () async {
      final n = notifier();
      await n.navigateToBuilding(building, from: const LatLng(30.799, 29.499));

      expect(n.state.hasOutdoor, isTrue);
      expect(n.state.hasIndoor, isFalse);
      expect(n.state.outdoorEnd?.latitude, 30.8001); // entrance
    });

    test('clearRoute resets state', () async {
      final n = notifier();
      await n.navigateToPoi(
        office,
        from: const LatLng(30.799, 29.499),
      );
      n.clearRoute();
      expect(n.state.isActive, isFalse);
      expect(n.state.destination, isNull);
    });
  });
}
