import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/campus_gate.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../repositories/custom_route_repository.dart';
import '../repositories/navigation_repository.dart';

/// Computes the pure route-geometry leaves of the navigation cascade.
///
/// Owns stateless, computation-only routing work shared by navigation
/// requests: POI→connector→POI indoor paths and OSRM→campus-graph combined
/// paths. It holds NO presentation state — status transitions, request-id
/// de-duplication and change notifications remain owned by the orchestrating
/// view model.
class RoutingService {
  RoutingService(this._navigationRepository, this._customRouteRepository);

  final NavigationRepository _navigationRepository;
  final CustomRouteRepository _customRouteRepository;

  NavigationRoutePoint poiToRoutePoint(PoiModel poi) {
    return NavigationRoutePoint(
      latitude: poi.latitude,
      longitude: poi.longitude,
      puid: poi.puid,
      buid: poi.buid,
      floorNumber: poi.floorNumber,
      poisType: poi.poisType,
    );
  }

  /// Routes from entrance to target POI through intermediate connector POIs.
  ///
  /// The server requires edges between POIs for routing. Room/entrance POIs
  /// often lack edges, but connector POIs (pois_type == "None") have edges
  /// between them in the hallway.
  Future<NavigationRouteModel?> routeIndoorViaConnectors({
    required List<PoiModel> pois,
    required PoiModel entrancePoi,
    required PoiModel targetPoi,
  }) async {
    // Find all connector POIs for the target building on the same floor
    final connectors = pois
        .where(
          (p) =>
              p.buid == targetPoi.buid &&
              p.puid.isNotEmpty &&
              p.poisType == 'None',
        )
        .toList();
    if (connectors.isEmpty) {
      debugPrint('[RoutingService] No connector POIs found for building');
      return null;
    }
    debugPrint(
      '[RoutingService] Found ${connectors.length} connectors for building',
    );

    // Find nearest connector to entrance
    PoiModel? nearestToEntrance;
    double minDistEntrance = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        entrancePoi.latitude,
        entrancePoi.longitude,
        c.latitude,
        c.longitude,
      );
      if (dist < minDistEntrance) {
        minDistEntrance = dist;
        nearestToEntrance = c;
      }
    }

    // Find nearest connector to target
    PoiModel? nearestToTarget;
    double minDistTarget = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        targetPoi.latitude,
        targetPoi.longitude,
        c.latitude,
        c.longitude,
      );
      if (dist < minDistTarget) {
        minDistTarget = dist;
        nearestToTarget = c;
      }
    }

    if (nearestToEntrance == null || nearestToTarget == null) return null;

    debugPrint(
      '[RoutingService] Nearest connector to entrance: ${nearestToEntrance.name} '
      '(${minDistEntrance.toStringAsFixed(0)}m)',
    );
    debugPrint(
      '[RoutingService] Nearest connector to target: ${nearestToTarget.name} '
      '(${minDistTarget.toStringAsFixed(0)}m)',
    );

    // If both connectors are the same, return a simple 3-point path
    if (nearestToEntrance.puid == nearestToTarget.puid) {
      debugPrint('[RoutingService] Same connector — straight through');
      return NavigationRouteModel.hybrid(
        outdoorPoints: [],
        indoorRoute: NavigationRouteModel(
          points: [
            poiToRoutePoint(entrancePoi),
            poiToRoutePoint(nearestToEntrance),
            poiToRoutePoint(targetPoi),
          ],
        ),
      );
    }

    // Route between the two connectors via the server API
    try {
      debugPrint(
        '[RoutingService] Connector→connector route: ${nearestToEntrance.puid} → ${nearestToTarget.puid}',
      );
      final connectorRoute = await _navigationRepository.getRouteBetweenPois(
        fromPuid: nearestToEntrance.puid,
        toPuid: nearestToTarget.puid,
      );

      if (connectorRoute.hasRenderablePath &&
          connectorRoute.points.length >= 2) {
        debugPrint(
          '[RoutingService] Connector route succeeded (${connectorRoute.points.length} points)',
        );
        // Build full path: entrance → connector_start + route + connector_end → target
        final fullPath = <NavigationRoutePoint>[
          NavigationRoutePoint(
            latitude: entrancePoi.latitude,
            longitude: entrancePoi.longitude,
            puid: entrancePoi.puid,
            buid: entrancePoi.buid,
            floorNumber: entrancePoi.floorNumber,
            poisType: entrancePoi.poisType,
          ),
          NavigationRoutePoint(
            latitude: nearestToEntrance.latitude,
            longitude: nearestToEntrance.longitude,
            puid: nearestToEntrance.puid,
            buid: nearestToEntrance.buid,
            floorNumber: nearestToEntrance.floorNumber,
            poisType: nearestToEntrance.poisType,
          ),
          ...connectorRoute.points,
          NavigationRoutePoint(
            latitude: nearestToTarget.latitude,
            longitude: nearestToTarget.longitude,
            puid: nearestToTarget.puid,
            buid: nearestToTarget.buid,
            floorNumber: nearestToTarget.floorNumber,
            poisType: nearestToTarget.poisType,
          ),
          NavigationRoutePoint(
            latitude: targetPoi.latitude,
            longitude: targetPoi.longitude,
            puid: targetPoi.puid,
            buid: targetPoi.buid,
            floorNumber: targetPoi.floorNumber,
            poisType: targetPoi.poisType,
          ),
        ];

        return NavigationRouteModel.hybrid(
          outdoorPoints: [],
          indoorRoute: NavigationRouteModel(points: fullPath),
        );
      } else {
        debugPrint(
          '[RoutingService] Connector route returned ${connectorRoute.points.length} points',
        );
      }
    } catch (e) {
      debugPrint('[RoutingService] Connector→connector route failed: $e');
    }

    // Last resort: straight lines through the nearest connectors
    debugPrint(
      '[RoutingService] Falling back to straight-line through connectors',
    );
    return NavigationRouteModel.hybrid(
      outdoorPoints: [],
      indoorRoute: NavigationRouteModel(
        points: [
          poiToRoutePoint(entrancePoi),
          poiToRoutePoint(nearestToEntrance),
          poiToRoutePoint(nearestToTarget),
          poiToRoutePoint(targetPoi),
        ],
      ),
    );
  }

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
