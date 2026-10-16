import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../datasources/anyplace_api_client.dart';
import '../models/navigation_route_model.dart';

/// Re-exposes the API error contract so consumers operating on repositories
/// (view models, services) never need a direct datasource import.
export '../datasources/anyplace_api_client.dart' show ApiException;

/// Repository interface for Anyplace navigation route acquisition.
///
/// Covers both indoor (POI/graph-based) routing and outdoor walking routes
/// (OSRM public-road leg) so higher levels never reach the API client
/// directly for route data.
abstract class NavigationRepository {
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  });

  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    String? floorNumber,
    required String destinationPuid,
  });

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
  final AnyplaceApiClient _apiClient;

  AnyplaceNavigationRepository({AnyplaceApiClient? apiClient})
    : _apiClient = apiClient ?? AnyplaceApiClient();

  @override
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  }) {
    return _apiClient.fetchNavigationRoute(fromPuid: fromPuid, toPuid: toPuid);
  }

  @override
  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    String? floorNumber,
    required String destinationPuid,
  }) {
    return _apiClient.fetchNavigationRouteFromCoordinates(
      latitude: latitude,
      longitude: longitude,
      floorNumber: floorNumber,
      destinationPuid: destinationPuid,
    );
  }

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