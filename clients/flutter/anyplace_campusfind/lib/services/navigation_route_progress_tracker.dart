import '../config/navigation_config.dart';
import '../models/navigation_state.dart';
import '../models/route_progress.dart';
import '../models/user_location.dart';
import 'navigation_route_scope.dart';
import 'navigation_state_machine.dart';

/// Custom-route progress tracking extracted from [NavigationPilot].
///
/// Owns the along-route progress state produced by the custom KMZ graph for
/// outdoor legs; the deviation handler consumes it as the source of truth
/// when the user is on a custom route.
class NavigationRouteProgressTracker {
  NavigationRouteProgressTracker({
    required NavigationRouteScope scope,
    required NavigationStateMachine machine,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine;

  final NavigationRouteScope _scope;
  final NavigationStateMachine _machine;

  RouteProgress? _customRouteProgress;

  RouteProgress? get progress => _customRouteProgress;
  bool get isOnCustomRoute => _customRouteProgress?.isOnRoute ?? false;

  /// Updates progress along the nearest custom route based on current GPS.
  void update(UserLocation location) {
    if (_machine.state != NavigationState.activeOutdoor) {
      _customRouteProgress = null;
      return;
    }

    final customRepo = _scope.customRouteRepository;
    if (!customRepo.isLoaded) {
      _customRouteProgress = null;
      return;
    }

    _customRouteProgress = customRepo.getRouteProgress(
      location.latLng,
      maxSnapDistance: NavigationConfig.customRouteSnapThreshold,
      offRouteThreshold: NavigationConfig.customRouteOnThreshold,
    );
  }

  void clear() {
    _customRouteProgress = null;
  }
}
