/// Map tile and style configuration constants.
class MapConfig {
  MapConfig._();

  /// CARTO Voyager Tile URL template with English and Arabic labels.
  ///
  /// This tile provider renders global place and road labels in English/Latin,
  /// displays Arabic script in Arabic-speaking locales, and eliminates Greek,
  /// Cyrillic, and other regional scripts.
  static const String cartoVoyagerUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';

  /// Subdomains used by the CARTO basemap CDN.
  static const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];

  /// App package identifier used in tile requests.
  static const String userAgentPackageName = 'eg.edu.ejust.anyplace_campusfind';

  /// Maximum native zoom level for base raster tiles.
  static const double maxNativeTileZoom = 19.0;

  /// Maximum zoom level supported across FlutterMap for deep indoor room inspection.
  static const double maxZoom = 26.0;

  /// Minimum zoom level.
  static const double minZoom = 3.0;

  /// Default zoom level for initial map load.
  static const double defaultZoom = 14.0;

  /// Zoom level when focusing on a specific building or GPS location.
  static const double focusedZoom = 17.0;

  /// Zoom level when focusing on an indoor floorplan.
  static const double indoorFloorplanZoom = 19.5;
}
