import '../datasources/anyplace_api_client.dart';
import '../models/navigation_route_model.dart';

/// Repository interface for Anyplace navigation route acquisition.
abstract class NavigationRepository {
  Future<NavigationRouteModel> getRouteBetweenPois({
    required String fromPuid,
    required String toPuid,
  });

  Future<NavigationRouteModel> getRouteFromCoordinates({
    required double latitude,
    required double longitude,
    required String floorNumber,
    required String destinationPuid,
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
    required String floorNumber,
    required String destinationPuid,
  }) {
    return _apiClient.fetchNavigationRouteFromCoordinates(
      latitude: latitude,
      longitude: longitude,
      floorNumber: floorNumber,
      destinationPuid: destinationPuid,
    );
  }
}
