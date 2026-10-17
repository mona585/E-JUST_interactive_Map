import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/map_config.dart';
import '../config/navigation_config.dart';
import '../viewmodels/location_view_model.dart';
import '../viewmodels/navigation_view_model.dart';
import '../viewmodels/space_view_model.dart';

/// ViewModel for the map screen (MVVM).
///
/// Owns the deterministic presentation decisions that the legacy widget
/// computed inline inside its `build` method:
///  * campus-overview detection (no selection, no active session),
///  * the initial camera target when the map is first created,
///  * the follow-mode zoom for a navigation sub-state,
///  * the held-position logic during a floor transition,
///  * the connector-POI hiding predicate.
///
/// The widget retains everything tightly coupled to the `GoogleMapController`
/// lifecycle (camera animations, marker-icon bitmaps, floorplan overlay
/// caching); those are pure rendering concerns. State comes exclusively from
/// the injected providers — this ViewModel mutates nothing.
class MapViewModel {
  MapViewModel({
    required this.spaceProvider,
    required this.locationProvider,
    required this.navigationController,
  });

  final SpaceViewModel spaceProvider;
  final LocationViewModel locationProvider;
  final NavigationViewModel navigationController;

  /// Healthy bounds used ONLY to fit the initial / campus-overview camera
  /// viewport (never drawn). Single shared definition (config layer).
  ///
  /// These bounds are the user-supplied campus BOUNDARY rectangle
  /// ([ejustCampusBounds]) — independent of the (still incomplete) building
  /// registry.
  LatLngBounds get campusBounds => ejustCampusBounds;

  /// Campus-overview camera target.
  ///
  /// This is the centre of the user-supplied campus boundary rectangle
  /// ([ejustCampusBoundaryCenter], ≈ `30.8591015, 29.564043`) — an independent
  /// geographic reference. It is deliberately NOT the centroid of the live
  /// buildings ([SpaceViewModel.defaultCenter]): the campus registry is still
  /// incomplete, so that centroid is not a reliable campus centre and using it
  /// displaced the initial framing toward the north-east.
  ///
  /// NOTE: this is a bounding-rectangle centre, not a traced polygon centroid.
  LatLng get campusCenter => ejustCampusBoundaryCenter;

  /// True when the app is in the campus overview (nothing selected and no
  /// live navigation session). Used to (a) skip the one-shot GPS camera
  /// animation, (b) fit the healthy bounds once per entry.
  ///
  /// Mirrors the legacy inline condition EXACTLY (gate selection does not
  /// leave the overview — see map_screen's historical build logic).
  bool get isCampusOverview {
    final s = spaceProvider;
    return s.selectedSpace == null &&
        s.selectedFloor == null &&
        s.selectedPoi == null &&
        !navigationController.isActive;
  }

  /// Initial camera target for the first map frame: campus bounds center in
  /// overview, otherwise the selected building / current fix / default.
  LatLng get initialCameraTarget {
    final s = spaceProvider;
    if (isCampusOverview) return campusCenter;
    final selected = s.selectedSpace?.latLng;
    if (selected != null) return selected;
    final fix = locationProvider.currentLocation?.latLng;
    if (fix != null) return fix;
    return SpaceViewModel.defaultCenter;
  }

  /// Follow-mode zoom for a given navigation sub-state
  /// (unchanged legacy mapping).
  double followZoomFor(NavigationSubState subState) =>
      subState == NavigationSubState.indoor
      ? NavigationConfig.indoorFollowZoom
      : NavigationConfig.outdoorFollowZoom;

  /// True when this POI record is a hidden connector (elevator, stairs, or
  /// `pois_type == "None"`). Connectors stay in the data/navigation layers
  /// but are never drawn as markers.
  static bool isConnectorPoi(String poisType, String name) {
    final t = poisType.toLowerCase();
    return t == 'none' ||
        t.contains('elevator') ||
        t.contains('stairs') ||
        t.contains('staircase');
  }
}
