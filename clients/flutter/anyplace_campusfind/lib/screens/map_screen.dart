import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../config/constants.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/map_view_provider.dart';
import '../providers/providers.dart';
import '../providers/route_provider.dart';
import '../providers/search_provider.dart';
import '../services/tile_service.dart';
import '../utils/category_deriver.dart';
import '../widgets/filter_chips.dart';
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

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheServiceProvider);
    final mapState = ref.watch(mapViewStateProvider);
    final index = ref.watch(searchIndexProvider);
    final route = ref.watch(routeStateProvider);

    final spaces = cache.spaces;
    final selectedFloor = mapState.selectedFloor;
    final poiCategory = mapState.poiCategory;

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
        title: Text(mapState.selectedSpace?.name ?? 'University Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          FilterChips(
            categories: categories,
            selected: poiCategory,
            onSelected: (c) =>
                ref.read(mapViewStateProvider.notifier).setCategory(c),
          ),
          if (route.isLoading)
            const LinearProgressIndicator(minHeight: 2)
          else if (route.error != null)
            _RouteNotice(text: 'Route unavailable: ${route.error}'),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(30.8564, 29.5945),
                initialZoom: 16,
                minZoom: 14,
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
                          point: LatLng(poi.coordinatesLat, poi.coordinatesLon),
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
      floatingActionButton: mapState.selectedSpace != null || route.isActive
          ? FloatingActionButton.small(
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
              child: Icon(route.isActive ? Icons.close : Icons.close),
            )
          : null,
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

  static const Color _outdoorColor = Colors.blue;
  static const Color _indoorColor = Colors.red;

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
      await widget.tileService.downloadAndExtract(widget.floor);
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
          ],
        ),
      ),
    );
  }
}
