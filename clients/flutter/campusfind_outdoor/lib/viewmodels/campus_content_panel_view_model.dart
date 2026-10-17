import 'package:flutter/foundation.dart';

import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../providers/panel_provider.dart';
import '../viewmodels/navigation_view_model.dart';
import '../viewmodels/space_view_model.dart';

/// Derived action state for the building-route button.
enum BuildingRouteAction { navigating, clearRoute, routeHere, routing }

/// ViewModel for [CampusContentPanel].
///
/// Owns the derived orchestration decisions that previously lived in the View
/// (multi-step navigation start, panel-context transitions, back affordances,
/// derived building-route action state). It depends only on other ViewModels and
/// plain callbacks — never on widgets, BuildContext, controllers, or camera APIs.
/// Camera fitting stays behind an explicit UI callback supplied by the View.
class CampusContentPanelViewModel extends ChangeNotifier {
  CampusContentPanelViewModel({
    required this.spaceViewModel,
    required this.navigationViewModel,
    this.onPanelContextChanged,
    this.onNavPanelOpenChanged,
    this.onActiveServiceCleared,
    this.onFitRouteBounds,
    this.isServiceActive,
  });

  final SpaceViewModel spaceViewModel;
  final NavigationViewModel navigationViewModel;

  /// Called when the panel context should change (campus/building).
  final void Function(PanelContext context)? onPanelContextChanged;

  /// Called when the nav panel open state should change.
  final void Function(bool open)? onNavPanelOpenChanged;

  /// Called when the active service should be cleared.
  final void Function()? onActiveServiceCleared;

  /// Explicit UI callback for camera fitting (camera stays in the View).
  final void Function(SpaceViewModel space)? onFitRouteBounds;

  /// Returns true when a service is active on the Services tab.
  final bool Function()? isServiceActive;

  String? _lastAutoContextBuid;

  /// Keeps the panel context in step with selection changes.
  ///
  /// Cleared selection -> Campus; a NEWLY selected building -> Building.
  /// Back-driven campus context is never overridden for the SAME buid.
  /// [currentContext] is the panel context the View currently holds, so the
  /// VM can apply the original guard without reading Riverpod providers itself.
  void handleSpaceChanged(PanelContext currentContext) {
    final selected = spaceViewModel.selectedSpace;
    if (selected == null) {
      _lastAutoContextBuid = null;
      if (currentContext != PanelContext.campus) {
        onPanelContextChanged?.call(PanelContext.campus);
      }
      notifyListeners();
      return;
    }

    final serviceActive = isServiceActive?.call() ?? false;
    if (!serviceActive &&
        selected.buid != _lastAutoContextBuid &&
        currentContext == PanelContext.campus) {
      _lastAutoContextBuid = selected.buid;
      onPanelContextChanged?.call(PanelContext.building);
    }
    notifyListeners();
  }

  /// Multi-step navigation start flow (moved from the View).
  Future<void> startDirectionsForPoi(PoiModel poi) async {
    if (navigationViewModel.isActive) {
      await navigationViewModel.retargetDestination(poi);
      return;
    }
    try {
      await spaceViewModel.navigateToPoi(poi);
    } catch (e) {
      // Preserve prior behavior: log and continue.
      // ignore: avoid_print
      print('[CampusPanel] destination chain failed: $e');
    }
    if (!spaceViewModel.hasActiveNavigationRoute) {
      await spaceViewModel.requestRouteToSelectedPoi();
    }
    navigationViewModel.startRoutePreview(
      destinationPuid: poi.puid,
      destinationSpace: spaceViewModel.selectedSpace!,
    );
    navigationViewModel.startActiveNavigation();
    navigationViewModel.resumeFollowMode();
    onNavPanelOpenChanged?.call(false);
  }

  /// Back affordance for the destination view.
  void handleBackDestination() {
    if (navigationViewModel.isPreview) {
      navigationViewModel.terminateNavigation();
    }
    spaceViewModel.clearSelectedPoi();
  }

  /// Back affordance for the gate view.
  void handleBackGate() {
    spaceViewModel.clearSelectedGate();
  }

  /// Back affordance for the floor view.
  void handleBackFloor() {
    spaceViewModel.clearFloorSelection();
  }

  /// Back affordance for the service view.
  void handleBackService() {
    onActiveServiceCleared?.call();
  }

  /// Back affordance for the building view.
  void handleBackBuilding() {
    onPanelContextChanged?.call(PanelContext.campus);
  }

  /// Explicit tap on an already-selected place re-opens its Building context.
  void openBuildingContextFor(SpaceModel space) {
    _lastAutoContextBuid = space.buid;
    onPanelContextChanged?.call(PanelContext.building);
    notifyListeners();
  }

  static BuildingRouteAction resolveBuildingRouteAction({
    required bool isNavActive,
    required bool hasRoute,
    required bool isLoading,
  }) {
    if (isNavActive) return BuildingRouteAction.navigating;
    if (hasRoute) return BuildingRouteAction.clearRoute;
    if (isLoading) return BuildingRouteAction.routing;
    return BuildingRouteAction.routeHere;
  }

  /// Camera fit remains behind an explicit UI callback.
  void fitRouteBounds(SpaceViewModel space) {
    onFitRouteBounds?.call(space);
  }

  // dispose inherited from ChangeNotifier; no extra resources owned.
}
