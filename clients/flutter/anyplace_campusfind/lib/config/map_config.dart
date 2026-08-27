import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Map-related configuration constants.
class MapConfig {
  MapConfig._();

  static const MapType mapType = MapType.hybrid;

  static const double defaultZoom = 16.0;
  static const double focusedZoom = 18.0;
  static const double indoorFloorplanZoom = 19.0;
  static const double minZoom = 3.0;
  static const double maxZoom = 19.0;

  static const String userAgentPackageName = 'eg.edu.ejust.anyplace.navigator';
}
