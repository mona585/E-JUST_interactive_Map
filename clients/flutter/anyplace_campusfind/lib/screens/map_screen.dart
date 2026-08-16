import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide ChangeNotifierProvider;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/constants.dart';
import '../map/config/map_config.dart';
import '../map/config/map_theme.dart';
import '../map/models/floor_model.dart';
import '../map/models/space_model.dart';
import '../map/repositories/space_repository.dart';
import '../map/state/location_provider.dart';
import '../map/state/space_provider.dart';
import '../map/widgets/building_detail_card.dart';
import '../map/widgets/building_marker.dart';
import '../map/widgets/building_search_sheet.dart';
import '../map/widgets/map_controls.dart';
import '../map/widgets/user_location_marker.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/map_view_provider.dart';
import '../providers/providers.dart';
import '../providers/route_provider.dart';
import '../services/cache_service.dart';
import '../utils/category_deriver.dart';

/// Map tab rendered on FlutterMap (ported from the map_refactor branch).
///
/// It consumes the same Anyplace data flow the rest of CampusFind uses:
///   * buildings/floors/POIs from the shared [CacheService] (via the cache-backed
///     [SpaceProvider]) — no duplicate network requests;
///   * the selection model from [mapViewStateProvider] (search + detail screens
///     write to it), synced into the map's [SpaceProvider];
///   * route polylines from [routeStateProvider];
///   * GPS via the map's [LocationProvider].
///
/// [mapSurfaceBuilderProvider] is honored as a test seam: when overridden, the
/// whole surface (including the map providers) is replaced, so widget tests
/// never instantiate FlutterMap or any platform plugin.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapBuilder = ref.watch(mapSurfaceBuilderProvider);
    if (mapBuilder != null) {
      return mapBuilder();
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SpaceProvider>(
          create: (_) => SpaceProvider(
            repository: CacheBackedSpaceRepository(
              cache: ref.read(cacheServiceProvider),
            ),
          ),
        ),
        ChangeNotifierProvider<LocationProvider>(
          create: (_) => LocationProvider(),
        ),
      ],
      child: const MapView(),
    );
  }
}

/// The real FlutterMap surface with the campus data adapter layers.
class MapView extends ConsumerStatefulWidget {
  const MapView({super.key});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> with TickerProviderStateMixin {
  late final MapController _mapController;

  double _zoom = MapConfig.defaultZoom;
  LatLng _cameraCenter = SpaceProvider.defaultCenter;

  /// POI tapped by the user (shown in the bottom card until closed or the
  /// selection/floor changes).
  Poi? _selectedPoi;

  /// Identity of the last cache spaces list we loaded into the SpaceProvider.
  List<Space>? _lastCacheSpaces;

  /// True while a focus request is being applied so the selection-change
  /// listener does not fight the focus camera move.
  bool _suppressSelectionCamera = false;

  /// Tracks the floor we already centered on, so we only animate once per floor.
  String? _lastCenteredFloorKey;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SpaceProvider>().loadSpaces();
      context.read<LocationProvider>().requestAndCenter();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // ---- Selection reconciliation ------------------------------------------

  /// Keeps [mapViewStateProvider] and the map [SpaceProvider] in sync in a
  /// convergent, idempotent way. Each step returns early after making a change
  /// so the next build (triggered by the notifier) continues where we left off.
  void _reconcileSelections(SpaceProvider spaceProvider) {
    final cache = ref.read(cacheServiceProvider);
    final mapState = ref.read(mapViewStateProvider);
    final notifier = ref.read(mapViewStateProvider.notifier);

    // A. floor mirror (SpaceProvider -> mapViewState), covers the floor chips
    //    inside BuildingDetailCard which call SpaceProvider directly.
    if (spaceProvider.selectedFloor != null) {
      if (mapState.selectedFloor?.floorNumber !=
          spaceProvider.selectedFloor!.floorNumber) {
        notifier.selectFloor(_floorFromModel(spaceProvider.selectedFloor!));
        return;
      }
    }

    // B. space mirror (SpaceProvider -> mapViewState), covers the card close
    //    button / map tap that clear the SpaceProvider selection.
    if (spaceProvider.selectedSpace != null) {
      if (mapState.selectedSpace?.buid != spaceProvider.selectedSpace!.buid) {
        final s = cache.spaceByBuid(spaceProvider.selectedSpace!.buid);
        if (s != null) {
          notifier.selectSpace(s);
          return;
        }
      }
    } else if (mapState.selectedSpace != null) {
      notifier.clearSelection();
      return;
    }

    // C. mapViewState -> SpaceProvider (external selection from search/detail).
    if (mapState.selectedSpace != null) {
      if (spaceProvider.selectedSpace?.buid != mapState.selectedSpace!.buid) {
        spaceProvider.selectSpaceByBuid(mapState.selectedSpace!.buid);
        return;
      }
    } else if (spaceProvider.selectedSpace != null) {
      spaceProvider.clearSelection();
      return;
    }

    // D. auto-select the first known floor once a building is selected.
    if (spaceProvider.selectedSpace != null &&
        mapState.selectedFloor == null) {
      final floors = cache.floorsOf(spaceProvider.selectedSpace!.buid);
      if (floors.isNotEmpty) {
        notifier.selectFloor(floors.first);
        return;
      }
    }

    // E. mapViewState floor -> SpaceProvider.
    final wantedFloor = mapState.selectedFloor;
    if (wantedFloor != null) {
      if (spaceProvider.selectedFloor?.floorNumber != wantedFloor.floorNumber) {
        spaceProvider.selectFloor(_floorModelFor(spaceProvider, wantedFloor));
      }
    } else if (spaceProvider.selectedFloor != null) {
      spaceProvider.clearFloorSelection();
    }
  }

  /// Reloads the map's spaces whenever the cache dataset is replaced.
  void _reconcileCache(SpaceProvider spaceProvider, CacheService cache) {
    final spaces = cache.spaces;
    if (!identical(_lastCacheSpaces, spaces)) {
      _lastCacheSpaces = spaces;
      spaceProvider.loadSpaces();
    }
  }

  FloorModel _floorModelFor(SpaceProvider spaceProvider, Floor floor) {
    for (final m in spaceProvider.floors) {
      if (m.floorNumber == floor.floorNumber) return m;
    }
    return FloorModel(
      buid: floor.buid,
      floorNumber: floor.floorNumber,
      floorName: floor.floorName ?? '',
      description: floor.description ?? '',
      fuid: floor.fuid,
      isPublished: floor.isPublished != 'false',
      bottomLeftLat: floor.bottomLeftLat,
      bottomLeftLng: floor.bottomLeftLng,
      topRightLat: floor.topRightLat,
      topRightLng: floor.topRightLng,
    );
  }

  Floor _floorFromModel(FloorModel model) {
    return Floor(
      buid: model.buid,
      floorNumber: model.floorNumber,
      floorName: model.floorName.isNotEmpty ? model.floorName : null,
      description: model.description.isEmpty ? null : model.description,
      fuid: model.fuid,
      isPublished: model.isPublished ? 'true' : 'false',
    );
  }

  // ---- Focus request (search results) -------------------------------------

  void _applyFocusRequest(MapFocusRequest request) {
    final cache = ref.read(cacheServiceProvider);
    final space = cache.spaceByBuid(request.buid);
    final notifier = ref.read(mapViewStateProvider.notifier);

    if (space == null) {
      ref.read(mapFocusRequestProvider.notifier).state = null;
      return;
    }

    debugPrint(
      '[map] focus: ${space.name} (${space.buid}) '
      'floor=${request.floorNumber} poi=${request.poi?.name}',
    );

    _suppressSelectionCamera = true;
    setState(() => _selectedPoi = null);
    notifier.selectSpace(space);

    final floorNumber = request.floorNumber;
    if (floorNumber != null) {
      Floor? floor;
      for (final f in cache.floorsOf(space.buid)) {
        if (f.floorNumber == floorNumber) {
          floor = f;
          break;
        }
      }
      floor ??= Floor(
        buid: space.buid,
        floorNumber: floorNumber,
        fuid: '${space.buid}_$floorNumber',
      );
      notifier.selectFloor(floor);
    }
    _suppressSelectionCamera = false;

    final poi = request.poi;
    if (poi != null) {
      setState(() => _selectedPoi = poi);
      _animatedMapMove(
        LatLng(poi.coordinatesLat, poi.coordinatesLon),
        _zoom < AppConstants.indoorZoomThreshold
            ? AppConstants.indoorZoomThreshold.toDouble()
            : _zoom,
      );
    } else {
      _animatedMapMove(
        LatLng(space.coordinatesLat, space.coordinatesLon),
        request.floorNumber != null
            ? MapConfig.indoorFloorplanZoom
            : MapConfig.focusedZoom,
      );
    }

    ref.read(mapFocusRequestProvider.notifier).state = null;
  }

  // ---- Camera -------------------------------------------------------------

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final latTween = Tween<double>(
      begin: _mapController.camera.center.latitude,
      end: destLocation.latitude,
    );
    final lngTween = Tween<double>(
      begin: _mapController.camera.center.longitude,
      end: destLocation.longitude,
    );
    final zoomTween = Tween<double>(
      begin: _mapController.camera.zoom,
      end: destZoom,
    );

    final controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );

    controller.addListener(() {
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void _zoomIn() {
    _animatedMapMove(_mapController.camera.center, _mapController.camera.zoom + 1.0);
  }

  void _zoomOut() {
    _animatedMapMove(_mapController.camera.center, _mapController.camera.zoom - 1.0);
  }

  Future<void> _onMyLocationTapped() async {
    final locationProvider = context.read<LocationProvider>();
    final spaceProvider = context.read<SpaceProvider>();

    final userLoc = await locationProvider.requestAndCenter();

    if (!mounted) return;

    if (userLoc != null) {
      _animatedMapMove(userLoc.latLng, MapConfig.focusedZoom);
    } else {
      final message = locationProvider.errorMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: const Color(0xE61E293B),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: Color(0x33FFFFFF)),
            ),
          ),
        );
      }

      if (spaceProvider.selectedSpace != null) {
        _animatedMapMove(spaceProvider.selectedSpace!.latLng, 16.5);
      } else if (spaceProvider.spaces.isNotEmpty) {
        _animatedMapMove(spaceProvider.spaces.first.latLng, 15.0);
      } else {
        _animatedMapMove(SpaceProvider.defaultCenter, MapConfig.defaultZoom);
      }
    }
  }

  void _openSearchSheet() {
    final provider = context.read<SpaceProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BuildingSearchSheet(
        spaces: provider.spaces,
        selectedSpace: provider.selectedSpace,
        onSelect: (space) {
          setState(() => _selectedPoi = null);
          provider.selectSpace(space);
          _animatedMapMove(space.latLng, 16.5);
        },
      ),
    );
  }

  void _onBuildingTapped(SpaceModel model) {
    setState(() => _selectedPoi = null);
    final s = ref.read(cacheServiceProvider).spaceByBuid(model.buid);
    if (s != null) {
      ref.read(mapViewStateProvider.notifier).selectSpace(s);
    }
  }

  void _checkFloorplanCameraCenter(SpaceProvider spaceProvider) {
    if (spaceProvider.hasActiveFloorplan &&
        spaceProvider.selectedSpace != null &&
        spaceProvider.selectedFloor != null) {
      final key =
          '${spaceProvider.selectedSpace!.buid}_${spaceProvider.selectedFloor!.floorNumber}';
      if (_lastCenteredFloorKey != key) {
        _lastCenteredFloorKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _mapController.camera.zoom < 18.0) {
            _animatedMapMove(
              spaceProvider.activeFloorplan?.center ??
                  spaceProvider.selectedSpace!.latLng,
              MapConfig.indoorFloorplanZoom,
            );
          }
        });
      }
    } else if (spaceProvider.selectedFloor == null) {
      _lastCenteredFloorKey = null;
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is MapEventMove || event is MapEventMoveEnd) {
      _zoom = event.camera.zoom;
      _cameraCenter = event.camera.center;
      if (event is MapEventMoveEnd) {
        setState(() {});
      }
    }
  }

  // ---- Data derived helpers ---------------------------------------------

  List<Poi> _filteredPois(
    List<Poi> pois,
    EntityCategory? category, {
    String? floorNumber,
  }) {
    if (floorNumber != null) {
      pois = pois.where((p) => p.floorNumber == floorNumber).toList();
    }
    if (category == null) return pois;
    return pois
        .where((p) => CategoryDeriver.derivePoi(p) == category)
        .toList();
  }

  /// Buildings near the current camera — keeps the marker set small while the
  /// dataset is large (the public server returns thousands of buildings).
  List<SpaceModel> _spacesInView(List<SpaceModel> spaces) {
    if (spaces.length <= 250) return spaces;

    final world = 256.0 * math.pow(2.0, _zoom).toDouble();
    final lonPerPx = 360.0 / world;
    final cosLat = math
        .cos(_cameraCenter.latitude * math.pi / 180)
        .clamp(0.05, 1.0)
        .toDouble();

    const viewportWidth = 760.0;
    const viewportHeight = 1520.0;
    const margin = 1.6;

    final dLon = lonPerPx * (viewportWidth / 2) * margin;
    final dLat = (lonPerPx * cosLat * (viewportHeight / 2) * margin)
        .clamp(0.25, 85.0);

    return [
      for (final s in spaces)
        if ((s.latitude - _cameraCenter.latitude).abs() <= dLat &&
            (s.longitude - _cameraCenter.longitude).abs() <= dLon)
          s,
    ];
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheServiceProvider);
    final mapState = ref.watch(mapViewStateProvider);
    final route = ref.watch(routeStateProvider);
    final focusRequest = ref.watch(mapFocusRequestProvider);

    ref.listen(mapViewStateProvider, _onMapViewSelectionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final spaceProvider = context.read<SpaceProvider>();
      _reconcileCache(spaceProvider, cache);
      _reconcileSelections(spaceProvider);
      if (focusRequest != null) {
        _applyFocusRequest(focusRequest);
      }
    });

    return Consumer2<SpaceProvider, LocationProvider>(
      builder: (context, spaceProvider, locationProvider, _) {
        final selectedSpace = spaceProvider.selectedSpace;
        final userLocation = locationProvider.currentLocation;

        // ---- Resolve the active floor for indoor content ----
        final selectedSpaceBuid = mapState.selectedSpace?.buid;
        final knownFloors = selectedSpaceBuid == null
            ? const <Floor>[]
            : cache.floorsOf(selectedSpaceBuid);

        final String? activeFloorNumber =
            mapState.selectedFloor?.floorNumber ??
                (knownFloors.isNotEmpty ? knownFloors.first.floorNumber : null);

        final pois = (selectedSpaceBuid != null &&
                activeFloorNumber != null &&
                _zoom >= AppConstants.indoorZoomThreshold)
            ? _filteredPois(
                cache.poisOf(selectedSpaceBuid),
                mapState.poiCategory,
                floorNumber: activeFloorNumber,
              )
            : const <Poi>[];

        final showIndoor = selectedSpaceBuid != null &&
            activeFloorNumber != null &&
            _zoom >= AppConstants.indoorZoomThreshold;

        final selectedPoi = (_selectedPoi != null &&
                showIndoor &&
                _selectedPoi!.floorNumber == activeFloorNumber)
            ? _selectedPoi
            : null;

        _checkFloorplanCameraCenter(spaceProvider);

        final buildingMarkers = _buildingMarkers(
          spaceProvider.spaces,
          selectedBuid: selectedSpace?.buid,
        );

        final routePolylines = _routePolylines(route, activeFloorNumber);

        return Scaffold(
          body: Stack(
            children: [
              // 1. FlutterMap Base + Indoor Floorplan Overlay + Markers
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: selectedSpace?.latLng ??
                      userLocation?.latLng ??
                      SpaceProvider.defaultCenter,
                  initialZoom: MapConfig.defaultZoom,
                  minZoom: MapConfig.minZoom,
                  maxZoom: MapConfig.maxZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onMapEvent: _onMapEvent,
                  onTap: (_, _) {
                    if (ref.read(mapViewStateProvider).selectedSpace != null) {
                      ref.read(mapViewStateProvider.notifier).clearSelection();
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: MapConfig.cartoVoyagerUrlTemplate,
                    subdomains: MapConfig.cartoSubdomains,
                    userAgentPackageName: MapConfig.userAgentPackageName,
                    maxNativeZoom: MapConfig.maxNativeTileZoom.toInt(),
                    maxZoom: MapConfig.maxZoom,
                  ),

                  if (spaceProvider.hasActiveFloorplan &&
                      spaceProvider.activeFloorplanImagePath != null)
                    OverlayImageLayer(
                      key: ValueKey(
                        'floorplan_${selectedSpace?.buid}_${spaceProvider.selectedFloor?.floorNumber}',
                      ),
                      overlayImages: [
                        OverlayImage(
                          bounds: spaceProvider.activeFloorplan!.bounds,
                          imageProvider: FileImage(
                            File(spaceProvider.activeFloorplanImagePath!),
                          ),
                          opacity: 1.0,
                        ),
                      ],
                    ),

                  MarkerLayer(
                    markers: buildingMarkers,
                  ),

                  if (showIndoor)
                    MarkerLayer(
                      markers: _poiMarkers(pois),
                    ),

                  if (userLocation != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: userLocation.latLng,
                          width: 48.0,
                          height: 48.0,
                          alignment: Alignment.center,
                          child: UserLocationMarker(
                            key: const Key('user_location_marker'),
                            location: userLocation,
                          ),
                        ),
                      ],
                    ),

                  if (routePolylines.isNotEmpty)
                    PolylineLayer(
                      polylines: routePolylines,
                    ),
                ],
              ),

              // 2. Top Header Bar
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: _HeaderChip(
                    isLoading: spaceProvider.isLoading,
                    buildingCount: spaceProvider.spaces.length,
                  ),
                ),
              ),

              // 3. Map Action Controls
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MapControls(
                      onSearch: _openSearchSheet,
                      onRecenter: _onMyLocationTapped,
                      onZoomIn: _zoomIn,
                      onZoomOut: _zoomOut,
                      onReload: () => ref.invalidate(bulkLoadProvider),
                      isLoading: spaceProvider.isLoading,
                      isTrackingLocation: locationProvider.isTracking,
                    ),
                  ),
                ),
              ),

              // 4. Selected POI card
              if (selectedPoi != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: selectedSpace != null ? 160 : 12,
                  child: SafeArea(
                    top: false,
                    child: _PoiCard(
                      poi: selectedPoi,
                      onClose: () => setState(() => _selectedPoi = null),
                    ),
                  ),
                ),

              // 5. Selected Building Detail Card
              if (selectedSpace != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: SafeArea(
                    top: false,
                    child: BuildingDetailCard(
                      space: selectedSpace,
                      onClose: () => spaceProvider.clearSelection(),
                      onFocus: () {
                        final zoom = spaceProvider.hasActiveFloorplan
                            ? MapConfig.indoorFloorplanZoom
                            : MapConfig.focusedZoom;
                        _animatedMapMove(
                          spaceProvider.activeFloorplan?.center ??
                              selectedSpace.latLng,
                          zoom,
                        );
                      },
                    ),
                  ),
                ),

              // 6. Error Banner
              if (spaceProvider.hasError && selectedSpace == null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE6DC2626),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              spaceProvider.errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => spaceProvider.loadSpaces(),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Moves the camera when the selection changes (building tap, floor switch,
  /// or an external focus from the search/detail features).
  void _onMapViewSelectionChanged(MapViewState? prev, MapViewState? next) {
    if (_suppressSelectionCamera) return;

    final prevSpace = prev?.selectedSpace?.buid;
    final nextSpace = next?.selectedSpace?.buid;
    final prevFloor = prev?.selectedFloor?.floorNumber;
    final nextFloor = next?.selectedFloor?.floorNumber;

    if (prevSpace == nextSpace && prevFloor == nextFloor) return;
    if (nextSpace == null) return;

    final cache = ref.read(cacheServiceProvider);
    final space = cache.spaceByBuid(nextSpace);
    if (space == null) return;

    final target = LatLng(space.coordinatesLat, space.coordinatesLon);

    if (prevSpace != nextSpace) {
      _animatedMapMove(target, MapConfig.focusedZoom);
    } else if (prevFloor != null && nextFloor != null) {
      // Explicit floor switch (auto-selection keeps the building-level zoom).
      _animatedMapMove(target, MapConfig.indoorFloorplanZoom);
    }
  }

  // ---- Marker / polyline builders -----------------------------------------

  List<Marker> _buildingMarkers(
    List<SpaceModel> spaces, {
    required String? selectedBuid,
  }) {
    final visible = _spacesInView(spaces);

    return [
      for (final space in visible)
        Marker(
          point: space.latLng,
          width: space.buid == selectedBuid ? 48.0 : 38.0,
          height: space.buid == selectedBuid ? 48.0 : 38.0,
          alignment: Alignment.center,
          child: BuildingMarker(
            space: space,
            isSelected: space.buid == selectedBuid,
            onTap: () => _onBuildingTapped(space),
          ),
        ),
    ];
  }

  List<Marker> _poiMarkers(List<Poi> pois) {
    return [
      for (final poi in pois)
        Marker(
          point: LatLng(poi.coordinatesLat, poi.coordinatesLon),
          width: 30.0,
          height: 30.0,
          alignment: Alignment.center,
          child: _PoiMarkerDot(
            poi: poi,
            onTap: () {
              debugPrint('[map] poi tapped: ${poi.name} '
                  '(floor=${poi.floorNumber})');
              setState(() => _selectedPoi = poi);
            },
          ),
        ),
    ];
  }

  List<Polyline> _routePolylines(RouteState route, String? activeFloorNumber) {
    final polylines = <Polyline>[];

    if (route.hasOutdoor) {
      polylines.add(
        Polyline(
          points: route.outdoorPoints,
          color: const Color(0xFF1976D2),
          strokeWidth: 5,
        ),
      );
    }

    final indoor = activeFloorNumber == null
        ? null
        : route.indoorPointsByFloor[activeFloorNumber];

    if (indoor != null && indoor.length >= 2) {
      polylines.add(
        Polyline(
          points: [for (final p in indoor) LatLng(p.lat, p.lon)],
          color: const Color(0xFFD32F2F),
          strokeWidth: 4,
        ),
      );
    }

    return polylines;
  }
}

// ---- Overlay widgets -----------------------------------------------------

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.isLoading, required this.buildingCount});

  final bool isLoading;
  final int buildingCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xE60F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x33FFFFFF)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apartment, color: MapTheme.primaryLight, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CampusFind',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: MapTheme.textPrimary,
                  ),
                ),
                Text(
                  isLoading
                      ? 'Loading campus spaces...'
                      : '$buildingCount buildings',
                  style: const TextStyle(fontSize: 11, color: MapTheme.textSecondary),
                ),
              ],
            ),
            if (isLoading) ...[
              const SizedBox(width: 12),
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MapTheme.primaryLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PoiMarkerDot extends StatelessWidget {
  const _PoiMarkerDot({required this.poi, required this.onTap});

  final Poi poi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = CategoryDeriver.derivePoi(poi);

    return GestureDetector(
      key: Key('poi_tap_${poi.puid}'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: category.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(category.icon, size: 13, color: Colors.white),
      ),
    );
  }
}

class _PoiCard extends StatelessWidget {
  const _PoiCard({required this.poi, required this.onClose});

  final Poi poi;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final category = CategoryDeriver.derivePoi(poi);

    return Material(
      color: MapTheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MapTheme.surfaceLight),
        ),
        child: Row(
          children: [
            Icon(category.icon, color: category.color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: MapTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      category.label,
                      if (poi.poisType != null && poi.poisType!.isNotEmpty)
                        poi.poisType,
                      if (poi.floorName != null && poi.floorName!.isNotEmpty)
                        'Floor ${poi.floorName}'
                      else
                        'Floor ${poi.floorNumber}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MapTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}