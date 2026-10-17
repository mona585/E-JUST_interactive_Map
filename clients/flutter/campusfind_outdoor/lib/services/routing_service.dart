import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/campus_gate.dart';
import '../repositories/custom_route_repository.dart';
import '../repositories/navigation_repository.dart';

/// Computes the pure route-geometry leaves of the outdoor navigation cascade.
///
/// Owns stateless, computation-only routing work shared by navigation
/// requests: the OSRM→campus-graph combined path. It holds NO presentation
/// state — status transitions, request-id de-duplication and change
/// notifications remain owned by the orchestrating view model.
///
/// OUTDOOR-ONLY (CP-8): the previous POI→connector→POI indoor path builder
/// (`routeIndoorViaConnectors` / `poiToRoutePoint`) has been removed — the app
/// performs no indoor routing.
class RoutingService {
  RoutingService(this._navigationRepository, this._customRouteRepository);

  final NavigationRepository _navigationRepository;
  final CustomRouteRepository _customRouteRepository;

  /// Builds a combined route: OSRM from user to nearest custom vertex,
  /// then custom route from there to the destination.
  ///
  /// When a preferred [CampusGate] is configured, the OSRM leg is routed to
  /// that gate and the campus road graph is entered at the gate's nearest
  /// vertex — `outside → preferred gate → campus roads → destination`.
  Future<List<LatLng>?> buildOsrmToCustomRoute(
    LatLng userLocation,
    LatLng destination, {
    CampusGate? gateEntry,
  }) async {
    final customRepo = _customRouteRepository;
    if (!customRepo.isLoaded) return null;

    final destVertex = customRepo.graph.nearestVertex(
      destination,
      maxDistance: 500.0,
    );
    if (destVertex == null) {
      debugPrint('[RoutingService] osrm→custom: no vertex within 500m of dest');
      return null;
    }
    final destVertexIdx = destVertex.$1;

    debugPrint(
      '[RoutingService] osrm→custom: dest vertex=$destVertexIdx, '
      '${destVertex.$2.toStringAsFixed(0)}m from destination, '
      'gate=${gateEntry?.id ?? "none"}',
    );

    // Step 1: When a configured gate is provided, enter the campus road graph
    // at the graph vertex nearest the gate and drive OSRM to that exact gate.
    int? bestEntryIdx;
    if (gateEntry != null) {
      final gateVertex = customRepo.graph.nearestVertex(
        LatLng(gateEntry.latitude, gateEntry.longitude),
        maxDistance: 750.0,
      );
      if (gateVertex == null) {
        debugPrint(
          '[RoutingService] osrm→custom: gate ${gateEntry.id} is not near the '
          'campus road graph; falling back to endpoint logic',
        );
      } else {
        bestEntryIdx = gateVertex.$1;
        debugPrint(
          '[RoutingService] osrm→custom: gate ${gateEntry.id} snapped to graph '
          'vertex $bestEntryIdx (${gateVertex.$2.toStringAsFixed(0)}m from gate)',
        );
      }
    }

    // Step 1b: Route endpoints (campus road entrances on public roads)
    final endpoints = customRepo.graph.getRouteEndpoints();
    debugPrint(
      '[RoutingService] osrm→custom: ${endpoints.length} route endpoints',
    );

    if (endpoints.isEmpty && bestEntryIdx == null) {
      debugPrint('[RoutingService] osrm→custom: no route endpoints');
      return null;
    }

    // Step 2: OSRM target = gate location when resolved, otherwise pick a
    // route endpoint (prefer one near the user that connects to the dest;
    // fall back to the endpoint nearest the destination).
    LatLng entryPos;
    if (bestEntryIdx != null) {
      entryPos = LatLng(gateEntry!.latitude, gateEntry.longitude);
    } else {
      int? nearestToDestIdx;
      double nearestToDestDist = double.infinity;

      for (final (epIdx, epPos) in endpoints) {
        final distToDest = Geolocator.distanceBetween(
          destination.latitude,
          destination.longitude,
          epPos.latitude,
          epPos.longitude,
        );
        if (distToDest < nearestToDestDist) {
          nearestToDestDist = distToDest;
          nearestToDestIdx = epIdx;
        }
      }

      bestEntryIdx = nearestToDestIdx;
      if (bestEntryIdx == null) {
        debugPrint('[RoutingService] osrm→custom: no endpoints at all');
        return null;
      }
      entryPos = customRepo.graph.getVertexPosition(bestEntryIdx);

      final entryUserDist = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        entryPos.latitude,
        entryPos.longitude,
      );
      debugPrint(
        '[RoutingService] osrm→custom: best entry=$bestEntryIdx '
        '(${entryUserDist.toStringAsFixed(0)}m from user)',
      );
    }

    // Step 3: OSRM from user to the campus entrance (gate or endpoint)
    final osrmResult =
        await _navigationRepository.getOutdoorWalkingRouteWithMetadata(
          fromLat: userLocation.latitude,
          fromLon: userLocation.longitude,
          toLat: entryPos.latitude,
          toLon: entryPos.longitude,
        );

    if (osrmResult == null || osrmResult.points.length < 2) {
      debugPrint('[RoutingService] osrm→custom: OSRM failed');
      return null;
    }

    final osrmPath = osrmResult.points;

    // Step 4: Route through custom graph from entry vertex to destination
    final customPath = customRepo.graph.shortestPath(
      bestEntryIdx,
      destVertexIdx,
    );

    if (customPath.isEmpty) {
      debugPrint(
        '[RoutingService] osrm→custom: no graph path $bestEntryIdx → $destVertexIdx; '
        'adding straight-line walk from entry to destination',
      );
      return [...osrmPath, destination];
    }

    final combined = <LatLng>[
      ...osrmPath,
      for (final idx in customPath) customRepo.graph.getVertexPosition(idx),
      destination,
    ];

    debugPrint(
      '[RoutingService] osrm→custom: ${osrmPath.length} OSRM + '
      '${customPath.length} custom = ${combined.length} total',
    );
    return combined;
  }
}
