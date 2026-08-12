/// Central API configuration for the Anyplace backend.
///
/// The server URL can be overridden at build time:
///   flutter run --dart-define=SERVER_URL=https://anyplace.cs.ucy.ac.cy
/// The default is the original Anyplace public server URL.
class ApiConfig {
  ApiConfig._();

  static const String _serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'https://anyplace.cs.ucy.ac.cy',
  );

  static String get serverUrl => _serverUrl;

  /// Timeout for a single request, in milliseconds.
  static const Duration requestTimeout = Duration(seconds: 20);

  // ---- Endpoints (public, no auth) ----
  static String get campusGet => '$_serverUrl/api/mapping/campus/get';
  static String get spacePublic => '$_serverUrl/api/mapping/space/public';
  static String get floorAll => '$_serverUrl/api/mapping/floor/all';
  static String get poisSpaceAll => '$_serverUrl/api/mapping/pois/space/all';
  static String get poisSearch => '$_serverUrl/api/mapping/pois/search';
  static String get navigationRoute => '$_serverUrl/api/navigation/route';
  static String get navigationRouteCoordinates =>
      '$_serverUrl/api/navigation/route/coordinates';
  static String get positionEstimate => '$_serverUrl/api/position/estimate';
  static String get positionPredictFloor =>
      '$_serverUrl/api/position/predictFloorAlgo1';

  /// Endpoint that returns a zip archive of floorplan tiles for a building/floor.
  static String floorTilesZip(String buid, String floorNumber) =>
      '$_serverUrl/api/floortiles/zip/$buid/$floorNumber';

  /// Base URL under which individual floorplan tile PNGs are served.
  static String floorTilesBase(String buid, String floorNumber) =>
      '$_serverUrl/api/floortiles/$buid/$floorNumber/';
}
