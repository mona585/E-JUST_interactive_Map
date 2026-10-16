import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


import '../models/campus_asset_status.dart';
import '../models/campus_gate.dart';
import '../models/floor_model.dart';
import '../models/navigation_route_model.dart';
import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../models/user_location.dart';
import '../repositories/navigation_repository.dart';
import '../services/cache_service.dart';
import '../utils/building_containment.dart';
import '../utils/poi_classification.dart';
import 'campus_route_assets.dart';

/// Owns every navigation-route REQUEST against the backend: the
/// POI/building/gate routing cascades (Strategy 1/2/3), cross-building
/// composition, retargeting, the O→I handoff guidance refresh, request-id
/// fencing/deduplication, and the route store itself (status, active route,
/// error, destination puid).
///
/// Extracted from [SpaceViewModel]. The coordinator holds NO selection or
/// browsing-asset state; selection semantics stay in the view model and are
/// driven here exclusively through the injected [selectSpace] /
/// [selectFloor] / navigation-safe variant / loader callbacks. All
/// notifications fan out through [notify], wired to the view model's
/// [ChangeNotifier].
class CampusRouteCoordinator {
  CampusRouteCoordinator({
    required CampusRoutingAssets assets,
    required NavigationRepository navigationRepository,
    required void Function() notify,
    CacheService? cacheService,
    required List<SpaceModel> Function() spaces,
    required List<PoiModel> Function() pois,
    required List<FloorModel> Function() floors,
    required List<FloorModel> Function(String buid) floorsForBuilding,
    required PoiModel? Function() selectedPoi,
    required FloorModel? Function() selectedFloor,
    required String? Function() selectedSpaceBuid,
    required String? Function() selectedFloorNumber,
    required UserLocation? Function() currentLocation,
    required RadioMapStatus Function() radioMapStatus,
    required String? Function() activeRadioMapBuid,
    required String? Function() activeRadioMapFloor,
    required void Function(PoiModel target) setDestinationPoi,
    required void Function(SpaceModel space) selectSpace,
    required void Function(SpaceModel space) selectSpaceForNavigation,
    required void Function(FloorModel floor) selectFloor,
    required void Function(FloorModel floor) selectFloorForNavigation,
    required Future<void> Function() loadFloors,
    required Future<void> Function() loadPois,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _assets = assets,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navigationRepository = navigationRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _notify = notify,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _cacheService = cacheService,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _spaces = spaces,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _pois = pois,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _floors = floors,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _floorsForBuilding = floorsForBuilding,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedPoi = selectedPoi,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedFloor = selectedFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedSpaceBuid = selectedSpaceBuid,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectedFloorNumber = selectedFloorNumber,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _currentLocation = currentLocation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _radioMapStatus = radioMapStatus,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _activeRadioMapBuid = activeRadioMapBuid,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _activeRadioMapFloor = activeRadioMapFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _setDestinationPoi = setDestinationPoi,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectSpace = selectSpace,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectSpaceForNavigation = selectSpaceForNavigation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectFloor = selectFloor,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _selectFloorForNavigation = selectFloorForNavigation,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _loadFloors = loadFloors,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _loadPois = loadPois;

  final CampusRoutingAssets _assets;
  final NavigationRepository _navigationRepository;
  final void Function() _notify;
  final CacheService? _cacheService;
  final List<SpaceModel> Function() _spaces;
  final List<PoiModel> Function() _pois;
  final List<FloorModel> Function() _floors;
  final List<FloorModel> Function(String buid) _floorsForBuilding;
  final PoiModel? Function() _selectedPoi;
  final FloorModel? Function() _selectedFloor;
  final String? Function() _selectedSpaceBuid;
  final String? Function() _selectedFloorNumber;
  final UserLocation? Function() _currentLocation;
  final RadioMapStatus Function() _radioMapStatus;
  final String? Function() _activeRadioMapBuid;
  final String? Function() _activeRadioMapFloor;
  final void Function(PoiModel target) _setDestinationPoi;
  final void Function(SpaceModel space) _selectSpace;
  final void Function(SpaceModel space) _selectSpaceForNavigation;
  final void Function(FloorModel floor) _selectFloor;
  final void Function(FloorModel floor) _selectFloorForNavigation;
  final Future<void> Function() _loadFloors;
  final Future<void> Function() _loadPois;

  // Navigation Route State
  NavigationRouteStatus _navigationRouteStatus = NavigationRouteStatus.idle;
  NavigationRouteModel? _activeNavigationRoute;
  String? _navigationRouteErrorMessage;
  String? _navigationDestinationPuid;
  int _navigationRouteRequestId = 0;

  NavigationRouteStatus get navigationRouteStatus => _navigationRouteStatus;
  NavigationRouteModel? get activeNavigationRoute => _activeNavigationRoute;
  String? get navigationRouteErrorMessage => _navigationRouteErrorMessage;
  String? get navigationDestinationPuid => _navigationDestinationPuid;
  bool get isLoadingNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.loading;
  bool get hasActiveNavigationRoute =>
      _navigationRouteStatus == NavigationRouteStatus.ready &&
      _activeNavigationRoute != null &&
      _activeNavigationRoute!.hasRenderablePath;
  bool get isNavigationRouteUnsupported =>
      _navigationRouteStatus == NavigationRouteStatus.unsupported;

  /// Status-field reset only (selection/browsing flows and route teardown).
  void resetRouteState() {
    _navigationRouteStatus = NavigationRouteStatus.idle;
    _activeNavigationRoute = null;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
  }

  /// Idempotent teardown of the route store (used by canonical termination
  /// and the browsing clear-route action).
  void clearNavigationRoute() {
    if (_navigationRouteStatus != NavigationRouteStatus.idle ||
        _activeNavigationRoute != null ||
        _navigationRouteErrorMessage != null) {
      _navigationRouteRequestId++;
      resetRouteState();
      _notify();
    }
  }

  /// Session write-through (MASTER PLAN PHASE 2, INV-1/2/6).
  ///
  /// The single route store is replaced atomically for observers: one field
  /// assignment, status ready, error cleared, ONE notification. Browsing
  /// state (radiomap/floorplan/POIs) and destination bookkeeping are never
  /// touched here — during a live session only the navigation controller
  /// calls this.
  void adoptNavigatedRoute(NavigationRouteModel route) {
    debugPrint('[SpaceViewModel] adoptNavigatedRoute (session write-through)');
    _activeNavigationRoute = route;
    _navigationRouteStatus = NavigationRouteStatus.ready;
    _navigationRouteErrorMessage = null;
    _notify();
  }

  /// Clears the navigation route-level error message.
  void clearNavigationRouteError() {
    if (_navigationRouteErrorMessage != null) {
      _navigationRouteErrorMessage = null;
      _notify();
    }
  }

  /// Opens a new route request: bumps the fence, sets loading, and records
  /// the destination. Returns the request id for later freshness checks.
  int startRouteRequest(String? destinationPuid) {
    final requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = destinationPuid;
    _notify();
    return requestId;
  }

  /// Whether [requestId] is still the newest route request.
  bool isCurrentRouteRequest(int requestId) =>
      requestId == _navigationRouteRequestId;

  /// Requests a navigation route from the current position to the selected POI.
  /// Uses a 3-strategy cascade identical to building routing.
  Future<void> requestRouteToSelectedPoi() async {
    final poi = _selectedPoi();
    final floor = _selectedFloor();
    final currentLocation = _currentLocation();

    if (poi == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage = 'Select a POI first.';
      _notify();
      return;
    }

    if (floor == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Select a floor before requesting a route.';
      _notify();
      return;
    }

    if (currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return;
    }

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = poi.puid;
    _notify();

    // Save to recent waypoints
    _cacheService?.addRecentWaypoint(poi.puid);

    // ── Cross-building / Outdoor→Indoor detection for POI navigation ──
    final userBuilding = _detectBuildingFromPolygon(currentLocation);
    final targetPoiBuilding = _spaces()
        .where((s) => s.buid == poi.buid)
        .firstOrNull;
    final shouldTryCrossBuilding =
        targetPoiBuilding != null &&
        (userBuilding == null || userBuilding.buid != targetPoiBuilding.buid);

    if (shouldTryCrossBuilding) {
      debugPrint(
        '[SpaceViewModel] POI cross-building: user ${userBuilding != null ? "in ${userBuilding.name}" : "outside"} → ${poi.name} in ${targetPoiBuilding.name}',
      );
      try {
        final crossRoute = await _assets.crossBuildingRouter.composeRoute(
          userLocation: currentLocation.latLng,
          targetSpace: targetPoiBuilding,
          allBuildings: _spaces(),
          targetPuid: poi.puid,
        );
        if (crossRoute != null) {
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = crossRoute;
          _navigationRouteErrorMessage = crossRoute.partialRouteWarning;
          _notify();
          return;
        }
      } catch (e) {
        debugPrint('[SpaceViewModel] POI cross-building router failed: $e');
        // Fall through to existing cascade
      }
    }

    final destLatLng = poi.latLng;

    // Whether the user is genuinely INSIDE the destination building. This gates
    // the indoor-origin strategies below.
    //
    // When the user is OUTDOORS (or in another building), coordinate-based and
    // nearest-POI routing would snap the raw GPS fix (or a far-away indoor POI)
    // onto an arbitrary indoor floor node such as G11 and start the route there,
    // even though the user is standing outside. In that case the only correct
    // origin is the user's actual GPS position, which Strategy 3's outdoor
    // GPS→entrance leg provides.
    final insideDestination = _isPositionInBuilding(
      currentLocation.latLng,
      poi.buid,
    );

    // ── Strategy 1: Anyplace coordinate-based routing (works when already indoors) ──
    debugPrint(
      '[SpaceViewModel] Strategy 1: coordinate-based routing'
      '(insideDestination: $insideDestination)...',
    );
    if (insideDestination) {
      try {
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
          floorNumber: floor.floorNumber,
          destinationPuid: poi.puid,
        );

        if (requestId != _navigationRouteRequestId ||
            _selectedPoi()?.puid != poi.puid) {
          return;
        }

        if (route.hasRenderablePath) {
          debugPrint('[SpaceViewModel] Strategy 1 succeeded');
          _navigationRouteStatus = NavigationRouteStatus.ready;
          // Same-building indoor geometry adopts the segmented indoorRouting
          // representation so it renders with the same intended indoor style
          // as composed cross-building journeys (geometry untouched).
          _activeNavigationRoute = route.toSegmentedIndoor(
            fallbackBuildingId: poi.buid,
            instruction: 'Head to ${poi.name}',
          );
          _navigationRouteErrorMessage = null;
          _notify();
          return;
        }
        debugPrint('[SpaceViewModel] Strategy 1 failed: no renderable path');
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        final msg = e.message.toLowerCase();
        if (msg.contains('not supported') ||
            msg.contains('no route found') ||
            msg.contains('not be connected') ||
            e.statusCode == 400 ||
            e.statusCode == 404) {
          debugPrint('[SpaceViewModel] Strategy 1 failed: ${e.message}');
        } else {
          debugPrint('[SpaceViewModel] Strategy 1 error: ${e.message}');
          _navigationRouteStatus = NavigationRouteStatus.error;
          _activeNavigationRoute = null;
          _navigationRouteErrorMessage = e.message;
          _notify();
          return;
        }
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceViewModel] Strategy 1 exception: $e');
        _navigationRouteStatus = NavigationRouteStatus.error;
        _activeNavigationRoute = null;
        _navigationRouteErrorMessage = 'Error requesting route: $e';
        _notify();
        return;
      }
    }

    // ── Strategy 2: POI-to-POI routing (closest POI near user → destination POI) ──
    if (requestId != _navigationRouteRequestId) return;

    // Like Strategy 1, using a nearby indoor POI as the origin only makes sense
    // when the user is genuinely indoors. When outdoors we must NOT start the
    // route from an indoor node (e.g. G11) — skip to Strategy 3's GPS leg.
    if (insideDestination) {
      debugPrint('[SpaceViewModel] Strategy 2: POI-to-POI routing...');

      // Find closest POI to user's GPS on the currently loaded POIs
      NavigationRoutePoint? originPoi;
      final loadedPois = _pois();
      if (loadedPois.isNotEmpty) {
        final userLatLng = currentLocation;
        var bestDist = double.infinity;
        for (final p in loadedPois) {
          if (p.puid == poi.puid) continue;
          final dist = Geolocator.distanceBetween(
            userLatLng.latitude,
            userLatLng.longitude,
            p.latitude,
            p.longitude,
          );
          if (dist < bestDist) {
            bestDist = dist;
            originPoi = NavigationRoutePoint(
              latitude: p.latitude,
              longitude: p.longitude,
              puid: p.puid,
              buid: p.buid,
              floorNumber: p.floorNumber,
              poisType: p.poisType,
            );
          }
        }
      }

      if (originPoi != null) {
        debugPrint(
          '[SpaceViewModel] Strategy 2: POI-to-POI ${originPoi.puid} -> ${poi.puid}',
        );
        try {
          final route = await _navigationRepository.getRouteBetweenPois(
            fromPuid: originPoi.puid,
            toPuid: poi.puid,
          );

          if (requestId != _navigationRouteRequestId ||
              _selectedPoi()?.puid != poi.puid) {
            return;
          }

          if (route.hasRenderablePath) {
            debugPrint('[SpaceViewModel] Strategy 2 succeeded');
            _navigationRouteStatus = NavigationRouteStatus.ready;
            // Representation unification — see Strategy 1 commit above.
            _activeNavigationRoute = route.toSegmentedIndoor(
              fallbackBuildingId: poi.buid,
              instruction: 'Head to ${poi.name}',
            );
            _navigationRouteErrorMessage = null;
            _notify();
            return;
          }
          debugPrint('[SpaceViewModel] Strategy 2 failed: no renderable path');
        } on ApiException catch (e) {
          if (requestId != _navigationRouteRequestId) return;
          debugPrint('[SpaceViewModel] Strategy 2 failed: ${e.message}');
        } catch (e) {
          if (requestId != _navigationRouteRequestId) return;
          debugPrint('[SpaceViewModel] Strategy 2 exception: $e');
        }
      } else {
        debugPrint('[SpaceViewModel] Strategy 2 skipped: no origin POI found');
      }
    }

    // ── Strategy 3: OSRM outdoor walking path to POI + indoor segment (ALWAYS works) ──
    if (requestId != _navigationRouteRequestId) return;

    debugPrint('[SpaceViewModel] Strategy 3 (hybrid): outdoor route to POI...');

    // T5.6 / L8: if the user is ALREADY inside the destination building, do
    // NOT synthesize a spurious outdoor OSRM/custom leg. Strategy 1/2 having
    // failed means coordinate/POI routing was unavailable, so we keep the route
    // purely indoor (entrance→target geometry) instead of a false "walk
    // outside" from an indoor position.

    // ── Strategy 3 outdoor leg (skipped when already indoors) ──
    List<LatLng>? outdoorPath;
    if (!insideDestination) {
      // Custom KMZ → hybrid → OSRM→custom → OSRM cascade (extracted; shares
      // the same repositories/services so geometry stays byte-identical).
      outdoorPath = await _assets.outdoorRoutePlanner.resolveOutdoorPath(
        from: currentLocation.latLng,
        to: destLatLng,
        gateEntry: _assets.preferredGate(),
      );
    }

    final outdoorPoints = <NavigationRoutePoint>[];
    if (outdoorPath != null && outdoorPath.length >= 2) {
      for (final pt in outdoorPath) {
        outdoorPoints.add(
          NavigationRoutePoint.outdoor(
            latitude: pt.latitude,
            longitude: pt.longitude,
          ),
        );
      }
    } else if (!insideDestination) {
      // Fallback: straight line if OSRM fails (only when an outdoor leg was
      // actually warranted).
      outdoorPoints.addAll([
        NavigationRoutePoint.outdoor(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
        ),
        NavigationRoutePoint(
          latitude: destLatLng.latitude,
          longitude: destLatLng.longitude,
          puid: poi.puid,
          buid: poi.buid,
          floorNumber: poi.floorNumber,
          poisType: poi.poisType,
        ),
      ]);
    }
    // When insideDestination, outdoorPoints stays empty → the hybrid route
    // below is purely indoor.

    // Try to get indoor route from entrance to target POI via connectors.
    // If the destination POI is itself an entrance/door (an outdoor-facing
    // POI), it is reached at the end of the outdoor GPS leg — routing to it
    // needs NO indoor leg. Skipping the indoor phase here keeps the route a
    // clean GPS→entrance path (and avoids synthesizing an indoor node origin).
    NavigationRouteModel? indoorRoute;
    final bool outdoorDestination =
        PoiClassification.isEntrance(poi) || PoiClassification.isDoor(poi);
    final loadedPois = _pois();
    if (loadedPois.isNotEmpty && !outdoorDestination) {
      // Find entrance POI nearest to the destination
      final entrancePoi = loadedPois
          .where(
            (p) =>
                p.buid == poi.buid &&
                (p.isBuildingEntrance ||
                    p.poisType.toLowerCase().contains('entrance')),
          )
          .firstOrNull;

      if (entrancePoi != null && entrancePoi.puid.isNotEmpty) {
        // Attempt 1: Direct entrance→target via server API
        try {
          debugPrint(
            '[SpaceViewModel] Strategy 3: indoor route ${entrancePoi.puid} → ${poi.puid}',
          );
          indoorRoute = await _navigationRepository.getRouteBetweenPois(
            fromPuid: entrancePoi.puid,
            toPuid: poi.puid,
          );
          if (indoorRoute.hasRenderablePath) {
            debugPrint(
              '[SpaceViewModel] Strategy 3: indoor route succeeded (${indoorRoute.points.length} points)',
            );
          } else {
            debugPrint(
              '[SpaceViewModel] Strategy 3: direct indoor route no renderable path — trying connector fallback',
            );
            indoorRoute = null;
          }
        } catch (e) {
          debugPrint(
            '[SpaceViewModel] Strategy 3: direct indoor route failed: $e',
          );
          indoorRoute = null;
        }

        // Attempt 2: Route through intermediate connector POIs
        // Server requires edges between POIs. Room/entrance POIs often lack edges,
        // but connector POIs (pois_type == "None") have edges between them.
        if (indoorRoute == null) {
          try {
            indoorRoute = await _assets.routingService.routeIndoorViaConnectors(
              pois: loadedPois,
              entrancePoi: entrancePoi,
              targetPoi: poi,
            );
          } catch (e) {
            debugPrint(
              '[SpaceViewModel] Strategy 3: connector-based indoor route failed: $e',
            );
          }
        }
      }
    }

    final hybridRoute = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: indoorRoute,
    );

    debugPrint(
      '[SpaceViewModel] Strategy 3 (hybrid): ${hybridRoute.points.length} points '
      '(outdoor: ${outdoorPoints.length}, indoor: ${indoorRoute?.points.length ?? 0})',
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = hybridRoute;
    _navigationRouteErrorMessage = null;
    _notify();
  }

  /// Requests a route from the user's current location to [targetSpace].
  ///
  /// **Always produces a visible route** using a hybrid strategy:
  /// 1. Try Anyplace coordinate-based routing (works when inside/nearby).
  /// 2. Try POI-to-POI indoor routing (entrance → interior).
  /// 3. Build a GPS→entrance outdoor polyline and merge with any indoor path.
  /// 4. Worst case: straight line from GPS to building center.
  Future<void> requestRouteToBuilding(SpaceModel targetSpace) async {
    final currentLocation = _currentLocation();

    if (currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return;
    }

    debugPrint(
      '[SpaceViewModel] requestRouteToBuilding: ${targetSpace.name} '
      '(buid: ${targetSpace.buid}, user GPS: ${currentLocation.latitude},${currentLocation.longitude})',
    );

    // ── Cross-building / Outdoor→Indoor detection ──
    // Always try cross-building router when user is NOT in the same building.
    // The router handles both: user inside another building AND user outside all buildings.
    final userBuilding = _detectBuildingFromPolygon(currentLocation);
    final shouldTryCrossBuilding =
        userBuilding == null || userBuilding.buid != targetSpace.buid;

    if (shouldTryCrossBuilding) {
      debugPrint(
        '[SpaceViewModel] Cross-building check: user ${userBuilding != null ? "in ${userBuilding.name}" : "outside"} → ${targetSpace.name}',
      );
      try {
        final crossRoute = await _assets.crossBuildingRouter.composeRoute(
          userLocation: currentLocation.latLng,
          targetSpace: targetSpace,
          allBuildings: _spaces(),
        );
        if (crossRoute != null) {
          _navigationRouteStatus = NavigationRouteStatus.ready;
          _activeNavigationRoute = crossRoute;
          _navigationRouteErrorMessage = crossRoute.partialRouteWarning;
          _notify();
          return;
        }
      } catch (e) {
        debugPrint('[SpaceViewModel] Cross-building router failed: $e');
        // Fall through to existing cascade
      }
    }

    // Make sure this building is selected and floors are loaded
    if (_selectedSpaceBuid() != targetSpace.buid) {
      _selectSpace(targetSpace);
      await _loadFloors();
    }

    // Find ground floor or first floor
    final floors = _floors();
    final groundFloor =
        floors.where((f) => f.floorNumber == '0').firstOrNull ??
        (floors.isNotEmpty ? floors.first : null);

    final String floorNumber = groundFloor?.floorNumber ?? '0';

    debugPrint(
      '[SpaceViewModel] requestRouteToBuilding: using floor $floorNumber',
    );

    // Select the ground floor to load POIs
    if (groundFloor != null && _selectedFloorNumber() != groundFloor.floorNumber) {
      _selectFloor(groundFloor);
      await _loadPois();
    }

    final loadedPois = _pois();
    debugPrint(
      '[SpaceViewModel] requestRouteToBuilding: ${loadedPois.length} POIs loaded',
    );

    // Whether the user is physically inside the target building. Gates the
    // indoor-origin strategies and drives "nearest-entrance" selection when the
    // user is outdoors.
    final bool insideTarget = _isPositionInBuilding(
      currentLocation.latLng,
      targetSpace.buid,
    );

    // Find entrance POI and any other interior POI.
    final entrances = loadedPois
        .where(
          (p) =>
              p.buid == targetSpace.buid &&
              (p.isBuildingEntrance ||
                  p.poisType.toLowerCase().contains('entrance')),
        )
        .toList();

    // When the user is OUTDOORS, direct the route to the entrance NEAREST the
    // user's GPS so they walk to the closest door (proximity-first), instead of
    // an arbitrary first-loaded entrance. Indoors, any entrance is the end of
    // the (indoor) exit leg, so keep the first-entrance default.
    final PoiModel? entrancePoi = entrances.isEmpty
        ? null
        : (insideTarget
              ? entrances.first
              : _nearestPoiToOne(entrances, currentLocation.latLng));
    final targetPoi = entrancePoi ?? (loadedPois.isNotEmpty ? loadedPois.first : null);
    final interiorPoi = loadedPois
        .where((p) => p.puid != targetPoi?.puid)
        .firstOrNull;

    // Destination for the route = entrance if found, else the building's own coordinates
    final destLatLng = targetPoi != null
        ? targetPoi.latLng
        : targetSpace.latLng;
    final destBuid = targetPoi?.buid ?? targetSpace.buid;

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = targetPoi?.puid;
    _notify();

    debugPrint(
      '[SpaceViewModel] requestRouteToBuilding: insideTarget=$insideTarget, '
      'targetPoi=${targetPoi?.name}(puid=${targetPoi?.puid})',
    );

    // ── Strategy 1: Coordinate-based routing (indoor / near building) ──
    if (targetPoi != null && insideTarget) {
      try {
        debugPrint('[SpaceViewModel] Strategy 1: coordinate-based routing...');
        final route = await _navigationRepository.getRouteFromCoordinates(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
          floorNumber: floorNumber,
          destinationPuid: targetPoi.puid,
        );
        if (requestId != _navigationRouteRequestId) return;

        if (route.hasRenderablePath) {
          debugPrint(
            '[SpaceViewModel] Strategy 1 succeeded: ${route.points.length} points',
          );
          _navigationRouteStatus = NavigationRouteStatus.ready;
          // Representation unification — see requestRouteToSelectedPoi.
          _activeNavigationRoute = route.toSegmentedIndoor(
            fallbackBuildingId: targetSpace.buid,
            instruction: 'Enter ${targetSpace.name}',
          );
          _navigationRouteErrorMessage = null;
          _notify();
          return;
        }
        debugPrint(
          '[SpaceViewModel] Strategy 1 returned ${route.points.length} pts (need >=2)',
        );
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceViewModel] Strategy 1 failed: ${e.message}');
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceViewModel] Strategy 1 error: $e');
      }
    }

    // ── Strategy 2: POI-to-POI indoor route (entrance → interior) ──
    NavigationRouteModel? indoorRoute;
    if (targetPoi != null && interiorPoi != null && insideTarget) {
      try {
        debugPrint(
          '[SpaceViewModel] Strategy 2: POI-to-POI ${interiorPoi.puid} → ${targetPoi.puid}',
        );
        indoorRoute = await _navigationRepository.getRouteBetweenPois(
          fromPuid: interiorPoi.puid,
          toPuid: targetPoi.puid,
        );
        if (requestId != _navigationRouteRequestId) return;

        if (indoorRoute.hasRenderablePath) {
          debugPrint(
            '[SpaceViewModel] Strategy 2 succeeded: ${indoorRoute.points.length} points',
          );
        } else {
          debugPrint(
            '[SpaceViewModel] Strategy 2 returned ${indoorRoute.points.length} pts',
          );
          indoorRoute = null;
        }
      } on ApiException catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceViewModel] Strategy 2 failed: ${e.message}');
        indoorRoute = null;
      } catch (e) {
        if (requestId != _navigationRouteRequestId) return;
        debugPrint('[SpaceViewModel] Strategy 2 error: $e');
        indoorRoute = null;
      }
    }

    // ── Strategy 3: OSRM outdoor walking path + indoor route (ALWAYS produces a route) ──
    if (requestId != _navigationRouteRequestId) return;

    // Try custom KMZ routes first
    List<LatLng>? outdoorPath;
    // Custom KMZ → hybrid → OSRM→custom → OSRM cascade (extracted; shares
    // the same repositories/services so geometry stays byte-identical).
    outdoorPath = await _assets.outdoorRoutePlanner.resolveOutdoorPath(
      from: currentLocation.latLng,
      to: destLatLng,
      gateEntry: _assets.preferredGate(),
    );

    // Convert path to NavigationRoutePoints (marked as outdoor)
    final outdoorPoints = <NavigationRoutePoint>[];
    if (outdoorPath.length >= 2) {
      for (final pt in outdoorPath) {
        outdoorPoints.add(
          NavigationRoutePoint.outdoor(
            latitude: pt.latitude,
            longitude: pt.longitude,
          ),
        );
      }
    } else {
      // Fallback: straight line if OSRM fails
      outdoorPoints.addAll([
        NavigationRoutePoint.outdoor(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude,
        ),
        NavigationRoutePoint(
          latitude: destLatLng.latitude,
          longitude: destLatLng.longitude,
          puid: targetPoi?.puid ?? '__building_center__',
          buid: destBuid,
          floorNumber: floorNumber,
          poisType: targetPoi?.poisType ?? 'building',
        ),
      ]);
    }

    final hybridRoute = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: indoorRoute,
    );

    debugPrint(
      '[SpaceViewModel] Strategy 3 (hybrid): ${hybridRoute.points.length} points '
      '(outdoor: ${outdoorPoints.length}, indoor: ${indoorRoute?.points.length ?? 0})',
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = hybridRoute;
    _navigationRouteErrorMessage = null;
    _notify();
  }

  /// Routes the user to a campus gate, using the gate's EXACT coordinates
  /// (from `university gates.kmz`) as the destination.
  ///
  /// A gate is an outdoor, campus-scoped destination — no building/floor/POI
  /// layer is involved. This reuses the existing outdoor routing cascade
  /// (custom road graph → hybrid → OSRM-to-custom → OSRM) so the route follows
  /// the campus road network wherever the gate is graph-connected.
  ///
  /// IMPORTANT (gate policy separation): the selected [gate] IS the
  /// destination and is deliberately NOT passed as a `gateEntry` to
  /// [RoutingService.buildOsrmToCustomRoute] — so the preferred automatic
  /// entry gate (G2)
  /// is never forced as an intermediate point. Routing to a gate never changes
  /// the routing policy.
  Future<bool> requestRouteToGate(CampusGate gate) async {
    final currentLocation = _currentLocation();

    if (currentLocation == null) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _navigationRouteErrorMessage =
          'Current location is unavailable. Center on your location first.';
      _notify();
      return false;
    }

    final destLatLng = LatLng(gate.latitude, gate.longitude);
    final fromLatLng = currentLocation.latLng;

    debugPrint(
      '[SpaceViewModel] requestRouteToGate: ${gate.id} '
      '(destination: ${gate.latitude},${gate.longitude}, '
      'user GPS: ${currentLocation.latitude},${currentLocation.longitude})',
    );

    final int requestId = ++_navigationRouteRequestId;
    _navigationRouteStatus = NavigationRouteStatus.loading;
    _navigationRouteErrorMessage = null;
    _navigationDestinationPuid = null;
    _notify();

    List<LatLng>? outdoorPath;

    // Outdoor cascade: custom → hybrid → OSRM→custom → OSRM (extracted).
    // No gateEntry is supplied — the gate IS the destination, so the preferred
    // entry gate is never forced as an intermediate point (gate policy
    // separation).
    outdoorPath = await _assets.outdoorRoutePlanner.resolveOutdoorPath(
      from: fromLatLng,
      to: destLatLng,
      gateEntry: null,
    );
    if (requestId != _navigationRouteRequestId) return false;

    if (outdoorPath.length < 2) {
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage =
          'Could not build a route to gate ${gate.id}.';
      debugPrint('[SpaceViewModel] requestRouteToGate: no outdoor path found');
      _notify();
      return false;
    }
    final outdoorPoints = <NavigationRoutePoint>[
      for (final pt in outdoorPath)
        NavigationRoutePoint.outdoor(
          latitude: pt.latitude,
          longitude: pt.longitude,
        ),
    ];

    final route = NavigationRouteModel.hybrid(
      outdoorPoints: outdoorPoints,
      indoorRoute: null,
    );

    _navigationRouteStatus = NavigationRouteStatus.ready;
    _activeNavigationRoute = route;
    _navigationRouteErrorMessage = null;
    _notify();

    debugPrint(
      '[SpaceViewModel] requestRouteToGate: ${route.points.length} outdoor points',
    );
    return route.hasRenderablePath;
  }

  /// Retarget support (MASTER PLAN PHASE 4).
  ///
  /// Selects the destination context exclusively through navigation-safe
  /// variants (never resetting navigation fields), then runs the initial
  /// route cascade — reusing its request-id machinery unchanged. Returns
  /// true when a renderable route for [target] is in the store afterwards.
  Future<bool> requestRouteForRetarget(PoiModel target) async {
    final building = _spaces().where((s) => s.buid == target.buid).firstOrNull;
    if (building == null) {
      debugPrint(
        '[SpaceViewModel] retarget: building ${target.buid} not loaded',
      );
      return false;
    }
    _selectSpaceForNavigation(building);
    await _loadFloors();
    final floors = _floors();
    final floor =
        floors.where((f) => f.floorNumber == target.floorNumber).firstOrNull ??
        floors.where((f) => f.floorNumber == '0').firstOrNull ??
        (floors.isEmpty
            ? null
            : floors.reduce(
                (a, b) => a.numericFloor <= b.numericFloor ? a : b,
              ));
    if (floor != null) {
      _selectFloorForNavigation(floor);
    }
    // Selecting the new target POI must not trip the legacy reset even when
    // idle-guard logic changes later; the session liveness guard already
    // covers it, this is belt-and-braces for the retarget window.
    _setDestinationPoi(target);

    await requestRouteToSelectedPoi();
    final ok =
        _navigationRouteStatus == NavigationRouteStatus.ready &&
        _activeNavigationRoute != null &&
        _activeNavigationRoute!.hasRenderablePath;
    debugPrint(
      '[SpaceViewModel] requestRouteForRetarget(${target.puid}) '
      '-> ${ok ? "ready" : "failed"}',
    );
    return ok;
  }

  /// O→I handoff guidance refresh (MASTER PLAN PHASE 8).
  ///
  /// Narrow wrapper reusing the cascade pieces: waits (bounded) for RadioMap
  /// readiness of the confirmed scope, then anchors an indoor POI-to-POI
  /// request on the nearest known POI of that scope. The candidate is
  /// returned uncommitted — the controller owns the fenced write-through.
  Future<NavigationRouteModel?> requestIndoorRouteForSession({
    required String destinationPuid,
    required String confirmedBuid,
    required String confirmedFloor,
  }) async {
    // Radiomap readiness gate: wait up to 20 s for the confirmed scope's map
    // to be resident/ready; proceed-with-null afterwards.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final ready =
          _activeRadioMapBuid() == confirmedBuid &&
          _activeRadioMapFloor() == confirmedFloor &&
          _radioMapStatus() == RadioMapStatus.ready;
      if (ready) break;
      // Unsupported scope will never become ready — stop waiting early.
      if (_activeRadioMapBuid() == confirmedBuid &&
          _activeRadioMapFloor() == confirmedFloor &&
          _radioMapStatus() == RadioMapStatus.unsupported) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 250));
    }

    // Anchor: nearest loaded POI on the confirmed scope, else nothing usable.
    PoiModel? anchor;
    var best = double.infinity;
    final loadedPois = _pois();
    final location = _currentLocation();
    for (final p in loadedPois) {
      if (p.buid != confirmedBuid || p.puid == destinationPuid) continue;
      final d = Geolocator.distanceBetween(
        location?.latitude ?? p.latitude,
        location?.longitude ?? p.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < best) {
        best = d;
        anchor = p;
      }
    }
    if (anchor == null) return null;

    try {
      final route = await _navigationRepository.getRouteBetweenPois(
        fromPuid: anchor.puid,
        toPuid: destinationPuid,
      );
      // Representation unification: a legitimately refetched indoor guidance
      // route renders through the same indoorRouting projection as composed
      // journeys instead of the legacy path.
      return route.toSegmentedIndoor(
        fallbackBuildingId: confirmedBuid,
        instruction: 'Head to your destination',
      );
    } catch (e) {
      debugPrint('[SpaceViewModel] requestIndoorRouteForSession failed: $e');
      return null;
    }
  }

  /// UI/UX REDESIGN PHASE 2 — ADDITIVE custom-origin directions.
  ///
  /// Requests an indoor POI→POI route using the EXISTING repository API
  /// ([NavigationRepository.getRouteBetweenPois] — the identical call used by
  /// Strategy 2 of [requestRouteToSelectedPoi] and by the O→I handoff above).
  /// No routing logic is modified or duplicated here.
  ///
  /// The caller (view model) has already set up destination residency through
  /// the navigation-safe selection variants and started the request via
  /// [startRouteRequest]; this method runs the fenced fetch + adoption.
  ///
  /// Returns true when a renderable route for [target] is in the store.
  Future<bool> requestBetweenPois(
    PoiModel origin,
    PoiModel target, {
    required int requestId,
  }) async {
    try {
      final route = await _navigationRepository.getRouteBetweenPois(
        fromPuid: origin.puid,
        toPuid: target.puid,
      );
      if (requestId != _navigationRouteRequestId ||
          _navigationDestinationPuid != target.puid) {
        return false;
      }
      if (route.hasRenderablePath) {
        _navigationRouteStatus = NavigationRouteStatus.ready;
        _activeNavigationRoute = route.toSegmentedIndoor(
          fallbackBuildingId: target.buid,
          instruction: 'Head to ${target.name}',
        );
        _navigationRouteErrorMessage = null;
        _setDestinationPoi(target);
        debugPrint(
          '[SpaceViewModel] requestRouteBetweenPois ready '
          '(${origin.puid} → ${target.puid})',
        );
        return true;
      }
      _navigationRouteStatus = NavigationRouteStatus.unsupported;
      _navigationRouteErrorMessage =
          'No indoor route found between the selected places.';
      _notify();
      return false;
    } on ApiException catch (e) {
      if (requestId != _navigationRouteRequestId) return false;
      final msg = e.message.toLowerCase();
      final unsupported =
          msg.contains('not supported') ||
          msg.contains('no route') ||
          msg.contains('not be connected') ||
          e.statusCode == 400 ||
          e.statusCode == 404;
      _navigationRouteStatus = unsupported
          ? NavigationRouteStatus.unsupported
          : NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = e.message;
      _notify();
      return false;
    } catch (e) {
      if (requestId != _navigationRouteRequestId) return false;
      _navigationRouteStatus = NavigationRouteStatus.error;
      _activeNavigationRoute = null;
      _navigationRouteErrorMessage = 'Error requesting route: $e';
      _notify();
      return false;
    }
  }

  /// Returns the [PoiModel] from [pois] whose position is nearest [point] by
  /// geodesic distance. Returns null when [pois] is empty.
  static PoiModel? _nearestPoiToOne(List<PoiModel> pois, LatLng point) {
    PoiModel? nearest;
    double best = double.infinity;
    for (final p in pois) {
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < best) {
        best = d;
        nearest = p;
      }
    }
    return nearest;
  }

  /// Checks if a [position] is inside [buildingBuid] using the canonical
  /// [BuildingContainment] service over that building's server-real floor
  /// bounds. Returns false for [BuildingContainmentStatus.unknown] (a building
  /// with no reliable geometry is never reported as inside).
  bool _isPositionInBuilding(LatLng position, String buildingBuid) {
    final floors = _floorsForBuilding(buildingBuid);
    return BuildingContainment.isInside(position, floors);
  }

  /// Detects which building the user is inside using the canonical
  /// [BuildingContainment] service over each building's server-real floor
  /// bounds. Returns null if the user is outside every building (or every
  /// building's geometry is unknown).
  ///
  /// Resolution among overlapping building rectangles is deterministic:
  /// the containing building whose matched floor bounds are the STRICTEST
  /// (smallest) wins, with a stable buid tie-break. No centroid/distance
  /// heuristic is applied.
  SpaceModel? _detectBuildingFromPolygon(UserLocation userLocation) {
    final point = userLocation.latLng;
    SpaceModel? result;
    double? bestSpan;
    String? bestBuid;

    for (final building in _spaces()) {
      final floors = _floorsForBuilding(building.buid);
      final containment = BuildingContainment.classify(point, floors);
      if (!containment.isInside || containment.containingFloor == null) {
        continue;
      }
      final span = BuildingContainment.approxSpanMeters(
        containment.containingFloor!,
      );
      final better =
          result == null ||
          span < bestSpan! ||
          (span == bestSpan && building.buid.compareTo(bestBuid!) < 0);
      if (better) {
        result = building;
        bestSpan = span;
        bestBuid = building.buid;
      }
    }

    return result;
  }
}