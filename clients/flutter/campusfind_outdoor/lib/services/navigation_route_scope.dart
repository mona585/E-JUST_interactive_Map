import 'package:flutter/foundation.dart';

import '../repositories/custom_route_repository.dart';
import '../models/floor_model.dart';
import '../models/floorplan_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';

/// Narrow read/write surface the navigation machine needs from space state.
///
/// [SpaceViewModel] implements this directly; tests supply fakes. Exists so the
/// state machine can be exercised without network-backed providers.
abstract class NavigationRouteScope implements Listenable {
  NavigationRouteModel? get activeNavigationRoute;
  FloorModel? get selectedFloor;
  SpaceModel? get selectedSpace;
  List<FloorModel> get floors;
  List<PoiModel> get pois;
  bool get hasPois;
  FloorplanModel? get activeFloorplan;
  CustomRouteRepository get customRouteRepository;

  void selectSpace(SpaceModel space);
  void selectFloor(FloorModel floor);
  void clearSelection();

  /// Navigation-driven selection variants (MASTER PLAN PHASE 3, INV-5):
  /// used exclusively by the controller so residency preloads never reset
  /// navigation fields, whatever browsing APIs do elsewhere.
  void selectFloorForNavigation(FloorModel floor);
  void selectSpaceForNavigation(SpaceModel space);

  /// Route-safe building-exit context release (INV-9 route-safety half):
  /// clears indoor browsing residency while preserving the route store.
  void releaseIndoorContextForNavigation();

  /// Retarget support (MASTER PLAN PHASE 4): selects the destination
  /// context exclusively through navigation-safe variants, then runs the
  /// INITIAL CASCADE under its existing request-id machinery. Returns true
  /// when a renderable route for [target] was committed to the store.
  Future<bool> requestRouteForRetarget(PoiModel target);

  /// The ONLY way a live session writes the route store (MASTER PLAN PHASE 2,
  /// INV-1/2/6). Implementations must set the store atomically for observers:
  /// assign + status ready + a single [notifyListeners], touching nothing
  /// else (no browsing state, no destination bookkeeping).
  void adoptNavigatedRoute(NavigationRouteModel route);

  /// Idempotent teardown of the route store (used by canonical termination).
  void clearNavigationRoute();
}