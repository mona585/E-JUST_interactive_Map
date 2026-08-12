import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/constants.dart';
import '../config/theme.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/bulk_load_provider.dart';
import '../providers/map_view_provider.dart';
import '../providers/position_provider.dart';
import '../providers/providers.dart';
import '../providers/route_provider.dart';
import '../providers/search_provider.dart';
import '../services/tile_service.dart';
import '../utils/category_deriver.dart';
import '../widgets/local_floorplan_tile_provider.dart';
import 'building_detail_screen.dart';
import 'detail_navigation.dart';

/// Map tab: flutter_map with outdoor base tiles, building + POI markers,
/// dynamic category filter chips, tiled floorplan overlay and floor switcher.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  double _zoom = 16;
  bool _fittedToCampus = false;
  bool _centeredOnUser = false;
  String? _lastSelectedBuid;
  String? _lastAutoSelectedBuid;

  /// Fits the camera to the campus bounding box once data has loaded.
  void _fitToCampus(List<Space> spaces) {
    if (spaces.isEmpty || _fittedToCampus) return;
    _fittedToCampus = true;
    final bounds = LatLngBounds.fromPoints([
      for (final s in spaces) LatLng(s.coordinatesLat, s.coordinatesLon),
    ]);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(56),
        maxZoom: 18,
      ),
    );
  }

  /// Moves the camera to the user's position. Called once on the first GPS
  /// fix (when nothing is selected) and again via the locate-me button.
  void _moveToUser(LatLng position) {
    _mapController.move(position, _zoom < 15 ? 17 : _zoom);
  }

  /// Pans to a building that was just selected from outside the map (search,
  /// nearest-location card, etc.).
  void _focusBuilding(Space space) {
    _mapController.move(
      LatLng(space.coordinatesLat, space.coordinatesLon),
      _zoom < 16 ? 16 : _zoom,
    );
  }

  /// Returns the nearest building within [maxDistanceMeters], or null.
  static Space? _nearestBuildingWithin(
    LatLng userPosition,
    List<Space> spaces,
    double maxDistanceMeters,
  ) {
    final distance = const Distance();
    Space? nearest;
    double nearestDist = double.infinity;
    for (final space in spaces) {
      final d = distance.as(
        LengthUnit.Meter,
        userPosition,
        LatLng(space.coordinatesLat, space.coordinatesLon),
      );
      if (d < nearestDist) {
        nearestDist = d;
        nearest = space;
      }
    }
    if (nearest != null && nearestDist <= maxDistanceMeters) return nearest;
    return null;
  }

  /// Global center until GPS fix arrives.
  LatLng _initialMapCenter(List<Space> spaces) {
    return const LatLng(30.0, 31.0);
  }

  /// Global zoom until data/GPS arrives.
  double _initialMapZoom(List<Space> spaces) {
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheServiceProvider);
    final mapState = ref.watch(mapViewStateProvider);
    final index = ref.watch(searchIndexProvider);
    final route = ref.watch(routeStateProvider);
    final position = ref.watch(positionStateProvider);
    final bulkLoad = ref.watch(bulkLoadProvider);

    final spaces = cache.spaces;
    final selectedFloor = mapState.selectedFloor;
    final poiCategory = mapState.poiCategory;

    if (bulkLoad.hasValue &&
        !bulkLoad.isLoading &&
        spaces.isNotEmpty &&
        !_fittedToCampus &&
        position.gps == null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitToCampus(spaces),
      );
    }

    // On the first GPS fix, pan to the user so the map opens at their
    // location instead of a fixed point.
    final userFix = position.gps;
    if (userFix != null &&
        !_centeredOnUser &&
        mapState.selectedSpace == null &&
        !route.isActive) {
      _centeredOnUser = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToUser(userFix);
      });
    }

    // Auto-detect building proximity: when GPS is within 50m of a known
    // building and no building is currently selected, auto-select it.
    if (userFix != null &&
        spaces.isNotEmpty &&
        mapState.selectedSpace == null &&
        !route.isActive) {
      final nearest = _nearestBuildingWithin(userFix, spaces, 50);
      if (nearest != null && nearest.buid != _lastAutoSelectedBuid) {
        _lastAutoSelectedBuid = nearest.buid;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(mapViewStateProvider.notifier).selectSpace(nearest);
          }
        });
      }
    }

    // Pan to a building that was just selected from outside the map.
    final selectedSpace = mapState.selectedSpace;
    if (selectedSpace != null &&
        selectedSpace.buid != _lastSelectedBuid) {
      _lastSelectedBuid = selectedSpace.buid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusBuilding(selectedSpace);
      });
    }

    // Indoor/outdoor switching (task 3.7): POIs and floorplan only make
    // sense when a building+floor is selected AND the user is zoomed in to
    // the indoor range.
    final indoorMode = mapState.selectedSpace != null &&
        selectedFloor != null &&
        _zoom >= AppConstants.indoorZoomThreshold;

    // POIs to show: from the selected building, filtered by category.
    final pois = indoorMode
        ? cache.poisOf(selectedFloor.buid).where((p) {
            if (poiCategory == null) return true;
            return CategoryDeriver.derivePoi(p) == poiCategory;
          }).toList()
        : <Poi>[];

    final categories = CategoryDeriver.discoverCategories(index.all
        .where((r) => r.poi != null)
        .map((r) => r.poi!)
        .toList());

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add_location_alt, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Text(mapState.selectedSpace?.name ?? 'University Map',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.notifications_none, color: AppTheme.textSecondary, size: 22),
              onPressed: () {},
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _MapFilterChips(
            categories: categories,
            selected: poiCategory,
            onSelected: (c) =>
                ref.read(mapViewStateProvider.notifier).setCategory(c),
          ),
          if (route.isLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (route.error != null)
            _RouteNotice(text: 'Route unavailable: ${route.error}'),
          if (position.error != null && mapState.selectedSpace == null)
            _RouteNotice(text: position.error!),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialMapCenter(spaces),
                    initialZoom: _initialMapZoom(spaces),
                    minZoom: 3,
                    maxZoom: 22,
                    onPositionChanged: (camera, hasGesture) {
                      final newZoom = camera.zoom;
                      if ((newZoom - _zoom).abs() > 0.01) {
                        setState(() => _zoom = newZoom);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: AppConstants.outdoorTilesUrl,
                      userAgentPackageName: 'eg.edu.ejust.anyplace_campusfind',
                    ),
                    if (indoorMode)
                      _FloorplanOverlay(
                        floor: selectedFloor,
                        tileService: ref.read(tileServiceProvider),
                      ),
                    if (pois.isNotEmpty)
                      MarkerLayer(
                        markers: [
                          for (final poi in pois)
                            Marker(
                              point: LatLng(
                                  poi.coordinatesLat, poi.coordinatesLon),
                              width: 40,
                              height: 40,
                              child: _PoiMarker(poi: poi),
                            ),
                        ],
                      ),
                    _BuildingMarkers(
                      spaces: spaces,
                      selectedBuid: mapState.selectedSpace?.buid,
                      zoom: _zoom,
                    ),
                    if (route.isActive)
                      _RouteOverlay(
                        route: route,
                        currentFloorNumber: selectedFloor?.floorNumber,
                      ),
                    if (position.position != null)
                      _UserPositionMarker(position: position.position!),
                  ],
                ),
                if (position.position != null &&
                    mapState.selectedSpace == null &&
                    !route.isActive)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: _NearestLocationCard(
                      userPosition: position.position!,
                      spaces: spaces,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: mapState.selectedSpace == null
          ? null
          : _BuildingBottomSheet(
              space: mapState.selectedSpace!,
              floors: cache.floorsOf(mapState.selectedSpace!.buid),
              selectedFloor: selectedFloor,
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (position.gps != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FloatingActionButton.small(
                onPressed: () => _moveToUser(position.gps!),
                tooltip: 'Center on my location',
                heroTag: 'locate-me',
                child: const Icon(Icons.my_location),
              ),
            ),
          if (mapState.selectedSpace != null || route.isActive)
            FloatingActionButton.small(
              onPressed: () {
                if (route.isActive) {
                  ref.read(routeStateProvider.notifier).clearRoute();
                } else {
                  ref
                      .read(mapViewStateProvider.notifier)
                      .clearSelection();
                }
              },
              tooltip: route.isActive ? 'Clear route' : 'Clear selection',
              heroTag: 'clear-action',
              child: Icon(route.isActive ? Icons.close : Icons.close),
            ),
        ],
      ),
    );
  }
}

class _PoiMarker extends ConsumerWidget {
  const _PoiMarker({required this.poi});

  final Poi poi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isEntrance = poi.isEntrance;
    return GestureDetector(
      onTap: () => openPoi(context, ref, poi),
      child: Icon(
        isEntrance ? Icons.door_front_door : Icons.place,
        color: isEntrance ? scheme.tertiary : scheme.primary,
        size: 28,
      ),
    );
  }
}

/// Building markers with simple clustering at low zoom (task 3.6).
///
/// At zoom levels below the cluster threshold, buildings closer than a fixed
/// pixel distance collapse into a single count bubble.
class _BuildingMarkers extends ConsumerWidget {
  const _BuildingMarkers({
    required this.spaces,
    required this.selectedBuid,
    required this.zoom,
  });

  final List<Space> spaces;
  final String? selectedBuid;
  final double zoom;

  static const double _clusterZoom = 16.0;
  static const double _clusterPixelDistance = 48.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    final markers = <Marker>[];
    if (spaces.isEmpty) return MarkerLayer(markers: markers);

    if (zoom >= _clusterZoom || spaces.length < AppConstants.clusterThreshold) {
      // No clustering needed.
      for (final space in spaces) {
        markers.add(_singleMarker(ref, space, scheme));
      }
      return MarkerLayer(markers: markers);
    }

    // Simple grid clustering: bucket markers by coarse lat/lon buckets derived
    // from the pixel distance at the current zoom.
    final buckets = <int, List<Space>>{};
    for (final space in spaces) {
      final key = _bucketKey(space);
      (buckets[key] ??= []).add(space);
    }

    for (final group in buckets.values) {
      if (group.length == 1) {
        markers.add(_singleMarker(ref, group.single, scheme));
      } else {
        final lat = group.map((s) => s.coordinatesLat).reduce((a, b) => a + b) /
            group.length;
        final lon = group.map((s) => s.coordinatesLon).reduce((a, b) => a + b) /
            group.length;
        markers.add(
          Marker(
            point: LatLng(lat, lon),
            width: 44,
            height: 44,
            child: _ClusterBubble(count: group.length),
          ),
        );
      }
    }
    return MarkerLayer(markers: markers);
  }

  int _bucketKey(Space space) {
    // Convert pixel distance to degrees at this zoom using Web Mercator
    // approximation: 256 * 2^zoom pixels span 360 degrees of longitude.
    final degPerPixel = 360.0 / (256.0 * math.pow(2, zoom));
    final latBucket = math.pow(2, 12) *
        (space.coordinatesLat / _clusterPixelDistance * degPerPixel).round();
    final lonBucket = math.pow(2, 12) *
        (space.coordinatesLon / _clusterPixelDistance * degPerPixel).round();
    return latBucket.hashCode ^ lonBucket.hashCode;
  }

  Marker _singleMarker(WidgetRef ref, Space space, ColorScheme scheme) {
    return Marker(
      point: LatLng(space.coordinatesLat, space.coordinatesLon),
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => ref.read(mapViewStateProvider.notifier).selectSpace(space),
        child: Icon(
          Icons.apartment,
          color: space.buid == selectedBuid ? scheme.tertiary : scheme.primary,
          size: 32,
        ),
      ),
    );
  }
}

class _ClusterBubble extends StatelessWidget {
  const _ClusterBubble({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.onPrimary, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Inline status banner shown above the map for route errors.
class _RouteNotice extends StatelessWidget {
  const _RouteNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
      ),
    );
  }
}

/// Draws the active route: blue outdoor polyline + red indoor polyline for
/// the currently selected floor (task 5.4). Switching floors via the bottom
/// sheet moves the red polyline to that floor's segment (task 5.5).
class _RouteOverlay extends StatelessWidget {
  const _RouteOverlay({required this.route, required this.currentFloorNumber});

  final RouteState route;
  final String? currentFloorNumber;

  static const Color _outdoorColor = Color(0xFF1976D2);
  static const Color _indoorColor = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    final polylines = <Polyline>[];

    if (route.hasOutdoor) {
      polylines.add(Polyline(
        points: route.outdoorPoints,
        strokeWidth: 5,
        color: _outdoorColor,
      ));
    }

    final indoor = currentFloorNumber == null
        ? null
        : route.indoorPointsByFloor[currentFloorNumber];
    if (indoor != null && indoor.length >= 2) {
      polylines.add(Polyline(
        points: indoor.map((p) => LatLng(p.lat, p.lon)).toList(),
        strokeWidth: 4,
        color: _indoorColor,
      ));
    }

    return PolylineLayer(polylines: polylines);
  }
}

/// Downloads and overlays the selected floor's tile set. Tiles are fetched
/// once, then served from the local cache.
class _FloorplanOverlay extends ConsumerStatefulWidget {
  const _FloorplanOverlay({required this.floor, required this.tileService});

  final Floor floor;
  final TileService tileService;

  @override
  ConsumerState<_FloorplanOverlay> createState() => _FloorplanOverlayState();
}

class _FloorplanOverlayState extends ConsumerState<_FloorplanOverlay> {
  Future<Object?> _downloadFuture = Future.value();

  @override
  void initState() {
    super.initState();
    _downloadFuture = _ensureTiles();
  }

  @override
  void didUpdateWidget(_FloorplanOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floor.fuid != widget.floor.fuid) {
      _downloadFuture = _ensureTiles();
    }
  }

  Future<Object?> _ensureTiles() async {
    try {
      await widget.tileService.ensureTiles(widget.floor);
      return null;
    } catch (e) {
      return e;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Object?>(
      future: _downloadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                'Floorplan unavailable',
                style: TextStyle(
                  backgroundColor: Colors.black54,
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }
        return FutureBuilder(
          future: widget.tileService.tileDirFor(widget.floor),
          builder: (context, dirSnapshot) {
            final dir = dirSnapshot.data;
            if (dir == null) return const SizedBox.shrink();
            return TileLayer(
              urlTemplate: 'local://tiles',
              tileProvider: LocalFloorplanTileProvider(dir),
              minZoom: 19,
              maxZoom: 22,
            );
          },
        );
      },
    );
  }
}

class _BuildingBottomSheet extends ConsumerWidget {
  const _BuildingBottomSheet({
    required this.space,
    required this.floors,
    required this.selectedFloor,
  });

  final Space space;
  final List<Floor> floors;
  final Floor? selectedFloor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasFloors = floors.isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.apartment, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(space.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BuildingDetailScreen(space: space),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Details'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (hasFloors) ...[
              Text('Floors', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final floor in floors)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(floor.floorName ??
                              'Floor ${floor.floorNumber}'),
                          selected: selectedFloor?.fuid == floor.fuid,
                          onSelected: (_) => ref
                              .read(mapViewStateProvider.notifier)
                              .selectFloor(floor),
                        ),
                      ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: scheme.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No floor data for this building. Showing GPS position.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.outline,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UserPositionMarker extends StatelessWidget {
  const _UserPositionMarker({required this.position});

  final LatLng position;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MarkerLayer(
      markers: [
        Marker(
          point: position,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: scheme.primary, width: 2),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NearestLocationCard extends ConsumerWidget {
  const _NearestLocationCard({
    required this.userPosition,
    required this.spaces,
  });

  final LatLng userPosition;
  final List<Space> spaces;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Space? nearest;
    double nearestDistance = double.infinity;
    for (final space in spaces) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        userPosition,
        LatLng(space.coordinatesLat, space.coordinatesLon),
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = space;
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nearest Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(
              nearest != null
                  ? 'You are currently near ${nearest.name}'
                  : 'Your position',
              style: const TextStyle(fontSize: 14, color: AppTheme.textTertiary),
            ),
            if (nearest != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.apartment, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nearest.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                            'Building · ${nearestDistance.toStringAsFixed(0)}m',
                            style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Text('${nearestDistance.toStringAsFixed(0)}m',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primary)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MapFilterChips extends StatelessWidget {
  const _MapFilterChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<EntityCategory> categories;
  final EntityCategory? selected;
  final ValueChanged<EntityCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        children: [
          _MapChip(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final c in categories)
            _MapChip(
              label: c.label,
              selected: selected == c,
              onTap: () => onSelected(selected == c ? null : c),
            ),
        ],
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
