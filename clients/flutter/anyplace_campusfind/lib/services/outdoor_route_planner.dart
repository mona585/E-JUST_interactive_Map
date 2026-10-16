import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/campus_gate.dart';
import '../repositories/custom_route_repository.dart';
import '../repositories/navigation_repository.dart';
import 'routing_service.dart';

/// Resolves the best outdoor walking path between two points.
///
/// Strategy cascade (identical semantics to the ladder previously inlined in
/// the space view model in three places):
/// 1. Pure custom road-graph routing (both endpoints graph-near).
/// 2. Edge-based hybrid routing (snap threshold 250m).
/// 3. OSRM to a campus entry vertex + custom road graph to the destination
///    (optionally via a configured campus [CampusGate]). When a gate is
///    supplied, the OSRM leg ends AT that gate (preferred entry policy).
/// 4. Plain OSRM, with a custom-tail splice (connection threshold 150m) when
///    the road graph is loaded.
///
/// The cascade always resolves to a path: the final OSRM step is the
/// guaranteed fallback (callers still validate path length).
class OutdoorRoutePlanner {
  OutdoorRoutePlanner({
    required this.routingService,
    required this.customRouteRepository,
    required this.navigationRepository,
  });

  final RoutingService routingService;
  final CustomRouteRepository customRouteRepository;
  final NavigationRepository navigationRepository;

  /// Resolves an outdoor path from [from] to [to].
  ///
  /// [gateEntry] is the preferred campus gate to route the OSRM leg toward
  /// (the road graph is then entered at the gate's nearest vertex). Pass
  /// `null` when the destination IS a gate (never force a preferred gate as an
  /// intermediate point for a gate destination).
  Future<List<LatLng>> resolveOutdoorPath({
    required LatLng from,
    required LatLng to,
    CampusGate? gateEntry,
  }) async {
    List<LatLng>? outdoorPath;

    // Strategy 1: pure custom road-graph routing (both endpoints graph-near).
    if (customRouteRepository.isLoaded) {
      final customPath = customRouteRepository.findRoute(from, to);
      if (customPath.length >= 2) {
        outdoorPath = customPath;
        debugPrint(
          '[OutdoorRoutePlanner] using custom KMZ route (${outdoorPath.length} points)',
        );
      } else {
        // Strategy 2: edge-based hybrid routing.
        final hybridPath = customRouteRepository.findHybridRoute(
          from,
          to,
          snapThreshold: 250.0,
        );
        if (hybridPath != null && hybridPath.length >= 2) {
          outdoorPath = hybridPath;
          debugPrint(
            '[OutdoorRoutePlanner] using hybrid custom route (${outdoorPath.length} points)',
          );
        }
      }
    }

    // Strategy 3: OSRM to a campus entry + custom graph to the destination.
    if (outdoorPath == null && customRouteRepository.isLoaded) {
      final osrmToCustomPath = await routingService.buildOsrmToCustomRoute(
        from,
        to,
        gateEntry: gateEntry,
      );
      if (osrmToCustomPath != null && osrmToCustomPath.length >= 2) {
        outdoorPath = osrmToCustomPath;
        debugPrint(
          '[OutdoorRoutePlanner] using OSRM->Custom route (${outdoorPath.length} points)',
        );
      }
    }

    // Strategy 4: OSRM fallback (with custom-tail splice when routes loaded).
    if (outdoorPath == null) {
      final osrmPath = await navigationRepository.getOutdoorWalkingRoute(
        fromLat: from.latitude,
        fromLon: from.longitude,
        toLat: to.latitude,
        toLon: to.longitude,
      );
      if (osrmPath.length >= 2 && customRouteRepository.isLoaded) {
        final splicedPath = customRouteRepository.spliceCustomTail(
          osrmPath,
          to,
          connectionThreshold: 150.0,
        );
        if (splicedPath != null) {
          outdoorPath = splicedPath;
          debugPrint(
            '[OutdoorRoutePlanner] using OSRM+Custom splice (${outdoorPath.length} points)',
          );
        } else {
          outdoorPath = osrmPath;
        }
      } else {
        outdoorPath = osrmPath;
      }
    }

    return outdoorPath;
  }
}