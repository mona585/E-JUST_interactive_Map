import 'dart:math' show cos, sin, atan2, pi;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../datasources/anyplace_api_client.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../../utils/poi_classification.dart';
import 'custom_route_repository.dart';

/// Orchestrates cross-building navigation by composing multi-segment routes.
///
/// When the user is detected indoors at a different building than the
/// destination, this class generates a complete journey:
/// ```
/// User Location → [Indoor Route to Exit] → Exit Transition →
/// [Outdoor Walking Route] → Destination Entrance →
/// [Indoor Route to Destination]
/// ```
class CrossBuildingRouter {
  /// Detects if the user is inside a building polygon.
  final bool Function(LatLng position, String buildingBuid) isPositionInBuilding;

  /// Loads POIs for a building's floor.
  Future<List<PoiModel>> Function(String buid, String floorNumber) loadPois;

  /// Loads all floors for a building.
  Future<List<String>> Function(String buid) loadFloorNumbers;

  /// Custom route repository for outdoor walking paths (KMZ routes).
  final CustomRouteRepository? customRouteRepository;

  CrossBuildingRouter({
    required this.isPositionInBuilding,
    required this.loadPois,
    required this.loadFloorNumbers,
    this.customRouteRepository,
  });

  /// Composes a cross-building route from [userLocation] to [targetSpace].
  ///
  /// Returns a [NavigationRouteModel] with segments if cross-building routing
  /// applies. Returns `null` if the user is in the same building
  /// (callers should fall through to the existing cascade).
  Future<NavigationRouteModel?> composeRoute({
    required LatLng userLocation,
    required SpaceModel targetSpace,
    required List<SpaceModel> allBuildings,
    String? targetPuid,
  }) async {
    // ── Step 1: Detect cross-building scenario ──
    final userBuilding = _findBuildingAtLocation(userLocation, allBuildings);

    if (userBuilding != null && userBuilding.buid == targetSpace.buid) {
      debugPrint('[CrossBuildingRouter] Same building — use existing cascade');
      return null;
    }

    // User is inside another building OR outside all buildings
    debugPrint(
      userBuilding != null
          ? '[CrossBuildingRouter] Indoor→Outdoor→Indoor: ${userBuilding.name} → ${targetSpace.name}'
          : '[CrossBuildingRouter] Outdoor→Indoor: user is outside → ${targetSpace.name}',
    );

    final segments = <RouteSegment>[];
    final warnings = <String>[];

    // Starting point for outdoor route
    LatLng startOutdoor;

    if (userBuilding != null) {
      // ── Step 2: Select exit POI ──
      final exitPoi = await _selectExitPoi(userBuilding);
      final exitPoint = exitPoi?.latLng ?? userBuilding.latLng;
      final isExitFallback = exitPoi == null;

      debugPrint(
        '[CrossBuildingRouter] Exit: ${isExitFallback ? "centroid fallback" : exitPoi.name}',
      );

      // ── Step 3: Generate exit segment ──
      final exitSegment = await _generateExitSegment(
        userLocation: userLocation,
        exitPoint: exitPoint,
        exitPoi: exitPoi,
        userBuilding: userBuilding,
        isFallback: isExitFallback,
      );
      if (exitSegment != null) {
        segments.add(exitSegment);
      } else {
        warnings.add('Could not generate indoor route to exit');
      }
      startOutdoor = exitPoint;
    } else {
      // User is outdoors — start outdoor route from GPS position
      startOutdoor = userLocation;
    }

    // ── Step 4: Select entrance POI (two-pass) ──
    final entranceResult = await _selectEntrancePoi(
      exitPoint: startOutdoor,
      targetSpace: targetSpace,
    );
    final entrancePoi = entranceResult.poi;
    final entrancePoint = entrancePoi?.latLng ?? targetSpace.latLng;
    final isEntranceFallback = entrancePoi == null;

    print(
      '[ENTRANCE_DEBUG] Step 4: entrancePoi=${entrancePoi?.name}(puid=${entrancePoi?.puid}, floor=${entrancePoi?.floorNumber}), '
      'isFallback=$isEntranceFallback, entrancePoint=$entrancePoint, targetPuid=$targetPuid',
    );

    debugPrint(
      '[CrossBuildingRouter] Entrance: ${isEntranceFallback ? "centroid fallback" : entrancePoi.name} '
      '(score: ${entranceResult.score.toStringAsFixed(1)})',
    );

    // ── Step 5: Generate outdoor segment ──
    final outdoorSegment = await _generateOutdoorSegment(
      exitPoint: startOutdoor,
      entrancePoint: entrancePoint,
      targetBuid: targetSpace.buid,
    );
    if (outdoorSegment != null) {
      segments.add(outdoorSegment);
    } else {
      warnings.add('Could not generate outdoor walking route');
    }

    // ── Step 6: Generate entrance segment ──
    final entranceSegment = await _generateEntranceSegment(
      entrancePoint: entrancePoint,
      entrancePoi: entrancePoi,
      targetSpace: targetSpace,
      targetPuid: targetPuid,
      isFallback: isEntranceFallback,
    );
    if (entranceSegment != null) {
      segments.add(entranceSegment);
    } else {
      warnings.add('Could not generate indoor route from entrance to destination');
    }

    // ── Step 7: Assemble route ──
    if (segments.isEmpty) {
      debugPrint('[CrossBuildingRouter] No segments generated — returning null');
      return null;
    }

    // Filter empty segments
    final validSegments = segments.where((s) => !s.isEmpty).toList();

    // PHASE 7 / BUG-14: never truncate silently. If a composed journey ever
    // exceeds the maximum, keep FIRST + LAST (origin and destination ends)
    // and surface an explicit partial warning instead of dropping the tail.
    const kMaxComposedSegments = 8;
    var truncated = false;
    if (validSegments.length > kMaxComposedSegments) {
      debugPrint(
        '[CrossBuildingRouter] ERROR: ${validSegments.length} segments '
        'exceed max $kMaxComposedSegments — truncating with warning',
      );
      final head = validSegments.first;
      final tail = validSegments.last;
      validSegments
        ..clear()
        ..add(head)
        ..add(tail);
      truncated = true;
    }

    // Determine status
    final hasIncomplete = validSegments.any((s) => s.isIncomplete) || truncated;
    final status = hasIncomplete
        ? RouteModelStatus.partial
        : RouteModelStatus.ready;
    final warning = hasIncomplete
        ? (truncated
            ? 'Journey truncated — too many segments to compose. '
                'Navigate manually for part of the trip.'
                '${warnings.isNotEmpty ? " Details: ${warnings.join("; ")}" : ""}'
            : 'Route incomplete — ${warnings.join("; ")}. '
              'You may need to navigate manually for part of the journey.')
        : null;

    debugPrint(
      '[CrossBuildingRouter] Route: ${validSegments.length} segments, '
      'status: $status',
    );

    return NavigationRouteModel.fromSegments(
      segments: validSegments,
      status: status,
      partialRouteWarning: warning,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Step 1: Building detection
  // ──────────────────────────────────────────────────────────────

  /// Finds the building containing [position] by checking polygon containment.
  SpaceModel? _findBuildingAtLocation(
    LatLng position,
    List<SpaceModel> buildings,
  ) {
    for (final building in buildings) {
      if (isPositionInBuilding(position, building.buid)) {
        return building;
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────
  // Step 2: Exit POI selection
  // ──────────────────────────────────────────────────────────────

  /// Selects the best exit POI from the user's building.
  ///
  /// Returns the floor-transition POI closest to the user's position,
  /// or `null` if none found (centroid fallback).
  Future<PoiModel?> _selectExitPoi(SpaceModel userBuilding) async {
    final floorNumbers = await loadFloorNumbers(userBuilding.buid);
    if (floorNumbers.isEmpty) return null;

    final allPois = <PoiModel>[];
    for (final floor in floorNumbers) {
      final pois = await loadPois(userBuilding.buid, floor);
      allPois.addAll(pois);
    }

    // ONLY use entrance/door POIs — never elevators, stairs, or connectors
    final entrances = PoiClassification.getBuildingEntrances(
      allPois,
      userBuilding.buid,
    ).where((p) =>
        PoiClassification.isEntrance(p) || PoiClassification.isDoor(p),
    ).toList();

    // Prefer ground floor exits
    final groundFloor = entrances.where(
      (p) => p.floorNumber == '0' || p.floorNumber == 'G',
    );

    final candidates =
        groundFloor.isNotEmpty ? groundFloor.toList() : entrances;

    if (candidates.isEmpty) return null;

    // Return the first candidate (closest will be determined by exit segment routing)
    return candidates.first;
  }

  // ──────────────────────────────────────────────────────────────
  // Step 3: Exit segment generation
  // ──────────────────────────────────────────────────────────────

  /// Generates an exit segment from the user's position to the exit point.
  Future<RouteSegment?> _generateExitSegment({
    required LatLng userLocation,
    required LatLng exitPoint,
    PoiModel? exitPoi,
    required SpaceModel userBuilding,
    required bool isFallback,
  }) async {
    if (isFallback) {
      // Straight line from user position to building centroid.
      // PHASE 7 / BUG-14: a centroid fallback IS an incomplete leg — the
      // partial flag must reflect reality.
      return RouteSegment.fallback(
        type: RouteSegmentType.exitTransition,
        points: [userLocation, exitPoint],
        buildingId: userBuilding.buid,
        instruction: 'Exit ${userBuilding.name}',
        isIncomplete: true,
      );
    }

    // Try Anyplace API for indoor routing to exit POI
    if (exitPoi != null && exitPoi.puid.isNotEmpty) {
      try {
        final result = await AnyplaceApiClient().fetchNavigationRouteFromCoordinates(
          latitude: userLocation.latitude,
          longitude: userLocation.longitude,
          floorNumber: exitPoi.floorNumber,
          destinationPuid: exitPoi.puid,
        );

        if (result.hasRenderablePath) {
          return RouteSegment.exit(
            points: result.polylinePoints,
            buildingId: userBuilding.buid,
            floorNumber: exitPoi.floorNumber,
            connectorPoiId: exitPoi.puid,
            instruction: 'Exit ${userBuilding.name} via ${exitPoi.name}',
          );
        }
      } catch (e) {
        debugPrint('[CrossBuildingRouter] Exit API failed: $e');
      }
    }

    // Fallback: straight line
    return RouteSegment.exit(
      points: [userLocation, exitPoint],
      buildingId: userBuilding.buid,
      floorNumber: exitPoi?.floorNumber ?? '0',
      instruction: 'Exit ${userBuilding.name}',
      isIncomplete: true,
      isFallbackLocation: true,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Step 4: Entrance POI selection (two-pass)
  // ──────────────────────────────────────────────────────────────

  /// Selects the best entrance POI at the destination building using
  /// two-pass scoring: OSRM cost + approach direction bearing.
  Future<_EntranceSelectionResult> _selectEntrancePoi({
    required LatLng exitPoint,
    required SpaceModel targetSpace,
  }) async {
    final floorNumbers = await loadFloorNumbers(targetSpace.buid);
    if (floorNumbers.isEmpty) {
      return const _EntranceSelectionResult(
        poi: null,
        score: double.infinity,
        distance: 0,
        bearing: 0,
      );
    }

    final allPois = <PoiModel>[];
    for (final floor in floorNumbers) {
      final pois = await loadPois(targetSpace.buid, floor);
      allPois.addAll(pois);
    }

    // ONLY use entrance/door POIs — never elevators, stairs, or connectors
    final entrances = PoiClassification.getBuildingEntrances(
      allPois,
      targetSpace.buid,
    ).where((p) =>
        PoiClassification.isEntrance(p) || PoiClassification.isDoor(p),
    ).toList();

    // Deduplicate by puid
    final candidatesMap = <String, PoiModel>{};
    for (final p in entrances) {
      candidatesMap[p.puid] = p;
    }
    final candidates = candidatesMap.values.toList();

    if (candidates.isEmpty) {
      return const _EntranceSelectionResult(
        poi: null,
        score: double.infinity,
        distance: 0,
        bearing: 0,
      );
    }

    if (candidates.length == 1) {
      // Only one candidate — get its OSRM cost
      final result = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
        fromLat: exitPoint.latitude,
        fromLon: exitPoint.longitude,
        toLat: candidates.first.latitude,
        toLon: candidates.first.longitude,
      );
      return _EntranceSelectionResult(
        poi: candidates.first,
        score: result?.distanceMeters ?? double.infinity,
        distance: result?.distanceMeters ?? 0,
        bearing: result?.finalBearingDegrees ?? 0,
      );
    }

    // Pass 1: Get OSRM cost + bearing for each candidate
    final scoredCandidates = <_ScoredEntrance>[];
    for (final candidate in candidates) {
      final result = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
        fromLat: exitPoint.latitude,
        fromLon: exitPoint.longitude,
        toLat: candidate.latitude,
        toLon: candidate.longitude,
      );

      if (result == null) continue;

      scoredCandidates.add(_ScoredEntrance(
        poi: candidate,
        distance: result.distanceMeters,
        bearing: result.finalBearingDegrees,
      ));
    }

    if (scoredCandidates.isEmpty) {
      return const _EntranceSelectionResult(
        poi: null,
        score: double.infinity,
        distance: 0,
        bearing: 0,
      );
    }

    // Pass 2: Score and select
    _ScoredEntrance? best;
    double bestScore = double.infinity;

    for (final candidate in scoredCandidates) {
      // Vector from building centroid to entrance
      final centroidToEntrance = _computeBearing(
        targetSpace.latLng,
        candidate.poi.latLng,
      );

      // Angular difference between approach bearing and centroid-to-entrance bearing
      final angleDiff = _angleDifference(candidate.bearing, centroidToEntrance);

      // Composite score: distance * 0.6 + angular penalty * 0.4
      final score = candidate.distance * 0.6 + angleDiff * 100 * 0.4;

      debugPrint(
        '[CrossBuildingRouter] Entrance candidate: ${candidate.poi.name} '
        '(${candidate.distance.toStringAsFixed(0)}m, '
        'bearing: ${candidate.bearing.toStringAsFixed(1)}°, '
        'angle: ${angleDiff.toStringAsFixed(1)}°, '
        'score: ${score.toStringAsFixed(1)})',
      );

      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return _EntranceSelectionResult(
      poi: best?.poi,
      score: bestScore,
      distance: best?.distance ?? 0,
      bearing: best?.bearing ?? 0,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Step 5: Outdoor segment generation
  // ──────────────────────────────────────────────────────────────

  /// Generates an outdoor walking segment from exit to entrance.
  ///
  /// Uses a multi-tier approach:
  /// 1. Pure custom KMZ route (both endpoints near graph vertices)
  /// 2. Hybrid custom route (edge-snap both endpoints)
  /// 3. OSRM to nearest custom vertex + custom route to destination
  /// 4. OSRM route with custom tail splice
  /// 5. OSRM-only fallback
  Future<RouteSegment?> _generateOutdoorSegment({
    required LatLng exitPoint,
    required LatLng entrancePoint,
    required String targetBuid,
  }) async {
    final customRepo = customRouteRepository;

    // ── Tier 1: Pure custom graph routing ──
    if (customRepo != null && customRepo.isLoaded) {
      final customPath = customRepo.findRoute(exitPoint, entrancePoint);
      if (customPath.length >= 2) {
        debugPrint(
          '[CrossBuildingRouter] Outdoor: pure custom route (${customPath.length} points)',
        );
        return RouteSegment.outdoor(
          points: customPath,
          buildingId: targetBuid,
          instruction: 'Walk to destination building (campus route)',
          distance: _computePathDistance(customPath),
        );
      }
    }

    // ── Tier 2: Hybrid custom route (edge-snap) ──
    if (customRepo != null && customRepo.isLoaded) {
      final hybridPath = customRepo.findHybridRoute(
        exitPoint,
        entrancePoint,
        snapThreshold: 150.0,
      );
      if (hybridPath != null && hybridPath.length >= 2) {
        debugPrint(
          '[CrossBuildingRouter] Outdoor: hybrid custom route (${hybridPath.length} points)',
        );
        return RouteSegment.outdoor(
          points: hybridPath,
          buildingId: targetBuid,
          instruction: 'Walk to destination building (campus route)',
          distance: _computePathDistance(hybridPath),
        );
      }
    }

    // ── Tier 3: OSRM to nearest custom vertex + custom to destination ──
    // This is the KEY tier for campus navigation:
    // OSRM handles the public road to the campus edge,
    // then custom routes handle the campus roads to the building.
    if (customRepo != null && customRepo.isLoaded) {
      final combinedPath = await _buildOsrmToCustomRoute(
        exitPoint,
        entrancePoint,
        customRepo,
      );
      if (combinedPath != null && combinedPath.length >= 2) {
        debugPrint(
          '[CrossBuildingRouter] Outdoor: OSRM→Custom route '
          '(${combinedPath.length} points)',
        );
        return RouteSegment.outdoor(
          points: combinedPath,
          buildingId: targetBuid,
          instruction: 'Walk to destination building (campus route)',
          distance: _computePathDistance(combinedPath),
        );
      }
    }

    // ── Tier 4: OSRM with custom tail splice ──
    final osrmResult = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
      fromLat: exitPoint.latitude,
      fromLon: exitPoint.longitude,
      toLat: entrancePoint.latitude,
      toLon: entrancePoint.longitude,
    );

    if (osrmResult != null && osrmResult.points.length >= 2) {
      final osrmPath = osrmResult.points;
      debugPrint(
        '[CrossBuildingRouter] Outdoor: OSRM returned ${osrmPath.length} points, '
        '${osrmResult.distanceMeters.toStringAsFixed(0)}m',
      );

      // Try to splice custom routes into the tail portion of OSRM
      if (customRepo != null && customRepo.isLoaded) {
        final combinedPath = _spliceCustomTail(osrmPath, entrancePoint, customRepo);
        if (combinedPath != null) {
          debugPrint(
            '[CrossBuildingRouter] Outdoor: OSRM+Custom splice '
            '(${combinedPath.length} points total)',
          );
          return RouteSegment.outdoor(
            points: combinedPath,
            buildingId: targetBuid,
            instruction: 'Walk to destination building (campus route)',
            distance: _computePathDistance(combinedPath),
          );
        }
      }

      // ── Tier 5: OSRM-only ──
      debugPrint('[CrossBuildingRouter] Outdoor: OSRM-only (${osrmPath.length} points)');
      return RouteSegment.outdoor(points: osrmPath,
        buildingId: targetBuid,
        instruction: 'Walk to destination building',
        distance: osrmResult.distanceMeters,);
    }

    // ── Fallback: straight line ──
    return RouteSegment.outdoor(points: [exitPoint, entrancePoint],
      buildingId: targetBuid,
      instruction: 'Walk to destination building',
      isIncomplete: true,);
  }

  /// Builds a combined route: OSRM from user to a campus entrance endpoint,
  /// then custom route through the campus to the destination.
  ///
  /// Key insight: OSRM routes to a route ENDPOINT (where campus roads meet
  /// public roads), NOT to a vertex near the destination. This prevents OSRM
  /// from following parallel public roads inside the campus.
  Future<List<LatLng>?> _buildOsrmToCustomRoute(
    LatLng userLocation,
    LatLng destination,
    CustomRouteRepository customRepo,
  ) async {
    final destVertex = customRepo.graph.nearestVertex(
      destination,
      maxDistance: 500.0,
    );
    if (destVertex == null) {
      debugPrint('[CrossBuildingRouter] osrm→custom: no vertex within 500m of dest');
      return null;
    }
    final destVertexIdx = destVertex.$1;

    debugPrint(
      '[CrossBuildingRouter] osrm→custom: dest vertex=$destVertexIdx, '
      '${destVertex.$2.toStringAsFixed(0)}m from destination',
    );

    // Step 1: Get all route endpoints (where campus roads meet public roads)
    final endpoints = customRepo.graph.getRouteEndpoints();
    debugPrint(
      '[CrossBuildingRouter] osrm→custom: ${endpoints.length} route endpoints',
    );

    if (endpoints.isEmpty) {
      debugPrint('[CrossBuildingRouter] osrm→custom: no route endpoints');
      return null;
    }

    // Step 2: Among endpoints connected to destVertex, find closest to user
    int? bestEntryIdx;
    double bestEntryDist = double.infinity;

    for (final (epIdx, epPos) in endpoints) {
      final path = customRepo.graph.shortestPath(epIdx, destVertexIdx);
      if (path.isEmpty) continue;

      final dist = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        epPos.latitude,
        epPos.longitude,
      );

      debugPrint(
        '[CrossBuildingRouter] osrm→custom: endpoint $epIdx, '
        '${dist.toStringAsFixed(0)}m from user, '
        'path to dest: ${path.length} vertices',
      );

      if (dist < bestEntryDist) {
        bestEntryDist = dist;
        bestEntryIdx = epIdx;
      }
    }

    if (bestEntryIdx == null) {
      debugPrint('[CrossBuildingRouter] osrm→custom: no endpoint connected to dest');
      return null;
    }

    final entryPos = customRepo.graph.getVertexPosition(bestEntryIdx);
    debugPrint(
      '[CrossBuildingRouter] osrm→custom: best entry=$bestEntryIdx, '
      '${bestEntryDist.toStringAsFixed(0)}m from user, '
      'at ${entryPos.latitude},${entryPos.longitude}',
    );

    // Step 3: OSRM from user to the chosen campus entrance endpoint
    final osrmResult = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
      fromLat: userLocation.latitude,
      fromLon: userLocation.longitude,
      toLat: entryPos.latitude,
      toLon: entryPos.longitude,
    );

    if (osrmResult == null || osrmResult.points.length < 2) {
      debugPrint('[CrossBuildingRouter] osrm→custom: OSRM failed to endpoint');
      return null;
    }

    final osrmPath = osrmResult.points;
    debugPrint(
      '[CrossBuildingRouter] osrm→custom: OSRM to endpoint = '
      '${osrmPath.length} points, ${osrmResult.distanceMeters.toStringAsFixed(0)}m',
    );

    // Step 4: Route through custom graph from entry endpoint to destination vertex
    final customPath = customRepo.graph.shortestPath(bestEntryIdx, destVertexIdx);

    if (customPath.isEmpty) {
      debugPrint(
        '[CrossBuildingRouter] osrm→custom: no graph path from '
        '$bestEntryIdx to $destVertexIdx',
      );
      return [...osrmPath, destination];
    }

    debugPrint(
      '[CrossBuildingRouter] osrm→custom: custom graph path = '
      '${customPath.length} vertices',
    );

    // Step 5: Build combined route: OSRM → custom graph → walk to destination
    final combined = <LatLng>[
      ...osrmPath,
      for (final idx in customPath)
        customRepo.graph.getVertexPosition(idx),
      destination,
    ];

    debugPrint(
      '[CrossBuildingRouter] osrm→custom: combined = '
      '${osrmPath.length} OSRM + ${customPath.length} custom + 1 dest = '
      '${combined.length} total',
    );

    return combined;
  }

  /// Attempts to replace the tail of the OSRM route with a custom route.
  ///
  /// Strategy:
  /// 1. Search the ENTIRE OSRM path backward for points near the custom graph.
  /// 2. From the found snap point, route through the custom graph to the vertex
  ///    nearest the destination.
  /// 3. Append a straight-line walk from the last custom vertex to the destination.
  List<LatLng>? _spliceCustomTail(
    List<LatLng> osrmPath,
    LatLng destination,
    CustomRouteRepository customRepo,
  ) {
    if (osrmPath.length < 2) return null;

    // Find the nearest custom graph vertex to the destination (allow 500m)
    final destVertex = customRepo.graph.nearestVertex(
      destination,
      maxDistance: 500.0,
    );
    if (destVertex == null) {
      debugPrint('[CrossBuildingRouter] splice: no custom graph vertices within 500m of destination');
      return null;
    }
    final destVertexIdx = destVertex.$1;
    final distToDest = destVertex.$2;

    debugPrint(
      '[CrossBuildingRouter] splice: dest vertex index=$destVertexIdx, '
      'dist=${distToDest.toStringAsFixed(0)}m',
    );

    // Search the ENTIRE OSRM path backward (closest to destination first)
    for (var i = osrmPath.length - 1; i >= 0; i--) {
      final snap = customRepo.snapToRoute(
        osrmPath[i],
        maxSnapDistance: 150.0,
      );
      if (snap == null) continue;

      debugPrint(
        '[CrossBuildingRouter] splice: found connection at OSRM[$i], '
        'snap dist: ${snap.distanceMeters.toStringAsFixed(1)}m',
      );

      // Get the two vertices of the snapped edge
      final fromV = customRepo.graph.edgeFromVertex(snap.edgeIndex);
      final toV = customRepo.graph.edgeToVertex(snap.edgeIndex);
      if (fromV < 0 || toV < 0) continue;

      // Try both edge vertices as entry points
      for (final entryIdx in [fromV, toV]) {
        final path = customRepo.graph.shortestPath(entryIdx, destVertexIdx);
        if (path.isEmpty) continue;

        // Build: OSRM[0..i] + custom graph path + straight line to destination
        final combined = <LatLng>[
          ...osrmPath.sublist(0, i),
          for (final idx in path) customRepo.graph.getVertexPosition(idx),
          destination,
        ];

        final osrmPart = osrmPath.sublist(0, i);
        final totalDist = _computePathDistance(combined);

        debugPrint(
          '[CrossBuildingRouter] splice: combined '
          '${osrmPart.length} OSRM + '
          '${path.length} custom vertices + '
          '1 walk = '
          '${combined.length} points, '
          '${totalDist.toStringAsFixed(0)}m total',
        );
        return combined;
      }

      debugPrint(
        '[CrossBuildingRouter] splice: no path from edge ${snap.edgeIndex} '
        '(vertices $fromV,$toV) to dest vertex $destVertexIdx',
      );
      // Continue searching for a better snap point
    }

    debugPrint('[CrossBuildingRouter] splice: no custom connection found in OSRM path');
    return null;
  }

  /// Computes total geodesic distance of a path in meters.
  static double _computePathDistance(List<LatLng> points) {
    double total = 0;
    for (var i = 0; i < points.length - 1; i++) {
      total += Geolocator.distanceBetween(
        points[i].latitude,
        points[i].longitude,
        points[i + 1].latitude,
        points[i + 1].longitude,
      );
    }
    return total;
  }

  // ──────────────────────────────────────────────────────────────
  // Step 6: Entrance segment generation
  // ──────────────────────────────────────────────────────────────

  /// Generates the destination-building leg from the building entrance to
  /// the destination.
  ///
  /// Representation semantics: when REAL indoor geometry exists (server /
  /// connector-derived), it is typed [RouteSegmentType.indoorRouting] — it
  /// IS indoor navigation, so it renders with the same intended indoor style
  /// as every other genuine indoor leg. Only the unknown-geometry fallbacks
  /// remain [RouteSegmentType.entranceTransition] (an honest boundary-gap
  /// marker flagged incomplete) — a boundary polyline cannot be fabricated
  /// from data we do not have.
  Future<RouteSegment?> _generateEntranceSegment({
    required LatLng entrancePoint,
    PoiModel? entrancePoi,
    required SpaceModel targetSpace,
    String? targetPuid,
    required bool isFallback,
  }) async {
    print('[ENTRANCE_DEBUG] isFallback=$isFallback, entrancePoi=${entrancePoi?.name}(puid=${entrancePoi?.puid}), targetPuid=$targetPuid, targetSpace=${targetSpace.name}(buid=${targetSpace.buid})');

    if (isFallback) {
      // Straight line from entrance to building centroid.
      // PHASE 7 / BUG-14: partiality is explicit (see exit-side twin).
      return RouteSegment.fallback(
        type: RouteSegmentType.entranceTransition,
        points: [entrancePoint, targetSpace.latLng],
        buildingId: targetSpace.buid,
        instruction: 'Enter ${targetSpace.name}',
        isIncomplete: true,
      );
    }

    // Route from entrance POI to the user's actual target POI
    if (entrancePoi != null && entrancePoi.puid.isNotEmpty && targetPuid != null) {
      // Try POI-to-POI routing first (uses connector graph from Anyplace Architect)
      try {
        print('[ENTRANCE_DEBUG] Trying POI-to-POI: ${entrancePoi.puid} → $targetPuid');
        final result = await AnyplaceApiClient().fetchNavigationRoute(
          fromPuid: entrancePoi.puid,
          toPuid: targetPuid,
        );

        if (result.hasRenderablePath) {
          print('[ENTRANCE_DEBUG] POI-to-POI SUCCESS: ${result.points.length} points');
          return RouteSegment.indoor(
            points: result.polylinePoints,
            buildingId: targetSpace.buid,
            floorNumber: entrancePoi.floorNumber,
            pointFloors: result.points.map((p) => p.floorNumber).toList(),
            connectorPoiId: entrancePoi.puid,
            instruction: 'Enter ${targetSpace.name}',
          );
        } else {
          print('[ENTRANCE_DEBUG] POI-to-POI returned no renderable path (${result.points.length} points)');
        }
      } catch (e) {
        print('[ENTRANCE_DEBUG] POI-to-POI FAILED: $e');
      }

      // Fallback: coordinate-based routing
      try {
        print('[ENTRANCE_DEBUG] Trying coord-based: ${entrancePoint.latitude},${entrancePoint.longitude} floor=${entrancePoi.floorNumber} → $targetPuid');
        final result = await AnyplaceApiClient().fetchNavigationRouteFromCoordinates(
          latitude: entrancePoint.latitude,
          longitude: entrancePoint.longitude,
          floorNumber: entrancePoi.floorNumber,
          destinationPuid: targetPuid,
        );

        if (result.hasRenderablePath) {
          print('[ENTRANCE_DEBUG] coord-based SUCCESS: ${result.points.length} points');
          return RouteSegment.indoor(
            points: result.polylinePoints,
            buildingId: targetSpace.buid,
            floorNumber: entrancePoi.floorNumber,
            pointFloors: result.points.map((p) => p.floorNumber).toList(),
            connectorPoiId: entrancePoi.puid,
            instruction: 'Enter ${targetSpace.name}',
          );
        } else {
          print('[ENTRANCE_DEBUG] coord-based returned no renderable path');
        }
      } catch (e) {
        print('[ENTRANCE_DEBUG] coord-based FAILED: $e');
      }

      // Fallback: Route through intermediate connector POIs
      // The server requires edges between POIs. Rooms/entrances often lack edges,
      // but connector POIs (pois_type == "None") have edges between them.
      try {
        print('[ENTRANCE_DEBUG] Trying connector-based routing...');
        final route = await _routeViaConnectors(
          entrancePoi: entrancePoi,
          targetPuid: targetPuid,
          targetSpace: targetSpace,
        );
        if (route != null) {
          print('[ENTRANCE_DEBUG] connector-based SUCCESS: ${route.length} points');
          return RouteSegment.indoor(
            points: route,
            buildingId: targetSpace.buid,
            floorNumber: entrancePoi.floorNumber,
            connectorPoiId: entrancePoi.puid,
            instruction: 'Enter ${targetSpace.name}',
          );
        }
      } catch (e) {
        print('[ENTRANCE_DEBUG] connector-based FAILED: $e');
      }
    } else {
      print('[ENTRANCE_DEBUG] SKIPPED API calls: entrancePoi=${entrancePoi?.name}, puid=${entrancePoi?.puid}, targetPuid=$targetPuid');
    }

    // Fallback: straight line
    return RouteSegment.entrance(
      points: [entrancePoint, targetSpace.latLng],
      buildingId: targetSpace.buid,
      floorNumber: entrancePoi?.floorNumber ?? '0',
      instruction: 'Enter ${targetSpace.name}',
      isIncomplete: true,
      isFallbackLocation: true,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Bearing utilities
  // ──────────────────────────────────────────────────────────────

  /// Computes the initial bearing (in degrees, 0-360) from [from] to [to].
  static double _computeBearing(LatLng from, LatLng to) {
    final dLon = _toRadians(to.longitude - from.longitude);
    final lat1 = _toRadians(from.latitude);
    final lat2 = _toRadians(to.latitude);
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final bearing = atan2(y, x);
    return (_toDegrees(bearing) + 360) % 360;
  }

  /// Computes the smallest angle between two bearings (0-180 degrees).
  static double _angleDifference(double a, double b) {
    final diff = (a - b).abs() % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  static double _toRadians(double degrees) => degrees * pi / 180.0;
  static double _toDegrees(double radians) => radians * 180.0 / pi;

  /// Routes from entrance to target by finding nearest connector POIs
  /// and routing through the connector graph.
  ///
  /// The server requires edges between POIs for routing. Room/entrance POIs
  /// often lack edges, but connector POIs (pois_type == "None") have edges
  /// between them in the hallway.
  Future<List<LatLng>?> _routeViaConnectors({
    required PoiModel entrancePoi,
    required String targetPuid,
    required SpaceModel targetSpace,
  }) async {
    // Load all POIs for the entrance's floor
    final floorPois = await loadPois(targetSpace.buid, entrancePoi.floorNumber);
    if (floorPois.isEmpty) return null;

    // Find connector POIs (pois_type == "None" in Anyplace)
    final connectors = floorPois
        .where((p) => p.puid.isNotEmpty && p.poisType == 'None')
        .toList();
    if (connectors.isEmpty) {
      print('[ENTRANCE_DEBUG] No connector POIs found on floor ${entrancePoi.floorNumber}');
      return null;
    }
    print('[ENTRANCE_DEBUG] Found ${connectors.length} connectors on floor ${entrancePoi.floorNumber}');

    // Find nearest connector to entrance
    PoiModel? nearestToEntrance;
    double minDistEntrance = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        entrancePoi.latitude, entrancePoi.longitude,
        c.latitude, c.longitude,
      );
      if (dist < minDistEntrance) {
        minDistEntrance = dist;
        nearestToEntrance = c;
      }
    }

    // Find nearest connector to target
    final targetPoi = floorPois.firstWhere(
      (p) => p.puid == targetPuid,
      orElse: () => entrancePoi,
    );
    PoiModel? nearestToTarget;
    double minDistTarget = double.infinity;
    for (final c in connectors) {
      final dist = Geolocator.distanceBetween(
        targetPoi.latitude, targetPoi.longitude,
        c.latitude, c.longitude,
      );
      if (dist < minDistTarget) {
        minDistTarget = dist;
        nearestToTarget = c;
      }
    }

    if (nearestToEntrance == null || nearestToTarget == null) return null;

    print('[ENTRANCE_DEBUG] nearest connector to entrance: ${nearestToEntrance.name} (${minDistEntrance.toStringAsFixed(0)}m)');
    print('[ENTRANCE_DEBUG] nearest connector to target: ${nearestToTarget.name} (${minDistTarget.toStringAsFixed(0)}m)');

    // If both connectors are the same, just do a straight line
    if (nearestToEntrance.puid == nearestToTarget.puid) {
      print('[ENTRANCE_DEBUG] Same connector for both — straight line');
      return [entrancePoi.latLng, nearestToEntrance.latLng, targetPoi.latLng];
    }

    // Route between the two connectors via the server API
    try {
      final connectorRoute = await AnyplaceApiClient().fetchNavigationRoute(
        fromPuid: nearestToEntrance.puid,
        toPuid: nearestToTarget.puid,
      );

      if (connectorRoute.hasRenderablePath && connectorRoute.points.length >= 2) {
        print('[ENTRANCE_DEBUG] connector→connector route: ${connectorRoute.points.length} points');
        // Build full path: entrance → connector_start + route + connector_end → target
        final fullPath = <LatLng>[
          entrancePoi.latLng,
          nearestToEntrance.latLng,
          ...connectorRoute.polylinePoints,
          nearestToTarget.latLng,
          targetPoi.latLng,
        ];
        return fullPath;
      } else {
        print('[ENTRANCE_DEBUG] connector→connector returned ${connectorRoute.points.length} points');
      }
    } catch (e) {
      print('[ENTRANCE_DEBUG] connector→connector FAILED: $e');
    }

    // Last resort: straight lines through the nearest connectors
    print('[ENTRANCE_DEBUG] Falling back to straight-line through connectors');
    return [
      entrancePoi.latLng,
      nearestToEntrance.latLng,
      nearestToTarget.latLng,
      targetPoi.latLng,
    ];
  }
}

/// Internal helper for scored entrance candidates.
class _ScoredEntrance {
  final PoiModel poi;
  final double distance;
  final double bearing;

  const _ScoredEntrance({
    required this.poi,
    required this.distance,
    required this.bearing,
  });
}

/// Result of entrance POI selection with scoring.
class _EntranceSelectionResult {
  final PoiModel? poi;
  final double score;
  final double distance;
  final double bearing;

  const _EntranceSelectionResult({
    required this.poi,
    required this.score,
    required this.distance,
    required this.bearing,
  });
}
