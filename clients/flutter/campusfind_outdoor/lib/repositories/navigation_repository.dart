import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../datasources/anyplace_api_client.dart';

/// Re-exposes the API error contract so consumers operating on repositories
/// (view models, services) never need a direct datasource import.
export '../datasources/anyplace_api_client.dart' show ApiException;

/// Repository interface for Anyplace navigation route acquisition.
///
/// OUTDOOR-ONLY (CP-8): the indoor Anyplace navigation API (POI→POI and
/// coordinates→POI, both backed by the server's building POI graph) has been
/// removed. The only route data this repository exposes is the OSRM outdoor
/// walking leg; campus road-graph/KMZ routing is exposed separately through
/// [CustomRouteRepository].
abstract class NavigationRepository {
  /// OSRM outdoor walking path without metadata.
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  });

  /// OSRM outdoor walking path with distance + final-bearing metadata
  /// (used by entrance scoring).
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  });
}

/// Anyplace-backed navigation repository with no local cache layer.
class AnyplaceNavigationRepository implements NavigationRepository {
  AnyplaceNavigationRepository();

  @override
  Future<List<LatLng>> getOutdoorWalkingRoute({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) {
    return AnyplaceApiClient.fetchOutdoorWalkingRoute(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );
  }

  @override
  Future<OsrmRouteResult?> getOutdoorWalkingRouteWithMetadata({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
  }) {
    return AnyplaceApiClient.fetchOutdoorWalkingRouteWithMetadata(
      fromLat: fromLat,
      fromLon: fromLon,
      toLat: toLat,
      toLon: toLon,
    );
  }
}