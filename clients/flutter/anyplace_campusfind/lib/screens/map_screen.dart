import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/floorplan_provider.dart';
import '../providers/map_view_provider.dart';
import '../providers/position_provider.dart';
import '../providers/providers.dart';
import '../providers/route_provider.dart';
import '../utils/category_deriver.dart';
import '../widgets/google_floorplan_tile_provider.dart';

/// Map tab rendered on the Google Maps SDK, feeding it the same Anyplace data
/// flow that was verified end-to-end on the real backend:
///   * buildings (from `space/public` via the bulk cache) as markers/clusters
///   * floors (from `floor/all`, else the Floor-0 probe) via the bottom card
///   * floorplan tiles (from `floortiles/zip`, extracted locally) as a TileOverlay
///   * POI markers, route polylines and the device-position marker
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Cyprus / UCY — the primary campus. Opening here keeps the map useful
  /// even though `space/public` also returns global buildings.
  static const _ucyCenter = gm.LatLng(35.1444, 33.4105);

  static const _minZoom = 3.0;
  static const _maxZoom = 21.0;
  static const _defaultZoom = 14.0;

  gm.GoogleMapController? _mapController;
  double _zoom = _defaultZoom;
  gm.LatLng _cameraCenter = _ucyCenter;
  bool _didAutoCenterOnUser = false;

  /// Pending camera target applied as soon as the map controller exists
  /// (the map may not be created yet when a focus request arrives).
  gm.LatLng? _pendingCameraTarget;
  double? _pendingCameraZoom;

  /// POI tapped by the user (shown in the bottom info card until closed or
  /// the selection/floor changes).
  Poi? _selectedPoi;

  /// Marker icons keyed by category/role, built off the platform thread once.
  Map<String, gm.BitmapDescriptor>? _icons;

  @override
  void initState() {
    super.initState();
    _prepareIcons();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when floors/POIs arrive after the bulk load.
    ref.watch(cacheVersionProvider);
    final bulkLoad = ref.watch(bulkLoadProvider);
    final cache = ref.watch(cacheServiceProvider);
    final mapState = ref.watch(mapViewStateProvider);
    final route = ref.watch(routeStateProvider);
    final position = ref.watch(positionStateProvider);

    final spaces = cache.spaces;
    final selectedSpace = mapState.selectedSpace;

    // ---- Resolve the floor used for indoor content ----------------------
    // Prefer the user-selected floor, then the building's first known floor.
    // When a building has no known floors (floor/all is blocked on the public
    // UCY deployment) fall back to probing the default floor "0" so real
    // floorplans still render wherever they exist.
    final knownFloors = selectedSpace == null
        ? const <Floor>[]
        : cache.floorsOf(selectedSpace.buid);

    final String? activeFloorNumber =
        mapState.selectedFloor?.floorNumber ??
        (knownFloors.isNotEmpty ? knownFloors.first.floorNumber : null);

    FloorplanKey? activeFloorplanKey;

    if (selectedSpace != null) {
      activeFloorplanKey = FloorplanKey(
        selectedSpace.buid,
        activeFloorNumber ?? AppConstants.probeFloorNumber,
      );
    }

    final floorplan = activeFloorplanKey == null
        ? null
        : ref.watch(floorplanTilesProvider(activeFloorplanKey));

    if (floorplan != null && floorplan.status == FloorplanStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && activeFloorplanKey != null) {
          ref
              .read(floorplanTilesProvider(activeFloorplanKey).notifier)
              .ensure();
        }
      });
    }

    // POIs of the selected building (filtered by category and floor when set),
    // shown only once the user is zoomed into the indoor range.
    final zoomedIn = _zoom >= AppConstants.indoorZoomThreshold;

    final showIndoor = selectedSpace != null &&
        activeFloorNumber != null &&
        zoomedIn;

    final pois = showIndoor
        ? _filteredPois(
            cache.poisOf(selectedSpace.buid),
            mapState.poiCategory,
            floorNumber: activeFloorNumber,
          )
        : const <Poi>[];

    if (showIndoor) {
      debugPrint(
        '[map] pois floor=$activeFloorNumber count=${pois.length} '
        '(cached=${cache.poisOf(selectedSpace.buid).length})',
      );
    }

    // A POI card stays visible only while its POI is on the current floor.
    final selectedPoi =
        (_selectedPoi != null &&
            showIndoor &&
            _selectedPoi!.floorNumber == activeFloorNumber)
        ? _selectedPoi
        : null;

    final markers = <gm.Marker>{
      ..._buildingMarkers(
        spaces,
        selectedBuid: selectedSpace?.buid,
        zoom: _zoom,
      ),
      ..._poiMarkers(pois),
    };

    final userMarker = _userMarker(position);

    if (userMarker != null) {
      markers.add(userMarker);
    }

    final polylines = _routePolylines(route, activeFloorNumber);
    final tileOverlay = _tileOverlay(floorplan);

    // Center on the user once when the app starts tracking and no building
    // or route is active.
    final userPos = position.position;

    if (userPos != null &&
        !_didAutoCenterOnUser &&
        selectedSpace == null &&
        !route.isActive) {
      _didAutoCenterOnUser = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _moveCamera(userPos.latitude, userPos.longitude, 17);
        }
      });
    }

    // Apply an external focus request (search result → building/floor/POI).
    final focusRequest = ref.watch(mapFocusRequestProvider);

    if (focusRequest != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _applyFocusRequest(focusRequest);
        ref.read(mapFocusRequestProvider.notifier).state = null;
      });
    }

    // ---- Map surface ----------------------------------------------------
    final mapBuilder = ref.watch(mapSurfaceBuilderProvider);

    final Widget mapSurface = mapBuilder != null
        ? mapBuilder()
        : gm.GoogleMap(
            key: const ValueKey('campus_map'),
            mapType: gm.MapType.normal,
            initialCameraPosition: gm.CameraPosition(
              target: _ucyCenter,
              zoom: _defaultZoom,
            ),
            minMaxZoomPreference: gm.MinMaxZoomPreference(
              _minZoom,
              _maxZoom,
            ),
            onMapCreated: (controller) {
              _mapController = controller;
              _flushPendingCamera();
              _refreshMarkers();
            },
            onTap: (_) {
              if (mapState.selectedSpace != null) {
                ref
                    .read(mapViewStateProvider.notifier)
                    .selectSpace(null);
              }
            },
            onCameraMove: (position) {
              _zoom = position.zoom;
              _cameraCenter = position.target;
            },
            onCameraIdle: _refreshMarkers,
            markers: markers,
            polylines: polylines,
            tileOverlays: tileOverlay == null
                ? const <gm.TileOverlay>{}
                : {tileOverlay},
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          );

    return Stack(
      children: [
        Positioned.fill(child: mapSurface),

        // Header: dataset status.
        Positioned(
          top: 8,
          left: 12,
          child: SafeArea(
            child: _HeaderChip(
              isLoading: bulkLoad.isLoading,
              buildingCount: spaces.length,
            ),
          ),
        ),

        // Map controls (zoom in/out, recentre on user).
        //
        // Positioned at the bottom-right, similar to Google Maps.
        // Move them above the bottom cards when a building is selected.
        Positioned(
          right: 12,
          bottom: selectedSpace != null ? 170 : 24,
          child: SafeArea(
            top: false,
            child: _MapControls(
              onZoomIn: () => _moveCamera(
                _cameraCenter.latitude,
                _cameraCenter.longitude,
                _zoom + 1,
              ),
              onZoomOut: () => _moveCamera(
                _cameraCenter.latitude,
                _cameraCenter.longitude,
                _zoom - 1,
              ),
              onRecenter: _recenter,
            ),
          ),
        ),

        // Selected POI: name/type/floor info. Shown above the building card.
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

        // Selected building: floors + close.
        if (selectedSpace != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _BuildingCard(
                space: selectedSpace,
                floorOptions: _floorOptions(
                  selectedSpace,
                  knownFloors,
                  floorplan,
                ),
                activeFloorNumber: activeFloorNumber,
                floorplanReady: floorplan?.isReady ?? false,
                onFloorSelected: (f) =>
                    _onFloorSelected(selectedSpace, f),
                onClose: () {
                  setState(() => _selectedPoi = null);
                  ref
                      .read(mapViewStateProvider.notifier)
                      .selectSpace(null);
                },
              ),
            ),
          ),
      ],
    );
  }

  // ---- Interactions -----------------------------------------------------

  /// Applies a focus request from search: selects the building, its floor
  /// (when requested), and moves the camera to the building or POI.
  void _applyFocusRequest(MapFocusRequest request) {
    final cache = ref.read(cacheServiceProvider);
    final space = cache.spaceByBuid(request.buid);

    if (space == null) return;

    debugPrint(
      '[map] focus: ${space.name} (${space.buid}) '
      'floor=${request.floorNumber} poi=${request.poi?.name}',
    );

    _selectedPoi = null;

    ref
        .read(mapViewStateProvider.notifier)
        .selectSpace(space);

    final poi = request.poi;
    final floorNumber = request.floorNumber;

    if (floorNumber != null) {
      final floors = cache.floorsOf(space.buid);

      Floor? floor;

      for (final f in floors) {
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

      ref
          .read(mapViewStateProvider.notifier)
          .selectFloor(floor);
    }

    if (poi != null) {
      _selectedPoi = poi;

      _moveCamera(
        poi.coordinatesLat,
        poi.coordinatesLon,
        _zoom < AppConstants.indoorZoomThreshold
            ? AppConstants.indoorZoomThreshold.toDouble()
            : _zoom,
      );

      return;
    }

    _moveCamera(
      space.coordinatesLat,
      space.coordinatesLon,
      floorNumber != null
          ? AppConstants.indoorZoomThreshold.toDouble()
          : (_zoom < AppConstants.focusedZoom
              ? AppConstants.focusedZoom
              : _zoom),
    );
  }

  void _onBuildingSelected(Space space) {
    debugPrint(
      '[map] building selected: ${space.name} (${space.buid})',
    );

    _selectedPoi = null;

    ref
        .read(mapViewStateProvider.notifier)
        .selectSpace(space);

    _moveCamera(
      space.coordinatesLat,
      space.coordinatesLon,
      _zoom < AppConstants.focusedZoom
          ? AppConstants.focusedZoom
          : _zoom,
    );
  }

  void _onFloorSelected(Space building, Floor floor) {
    ref
        .read(mapViewStateProvider.notifier)
        .selectFloor(floor);

    _moveCamera(
      building.coordinatesLat,
      building.coordinatesLon,
      _zoom < AppConstants.indoorZoomThreshold
          ? AppConstants.indoorZoomThreshold.toDouble()
          : _zoom,
    );
  }

  void _recenter() {
    final pos = ref.read(positionStateProvider).position;

    if (pos == null) {
      _moveCamera(
        _ucyCenter.latitude,
        _ucyCenter.longitude,
        _defaultZoom,
      );
      return;
    }

    _moveCamera(
      pos.latitude,
      pos.longitude,
      _zoom < 17 ? 17 : _zoom,
    );
  }

  void _refreshMarkers() {
    if (mounted) {
      setState(() {});
    }
  }

  void _moveCamera(double lat, double lng, double zoom) {
    _zoom = zoom;

    _pendingCameraTarget = gm.LatLng(lat, lng);
    _pendingCameraZoom = zoom;

    final controller = _mapController;

    if (controller == null) return;

    _flushPendingCamera();
  }

  void _flushPendingCamera() {
    final controller = _mapController;
    final target = _pendingCameraTarget;
    final zoom = _pendingCameraZoom;

    if (controller == null || target == null || zoom == null) return;

    _pendingCameraTarget = null;
    _pendingCameraZoom = null;

    controller
        .animateCamera(
          gm.CameraUpdate.newLatLngZoom(target, zoom),
        )
        .catchError((_) {
          // Not fatal: the camera just stays where it is.
        });
  }

  // ---- Icons ------------------------------------------------------------

  /// Builds the marker bitmaps (category dots, cluster labels, user dot) once
  /// per session, since Google Maps icons are cheap immutable bitmaps.
  Future<void> _prepareIcons() async {
    final icons = <String, gm.BitmapDescriptor>{};

    for (final category in EntityCategory.values) {
      icons['bld_${category.name}'] =
          await _dotIcon(color: category.color, size: 44);

      icons['poi_${category.name}'] =
          await _dotIcon(color: category.color, size: 34);
    }

    icons['sel'] =
        await _dotIcon(color: AppTheme.primary, size: 50);

    icons['user'] =
        await _dotIcon(color: const Color(0xFF1E88E5), size: 44);

    for (var n = 2; n <= 99; n++) {
      icons['cl_$n'] =
          await _dotIcon(
            color: AppTheme.primary,
            size: 44,
            label: '$n',
          );
    }

    icons['cl_99+'] =
        await _dotIcon(
          color: AppTheme.primary,
          size: 44,
          label: '99+',
        );

    if (!mounted) return;

    setState(() => _icons = icons);
  }

  Future<gm.BitmapDescriptor> _dotIcon({
    required Color color,
    required double size,
    String? label,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - 1;

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = color,
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (label != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      painter.paint(
        canvas,
        center - Offset(
          painter.width / 2,
          painter.height / 2,
        ),
      );
    }

    final image = await recorder
        .endRecording()
        .toImage(size.toInt(), size.toInt());

    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    return gm.BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
    );
  }

  // ---- Data derived helpers ---------------------------------------------

  List<Poi> _filteredPois(
    List<Poi> pois,
    EntityCategory? category, {
    String? floorNumber,
  }) {
    if (floorNumber != null) {
      pois = pois
          .where((p) => p.floorNumber == floorNumber)
          .toList();
    }

    if (category == null) return pois;

    return pois
        .where(
          (p) => CategoryDeriver.derivePoi(p) == category,
        )
        .toList();
  }

  /// Floors offered by the bottom card: the building's known floors, plus a
  /// "Floor 0" probe when the backend could not provide a floor list but the
  /// floorplan tiles for the default floor are downloading/ready.
  List<Floor> _floorOptions(
    Space building,
    List<Floor> knownFloors,
    FloorplanState? floorplan,
  ) {
    if (knownFloors.isNotEmpty) return knownFloors;

    if (floorplan != null &&
        (floorplan.status == FloorplanStatus.ready ||
            floorplan.status == FloorplanStatus.loading)) {
      return [
        Floor(
          buid: building.buid,
          floorNumber: AppConstants.probeFloorNumber,
          fuid: '${building.buid}_${AppConstants.probeFloorNumber}',
        ),
      ];
    }

    return const [];
  }

  /// Buildings near the current camera — keeps the marker set small while the
  /// dataset is large (the public server returns thousands of buildings).
  List<Space> _spacesInView(
    List<Space> spaces,
    double zoom,
  ) {
    if (spaces.length <= 120) return spaces;

    final world =
        256.0 * math.pow(2.0, zoom).toDouble();

    final lonPerPx = 360.0 / world;

    final cosLat = math
        .cos(
          _cameraCenter.latitude * math.pi / 180,
        )
        .clamp(0.05, 1.0)
        .toDouble();

    const viewportWidth = 760.0;
    const viewportHeight = 1520.0;
    const margin = 1.6;

    final dLon =
        lonPerPx * (viewportWidth / 2) * margin;

    final dLat =
        (lonPerPx *
                cosLat *
                (viewportHeight / 2) *
                margin)
            .clamp(0.25, 85.0);

    return [
      for (final s in spaces)
        if ((s.coordinatesLat - _cameraCenter.latitude)
                    .abs() <=
                dLat &&
            (s.coordinatesLon - _cameraCenter.longitude)
                    .abs() <=
                dLon)
          s,
    ];
  }

  // ---- Google Map objects -------------------------------------------------

  Set<gm.Marker> _buildingMarkers(
    List<Space> spaces, {
    required String? selectedBuid,
    required double zoom,
  }) {
    final icons = _icons;

    if (icons == null) return const {};

    final visible = _spacesInView(spaces, zoom);

    if (zoom >= AppConstants.indoorZoomThreshold ||
        visible.length <= AppConstants.clusterThreshold) {
      return {
        for (final s in visible)
          _singleBuildingMarker(
            s,
            s.buid == selectedBuid,
          ),
      };
    }

    // Clustering: group visible buildings by a rough 0.01° (~1 km) grid.
    final buckets = <String, List<Space>>{};

    for (final s in visible) {
      final bx =
          (s.coordinatesLat / 0.01).floor();

      final by =
          (s.coordinatesLon / 0.01).floor();

      (buckets['$bx:$by'] ??= []).add(s);
    }

    final markers = <gm.Marker>{};

    for (final entry in buckets.entries) {
      final group = entry.value;

      if (group.length == 1) {
        markers.add(
          _singleBuildingMarker(
            group.single,
            group.single.buid == selectedBuid,
          ),
        );
      } else {
        var lat = 0.0;
        var lng = 0.0;

        for (final s in group) {
          lat += s.coordinatesLat;
          lng += s.coordinatesLon;
        }

        final centerLat = lat / group.length;
        final centerLng = lng / group.length;

        final label =
            group.length >= 100
                ? '99+'
                : '${group.length}';

        markers.add(
          gm.Marker(
            markerId:
                gm.MarkerId('cluster_${entry.key}'),
            position: gm.LatLng(
              centerLat,
              centerLng,
            ),
            icon:
                icons['cl_$label'] ??
                icons['cl_99+']!,
            onTap: () => _moveCamera(
              centerLat,
              centerLng,
              zoom < 17 ? 17 : zoom + 1,
            ),
          ),
        );
      }
    }

    return markers;
  }

  gm.Marker _singleBuildingMarker(
    Space space,
    bool isSelected,
  ) {
    final icons = _icons!;

    return gm.Marker(
      markerId: gm.MarkerId('b_${space.buid}'),
      position: gm.LatLng(
        space.coordinatesLat,
        space.coordinatesLon,
      ),
      icon: icons[
          isSelected
              ? 'sel'
              : 'bld_${CategoryDeriver.deriveSpace(space).name}'
      ]!,
      zIndexInt: isSelected ? 2 : 1,
      onTap: () => _onBuildingSelected(space),
    );
  }

  Set<gm.Marker> _poiMarkers(List<Poi> pois) {
    final icons = _icons;

    if (icons == null) return const {};

    return {
      for (final poi in pois)
        gm.Marker(
          markerId: gm.MarkerId('p_${poi.puid}'),
          position: gm.LatLng(
            poi.coordinatesLat,
            poi.coordinatesLon,
          ),
          icon: icons[
              'poi_${CategoryDeriver.derivePoi(poi).name}'
          ]!,
          zIndexInt: 1,
          onTap: () {
            debugPrint(
              '[map] poi tapped: ${poi.name} '
              '(floor=${poi.floorNumber})',
            );

            setState(
              () => _selectedPoi = poi,
            );
          },
        ),
    };
  }

  gm.Marker? _userMarker(PositionState position) {
    final icons = _icons;
    final pos = position.position;

    if (icons == null || pos == null) return null;

    return gm.Marker(
      markerId: const gm.MarkerId('user'),
      position: gm.LatLng(
        pos.latitude,
        pos.longitude,
      ),
      icon: icons['user']!,
      zIndexInt: 3,
    );
  }

  Set<gm.Polyline> _routePolylines(
    RouteState route,
    String? activeFloorNumber,
  ) {
    final polylines = <gm.Polyline>{};

    if (route.hasOutdoor) {
      polylines.add(
        gm.Polyline(
          polylineId:
              const gm.PolylineId('outdoor'),
          points: [
            for (final p in route.outdoorPoints)
              gm.LatLng(
                p.latitude,
                p.longitude,
              ),
          ],
          color: const Color(0xFF1976D2),
          width: 5,
        ),
      );
    }

    final indoor = activeFloorNumber == null
        ? null
        : route.indoorPointsByFloor[
            activeFloorNumber
          ];

    if (indoor != null && indoor.length >= 2) {
      polylines.add(
        gm.Polyline(
          polylineId: gm.PolylineId(
            'indoor_$activeFloorNumber',
          ),
          points: [
            for (final p in indoor)
              gm.LatLng(p.lat, p.lon),
          ],
          color: const Color(0xFFD32F2F),
          width: 4,
        ),
      );
    }

    return polylines;
  }

  gm.TileOverlay? _tileOverlay(
    FloorplanState? floorplan,
  ) {
    if (floorplan == null || !floorplan.isReady) {
      return null;
    }

    return gm.TileOverlay(
      tileOverlayId:
          const gm.TileOverlayId('floorplan'),
      tileProvider:
          GoogleFloorplanTileProvider(
        floorplan.tilesDir!,
      ),
      tileSize: 256,
    );
  }
}

// ---- Overlay widgets -----------------------------------------------------

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({
    required this.isLoading,
    required this.buildingCount,
  });

  final bool isLoading;
  final int buildingCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE60F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0x33FFFFFF),
        ),
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
            crossAxisAlignment:
                CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'CampusFind',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                isLoading
                    ? 'Loading campus spaces...'
                    : '$buildingCount buildings',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white70,
                ),
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
                color: AppTheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenter,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenter;

  @override
  Widget build(BuildContext context) {
    Widget button(
      IconData icon,
      VoidCallback onTap,
    ) {
      return Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 22,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.add, onZoomIn),
        const SizedBox(height: 8),
        button(Icons.remove, onZoomOut),
        const SizedBox(height: 12),
        button(Icons.my_location, onRecenter),
      ],
    );
  }
}

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.space,
    required this.floorOptions,
    required this.activeFloorNumber,
    required this.floorplanReady,
    required this.onFloorSelected,
    required this.onClose,
  });

  final Space space;
  final List<Floor> floorOptions;
  final String? activeFloorNumber;
  final bool floorplanReady;
  final void Function(Floor) onFloorSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.cardBorder,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.apartment,
                  color: AppTheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    space.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity:
                      VisualDensity.compact,
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                  ),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (floorOptions.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final floor in floorOptions)
                    ChoiceChip(
                      label: Text(
                        floor.floorName ??
                            'Floor ${floor.floorNumber}',
                      ),
                      selected:
                          activeFloorNumber ==
                              floor.floorNumber,
                      onSelected: (_) =>
                          onFloorSelected(floor),
                    ),
                ],
              )
            else
              const Text(
                'No floor data on this server.',
                style: TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 13,
                ),
              ),
            if (floorplanReady)
              const Padding(
                padding:
                    EdgeInsets.only(top: 6),
                child: Text(
                  'Floorplan loaded - zoom in to view indoor map',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PoiCard extends StatelessWidget {
  const _PoiCard({
    required this.poi,
    required this.onClose,
  });

  final Poi poi;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final category =
        CategoryDeriver.derivePoi(poi);

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.cardBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              category.icon,
              color: category.color,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    poi.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      category.label,
                      if (poi.poisType != null &&
                          poi.poisType!.isNotEmpty)
                        poi.poisType,
                      if (poi.floorName != null &&
                          poi.floorName!.isNotEmpty)
                        'Floor ${poi.floorName}'
                      else
                        'Floor ${poi.floorNumber}',
                    ].join(' · '),
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              visualDensity:
                  VisualDensity.compact,
              icon: const Icon(
                Icons.close,
                size: 20,
              ),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}