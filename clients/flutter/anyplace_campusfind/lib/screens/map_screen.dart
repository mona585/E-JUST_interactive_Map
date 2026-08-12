import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show TileLayer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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

/// Map tab: `google_maps_flutter` with building/POI markers, marker clustering,
/// tiled floorplan overlay with floor switcher, GPS blue-dot and nearest-location card.
class MapScreen extends ConsumerWidget {
  const MapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    // Indoor/outdoor switching: POIs and floorplan only make sense when a
    // building+floor is selected AND the user is zoomed in to the indoor range.
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

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _initialMapCenter(spaces).latitude > 0
            ? LatLng(_initialMapCenter(spaces).latitude, _initialMapCenter(spaces).longitude)
            : LatLng(30.0, 31.0),
        zoom: _initialMapZoom(spaces),
      ),
      onMapCreated: _onMapCreated,
      onCameraPositionChanged: _onCameraPositionChanged,
      markers: _buildMarkers(
        spaces,
        selectedBuid: mapState.selectedSpace?.buid,
        zoom: _zoom,
        indoorMode: indoorMode,
        selectedFloor: selectedFloor,
        pois: pois,
      ),
      polylines: _buildPolylines(route, selectedFloor),
      circles: _buildCircles(position),
      mapType: GoogleMap.mapTypeNormal,
      myLocationEnabled: true,
      myLocationButtonEnabled: true,
      indoorViewEnabled: true,
      buildings: true,
    );
  }

  // --- State ----------------------------------------------------------

  final MapController _mapController = MapController();
  double _zoom = 16;
  bool _fittedToCampus = false;
  bool _centeredOnUser = false;
  String? _lastSelectedBuid;
  String? _lastAutoSelectedBuid;

  void _fitToCampus(List<Space> spaces) {
    if (spaces.isEmpty || _fittedToCampus) return;
    _fittedToCampus = true;
    final bounds = LatLngBounds.fromPoints([
      for (final s in spaces) LatLng(s.coordinatesLat, s.coordinatesLon),
    ]);
    _mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: bounds.centerLatLng,
          zoom: math.max(12, math.min(18, _zoom - 1)),
        ),
      ),
    );
  }

  void _moveToUser(LatLng position) {
    _mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: position, zoom: _zoom < 15 ? 17 : _zoom),
      ),
    );
  }

  void _focusBuilding(Space space) {
    _mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(space.coordinatesLat, space.coordinatesLon), zoom: _zoom < 16 ? 16 : _zoom),
      ),
    );
  }

  static Space? _nearestBuildingWithin(
    LatLng userPosition,
    List<Space> spaces,
    double maxDistanceMeters,
  ) {
    final distance = Distance();
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

  LatLng _initialMapCenter(List<Space> spaces) {
    if (spaces.isEmpty) return LatLng(30.0, 31.0);
    return LatLng(spaces.first.coordinatesLat, spaces.first.coordinatesLon);
  }

  double _initialMapZoom(List<Space> spaces) {
    return spaces.isEmpty ? 3 : 10;
  }

  // --- Marker overlay -------------------------------------------------

  Set<Marker> _buildMarkers(
    List<Space> spaces,
    {
    required String? selectedBuid,
    required double zoom,
    required bool indoorMode,
    required Floor? selectedFloor,
    required List<Poi> pois,
    }) {
    final markers = <Marker>{};

    if (spaces.isEmpty) return markers;

    if (zoom >= 16 || spaces.length < 12) {
      // No clustering needed.
      for (final space in spaces) {
        final isSelected = space.buid == selectedBuid;
        markers.add(_singleMarker(space, isSelected));
      }
      return markers;
    }

    // Clustering: group by rough geographic buckets.
    final buckets = <int, List<Space>>{};
    for (final space in spaces) {
      final key = _bucketKey(space);
      (buckets[key] ??= []).add(space);
    }

    for (final group in buckets.values) {
      if (group.length == 1) {
        markers.add(_singleMarker(group.single, group.single.buid == selectedBuid));
      } else {
        final lat = group.map((s) => s.coordinatesLat).reduce((a, b) => a + b) / group.length;
        final lon = group.map((s) => s.coordinatesLon).reduce((a, b) => a + b) / group.length;
        markers.add(_clusterMarker(LatLng(lat, lon), group.length));
      }
    }
    return markers;
  }

  Marker _singleMarker(Space space, bool isSelected) {
    final color = isSelected ? Colors.teal : Colors.blue;
    return Marker(
      markerId: MarkerId('building_${space.buid}'),
      position: LatLng(space.coordinatesLat, space.coordinatesLon),
      infoWindow: InfoWindow(title: space.name),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        isSelected ? BitmapDescriptor.hueTeal : BitmapDescriptor.hueBlue,
      ),
    );
  }

  Marker _clusterMarker(LatLng position, int count) {
    return Marker(
      markerId: MarkerId('cluster_${count}'),
      position: position,
      infoWindow: InfoWindow(title: '$count buildings'),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    );
  }

  // --- Polyline overlay ----------------------------------------------

  Set<Polyline> _buildPolylines(RouteState route, Floor? selectedFloor) {
    final polylines = <Polyline>{};

    if (route.hasOutdoor) {
      polylines.add(Polyline(
        polylineId: const PolylineId('outdoor_route'),
        points: route.outdoorPoints,
        color: const Color(0xFF1976D2),
        strokeWidth: 5,
      ));
    }

    final indoor = selectedFloor == null
        ? null
        : route.indoorPointsByFloor[selectedFloor.fuid];
    if (indoor != null && indoor.length >= 2) {
      polylines.add(Polyline(
        polylineId: const PolylineId('indoor_route'),
        points: indoor.map((p) => LatLng(p.lat, p.lon)).toList(),
        color: const Color(0xFFD32F2F),
        strokeWidth: 4,
      ));
    }

    return polylines;
  }

  // --- Circle overlay (user position) --------------------------------

  Set<Circle> _buildCircles(PositionState position) {
    final circles = <Circle>{};
    if (position.position != null) {
      circles.add(Circle(
        circleId: const CircleId('user_position'),
        center: position.position!,
        radius: 8,
        fillColor: Colors.blue.withValues(alpha: 0.3),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      ));
    }
    return circles;
  }

  // --- Camera position listener --------------------------------------

  double _zoom = 16;
  bool _fittedToCampus = false;
  bool _centeredOnUser = false;
  String? _lastSelectedBuid;
  String? _lastAutoSelectedBuid;

  void _onCameraPositionChanged(CameraPosition position) {
    setState(() => _zoom = position.zoom);
  }

  void setState(VoidCallback fn) => fn();

  // --- Indoor/outdoor switching --------------------------------------

  // POIs to show: from the selected building, filtered by category.
  List<Poi> _buildPoiList(Floor? floor, EntityCategory? category) {
    if (floor == null) return <Poi>[];
    return cache.poisOf(floor.buid).where((p) {
      if (category == null) return true;
      return CategoryDeriver.derivePoi(p) == category;
    }).toList();
  }

  // --- Route notice --------------------------------------------------

  // (moved to bottom sheet logic)

  // --- Filter chips --------------------------------------------------

  // (moved to bottom sheet logic)

  // --- Nearest location card -----------------------------------------

  // (moved to bottom sheet logic)

  // --- Building bottom sheet -----------------------------------------

  // (moved to bottom sheet logic)

  // --- Recent waypoints list -----------------------------------------

  // (moved to bottom sheet logic)
}