import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../config/theme.dart';
import '../../data/models/space_model.dart';
import '../../state/location_provider.dart';
import '../../state/space_provider.dart';
import '../widgets/building_marker.dart';
import '../widgets/building_search_sheet.dart';
import '../widgets/map_bottom_sheet.dart';
import '../widgets/map_controls.dart';
import '../widgets/poi_marker.dart';
import '../widgets/user_location_marker.dart';

/// Main Map Screen displaying Anyplace buildings, indoor floorplans, indoor POIs, and device GPS on FlutterMap.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  late final MapController _mapController;
  String? _lastCenteredFloorKey;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Trigger initial loading of spaces and bind location provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final spaceProvider = context.read<SpaceProvider>();
      final locationProvider = context.read<LocationProvider>();
      spaceProvider.setLocationProvider(locationProvider);
      // Spaces are loaded by MainShell. Listen for when they arrive.
      if (spaceProvider.spaces.isEmpty) {
        void listener() {
          if (spaceProvider.spaces.isNotEmpty) {
            spaceProvider.removeListener(listener);
            if (mounted) setState(() {});
          }
        }
        spaceProvider.addListener(listener);
      }
    });
  }

  void _onBuildingTapped(SpaceModel space) {
    final provider = context.read<SpaceProvider>();
    provider.selectSpace(space);
    _animatedMapMove(space.latLng, 16.5);
  }

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
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom + 1.0);
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, currentZoom - 1.0);
  }

  Future<void> _onMyLocationTapped() async {
    final locationProvider = context.read<LocationProvider>();
    final spaceProvider = context.read<SpaceProvider>();

    final userLoc = await locationProvider.requestAndCenter();

    if (!mounted) return;

    if (userLoc != null) {
      _animatedMapMove(userLoc.latLng, MapConfig.focusedZoom);
    } else {
      // Show feedback if permission denied or GPS disabled
      final message = locationProvider.errorMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_off, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AppTheme.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
          ),
        );
      }

      // Fallback: center on selected space or default center
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
          provider.selectSpace(space);
          _animatedMapMove(space.latLng, 16.5);
        },
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpaceProvider, LocationProvider>(
      builder: (context, spaceProvider, locationProvider, _) {
        final selectedSpace = spaceProvider.selectedSpace;
        final userLocation = locationProvider.currentLocation;

        _checkFloorplanCameraCenter(spaceProvider);

        return Scaffold(
          body: Stack(
            children: [
              // 1. FlutterMap Base + Indoor Floorplan Image Overlay + POIs + Markers
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter:
                      selectedSpace?.latLng ??
                      userLocation?.latLng ??
                      SpaceProvider.defaultCenter,
                  initialZoom: MapConfig.defaultZoom,
                  minZoom: MapConfig.minZoom,
                  maxZoom: MapConfig.maxZoom,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onTap: (_, _) {
                    if (spaceProvider.selectedPoi != null) {
                      spaceProvider.clearSelectedPoi();
                    } else if (selectedSpace != null) {
                      spaceProvider.clearSelection();
                    }
                  },
                ),
                children: [
                  // 1. Base CARTO Voyager Layer (English & Arabic map labels)
                  TileLayer(
                    urlTemplate: MapConfig.cartoVoyagerUrlTemplate,
                    subdomains: MapConfig.cartoSubdomains,
                    userAgentPackageName: MapConfig.userAgentPackageName,
                    maxNativeZoom: MapConfig.maxNativeTileZoom.toInt(),
                    maxZoom: MapConfig.maxZoom,
                  ),

                  // 2. Indoor Floorplan Overlay Layer (geographically aligned WGS84 image overlay)
                  if (spaceProvider.hasActiveFloorplan &&
                      spaceProvider.activeFloorplanImagePath != null)
                    OverlayImageLayer(
                      key: ValueKey(
                        'floorplan_${spaceProvider.selectedSpace?.buid}_${spaceProvider.selectedFloor?.floorNumber}',
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

                  // 3. Active Navigation Route Layer
                  if (spaceProvider.hasActiveNavigationRoute)
                    PolylineLayer(
                      key: ValueKey(
                        'route_${spaceProvider.navigationDestinationPuid}_${spaceProvider.selectedFloor?.floorNumber}',
                      ),
                      polylines: [
                        Polyline(
                          points: spaceProvider
                              .activeNavigationRoute!
                              .polylinePoints,
                          strokeWidth: 6,
                          color: AppTheme.primary.withValues(alpha: 0.85),
                          borderStrokeWidth: 2,
                          borderColor: AppTheme.surface,
                        ),
                      ],
                    ),

                  // 4. Building Markers Layer
                  MarkerLayer(
                    markers: spaceProvider.spaces.map((space) {
                      final isSelected = selectedSpace?.buid == space.buid;
                      return Marker(
                        point: space.latLng,
                        width: isSelected ? 48.0 : 38.0,
                        height: isSelected ? 48.0 : 38.0,
                        alignment: Alignment.center,
                        child: BuildingMarker(
                          space: space,
                          isSelected: isSelected,
                          onTap: () => _onBuildingTapped(space),
                        ),
                      );
                    }).toList(),
                  ),

                  // 5. Indoor POI Markers Layer (rendered above floorplan image)
                  if (spaceProvider.hasPois)
                    MarkerLayer(
                      key: ValueKey(
                        'pois_${spaceProvider.selectedSpace?.buid}_${spaceProvider.selectedFloor?.floorNumber}',
                      ),
                      markers: spaceProvider.pois.map((poi) {
                        final isSelectedPoi =
                            spaceProvider.selectedPoi?.puid == poi.puid;
                        return Marker(
                          point: poi.latLng,
                          width: isSelectedPoi ? 65.0 : 60.0,
                          height: isSelectedPoi ? 65.0 : 60.0,
                          alignment: Alignment.topCenter,
                          child: PoiMarker(
                            poi: poi,
                            isSelected: isSelectedPoi,
                            onTap: () {
                              spaceProvider.selectPoi(poi);
                              _animatedMapMove(
                                poi.latLng,
                                _mapController.camera.zoom,
                              );
                            },
                          ),
                        );
                      }).toList(),
                    ),

                  // 6. User Location Marker Layer (ALWAYS top-most!)
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
                            isIndoor: locationProvider.isIndoorWifiActive,
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              // 2. Top Header Bar
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.apartment,
                            color: AppTheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Anyplace',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              Text(
                                spaceProvider.isLoading
                                    ? 'Loading campus spaces...'
                                    : '${spaceProvider.spaces.length} spaces mapped',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          if (locationProvider.isIndoorWifiActive) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.wifi,
                                    size: 12,
                                    color: Color(0xFF0D9488),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Indoor Wi-Fi (${locationProvider.latestIndoorEstimate?.matchedAps ?? 0} APs)',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0D9488),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (spaceProvider.isLoading) ...[
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Map Action Controls (Search, My Location, Zoom In, Zoom Out, Reload)
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
                      onReload: () =>
                          spaceProvider.loadSpaces(forceReload: true),
                      isLoading: spaceProvider.isLoading,
                      isTrackingLocation: locationProvider.isTracking,
                    ),
                  ),
                ),
              ),

              // 4. Draggable Bottom Sheet for Building/POI details
              if (spaceProvider.selectedSpace != null ||
                  spaceProvider.selectedPoi != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MapBottomSheet(
                    key: ValueKey(
                      'sheet_${spaceProvider.selectedSpace?.buid}_${spaceProvider.selectedPoi?.puid}',
                    ),
                  ),
                ),

              // 6. Error Banner (if any)
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
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
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
}
