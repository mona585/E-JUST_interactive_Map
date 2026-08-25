/// Central API configuration for the Anyplace backend.
class ApiConfig {
  ApiConfig._();

  /// Authoritative Anyplace server base URL.
  static const String _defaultBaseUrl = 'https://ap.cs.ucy.ac.cy:44';

  /// Server URL, overridable via `--dart-define=SERVER_URL=...`.
  static const String _serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: _defaultBaseUrl,
  );

  static String get serverUrl => _serverUrl;

  /// Alias used by data-layer code.
  static String get baseUrl => _serverUrl;

  /// Endpoint to retrieve all public spaces (buildings, vessels).
  static const String endpointSpacesPublic = '/api/mapping/space/public';

  /// Endpoint to retrieve details for a specific space.
  static const String endpointSpaceGet = '/api/mapping/space/get';

  /// Endpoint to retrieve all floors for a specific building/space.
  static const String endpointFloorAll = '/api/mapping/floor/all';

  /// Endpoint to retrieve radiomap metadata for a space and floor.
  static const String endpointRadiomapSpace = '/api/radiomap/space';

  /// Endpoint to download a frozen radiomap file.
  static const String endpointRadiomapFrozen = '/api/radiomaps_frozen';

  /// Endpoint to download the Base64 floorplan image.
  static const String endpointFloorplans64 = '/api/floorplans64';

  /// Endpoint to retrieve all POIs for a specific floor.
  static const String endpointPoisFloorAll = '/api/mapping/pois/floor/all';

  /// Endpoint to retrieve a route between two POIs.
  static const String endpointNavigationRoute = '/api/navigation/route';

  /// Endpoint to retrieve a route from coordinates on a floor to a POI.
  static const String endpointNavigationRouteCoordinates =
      '/api/navigation/route/coordinates';

  /// Default RadioMap filename used by Anyplace.
  static const String defaultRadiomapMeanFilename = 'indoor-radiomap-mean.txt';

  /// Timeout duration for HTTP requests.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Overall budget for bulk floorplan image downloads.
  ///
  /// Measured transfers of campus floorplans from the public Anyplace
  /// backend are ~8-11 MB of Base64 trickled at roughly 70-105 KB/s
  /// (~2 minutes wired). On mobile links measured as low as ~24 KB/s the
  /// same payload legitimately needs ~7.5 minutes, so the budget must
  /// cover the slow-link case; the on-disk cache makes each floor a
  /// one-time cost. A dead connection never waits this long — it is cut
  /// off after [floorplanStallTimeout] of complete silence.
  static const Duration floorplanImageTimeout = Duration(minutes: 15);

  /// Stall watchdog for floorplan downloads: the request fails if NO bytes
  /// arrive for this long. Unlike the overall budget this measures
  /// inter-chunk gaps, so a slow-but-alive trickle never trips it while a
  /// dead/stalled connection fails fast instead of hanging.
  static const Duration floorplanStallTimeout = Duration(seconds: 60);
}
