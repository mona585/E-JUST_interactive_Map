import 'dart:io';
import 'dart:math' show cos, pi;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../config/navigation_config.dart';
import '../../config/theme.dart';
import '../../data/models/route_segment.dart';
import '../../data/models/space_model.dart';
import '../../state/location_provider.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../widgets/building_search_sheet.dart';
import '../widgets/map_bottom_sheet.dart';
import '../widgets/map_controls.dart';

/// Main Map Screen displaying Anyplace buildings, indoor floorplans, indoor POIs, and device GPS on Google Maps.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _lastCenteredFloorKey;
  bool _lastFollowMode = false;
  bool _hasInitialCentering = false;

  // Marker icon caches (generated once from widget screenshots)
  BitmapDescriptor? _buildingIcon;
  BitmapDescriptor? _buildingSelectedIcon;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Generate marker icons from widgets
    _generateMarkerIcons();

    // Trigger initial loading of spaces and bind location provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final spaceProvider = context.read<SpaceProvider>();
      final locationProvider = context.read<LocationProvider>();
      spaceProvider.setLocationProvider(locationProvider);

      // Start GPS tracking and auto-center on first valid location.
      // requestAndCenter handles permission request + initial fix + starts tracking.
      locationProvider.addListener(_checkInitialCentering);
      locationProvider.requestAndCenter();

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

      // Listen for NavigationController changes to follow user position
      final navController = context.read<NavigationController>();
      navController.addListener(_onNavigationChanged);
    });
  }

  Future<void> _generateMarkerIcons() async {
    // Generate building marker icons using default Google Maps marker with custom hue
    _buildingIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    _buildingSelectedIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
  }

  /// Connector POIs (elevators, stairs, or `pois_type == "None"`) are hidden
  /// from the map but remain in the data/navigation layers for floor-transition
  /// detection and routing.
  static bool _isConnectorPoi(String poisType, String name) {
    final t = poisType.toLowerCase();
    return t == 'none' || t.contains('elevator') ||
        t.contains('stairs') || t.contains('staircase');
  }

  /// One-time listener that centers the map on the user's first valid location.
  void _checkInitialCentering() {
    if (_hasInitialCentering) return;
    final location = context.read<LocationProvider>().currentLocation;
    if (location != null && _mapController != null) {
      debugPrint('[MapScreen] Auto-centering on ${location.latitude},${location.longitude}');
      _hasInitialCentering = true;
      context.read<LocationProvider>().removeListener(_checkInitialCentering);
      _animatedMapMove(location.latLng, MapConfig.defaultZoom);
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _mapController = null;
    WidgetsBinding.instance.removeObserver(this);
    try {
      context.read<LocationProvider>().removeListener(_checkInitialCentering);
    } catch (_) {}
    try {
      final navController = context.read<NavigationController>();
      navController.removeListener(_onNavigationChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nav = context.read<NavigationController>();
    if (!nav.isActive) return;

    if (state == AppLifecycleState.paused) {
      debugPrint('[MapScreen] App paused ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â navigation continues');
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[MapScreen] App resumed ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â still navigating');
      // Re-center camera on user position after resume
      final location = context.read<LocationProvider>().currentLocation;
      if (location != null && nav.followMode) {
        _followUserPosition(location.latLng, nav.subState);
      }
    }
  }

  void _onNavigationChanged() {
    if (!mounted) return;
    final nav = context.read<NavigationController>();
    final locationProvider = context.read<LocationProvider>();
    final location = locationProvider.currentLocation;

    if (nav.isActive && nav.followMode && location != null) {
      _followUserPosition(location.latLng, nav.subState);
    }

    // Detect follow mode turning on (e.g. re-center tap)
    if (nav.followMode && !_lastFollowMode && location != null) {
      _followUserPosition(location.latLng, nav.subState);
    }
    _lastFollowMode = nav.followMode;
  }

  void _followUserPosition(LatLng userPosition, NavigationSubState subState) {
    if (!mounted || _mapController == null) return;
    final targetZoom = subState == NavigationSubState.indoor
        ? NavigationConfig.indoorFollowZoom
        : NavigationConfig.outdoorFollowZoom;

    // Lower-third positioning
    final screenHeight = MediaQuery.of(context).size.height;
    final latOffset = (screenHeight * (1.0 - NavigationConfig.followLowerThirdFraction)) * 0.000008;

    _animatedMapMove(
      LatLng(userPosition.latitude - latOffset, userPosition.longitude),
      targetZoom,
    );
  }

  void _onBuildingTapped(SpaceModel space) {
    final provider = context.read<SpaceProvider>();
    provider.selectSpace(space);
    _animatedMapMove(space.latLng, 16.5);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    if (_mapController == null) return;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: destLocation,
          zoom: destZoom,
        ),
      ),
    );
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
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
          if (mounted && _mapController != null) {
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

  /// Fits the camera to frame the full active navigation route with padding.
  void _fitRouteBounds(SpaceProvider spaceProvider) {
    final route = spaceProvider.activeNavigationRoute;
    if (route == null || route.polylinePoints.isEmpty) return;

    // Compute bounds from polyline points
    double minLat = route.polylinePoints.first.latitude;
    double maxLat = route.polylinePoints.first.latitude;
    double minLng = route.polylinePoints.first.longitude;
    double maxLng = route.polylinePoints.first.longitude;
    for (final point in route.polylinePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Apply padding to the bounds
    final paddingMeters = NavigationConfig.routeFramePadding;
    final latPad = paddingMeters / 111320.0;
    final centerLat = (minLat + maxLat) / 2.0;
    final lngPad = paddingMeters / (111320.0 * cos(centerLat * pi / 180));

    final paddedBounds = LatLngBounds(
      southwest: LatLng(minLat - latPad, minLng - lngPad),
      northeast: LatLng(maxLat + latPad, maxLng + lngPad),
    );

    final center = LatLng(
      (paddedBounds.southwest.latitude + paddedBounds.northeast.latitude) / 2.0,
      (paddedBounds.southwest.longitude + paddedBounds.northeast.longitude) / 2.0,
    );
    final latSpan = paddedBounds.northeast.latitude - paddedBounds.southwest.latitude;
    final lngSpan = paddedBounds.northeast.longitude - paddedBounds.southwest.longitude;

    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
    final estimatedZoom = (19.0 - (maxSpan * 100).clamp(0.0, 15.0)).clamp(
      MapConfig.indoorFloorplanZoom,
      19.0,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animatedMapMove(center, estimatedZoom);
    });
  }

  /// Build markers for the map
  Set<Marker> _buildMarkers(SpaceProvider spaceProvider, LocationProvider locationProvider, SpaceModel? selectedSpace) {
    final markers = <Marker>{};

    // Building markers
    for (final space in spaceProvider.spaces) {
      final isSelected = selectedSpace?.buid == space.buid;
      markers.add(Marker(
        markerId: MarkerId(space.buid),
        position: space.latLng,
        icon: isSelected ? (_buildingSelectedIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow)) : (_buildingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
        infoWindow: InfoWindow(
          title: space.name,
          snippet: space.spaceType,
          onTap: () => _onBuildingTapped(space),
        ),
        onTap: () => _onBuildingTapped(space),
      ));
    }

    // Indoor POI markers (connectors hidden — see _isConnectorPoi)
    if (spaceProvider.hasPois) {
      for (final poi in spaceProvider.pois) {
        if (_isConnectorPoi(poi.poisType, poi.name)) continue;
        markers.add(Marker(
          markerId: MarkerId(poi.puid),
          position: poi.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(
            title: poi.name,
            snippet: poi.poisType,
          ),
          onTap: () {
            spaceProvider.selectPoi(poi);
            _animatedMapMove(poi.latLng, _mapController != null ? 18.0 : MapConfig.defaultZoom);
          },
        ));
      }
    }

    // User location marker (using default blue dot)
    // Note: Custom UserLocationMarker with animation will be added as overlay in Phase 4
    if (locationProvider.currentLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('user_location'),
        position: locationProvider.currentLocation!.latLng,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ));
    }

    return markers;
  }

  /// Build polylines for navigation routes
  Set<Polyline> _buildPolylines(SpaceProvider spaceProvider) {
    final polylines = <Polyline>{};
    final route = spaceProvider.activeNavigationRoute;
    if (route == null) return polylines;

    // Segment-based rendering (cross-building navigation)
    if (route.hasSegments) {
      for (var i = 0; i < route.segments.length; i++) {
        final seg = route.segments[i];
        if (seg.isEmpty) continue;

        final style = _segmentStyles[seg.type];
        if (style != null) {
          polylines.add(Polyline(
            polylineId: PolylineId('route_segment_$i'),
            points: seg.points,
            width: style.width,
            color: style.color,
            patterns: style.patterns ?? [],
          ));
        }
      }
      return polylines;
    }

    // Legacy rendering (non-segment routes)
    // Outdoor segment (dotted blue)
    if (route.hasOutdoorSegment) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route_outdoor'),
        points: route.outdoorPolylinePoints,
        width: 5,
        color: const Color(0xFF1E88E5).withValues(alpha: 0.9),
        patterns: [PatternItem.dot, PatternItem.gap(10)],
      ));
    }

    // Indoor segment (solid red)
    if (route.hasIndoorSegment) {
      polylines.add(Polyline(
        polylineId: const PolylineId('route_indoor'),
        points: route.indoorPolylinePoints,
        width: 6,
        color: AppTheme.primary.withValues(alpha: 0.85),
      ));
    }

    return polylines;
  }

  /// Segment type → polyline style mapping.
  static final Map<RouteSegmentType, _SegmentStyle> _segmentStyles = {
    RouteSegmentType.outdoorWalking: _SegmentStyle(
      color: Color(0xFF1E88E5).withValues(alpha: 0.9),
      width: 5,
      patterns: [PatternItem.dot, PatternItem.gap(10)],
    ),
    RouteSegmentType.indoorRouting: _SegmentStyle(
      color: AppTheme.primary.withValues(alpha: 0.85),
      width: 6,
    ),
    RouteSegmentType.exitTransition: _SegmentStyle(
      color: Color(0xFFFF9800).withValues(alpha: 0.85),
      width: 5,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    ),
    RouteSegmentType.entranceTransition: _SegmentStyle(
      color: Color(0xFF4CAF50).withValues(alpha: 0.85),
      width: 5,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    ),
    RouteSegmentType.floorTransition: _SegmentStyle(
      color: Color(0xFF9C27B0).withValues(alpha: 0.85),
      width: 4,
      patterns: [PatternItem.dot, PatternItem.gap(8)],
    ),
  };

  /// Build ground overlays for floorplan images
  Set<GroundOverlay> _buildGroundOverlays(SpaceProvider spaceProvider) {
    final overlays = <GroundOverlay>{};
    if (!spaceProvider.hasActiveFloorplan || spaceProvider.activeFloorplanImagePath == null) {
      return overlays;
    }

    final floorplan = spaceProvider.activeFloorplan!;
    final imageBytes = File(spaceProvider.activeFloorplanImagePath!).readAsBytesSync();

    overlays.add(GroundOverlay.fromBounds(
      groundOverlayId: GroundOverlayId(
        'floorplan_${floorplan.buid}_${floorplan.floorNumber}',
      ),
      image: BitmapDescriptor.bytes(imageBytes, bitmapScaling: MapBitmapScaling.none),
      bounds: floorplan.bounds,
      transparency: 0.0,
    ));

    return overlays;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpaceProvider, LocationProvider>(
      builder: (context, spaceProvider, locationProvider, _) {
        final selectedSpace = spaceProvider.selectedSpace;
        final userLocation = locationProvider.currentLocation;

        _checkFloorplanCameraCenter(spaceProvider);

        // Initial camera position
        final initialTarget = selectedSpace?.latLng ??
            userLocation?.latLng ??
            SpaceProvider.defaultCenter;

        return Scaffold(
          body: Stack(
            children: [
              // 1. Google Map
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: MapConfig.defaultZoom,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  // If location was already acquired before map creation, center now
                  _checkInitialCentering();
                },
                onTap: (LatLng latLng) {
                  if (spaceProvider.selectedPoi != null) {
                    spaceProvider.clearSelectedPoi();
                  } else if (selectedSpace != null) {
                    spaceProvider.clearSelection();
                  }
                },
                onCameraMove: (CameraPosition position) {
                  final nav = context.read<NavigationController>();
                  if (nav.isActive && nav.followMode) {
                    // Don't exit follow mode during programmatic moves
                  }
                },
                onCameraIdle: () {
                  // Camera movement complete
                },
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                mapToolbarEnabled: false,
                
                
                markers: _buildMarkers(spaceProvider, locationProvider, selectedSpace),
                polylines: _buildPolylines(spaceProvider),
                groundOverlays: _buildGroundOverlays(spaceProvider),
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
                              GestureDetector(
                                onTap: spaceProvider.errorMessage != null &&
                                        spaceProvider.spaces.isEmpty &&
                                        !spaceProvider.isLoading
                                    ? () => spaceProvider.loadSpaces(forceReload: true)
                                    : null,
                                child: Text(
                                  spaceProvider.isLoading
                                      ? 'Loading campus spaces...'
                                      : spaceProvider.errorMessage != null &&
                                              spaceProvider.spaces.isEmpty
                                          ? 'No connection ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â tap to retry'
                                          : '${spaceProvider.spaces.length} spaces mapped',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: spaceProvider.errorMessage != null &&
                                            spaceProvider.spaces.isEmpty
                                        ? const Color(0xFFDC2626)
                                        : AppTheme.textSecondary,
                                  ),
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
                      onRecenter: () {
                        final nav = context.read<NavigationController>();
                        if (nav.isActive) {
                          nav.resumeFollowMode();
                        }
                        _onMyLocationTapped();
                      },
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
                    onFitRouteBounds: _fitRouteBounds,
                  ),
                ),

              // 5. Navigation Status Bar (during active navigation)
              if (context.select<NavigationController, bool>(
                (nav) => nav.isActive,
              ))
                Positioned(
                  left: 16,
                  right: 76,
                  bottom: 24,
                  child: Consumer<NavigationController>(
                    builder: (context, nav, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
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
                          children: [
                            Icon(
                              nav.subState == NavigationSubState.indoor
                                  ? Icons.wifi
                                  : nav.subState == NavigationSubState.transitioning
                                      ? Icons.swap_vert
                                      : Icons.gps_fixed,
                              size: 16,
                              color: nav.subState == NavigationSubState.indoor
                                  ? const Color(0xFF0D9488)
                                  : nav.subState == NavigationSubState.transitioning
                                      ? const Color(0xFFF59E0B)
                                      : AppTheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                   Text(
                                    nav.positioningStatus,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  if (nav.isRerouting)
                                    const Text(
                                      'Recalculating route...',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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

/// Polyline style for a route segment.
class _SegmentStyle {
  final Color color;
  final int width;
  final List<PatternItem>? patterns;

  const _SegmentStyle({
    required this.color,
    required this.width,
    this.patterns,
  });
}