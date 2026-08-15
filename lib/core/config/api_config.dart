/// Configuration for Anyplace Backend API.
class ApiConfig {
  ApiConfig._();

  /// Authoritative Anyplace server base URL.
  /// The live Anyplace 4.3.1 server runs on port 44.
  static const String baseUrl = 'https://ap.cs.ucy.ac.cy:44';

  /// Endpoint to retrieve all public spaces (buildings, vessels).
  /// Method: POST
  /// Body: {}
  static const String endpointSpacesPublic = '/api/mapping/space/public';

  /// Endpoint to retrieve details for a specific space.
  /// Method: POST
  /// Body: `{"buid": "<buid>"}`
  static const String endpointSpaceGet = '/api/mapping/space/get';

  /// Endpoint to retrieve all floors for a specific building/space.
  /// Method: POST
  /// Body: `{"buid": "<buid>"}`
  static const String endpointFloorAll = '/api/mapping/floor/all';

  /// Endpoint to retrieve radiomap metadata for a space and floor.
  /// Method: POST
  /// Body: `{"buid": "<buid>", "floor": "<floor>"}`
  static const String endpointRadiomapSpace = '/api/radiomap/space';

  /// Endpoint to download a frozen radiomap file.
  /// Method: POST
  /// URL pattern: `/api/radiomaps_frozen/{space}/{floor}/{filename}`
  /// Preferred filename: `indoor-radiomap-mean.txt`
  static const String endpointRadiomapFrozen = '/api/radiomaps_frozen';

  /// Endpoint to download the Base64 floorplan image (official Anyplace Viewer endpoint).
  /// Method: POST
  /// URL pattern: `/api/floorplans64/{buid}/{floor}`
  /// Body: `{}`
  static const String endpointFloorplans64 = '/api/floorplans64';

  /// Default RadioMap filename used by Anyplace.
  static const String defaultRadiomapMeanFilename = 'indoor-radiomap-mean.txt';

  /// Timeout duration for HTTP requests.
  static const Duration requestTimeout = Duration(seconds: 20);
}
