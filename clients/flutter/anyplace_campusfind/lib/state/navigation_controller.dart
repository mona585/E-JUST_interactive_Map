import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../config/navigation_config.dart';
import '../data/models/navigation_route_model.dart';
import '../data/models/poi_model.dart';
import '../data/models/space_model.dart';
import '../data/models/user_location.dart';
import '../data/repositories/navigation_repository.dart';
import 'location_provider.dart';
import 'space_provider.dart';

/// Top-level navigation phase.
enum NavigationPhase { idle, preview, active }

/// Sub-state during active navigation.
enum NavigationSubState { outdoor, indoor, transitioning }

/// Manages the indoor navigation lifecycle: route preview, active follow-mode
/// navigation, floor transitions, rerouting, and outdoorÃ¢â€ â€indoor transitions.
///
/// This controller coordinates between [SpaceProvider] (building/floor/route
/// state), [LocationProvider] (user position), and the map camera.
class NavigationController extends ChangeNotifier {
  final SpaceProvider _spaceProvider;
  final LocationProvider _locationProvider;
  final NavigationRepository _navigationRepository;

  NavigationPhase _phase = NavigationPhase.idle;
  NavigationSubState _subState = NavigationSubState.outdoor;

  // -- Active navigation state --
  String? _destinationPuid;
  SpaceModel? _destinationSpace;
  NavigationRouteModel? _activeRoute;
  bool _followMode = true;
  bool _isRerouting = false;
  DateTime? _lastRerouteTime;

  // -- Floor transition tracking --
  String? _currentNavigatingFloor;
  String? _expectedNextFloor;
  bool _isTransitioningFloors = false;
  int _exitConfirmationCounter = 0;
  int _newFloorEstimateCount = 0;
  DateTime? _lastFloorSwitchTime;
  DateTime? _transitionStartTime;

  // -- Position hold during transition --
  UserLocation? _lastIndoorPosition;

  // -- Building entry detection --
  bool _buildingPreloaded = false;

  NavigationController({
    required this._spaceProvider,
    required this._locationProvider,
    NavigationRepository? navigationRepository,
  })  : _navigationRepository =
            navigationRepository ?? AnyplaceNavigationRepository() {
    _locationProvider.addListener(_onLocationChanged);
    _spaceProvider.addListener(_onSpaceProviderChanged);
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Getters Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  NavigationPhase get phase => _phase;
  NavigationSubState get subState => _subState;
  bool get followMode => _followMode;
  bool get isActive => _phase == NavigationPhase.active;
  bool get isPreview => _phase == NavigationPhase.preview;
  NavigationRouteModel? get activeRoute => _activeRoute;
  String? get currentNavigatingFloor => _currentNavigatingFloor;
  bool get isTransitioningFloors => _isTransitioningFloors;
  bool get isRerouting => _isRerouting;
  String? get destinationPuid => _destinationPuid;
  SpaceModel? get destinationSpace => _destinationSpace;

  /// User-friendly positioning status message.
  String get positioningStatus {
    if (_isTransitioningFloors) {
      final nextFloor = _expectedNextFloor;
      if (nextFloor != null) {
        return '${NavigationConfig.transitionBlackoutMessage} $nextFloor...';
      }
      return '${NavigationConfig.transitionBlackoutMessage}...';
    }
    final floor = _currentNavigatingFloor;
    switch (_locationProvider.positionSource) {
      case LocationSource.indoorWifi:
        return floor != null ? 'Indoor \u2022 Floor $floor' : 'Indoor location';
      case LocationSource.gps:
        return 'GPS active';
      case LocationSource.none:
        return 'Updating location\u2026';
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Public API Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  /// Starts route preview mode after the user taps "Route Here".
  ///
  /// The route must already be loaded in [SpaceProvider].
  void startRoutePreview({
    required String destinationPuid,
    required SpaceModel destinationSpace,
    required String destinationFloorNumber,
  }) {
    if (_phase == NavigationPhase.active) return;

    final route = _spaceProvider.activeNavigationRoute;
    if (route == null || !route.hasRenderablePath) return;

    _destinationPuid = destinationPuid;
    _destinationSpace = destinationSpace;
    _activeRoute = route;
    _currentNavigatingFloor = _spaceProvider.selectedFloor?.floorNumber;
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = null;
    _lastIndoorPosition = null;

    _phase = NavigationPhase.preview;
    _subState = NavigationSubState.outdoor;
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;
    notifyListeners();
  }

  /// Transitions from preview to active navigation when user taps "Start Directions".
  void startActiveNavigation() {
    if (_phase != NavigationPhase.preview) return;

    _phase = NavigationPhase.active;
    _followMode = true;
    _lastRerouteTime = null;
    _isTransitioningFloors = false;
    _exitConfirmationCounter = 0;

    _evaluateSubState();
    notifyListeners();
  }

  /// Ends active navigation and returns to idle.
  void endNavigation() {
    _phase = NavigationPhase.idle;
    _subState = NavigationSubState.outdoor;
    _destinationPuid = null;
    _destinationSpace = null;
    _activeRoute = null;
    _currentNavigatingFloor = null;
    _expectedNextFloor = null;
    _isTransitioningFloors = false;
    _followMode = true;
    _exitConfirmationCounter = 0;
    _isRerouting = false;
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = null;
    _transitionStartTime = null;
    _lastIndoorPosition = null;
    notifyListeners();
  }

  /// Temporarily disables follow mode (e.g., user panned the map).
  void exitFollowMode() {
    if (!_followMode) return;
    _followMode = false;
    notifyListeners();
  }

  /// Re-enables follow mode (e.g., user tapped re-center button).
  void resumeFollowMode() {
    if (_followMode) return;
    _followMode = true;
    _exitConfirmationCounter = 0;
    notifyListeners();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Internal: Location Updates Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _onLocationChanged() {
    if (_phase != NavigationPhase.active) return;

    final location = _locationProvider.currentLocation;
    if (location == null) return;

    // Handle position hold during floor transition
    if (_isTransitioningFloors) {
      _checkTransitionTimeout();
      // Use cached position during transition instead of jumping to GPS
      if (_lastIndoorPosition != null) {
        notifyListeners();
        return;
      }
    }

    // Suppress rerouting briefly after floor switch (post-switch cooldown)
    if (_lastFloorSwitchTime != null) {
      final elapsed = DateTime.now().difference(_lastFloorSwitchTime!);
      if (elapsed.inSeconds < NavigationConfig.postFloorSwitchSuppressSeconds) {
        _evaluateSubState();
        notifyListeners();
        return;
      }
      _lastFloorSwitchTime = null;
    }

    _evaluateSubState();
    _checkDeviationAndReroute(location);
    _checkFloorTransition(location);
    _checkBuildingExit(location);
    checkBuildingApproach(location);
    checkEntranceProximity(location);
    notifyListeners();
  }

  void _onSpaceProviderChanged() {
    // Sync route if SpaceProvider's active route changed (e.g., reroute completed)
    final route = _spaceProvider.activeNavigationRoute;
    if (route != null && route != _activeRoute && route.hasRenderablePath) {
      _activeRoute = route;
      if (_phase == NavigationPhase.active) {
        notifyListeners();
      }
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Sub-state Evaluation Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _evaluateSubState() {
    if (_phase != NavigationPhase.active) return;

    final source = _locationProvider.positionSource;
    final floor = _currentNavigatingFloor;

    if (_isTransitioningFloors) {
      _subState = NavigationSubState.transitioning;
    } else if (source == LocationSource.indoorWifi && floor != null) {
      _subState = NavigationSubState.indoor;
    } else {
      _subState = NavigationSubState.outdoor;
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Deviation Detection & Rerouting Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _checkDeviationAndReroute(UserLocation location) {
    if (_activeRoute == null) return;
    if (_isRerouting) return;
    if (_isTransitioningFloors) return;

    // Cooldown check
    if (_lastRerouteTime != null) {
      final elapsed = DateTime.now().difference(_lastRerouteTime!);
      if (elapsed.inSeconds < NavigationConfig.rerouteCooldownSeconds) return;
    }

    final deviation = _computeMinDeviation(location.latLng, _activeRoute!);
    if (deviation > NavigationConfig.deviationThreshold) {
      _triggerReroute();
    }
  }

  /// Perpendicular distance from [point] to the nearest segment of [route]
  /// on the current navigating floor only.
  double _computeMinDeviation(LatLng point, NavigationRouteModel route) {
    final currentFloor = _currentNavigatingFloor;
    final points = currentFloor != null
        ? route.polylinePointsForFloor(currentFloor)
        : route.polylinePoints;
    if (points.length < 2) return double.infinity;

    double minDist = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final dist = _pointToSegmentDistance(point, points[i], points[i + 1]);
      if (dist < minDist) minDist = dist;
    }
    return minDist;
  }

  /// Haversine distance from [p] to the closest point on segment [a]Ã¢â‚¬â€œ[b].
  double _pointToSegmentDistance(LatLng p, LatLng a, LatLng b) {
    
    final abDist = Geolocator.distanceBetween(a.latitude, a.longitude, b.latitude, b.longitude);
    if (abDist < 0.001) return Geolocator.distanceBetween(p.latitude, p.longitude, a.latitude, a.longitude);

    final apDist = Geolocator.distanceBetween(a.latitude, a.longitude, p.latitude, p.longitude);
    final bpDist = Geolocator.distanceBetween(b.latitude, b.longitude, p.latitude, p.longitude);

    // Project p onto line ab, clamp to [0,1]
    final cosAngle =
        (apDist * apDist + abDist * abDist - bpDist * bpDist) /
            (2 * apDist * abDist);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    final ratio = (apDist * clampedCos) / abDist;
    final clampedRatio = ratio.clamp(0.0, 1.0);

    final projected = LatLng(
      a.latitude + clampedRatio * (b.latitude - a.latitude),
      a.longitude + clampedRatio * (b.longitude - a.longitude),
    );

    return Geolocator.distanceBetween(p.latitude, p.longitude, projected.latitude, projected.longitude);
  }

  Future<void> _triggerReroute() async {
    if (_isRerouting) return;
    if (_destinationPuid == null) return;

    final location = _locationProvider.currentLocation;
    if (location == null) return;

    _isRerouting = true;
    _lastRerouteTime = DateTime.now();
    notifyListeners();

    final currentFloor = _currentNavigatingFloor ?? '0';

    for (var attempt = 0; attempt < NavigationConfig.rerouteMaxRetries; attempt++) {
      try {
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: location.latitude,
          longitude: location.longitude,
          floorNumber: currentFloor,
          destinationPuid: _destinationPuid!,
        );
        if (route.hasRenderablePath) {
          _activeRoute = route;
          break;
        }
      } catch (e) {
        debugPrint('[NavigationController] Reroute attempt $attempt failed: $e');
      }
      // Exponential backoff: 1s, 2s, 4s
      await Future.delayed(Duration(seconds: 1 << attempt));
    }

    _isRerouting = false;
    notifyListeners();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Floor Transition Detection Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _checkFloorTransition(UserLocation location) {
    if (_activeRoute == null) return;
    if (_isTransitioningFloors) return;

    final currentFloor = _currentNavigatingFloor;
    if (currentFloor == null) return;

    // Check if we've reached a connector (floor-change point in route)
    final transitionIndices = _activeRoute!.floorTransitionIndices;
    for (final idx in transitionIndices) {
      final connectorPoint = _activeRoute!.points[idx];
      if (connectorPoint.floorNumber != currentFloor) continue;

      final dist = Geolocator.distanceBetween(location.latitude, location.longitude, connectorPoint.latitude, connectorPoint.longitude);
      if (dist < NavigationConfig.connectorProximityThreshold) {
        // User is near a connector Ã¢â‚¬â€ determine next floor
        final nextFloor = _activeRoute!.points[idx + 1].floorNumber;
        if (nextFloor != currentFloor) {
          _expectedNextFloor = nextFloor;
          _preLoadFloorIfNeeded(nextFloor);
          break;
        }
      }
    }

    // Check if positioning has confirmed a floor change
    if (_locationProvider.isIndoorWifiActive) {
      final estimate = _locationProvider.latestIndoorEstimate;
      if (estimate != null &&
          estimate.isValid &&
          estimate.floor != currentFloor) {
        // If we have an expected floor, verify the estimate matches it
        final expected = _expectedNextFloor;
        if (expected != null && estimate.floor != expected) {
          // Estimate is on a different floor than expected Ã¢â‚¬â€ ignore
          _newFloorEstimateCount = 0;
          return;
        }

        _newFloorEstimateCount++;

        // Require consecutive estimates on the new floor before confirming
        if (_newFloorEstimateCount >= NavigationConfig.stabilityMinEstimates) {
          _confirmFloorTransition(estimate.floor);
          _newFloorEstimateCount = 0;
        }
      } else if (estimate != null && estimate.floor == currentFloor) {
        // Estimate is on the current floor Ã¢â‚¬â€ reset counter
        _newFloorEstimateCount = 0;
      }
    }
  }

  void _confirmFloorTransition(String newFloor) {
    debugPrint(
      '[NavigationController] Floor transition confirmed: $_currentNavigatingFloor Ã¢â€ â€™ $newFloor',
    );
    _currentNavigatingFloor = newFloor;
    _isTransitioningFloors = false;
    _expectedNextFloor = null;
    _exitConfirmationCounter = 0;
    _newFloorEstimateCount = 0;
    _lastFloorSwitchTime = DateTime.now();
    _transitionStartTime = null;
    _lastIndoorPosition = null;

    // Sync SpaceProvider to the new floor
    final floors = _spaceProvider.floors;
    final newFloorModel = floors.where((f) => f.floorNumber == newFloor).firstOrNull;
    if (newFloorModel != null && _spaceProvider.selectedFloor?.floorNumber != newFloor) {
      _spaceProvider.selectFloor(newFloorModel);
    }

    notifyListeners();
  }

  void _preLoadFloorIfNeeded(String floorNumber) {
    if (_isTransitioningFloors) return;
    if (_currentNavigatingFloor == floorNumber) return;

    debugPrint(
      '[NavigationController] Pre-loading floor $floorNumber (approaching connector)',
    );
    _isTransitioningFloors = true;
    _transitionStartTime = DateTime.now();
    _newFloorEstimateCount = 0;

    // Cache last indoor position for hold during transition
    _lastIndoorPosition = _locationProvider.currentLocation;
    notifyListeners();

    // Trigger floor load in SpaceProvider
    final floors = _spaceProvider.floors;
    final targetFloor = floors.where((f) => f.floorNumber == floorNumber).firstOrNull;
    if (targetFloor != null && _spaceProvider.selectedFloor?.floorNumber != floorNumber) {
      _spaceProvider.selectFloor(targetFloor);
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Building Exit Detection Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  void _checkBuildingExit(UserLocation location) {
    if (_subState != NavigationSubState.indoor) return;

    final source = _locationProvider.positionSource;
    final gpsLocation = _locationProvider.gpsLocation;

    // Require: indoor positioning lost, GPS available with good accuracy
    if (source == LocationSource.indoorWifi) {
      _exitConfirmationCounter = 0;
      return;
    }
    if (gpsLocation == null) {
      _exitConfirmationCounter = 0;
      return;
    }
    if (gpsLocation.accuracy > NavigationConfig.exitAccuracyThreshold) {
      _exitConfirmationCounter = 0;
      return;
    }

    // Check if GPS position is outside the building
    final isOutside = _isOutsideBuilding(gpsLocation);
    if (!isOutside) {
      _exitConfirmationCounter = 0;
      return;
    }

    _exitConfirmationCounter++;
    if (_exitConfirmationCounter >= NavigationConfig.exitConfirmationCount) {
      debugPrint('[NavigationController] Building exit detected');
      _handleBuildingExit();
    }
  }

  bool _isOutsideBuilding(UserLocation gpsLocation) {
    final floorplan = _spaceProvider.activeFloorplan;
    if (floorplan != null && floorplan.hasValidBounds) {
      // Primary: check against floorplan bounds
      return !floorplan.bounds.contains(gpsLocation.latLng);
    }

    // Fallback: distance from building center
    final building = _spaceProvider.selectedSpace;
    if (building != null) {
      final dist = Geolocator.distanceBetween(gpsLocation.latitude, gpsLocation.longitude, building.latitude, building.longitude);
      return dist > NavigationConfig.exitDistanceThreshold;
    }

    return false;
  }

  void _handleBuildingExit() {
    _subState = NavigationSubState.outdoor;
    _currentNavigatingFloor = null;
    _isTransitioningFloors = false;
    _expectedNextFloor = null;
    _buildingPreloaded = false;
    _exitConfirmationCounter = 0;

    // Clear indoor floor selection Ã¢â‚¬â€ return to GPS-based tracking
    _spaceProvider.clearSelection();
    notifyListeners();
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Building Entry Detection Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  /// Called periodically during outdoor navigation to check if the user
  /// is approaching the destination building.
  void checkBuildingApproach(UserLocation location) {
    if (_phase != NavigationPhase.active) return;
    if (_subState != NavigationSubState.outdoor) return;
    if (_buildingPreloaded) return;

    final building = _destinationSpace;
    if (building == null) return;

    final dist = Geolocator.distanceBetween(location.latitude, location.longitude, building.latitude, building.longitude);

    // Stage 1: Early preparation
    if (dist < NavigationConfig.buildingPrepThreshold) {
      _preLoadBuildingData(building);
    }
  }

  Future<void> _preLoadBuildingData(SpaceModel building) async {
    debugPrint(
      '[NavigationController] Pre-loading building data for ${building.name} (${building.buid})',
    );
    _buildingPreloaded = true;

    // Auto-select the building Ã¢â‚¬â€ this triggers floor loading
    if (_spaceProvider.selectedSpace?.buid != building.buid) {
      _spaceProvider.selectSpace(building);
    }
  }

  /// Checks if the user is close enough to a building entrance to trigger
  /// the outdoorÃ¢â€ â€™indoor transition.
  void checkEntranceProximity(UserLocation location) {
    if (_phase != NavigationPhase.active) return;
    if (_subState != NavigationSubState.outdoor) return;
    if (!_buildingPreloaded) return;

    // Wait for ground floor POIs to be loaded
    if (!_spaceProvider.hasPois) return;

    // Find nearest entrance POI
    final entrancePois = _spaceProvider.pois
        .where((poi) =>
            poi.isBuildingEntrance ||
            poi.poisType.toLowerCase().contains('entrance'))
        .toList();
    if (entrancePois.isEmpty) {
      // Fallback: use building center proximity
      _checkFallbackEntranceProximity(location);
      return;
    }

    // Find nearest entrance by distance
    PoiModel? nearest;
    double minDist = double.infinity;
    for (final poi in entrancePois) {
      final dist = Geolocator.distanceBetween(location.latitude, location.longitude, poi.latitude, poi.longitude);
      if (dist < minDist) {
        minDist = dist;
        nearest = poi;
      }
    }

    // Stage 2: Indoor transition
    final threshold = NavigationConfig.entranceTransitionThreshold;
    if (minDist < threshold && nearest != null) {
      _triggerIndoorTransition();
    }
  }

  void _checkFallbackEntranceProximity(UserLocation location) {
    final building = _destinationSpace;
    if (building == null) return;

    final dist = Geolocator.distanceBetween(location.latitude, location.longitude, building.latitude, building.longitude);
    if (dist < NavigationConfig.entranceFallbackThreshold) {
      _triggerIndoorTransition();
    }
  }

  void _triggerIndoorTransition() {
    debugPrint('[NavigationController] Indoor transition triggered');

    // Auto-select ground floor
    final floors = _spaceProvider.floors;
    final groundFloor = floors
        .where((f) => f.floorNumber == '0')
        .firstOrNull ?? floors.firstOrNull;
    if (groundFloor != null) {
      _currentNavigatingFloor = groundFloor.floorNumber;
      _spaceProvider.selectFloor(groundFloor);
    }

    _subState = NavigationSubState.indoor;
    _exitConfirmationCounter = 0;

    // Request indoor route from current position
    _triggerReroute();
  }

  /// Returns the position to render during floor transition (held position),
  /// or the current location otherwise.
  UserLocation? get heldPositionDuringTransition =>
      _isTransitioningFloors ? _lastIndoorPosition : null;

  /// Checks if the floor transition has timed out and aborts if so.
  void _checkTransitionTimeout() {
    final startTime = _transitionStartTime;
    if (startTime == null) return;

    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inSeconds >= NavigationConfig.transitionTimeoutSeconds) {
      debugPrint(
        '[NavigationController] Floor transition timed out after ${elapsed.inSeconds}s Ã¢â‚¬â€ aborting',
      );
      // Abort transition: revert to previous floor, keep GPS-based tracking
      _isTransitioningFloors = false;
      _expectedNextFloor = null;
      _transitionStartTime = null;
      _lastIndoorPosition = null;
      _newFloorEstimateCount = 0;
      _evaluateSubState();
      notifyListeners();
    }
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬ Dispose Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬

  @override
  void dispose() {
    _locationProvider.removeListener(_onLocationChanged);
    _spaceProvider.removeListener(_onSpaceProviderChanged);
    super.dispose();
  }
}
