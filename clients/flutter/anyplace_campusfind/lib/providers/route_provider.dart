import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
import '../models/route.dart';
import '../models/space.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import '../services/outdoor_routing_service.dart';
import 'providers.dart';

/// Snapshot of the active navigation.
class RouteState {
  const RouteState({
    this.destination,
    this.indoorPointsByFloor = const {},
    this.outdoorPoints = const [],
    this.outdoorStart,
    this.outdoorEnd,
    this.isLoading = false,
    this.error,
    this.outdoorFallback = false,
    this.noEntranceFallback = false,
  });

  /// The POI being navigated to (null for building-only navigation).
  final Poi? destination;

  /// Indoor route points grouped by floor number (red polylines).
  final Map<String, List<RoutePoint>> indoorPointsByFloor;

  /// Outdoor route polyline, in travel order (blue polyline).
  final List<LatLng> outdoorPoints;

  /// Outdoor leg start (user GPS position), when known.
  final LatLng? outdoorStart;

  /// Outdoor leg end (entrance or building center).
  final LatLng? outdoorEnd;

  final bool isLoading;
  final String? error;

  /// True when OSRM failed and a straight-line fallback was used.
  final bool outdoorFallback;

  /// True when the destination building has no entrance POI, so the
  /// building center was used as the outdoor end / indoor start.
  final bool noEntranceFallback;

  bool get hasIndoor => indoorPointsByFloor.isNotEmpty;

  bool get hasOutdoor => outdoorPoints.length >= 2;

  bool get isActive =>
      !isLoading &&
      error == null &&
      (hasIndoor || hasOutdoor);
}

/// Coordinates + API access for the combined route provider.
class RouteNotifier extends StateNotifier<RouteState> {
  RouteNotifier(
    this._api,
    this._outdoorRouting,
    this._cache,
  ) : super(const RouteState());

  final ApiService _api;
  final OutdoorRoutingService _outdoorRouting;
  final CacheService _cache;  /// Computes the combined route to [destination]:
  ///  * indoor leg: nearest `is_building_entrance` POI → destination
  ///    (falls back to `route/coordinates` from the building center when no
  ///    entrance exists);
  ///  * outdoor leg: [from] (GPS) → entrance/building center via OSRM, with a
  ///    straight-line fallback on failure.
  Future<void> navigateToPoi(Poi destination, {LatLng? from}) async {
    state = RouteState(destination: destination, isLoading: true);
    try {
      final building = _cache.spaceByBuid(destination.buid);
      final entrances = _cache
          .poisOf(destination.buid)
          .where((p) => p.isEntrance)
          .toList();

      // ---- Indoor leg ----
      Map<String, List<RoutePoint>> indoorByFloor = const {};
      var noEntrance = false;

      if (entrances.isNotEmpty) {
        final entrance = entrances.first;
        final route = await _api.fetchNavigationRoute(
          entrance.puid,
          destination.puid,
        );
        indoorByFloor = _groupByFloor(route.pois);
      } else if (building != null) {
        // No entrance POI: route from the building center on the destination
        // floor (task 5.7 fallback).
        noEntrance = true;
        try {
          final route = await _api.fetchNavigationRouteFromCoords(
            coordinatesLat: building.coordinatesLat,
            coordinatesLon: building.coordinatesLon,
            floorNumber: destination.floorNumber,
            poisTo: destination.puid,
          );
          indoorByFloor = _groupByFloor(route.pois);
        } on ApiException {
          indoorByFloor = const {};
        }
      }

      // ---- Outdoor leg ----
      LatLng? entrancePoint;
      if (entrances.isNotEmpty) {
        final entrance = entrances.first;
        entrancePoint = LatLng(
          entrance.coordinatesLat,
          entrance.coordinatesLon,
        );
      } else if (building != null) {
        entrancePoint = LatLng(
          building.coordinatesLat,
          building.coordinatesLon,
        );
      }

      final outdoor = await _computeOutdoor(from, entrancePoint);

      state = RouteState(
        destination: destination,
        indoorPointsByFloor: indoorByFloor,
        outdoorPoints: outdoor.points,
        outdoorStart: from,
        outdoorEnd: entrancePoint,
        outdoorFallback: outdoor.fallback,
        noEntranceFallback: noEntrance,
      );
    } catch (e) {
      state = RouteState(destination: destination, error: e.toString());
    }
  }

  /// Outdoor-only navigation to a building: GPS → entrance (or building
  /// center when no entrance POI exists).
  Future<void> navigateToBuilding(Space building, {LatLng? from}) async {
    state = const RouteState(isLoading: true);
    try {
      final entrances = _cache
          .poisOf(building.buid)
          .where((p) => p.isEntrance)
          .toList();

      LatLng? end;
      var noEntrance = false;
      if (entrances.isNotEmpty) {
        final entrance = entrances.first;
        end = LatLng(entrance.coordinatesLat, entrance.coordinatesLon);
      } else {
        end = LatLng(building.coordinatesLat, building.coordinatesLon);
        noEntrance = true;
      }

      final outdoor = await _computeOutdoor(from, end);
      state = RouteState(
        outdoorPoints: outdoor.points,
        outdoorStart: from,
        outdoorEnd: end,
        outdoorFallback: outdoor.fallback,
        noEntranceFallback: noEntrance,
      );
    } catch (e) {
      state = RouteState(error: e.toString());
    }
  }

  Future<_OutdoorResult> _computeOutdoor(
    LatLng? from,
    LatLng? end,
  ) async {
    if (from == null || end == null) {
      return const _OutdoorResult(points: [], fallback: false);
    }
    try {
      final route = await _outdoorRouting.route(from, end);
      return _OutdoorResult(points: route.points, fallback: false);
    } catch (_) {
      // OSRM failure → straight-line fallback (task 5.7).
      return _OutdoorResult(points: [from, end], fallback: true);
    }
  }

  void clearRoute() => state = const RouteState();

  static Map<String, List<RoutePoint>> _groupByFloor(List<RoutePoint> pois) {
    final grouped = <String, List<RoutePoint>>{};
    for (final p in pois) {
      (grouped[p.floorNumber] ??= []).add(p);
    }
    return grouped;
  }
}

class _OutdoorResult {
  const _OutdoorResult({required this.points, required this.fallback});

  final List<LatLng> points;
  final bool fallback;
}

/// Current user GPS position (populated in Phase 6).
final userLocationProvider = StateProvider<LatLng?>((ref) => null);

final outdoorRoutingServiceProvider =
    Provider<OutdoorRoutingService>((ref) => OutdoorRoutingService());

final routeStateProvider = StateNotifierProvider<RouteNotifier, RouteState>(
  (ref) => RouteNotifier(
    ref.watch(apiServiceProvider),
    ref.watch(outdoorRoutingServiceProvider),
    ref.watch(cacheServiceProvider),
  ),
);
