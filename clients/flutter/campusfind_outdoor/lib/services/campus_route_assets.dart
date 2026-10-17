import 'package:flutter/foundation.dart';

import '../models/campus_gate.dart';
import '../models/floor_model.dart';
import '../models/poi_model.dart';
import '../repositories/campus_gate_repository.dart';
import '../repositories/cross_building_router.dart';
import '../repositories/custom_route_repository.dart';
import '../repositories/navigation_repository.dart';
import 'outdoor_route_planner.dart';
import 'routing_service.dart';

/// Owns the bundled route/assets infrastructure: the custom KMZ routes
/// repository, the campus gate repository (+ policy), and the stateless
/// routing services that compose them ([RoutingService],
/// [OutdoorRoutePlanner], [CrossBuildingRouter]).
///
/// Extracted from [SpaceViewModel]. [load] performs the one-time startup
/// bootstrap (routes → gates → gate policy); the view model and the route
/// coordinator consume the composable pieces through this single holder.
class CampusRoutingAssets {
  CampusRoutingAssets({
    required NavigationRepository navigationRepository,
    required Future<List<FloorModel>> Function(String buid)
        loadFloorsForBuilding,
    required Future<List<PoiModel>> Function(String buid, String floorNumber)
        loadPois,
    required Future<List<String>> Function(String buid) loadFloorNumbers,
    required void Function() notify,
  }) {
    _notify = notify;
    _customRouteRepository = CustomRouteRepository();
    _campusGateRepository = CampusGateRepository();
    _routingService = RoutingService(
      navigationRepository,
      _customRouteRepository,
    );
    _outdoorRoutePlanner = OutdoorRoutePlanner(
      routingService: _routingService,
      customRouteRepository: _customRouteRepository,
      navigationRepository: navigationRepository,
    );
    _crossBuildingRouter = CrossBuildingRouter(
      // Memory-backed building→floors index, populated by
      // loadFloorsForSelectedSpace and loadAllFloorsAndPois. Buildings whose
      // floors are not yet indexed resolve as empty → BuildingContainment
      // reports unknown → never classified as inside (safe outdoor default).
      loadFloorsForBuilding: (buid) async => loadFloorsForBuilding(buid),
      loadPois: (buid, floorNumber) async {
        try {
          return await loadPois(buid, floorNumber);
        } catch (e) {
          debugPrint(
            '[SpaceViewModel] loadPois callback failed for $buid/$floorNumber: $e',
          );
          return <PoiModel>[];
        }
      },
      loadFloorNumbers: (buid) async {
        try {
          return await loadFloorNumbers(buid);
        } catch (e) {
          debugPrint(
            '[SpaceViewModel] loadFloorNumbers callback failed for $buid: $e',
          );
          return <String>[];
        }
      },
      customRouteRepository: _customRouteRepository,
      campusGateRepository: _campusGateRepository,
      navigationRepository: navigationRepository,
    );
  }

  late final void Function() _notify;
  late final CustomRouteRepository _customRouteRepository;
  late final CampusGateRepository _campusGateRepository;
  late final RoutingService _routingService;
  late final OutdoorRoutePlanner _outdoorRoutePlanner;
  late final CrossBuildingRouter _crossBuildingRouter;

  CustomRouteRepository get customRouteRepository => _customRouteRepository;
  CampusGateRepository get campusGateRepository => _campusGateRepository;
  RoutingService get routingService => _routingService;
  OutdoorRoutePlanner get outdoorRoutePlanner => _outdoorRoutePlanner;
  CrossBuildingRouter get crossBuildingRouter => _crossBuildingRouter;

  /// The authoritative campus gate list (coordinates + ids from
  /// university gates.kmz). Unmodifiable — callers can never mutate internal
  /// gate state.
  List<CampusGate> get gates => _campusGateRepository.gates;

  /// The policy-selected automatic entry gate, or null.
  CampusGate? preferredGate() => _campusGateRepository.preferredGate();

  /// Loads custom KMZ routes AND campus gates from bundled assets.
  ///
  /// Should be called once during app startup, after spaces are loaded.
  /// Safe to call multiple times (no-op if already loaded).
  Future<void> load() async {
    debugPrint(
      '[SpaceViewModel] loadCustomRoutes: starting (isLoaded=${_customRouteRepository.isLoaded})',
    );
    if (!_customRouteRepository.isLoaded) {
      await _customRouteRepository.loadRoutes();
      debugPrint(
        '[SpaceViewModel] loadCustomRoutes: routes loaded=${_customRouteRepository.isLoaded}, routes=${_customRouteRepository.routes.length}',
      );
    }
    // Load the campus gate data (from university gates.kmz) alongside the
    // road network so the routing policy can select a preferred gate.
    if (!_campusGateRepository.isLoaded) {
      await _campusGateRepository.load();
      debugPrint(
        '[SpaceViewModel] loadCustomRoutes: gates loaded=${_campusGateRepository.isLoaded}, gates=${_campusGateRepository.gates.length}',
      );
    }
    // Load the gate routing policy (preferred + disabled gate ids) from
    // gate_policy.json and apply it to the repository. The policy contains
    // gate IDs only — never coordinates (those come exclusively from the KMZ).
    try {
      final policy = await _campusGateRepository.loadWithPolicy();
      debugPrint(
        '[SpaceViewModel] loadCustomRoutes: gate policy applied '
        'preferred=${policy.preferredGateId}, disabled=${policy.disabledGateIds}',
      );
    } catch (e) {
      debugPrint(
        '[SpaceViewModel] loadCustomRoutes: gate policy load failed '
        '(non-fatal): $e',
      );
    }
    _notify();
  }
}