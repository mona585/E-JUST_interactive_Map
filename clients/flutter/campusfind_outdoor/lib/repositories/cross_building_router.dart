import 'dart:math' show cos, sin, atan2, pi;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../utils/building_containment.dart';
import '../models/campus_gate.dart';
import '../models/floor_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../utils/poi_classification.dart';
import 'campus_gate_repository.dart';
import 'custom_route_repository.dart';
import 'navigation_repository.dart';

/// Orchestrates OUTDOOR-ONLY route composition.
///
/// Regardless of where the user (or the destination) sits relative to building
/// footprints, this class produces a single journey: an outdoor walking leg
/// (campus reverse-geocode graph / OSRM / campus road graph) that terminates at
/// the destination building's outdoor-accessible entrance.
/// ```
/// Origin (GPS, or origin building entrance) → [Outdoor Walking Route] →
/// Destination Building Entrance
/// ```
///
/// No indoor leg is ever produced. When the user's position is classified
/// inside a building footprint, the route starts at that building's nearest
/// outdoor-accessible entrance (see [composeRoute]); the interior portion is
/// never routed. Callers surface an [OutdoorRouteException] when no honest
/// outdoor route is possible.
///
/// The outdoor leg optionally honors a configured campus gate: when a
/// preferred [CampusGate] is available, the public-road (OSRM) portion ends
/// at that gate and the campus road graph carries the user to the
/// destination. The gate coordinates always come from [CampusGateRepository]
/// configuration — never from hardcoded values in this class.
class CrossBuildingRouter {
  /// Loads the [FloorModel]s (with server-real geographic bounds) for a
  /// building. Used by building-containment detection to decide which
  /// building the user is physically inside.
  final Future<List<FloorModel>> Function(String buid) loadFloorsForBuilding;

  /// Loads POIs for a building's floor.
  final Future<List<PoiModel>> Function(String buid, String floorNumber) loadPois;

  /// Loads all floors for a building.
  final Future<List<String>> Function(String buid) loadFloorNumbers;

  /// Custom route repository for outdoor walking paths (KMZ routes).
  final CustomRouteRepository? customRouteRepository;

  /// Campus gate data source + policy. When available and a preferred gate
  /// resolves, the outdoor OSRM leg is directed to that gate.
  final CampusGateRepository? campusGateRepository;

  /// Route acquisition (indoor + outdoor OSRM) behind an abstraction so this
  /// orchestrator never touches the API client directly.
  final NavigationRepository navigationRepository;

  CrossBuildingRouter({
    required this.loadFloorsForBuilding,
    required this.loadPois,
    required this.loadFloorNumbers,
    required this.navigationRepository,
    this.customRouteRepository,
    this.campusGateRepository,
  });

  /// Composes an OUTDOOR-ONLY route from [userLocation] to [targetSpace].
  ///
  /// The journey is a single outdoor walking leg (campus road graph / OSRM)
  /// that terminates at the destination building's outdoor-accessible
  /// entrance. No indoor leg is ever produced.
  ///
  /// Origin policy (CP-8 / D2): when the user's position is classified inside
  /// a building footprint, the outdoor route STARTS at that building's nearest
  /// outdoor-accessible entrance — never at the interior coordinate. If the
  /// user is inside a building with no resolvable entrance, an
  /// [OutdoorRouteException] is thrown so the caller can surface a clear
  /// failure instead of fabricating an interior origin.
  ///
  /// Same-building (user already inside the destination building): the only
  /// honest outdoor destination is the building's own entrance. When the
  /// resolved origin and destination entrances coincide there is no outdoor
  /// leg to travel, so an [OutdoorRouteException] is thrown with a clear
  /// message.
  Future<NavigationRouteModel> composeRoute({
    required LatLng userLocation,
    required SpaceModel targetSpace,
    required List<SpaceModel> allBuildings,
  }) async {
    final userBuilding = await _findBuildingAtLocation(
      userLocation,
      allBuildings,
    );

    // ── Origin resolution (D2) ──
    final LatLng startOutdoor;
    PoiModel? originEntrance;
    if (userBuilding != null) {
      originEntrance = await _selectExitPoi(userBuilding, userLocation);
      if (originEntrance == null) {
        throw OutdoorRouteException(
          'Cannot start an outdoor route from inside ${userBuilding.name}: '
          'no outdoor entrance is available.',
        );
      }
      debugPrint(
        '[CrossBuildingRouter] Origin entrance: ${originEntrance.name} '
        '(${userBuilding.name})',
      );
      startOutdoor = originEntrance.latLng;
    } else {
      // User is outdoors — start the outdoor route from the GPS position.
      startOutdoor = userLocation;
    }

    // ── Destination entrance resolution ──
    final entranceResult = await _selectEntrancePoi(
      exitPoint: startOutdoor,
      targetSpace: targetSpace,
    );
    final entrancePoi = entranceResult.poi;

    // Same-building: the user is inside the destination building. Without
    // indoor routing the route can only deliver them to the building's
    // entrance. If origin and destination entrances coincide there is no
    // outdoor leg to travel — refuse with a clear, truthful message.
    final bool sameBuilding =
        userBuilding != null && userBuilding.buid == targetSpace.buid;
    if (sameBuilding) {
      if (entrancePoi == null) {
        throw OutdoorRouteException(
          'No outdoor entrance is available for ${targetSpace.name}. '
          'Outdoor navigation ends at the building entrance.',
        );
      }
      if (originEntrance!.puid == entrancePoi.puid) {
        throw OutdoorRouteException(
          'You are already at the ${targetSpace.name} entrance. '
          'Outdoor navigation ends at the building entrance.',
        );
      }
    }

    final entrancePoint = entrancePoi?.latLng ?? targetSpace.latLng;

    debugPrint(
      '[CrossBuildingRouter] Entrance: ${entrancePoi?.name ?? "centroid fallback"} '
      '(score: ${entranceResult.score.toStringAsFixed(1)})',
    );

    final warnings = <String>[];

    // ── Outdoor leg ──
    final outdoorSegment = await _generateOutdoorSegment(
      exitPoint: startOutdoor,
      entrancePoint: entrancePoint,
      targetBuid: targetSpace.buid,
      warnings: warnings,
    );

    final segments = <RouteSegment>[
      ?outdoorSegment,
    ];

    if (segments.isEmpty) {
      throw const OutdoorRouteException(
        'Could not generate an outdoor walking route.',
      );
    }

    final validSegments = segments.where((s) => !s.isEmpty).toList();

    final hasIncomplete = validSegments.any((s) => s.isIncomplete);
    final status = hasIncomplete
        ? RouteModelStatus.partial
        : RouteModelStatus.ready;
    final warning = hasIncomplete
        ? 'Route incomplete — ${warnings.join("; ")}. '
              'You may need to navigate manually for part of the journey.'
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

  /// Finds the building containing [position] using the canonical
  /// [BuildingContainment] service over each building's server-real floor
  /// bounds.
  ///
  /// Collects every building whose real floor bounds contain [position], then
  /// resolves deterministically: the containing building with the STRICTEST
  /// (smallest) matched floor rectangle wins, with a stable buid tie-break.
  /// Never falls back to centroid/distance heuristics. Buildings with no
  /// reliable geometry are never reported as containing the point.
  Future<SpaceModel?> _findBuildingAtLocation(
    LatLng position,
    List<SpaceModel> buildings,
  ) async {
    SpaceModel? result;
    double? bestSpan;
    String? bestBuid;

    for (final building in buildings) {
      final floors = await loadFloorsForBuilding(building.buid);
      final containment = BuildingContainment.classify(position, floors);
      if (!containment.isInside || containment.containingFloor == null) {
        continue;
      }
      final span = BuildingContainment.approxSpanMeters(
        containment.containingFloor!,
      );
      final better = result == null ||
          span < bestSpan! ||
          (span == bestSpan && building.buid.compareTo(bestBuid!) < 0);
      if (better) {
        result = building;
        bestSpan = span;
        bestBuid = building.buid;
      }
    }

    return result;
  }

  /// Public seam over [_findBuildingAtLocation] used by callers that need the
  /// canonical building-containment answer without composing a full route.
  /// Deterministic and network-free (relies on the injected floor data).
  Future<SpaceModel?> detectUserBuilding(
    LatLng position,
    List<SpaceModel> buildings,
  ) {
    return _findBuildingAtLocation(position, buildings);
  }

  // ──────────────────────────────────────────────────────────────
  // Step 2: Origin entrance selection
  // ──────────────────────────────────────────────────────────────

  /// Selects the outdoor-accessible entrance that anchors the route origin
  /// when the user is classified inside [userBuilding].
  ///
  /// Returns the entrance/door POI closest to the user's CURRENT position (so
  /// the produced outdoor origin is the nearest way out), or `null` when the
  /// building exposes no usable entrance.
  Future<PoiModel?> _selectExitPoi(
    SpaceModel userBuilding,
    LatLng userLocation,
  ) async {
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

    // NAV-002 FIX: choose the exit NEAREST the user's current position so the
    // indoor walk-out is shortest — NOT the first in load order.
    PoiModel? nearest;
    double nearestDist = double.infinity;
    for (final c in candidates) {
      final d = Geolocator.distanceBetween(
        userLocation.latitude,
        userLocation.longitude,
        c.latitude,
        c.longitude,
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearest = c;
      }
    }
    return nearest;
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
      final result = await navigationRepository.getOutdoorWalkingRouteWithMetadata(
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
      final result = await navigationRepository.getOutdoorWalkingRouteWithMetadata(
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

    // Pass 2: Score and select.
    //
    // Walking proximity is the PRIMARY criterion: the entrance the user has to
    // walk the least to reach should normally win. The angular-alignment term
    // (how well the approach heading matches the direction the entrance faces)
    // is retained ONLY as a small tie-breaker, so a favourable approach angle
    // can never override a real distance gap.
    //
    // Weights are chosen so the angle term is bounded far below any meaningful
    // distance delta. With kAngleWeightPerDegree = 0.1 and angleDiff in
    // 0..180°, the worst-case angular contribution is 18m-equivalent — well
    // under the ~50m+ gaps that should decide entrance choice. E.g. in the B7
    // case a ~50m entrance (even at a poor angle) must beat a ~114m one (even
    // at a perfect angle).
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

      final score = _entranceScore(candidate.distance, angleDiff);

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
    required List<String> warnings,
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
        snapThreshold: 250.0,
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
      final gate = campusGateRepository?.preferredGate();
      final combinedPath = await _buildOsrmToCustomRoute(
        exitPoint,
        entrancePoint,
        customRepo,
        gateEntry: gate,
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
    final osrmResult = await navigationRepository.getOutdoorWalkingRouteWithMetadata(
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
    // T5.3 / P1: this is an explicit, VISIBLE degraded state — not a silent
    // substitution. The incomplete flag makes the route partial, and the
    // warning surfaces a clear "outdoor routing unavailable" message.
    warnings.add(
      'Outdoor routing unavailable — following an approximate straight-line '
      'path. You may need to navigate manually for this leg.',
    );
    return RouteSegment.outdoor(points: [exitPoint, entrancePoint],
      buildingId: targetBuid,
      instruction: 'Outdoor routing unavailable — following approximate path',
      isIncomplete: true,);
  }

  /// Builds a combined route: OSRM from user to a campus entrance endpoint,
  /// then custom route through the campus to the destination.
  ///
  /// Key insight: OSRM routes to a route ENDPOINT (where campus roads meet
  /// public roads), NOT to a vertex near the destination. This prevents OSRM
  /// from following parallel public roads inside the campus.
  ///
  /// When [gateEntry] is provided (a resolved [CampusGate] from the gate
  /// config), the OSRM leg is routed to that gate and the campus road graph
  /// is entered at the gate's nearest vertex — i.e.
  /// `outside → preferred gate → campus roads → destination`. Without a
  /// gate the function keeps the older endpoint-based behavior.
  Future<List<LatLng>?> _buildOsrmToCustomRoute(
    LatLng userLocation,
    LatLng destination,
    CustomRouteRepository customRepo, {
    CampusGate? gateEntry,
  }) async {
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
      '${destVertex.$2.toStringAsFixed(0)}m from destination, '
      'gate=${gateEntry?.id ?? "none"}',
    );

    // When a configured gate is provided, enter the campus road graph at the
    // graph vertex nearest the gate, and route the public-road (OSRM) leg to
    // that exact gate.
    int? bestEntryIdx;
    if (gateEntry != null) {
      final gateVertex = customRepo.graph.nearestVertex(
        LatLng(gateEntry.latitude, gateEntry.longitude),
        maxDistance: 750.0,
      );
      if (gateVertex == null) {
        debugPrint(
          '[CrossBuildingRouter] osrm→custom: gate ${gateEntry.id} is not '
          'near the campus road graph; falling back to endpoint logic',
        );
      } else {
        bestEntryIdx = gateVertex.$1;
        debugPrint(
          '[CrossBuildingRouter] osrm→custom: gate ${gateEntry.id} snapped '
          'to graph vertex $bestEntryIdx '
          '(${gateVertex.$2.toStringAsFixed(0)}m from gate)',
        );
      }
    }

    // Step 1: Get all route endpoints (where campus roads meet public roads)
    final endpoints = customRepo.graph.getRouteEndpoints();
    debugPrint(
      '[CrossBuildingRouter] osrm→custom: ${endpoints.length} route endpoints',
    );

    if (endpoints.isEmpty && bestEntryIdx == null) {
      debugPrint('[CrossBuildingRouter] osrm→custom: no route endpoints');
      return null;
    }

    // Step 2: OSRM target point = the gate location when a gate entry is
    // resolved, otherwise the chosen route endpoint (prefer one connected to
    // the dest vertex and close to the user).
    LatLng entryPos;
    if (bestEntryIdx != null) {
      entryPos = LatLng(gateEntry!.latitude, gateEntry.longitude);
    } else {
      // Fallback: among endpoints, pick a candidate entry connected to the
      // destination. If none can reach the destination, use the endpoint
      // nearest the destination (straight-line walk from it).
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

      // Use the endpoint nearest the destination (or, when reachable through
      // the graph, the closest connected one). For simplicity and to preserve
      // prior behavior we keep the nearest-to-destination selection here.
      bestEntryIdx = nearestToDestIdx;
      if (bestEntryIdx == null) {
        debugPrint('[CrossBuildingRouter] osrm→custom: no endpoints at all');
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
        '[CrossBuildingRouter] osrm→custom: best entry=$bestEntryIdx '
        '(${entryUserDist.toStringAsFixed(0)}m from user)',
      );
    }

    // Step 3: OSRM from user to the chosen campus entrance (gate or endpoint)
    final osrmResult = await navigationRepository.getOutdoorWalkingRouteWithMetadata(
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
      '[CrossBuildingRouter] osrm→custom: OSRM to entry '
      '(${gateEntry?.id ?? "endpoint"}) = '
      '${osrmPath.length} points, ${osrmResult.distanceMeters.toStringAsFixed(0)}m',
    );

    // Step 4: Route through custom graph from entry vertex to destination vertex
    final customPath = customRepo.graph.shortestPath(bestEntryIdx, destVertexIdx);

    if (customPath.isEmpty) {
      debugPrint(
        '[CrossBuildingRouter] osrm→custom: no graph path from '
        '$bestEntryIdx to $destVertexIdx; adding straight-line walk '
        'from entry to destination',
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
        maxSnapDistance: 250.0,
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
  // Bearing utilities
  // ──────────────────────────────────────────────────────────────

  /// Scores an entrance candidate for selection.
  ///
  /// [walkingDistanceMeters] is the OSRM walking-route distance to the
  /// entrance (the dominant, primary factor). [angleDiffDegrees] is the
  /// angular mismatch (0..180°) between the approach heading and the
  /// direction the entrance faces.
  ///
  /// The angle term is kept as a small tie-breaker only: its maximum
  /// contribution (at 180°) is 18m-equivalent, so it can never flip a real
  /// walking-distance gap of ~50m+. Lower is better.
  @visibleForTesting
  static double entranceScore({
    required double walkingDistanceMeters,
    required double angleDiffDegrees,
  }) {
    const double kDistanceWeight = 1.0; // dominant
    const double kAngleWeightPerDegree = 0.1; // ≤18m-equivalent max
    return walkingDistanceMeters * kDistanceWeight +
        angleDiffDegrees * kAngleWeightPerDegree;
  }

  static double _entranceScore(double walkingDistanceMeters, double angleDiffDegrees) =>
      entranceScore(
        walkingDistanceMeters: walkingDistanceMeters,
        angleDiffDegrees: angleDiffDegrees,
      );

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

  // ──────────────────────────────────────────────────────────────
  // Test accessors (used by remediation_crossbuilding_test.dart)
  // ──────────────────────────────────────────────────────────────

  @visibleForTesting
  Future<PoiModel?> selectExitPoiForTest(
    SpaceModel userBuilding, {
    required LatLng userLocation,
  }) =>
      _selectExitPoi(userBuilding, userLocation);
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

/// Thrown by [CrossBuildingRouter.composeRoute] when an honest outdoor route
/// cannot be produced (e.g. the user is inside a building with no resolvable
/// outdoor entrance, or origin and destination entrances coincide).
///
/// Carries a user-facing [message] so the caller can surface a clear failure
/// instead of fabricating interior geometry.
class OutdoorRouteException implements Exception {
  final String message;

  const OutdoorRouteException(this.message);

  @override
  String toString() => 'OutdoorRouteException: $message';
}
