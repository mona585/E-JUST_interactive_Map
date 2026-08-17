/// Map-related configuration constants.
class MapConfig {
  MapConfig._();

  static const double defaultZoom = 16.0;
  static const double focusedZoom = 18.0;
  static const double indoorFloorplanZoom = 19.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 19.0;
  static const double maxNativeTileZoom = 19.0;

  static const String cartoVoyagerUrlTemplate =
      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png';
  static const List<String> cartoSubdomains = ['a', 'b', 'c', 'd'];
  static const String userAgentPackageName = 'eg.edu.ejust.anyplace.navigator';
}
