/// Central API configuration for the Anyplace backend.
///
/// The server URL can be overridden at build time:
///   flutter run --dart-define=SERVER_URL=https://hostname:port
/// The default is the public UCY Anyplace deployment (the `:44` port is
/// required — the default HTTPS port of that server does not serve the API).
class ApiConfig {
  ApiConfig._();

  static const String _defaultServerUrl = 'https://ap.cs.ucy.ac.cy:44';

  static const String _serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: _defaultServerUrl,
  );

  static String get serverUrl => _serverUrl;

  /// Timeout for a single request, in milliseconds.
  static const Duration requestTimeout = Duration(seconds: 20);

  // ---- Endpoints (public, no auth) ----
  static String get campusGet => '$serverUrl/api/mapping/campus/get';
  static String get spacePublic => '$serverUrl/api/mapping/space/public';
  static String get spaceGet => '$serverUrl/api/mapping/space/get';
  static String get floorAll => '$serverUrl/api/mapping/floor/all';
  static String get poisSpaceAll => '$serverUrl/api/mapping/pois/space/all';
  static String get poisSearch => '$serverUrl/api/mapping/pois/search';
  static String get navigationRoute => '$serverUrl/api/navigation/route';
  static String get navigationRouteCoordinates =>
      '$serverUrl/api/navigation/route/coordinates';
  static String get positionEstimate => '$serverUrl/api/position/estimate';
  static String get positionPredictFloor =>
      '$serverUrl/api/position/predictFloorAlgo1';

  /// Endpoint that returns a zip archive of floorplan tiles for a building/floor.
  static String floorTilesZip(String buid, String floorNumber) =>
      '$serverUrl/api/floortiles/zip/$buid/$floorNumber';

  /// Base URL under which individual floorplan tile PNGs are served.
  static String floorTilesBase(String buid, String floorNumber) =>
      '$serverUrl/api/floortiles/$buid/$floorNumber/';

  // ---- Map (floorplan image + RadioMap) endpoints ----
  /// POST /api/radiomap/space — radiomap metadata for a building+floor.
  static String get radiomapSpace => '$serverUrl/api/radiomap/space';

  /// POST /api/radiomaps_frozen — frozen radiomap download root.
  static String get radiomapFrozen => '$serverUrl/api/radiomaps_frozen';

  /// POST /api/floorplans64 — Base64 floorplan image download root.
  static String get floorplans64 => '$serverUrl/api/floorplans64';

  /// Preferred radiomap filename served by the Anyplace backend.
  static const String defaultRadiomapMeanFilename = 'indoor-radiomap-mean.txt';
}
