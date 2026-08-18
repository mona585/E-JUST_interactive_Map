import 'dart:math' show cos, sin, atan2, pi;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../datasources/anyplace_api_client.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/route_segment.dart';
import '../models/space_model.dart';
import '../../utils/poi_classification.dart';

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

  CrossBuildingRouter({
    required this.isPositionInBuilding,
    required this.loadPois,
    required this.loadFloorNumbers,
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

    // Cap at 6 segments
    if (validSegments.length > 6) {
      validSegments.removeRange(6, validSegments.length);
    }

    // Determine status
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
      // Straight line from user position to building centroid
      return RouteSegment.fallback(
        type: RouteSegmentType.exitTransition,
        points: [userLocation, exitPoint],
        buildingId: userBuilding.buid,
        instruction: 'Exit ${userBuilding.name}',
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
  Future<RouteSegment?> _generateOutdoorSegment({
    required LatLng exitPoint,
    required LatLng entrancePoint,
    required String targetBuid,
  }) async {
    final result = await AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
      fromLat: exitPoint.latitude,
      fromLon: exitPoint.longitude,
      toLat: entrancePoint.latitude,
      toLon: entrancePoint.longitude,
    );

    if (result == null || result.points.length < 2) {
      // Fallback: straight line
      return RouteSegment.outdoor(
        points: [exitPoint, entrancePoint],
        buildingId: targetBuid,
        instruction: 'Walk to destination building',
        isIncomplete: true,
      );
    }

    return RouteSegment.outdoor(
      points: result.points,
      buildingId: targetBuid,
      instruction: 'Walk to destination building',
      distance: result.distanceMeters,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Step 6: Entrance segment generation
  // ──────────────────────────────────────────────────────────────

  /// Generates an entrance segment from the building entrance to the destination.
  Future<RouteSegment?> _generateEntranceSegment({
    required LatLng entrancePoint,
    PoiModel? entrancePoi,
    required SpaceModel targetSpace,
    String? targetPuid,
    required bool isFallback,
  }) async {
    if (isFallback) {
      // Straight line from entrance to building centroid
      return RouteSegment.fallback(
        type: RouteSegmentType.entranceTransition,
        points: [entrancePoint, targetSpace.latLng],
        buildingId: targetSpace.buid,
        instruction: 'Enter ${targetSpace.name}',
      );
    }

    // Route from entrance POI to the user's actual target POI
    if (entrancePoi != null && entrancePoi.puid.isNotEmpty && targetPuid != null) {
      try {
        final result = await AnyplaceApiClient().fetchNavigationRouteFromCoordinates(
          latitude: entrancePoint.latitude,
          longitude: entrancePoint.longitude,
          floorNumber: entrancePoi.floorNumber,
          destinationPuid: targetPuid,
        );

        if (result.hasRenderablePath) {
          return RouteSegment.entrance(
            points: result.polylinePoints,
            buildingId: targetSpace.buid,
            floorNumber: entrancePoi.floorNumber,
            connectorPoiId: entrancePoi.puid,
            instruction: 'Enter ${targetSpace.name}',
          );
        }
      } catch (e) {
        debugPrint('[CrossBuildingRouter] Entrance API failed: $e');
      }
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
