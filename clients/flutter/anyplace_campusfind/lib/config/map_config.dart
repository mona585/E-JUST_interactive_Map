import 'package:google_maps_flutter/google_maps_flutter.dart';

/// E-JUST campus boundary (ADDITIONAL REQUIREMENT): geographic bounds used
/// ONLY to fit the initial/campus-overview camera viewport. Never drawn.
/// Corners (DMS → decimal):
///   30°51'45.2"N 29°33'41.8"E   30°51'26.4"N 29°33'40.9"E
///   30°51'37.2"N 29°34'03.8"E   30°51'19.7"N 29°33'59.1"E
final LatLngBounds ejustCampusBounds = LatLngBounds(
  southwest: LatLng(30.8554722, 29.5613611),
  northeast: LatLng(30.8625556, 29.5677222),
);

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
