# Map Migration Plan: flutter_map → Google Maps

## Goal
Replace `flutter_map` (Leaflet-based) with `google_maps_flutter` (Google Maps SDK) for the outdoor base map, while keeping all indoor navigation features (floorplan overlay, POI markers, indoor routing) intact.

---

## Decisions Log

| # | Question | Decision |
|---|----------|----------|
| 1 | Google Maps API key? | **Yes** — `AIzaSyDK8JRCY8ZX1htNbqfKge2W7wCGTZTmtpw` |
| 2 | Billing account ready? | **Yes** — confirmed |
| 3 | UserLocationMarker approach? | **Keep custom** — dual GPS (blue) / Wi-Fi (teal) modes + heading arrow |
| 6 | Outdoor route dotted pattern? | **Keep dotted** — via `PatternItem.dot` + `PatternItem.gap` |
| 7 | Floorplan overlay approach? | **GroundOverlay** — direct mapping from current `OverlayImage` + `LatLngBounds` |
| 8 | Camera animation? | **Built-in** — `mapController.animateCamera()` replaces custom `_animatedMapMove` |
| 9 | Camera API adaptation? | **Yes** — adapt to `GoogleMapController.getCameraPosition()` etc. |
| 10 | Map rotation? | **Enabled** — keep two-finger rotate |
| 11 | Platform? | **Android-only** — no iOS for now |
| 12 | API key storage? | **`--dart-define`** — matches existing `MAPS_API_KEY` pattern |
| 13 | latlong2 removal strategy? | **Option (a): Clean break** — remove `latlong2`, use `google_maps_flutter.LatLng` everywhere |
| 14 | Distance() replacement? | **`Geolocator.distanceBetween()`** — already a project dependency |
| 15 | Offline map tiles? | **No change** — Google Maps tiles cache better by default |
| 16 | Marker clustering? | **Later** — test first, add only if performance demands it |

---

## Prototype Backlog (HF questions — resolved during implementation)

| # | Question | Resolution approach |
|---|----------|-------------------|
| 4 | Building markers — center-aligned circles vs pin-style vs custom BitmapDescriptor? | Build test markers, visually inspect on device at different zoom levels |
| 5 | POI markers — custom BitmapDescriptor + label vs infoWindow popup? | Build test markers, compare interaction models on device |

---

## Implementation Phases

### Phase 1: Package Swap

**Files to modify:**
- `pubspec.yaml` — remove `flutter_map` and `latlong2`, add `google_maps_flutter`
- `android/app/src/main/AndroidManifest.xml` — add `<meta-data>` for API key
- `build.gradle` — may need to add Google Maps repository

**Steps:**
1. Remove from `pubspec.yaml`:
   ```yaml
   flutter_map: ^7.0.2
   latlong2: ^0.9.1
   ```
2. Add to `pubspec.yaml`:
   ```yaml
   google_maps_flutter: ^2.10.0
   ```
3. Add to `android/app/src/main/AndroidManifest.xml` inside `<application>`:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="${MAPS_API_KEY}" />
   ```
4. The API key will be injected via `--dart-define=MAPS_API_KEY=...` at build time (matching existing pattern)
5. Run `flutter pub get`

---

### Phase 2: Model Migration (11 files)

**All files that import `latlong2`:**

| # | File | Changes needed |
|---|------|---------------|
| 1 | `lib/data/models/space_model.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 2 | `lib/data/models/poi_model.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 3 | `lib/data/models/floorplan_model.dart` | Replace `latlong2.LatLng` + `LatLngBounds` → `google_maps_flutter` equivalents |
| 4 | `lib/data/models/navigation_route_model.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 5 | `lib/data/models/user_location.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 6 | `lib/data/models/position_estimate.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 7 | `lib/data/datasources/anyplace_api_client.dart` | Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` |
| 8 | `lib/state/location_provider.dart` | Replace `latlong2.LatLng` + `Distance()` → `google_maps_flutter.LatLng` + `Geolocator.distanceBetween()` |
| 9 | `lib/state/navigation_controller.dart` | Replace `latlong2.LatLng` + `Distance()` → `google_maps_flutter.LatLng` + `Geolocator.distanceBetween()` |
| 10 | `lib/state/space_provider.dart` | Replace `latlong2.LatLng` + `Distance()` → `google_maps_flutter.LatLng` + `Geolocator.distanceBetween()` |
| 11 | `lib/ui/screens/map_screen.dart` | Replace `latlong2.LatLng` + `LatLngBounds` → `google_maps_flutter` equivalents |

**Key changes per file:**

#### Models (1-6): Simple type swap
- Replace `import 'package:latlong2/latlong.dart'` → `import 'package:google_maps_flutter/google_maps_flutter.dart'`
- `LatLng(...)` constructor: **same signature** — `LatLng(latitude, longitude)` works identically
- `.latitude` / `.longitude` property access: **same names** — no change needed
- `LatLngBounds(corner1, corner2)`: **same constructor** in google_maps_flutter

#### Data layer (7): API client
- Replace `latlong2.LatLng` → `google_maps_flutter.LatLng` in `fetchOutdoorWalkingRoute` return type
- The OSRM response parsing uses `LatLng(lat, lon)` — same constructor, no logic change

#### State layer (8-10): Distance replacement
- Replace `const Distance().distance(latlng1, latlng2)` → `Geolocator.distanceBetween(lat1, lng1, lat2, lng2)`
- Note: `Geolocator.distanceBetween()` takes raw doubles, not LatLng objects
- Pattern: `Geolocator.distanceBetween(p1.latitude, p1.longitude, p2.latitude, p2.longitude)`

**All8 `Distance()` call sites:**

| File | Line | Current | Replacement |
|------|------|---------|-------------|
| `space_provider.dart` | ~494 | `const Distance().distance(LatLng(...), LatLng(...))` | `Geolocator.distanceBetween(lat1, lng1, lat2, lng2)` |
| `navigation_controller.dart` | ~286 | `Distance()` in `_pointToSegmentDistance` | `Geolocator.distanceBetween(...)` |
| `navigation_controller.dart` | ~360 | `Distance()(location.latLng, connectorPoint.latLng)` | `Geolocator.distanceBetween(...)` |
| `navigation_controller.dart` | ~492 | `Distance()(gpsLocation.latLng, building.latLng)` | `Geolocator.distanceBetween(...)` |
| `navigation_controller.dart` | ~524 | `Distance()(location.latLng, building.latLng)` | `Geolocator.distanceBetween(...)` |
| `navigation_controller.dart` | ~570 | `Distance()(location.latLng, poi.latLng)` | `Geolocator.distanceBetween(...)` |
| `navigation_controller.dart` | ~588 | `Distance()(location.latLng, building.latLng)` | `Geolocator.distanceBetween(...)` |
| `location_provider.dart` | ~262-265 | `Distance()` for stability window | `Geolocator.distanceBetween(...)` |

---

### Phase 3: Map Widget Rewrite (`map_screen.dart`)

This is the largest change. The entire map rendering layer is replaced.

#### 3a. Widget structure

**Current (flutter_map):**
```dart
FlutterMap(
  mapController: _mapController,
  options: MapOptions(...),
  children: [
    TileLayer(...),
    OverlayImageLayer(...),
    PolylineLayer(...),  // outdoor route
    PolylineLayer(...),  // indoor route
    MarkerLayer(...),    // buildings
    MarkerLayer(...),    // POIs
    MarkerLayer(...),    // user location
  ],
)
```

**New (Google Maps):**
```dart
GoogleMap(
  mapController: _mapController,
  initialCameraPosition: CameraPosition(
    target: initialCenter,
    zoom: initialZoom,
  ),
  onMapCreated: (controller) { ... },
  onTap: (latLng) { ... },
  onCameraMove: (position) { ... },
  onCameraIdle: () { ... },
  myLocationEnabled: false,  // we use custom marker
  myLocationButtonEnabled: false,
  zoomControlsEnabled: false,
  compassEnabled: false,
  rotationGesturesEnabled: true,
  markers: _buildMarkers(),
  polylines: _buildPolylines(),
  groundOverlays: _buildGroundOverlays(),
)
```

#### 3b. Markers → `Set<Marker>`

**Current:** 3 separate `MarkerLayer` widgets
**New:** Single `Set<Marker>` built from a `_buildMarkers()` method

```dart
Set<Marker> _buildMarkers() {
  final markers = <Marker>{};

  // Building markers
  for (final space in spaceProvider.spaces) {
    markers.add(Marker(
      markerId: MarkerId(space.buid),
      position: space.latLng,
      anchor: const Offset(0.5, 0.5),  // center-aligned (not bottom-center)
      icon: _buildingIcon,  // BitmapDescriptor
      onTap: () => _onBuildingTapped(space),
    ));
  }

  // POI markers
  if (spaceProvider.hasPois) {
    for (final poi in spaceProvider.pois) {
      markers.add(Marker(
        markerId: MarkerId(poi.puid),
        position: poi.latLng,
        anchor: const Offset(0.5, 1.0),  // top-aligned
        icon: _poiIcon,  // BitmapDescriptor
        infoWindow: InfoWindow(
          title: poi.name,
          onTap: () { ... },
        ),
      ));
    }
  }

  // User location marker
  if (userLocation != null) {
    markers.add(Marker(
      markerId: const MarkerId('user_location'),
      position: userLocation.latLng,
      anchor: const Offset(0.5, 0.5),
      icon: _userLocationIcon,  // BitmapDescriptor
    ));
  }

  return markers;
}
```

**Marker icon generation:**
- Building markers: Screenshot `BuildingMarker` widget → `BitmapDescriptor.bytes()` (one-time)
- POI markers: Screenshot `PoiMarker` widget → `BitmapDescriptor.bytes()` (per-type, cached)
- User location: Keep as `Stack` overlay on top of `GoogleMap` (not a Marker) for animation support

#### 3c. Polylines → `Set<Polyline>`

**Current:** 2 conditional `PolylineLayer` widgets
**New:** Single `Set<Polyline>` built from `_buildPolylines()`

```dart
Set<Polyline> _buildPolylines() {
  final polylines = <Polyline>{};
  final route = spaceProvider.activeNavigationRoute;
  if (route == null) return polylines;

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
```

**Note:** Google Maps `Polyline` does not support `borderStrokeWidth` / `borderColor`. The white border effect from flutter_map is lost. The route will appear as solid colored lines without outlines.

#### 3d. Floorplan overlay → `GroundOverlay`

**Current:** `OverlayImageLayer` with `OverlayImage`
**New:** `GroundOverlay` with `GroundOverlayId`

```dart
Set<GroundOverlay> _buildGroundOverlays() {
  final overlays = <GroundOverlay>{};
  if (!spaceProvider.hasActiveFloorplan) return overlays;

  final floorplan = spaceProvider.activeFloorplan!;
  overlays.add(GroundOverlay(
    groundOverlayId: GroundOverlayId(
      'floorplan_${floorplan.buid}_${floorplan.floorNumber}',
    ),
    image: BitmapDescriptor.fromBytes(
      File(floorplan.imagePath).readAsBytesSync(),
    ),
    bounds: floorplan.bounds,  // LatLngBounds — same type
    transparency: 0.0,
  ));

  return overlays;
}
```

**Note:** `GroundOverlay` uses `BitmapDescriptor.fromBytes()` for the image. The floorplan PNG needs to be read as bytes. The `LatLngBounds` from `FloorplanModel.bounds` maps directly.

#### 3e. Map controller

**Current:**
```dart
late final MapController _mapController;
// Reading: _mapController.camera.center, .zoom, .rotation
// Moving: _mapController.move(LatLng, zoom)
// Animation: custom _animatedMapMove()
```

**New:**
```dart
GoogleMapController? _mapController;
// Reading: _mapController!.getCameraPosition() → CameraPosition(target, zoom, bearing)
// Moving: _mapController!.moveCamera(CameraUpdate.newLatLngZoom(LatLng, zoom))
// Animation: _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng, zoom))
```

**Delete:** The entire `_animatedMapMove()` method (lines 136-175) — replaced by built-in `animateCamera`.

#### 3f. Event handlers

| Current (flutter_map) | New (Google Maps) |
|----------------------|-------------------|
| `onTap: (_, _) { ... }` | `onTap: (LatLng latLng) { ... }` |
| `onPositionChanged: (MapCamera camera, bool hasGesture) { ... }` | `onCameraMove: (CameraPosition position) { ... }` + `onCameraIdle: () { ... }` |

---

### Phase 4: Custom Marker Widgets → BitmapDescriptor

**Current approach:** Custom Flutter widgets rendered as map markers via flutter_map's `child` parameter.

**New approach:** Google Maps `Marker` uses `BitmapDescriptor` (an image), not a widget. Two options:

#### Option A: Widget-to-image screenshot (recommended)
- Create a `RepaintBoundary` + `GlobalKey`
- Render the existing `BuildingMarker` / `PoiMarker` widget
- Screenshot to `Uint8List` via `RenderRepaintBoundary.toImage()`
- Convert to `BitmapDescriptor.bytes()`
- Cache per marker type (building normal, building selected, POI types)

**Pros:** Reuses existing widget designs exactly, no redesign needed.
**Cons:** Screenshot quality depends on device pixel ratio.

#### Option B: Custom BitmapDescriptor from canvas
- Draw markers programmatically using `Canvas` + `PictureRecorder`
- Convert to `Uint8List` → `BitmapDescriptor.bytes()`

**Pros:** Resolution-independent, cleaner.
**Cons:** Requires rewriting all marker visuals from scratch.

**Recommendation: Option A** — the existing widget designs are good, and screenshotting preserves them exactly.

#### User Location Marker special case
The `UserLocationMarker` has a **pulse animation** (2000ms repeating). Google Maps markers don't support animation. Two options:

1. **Overlay widget:** Place the `UserLocationMarker` as a `Stack` widget on top of the `GoogleMap`, positioned using camera projection math. Update position on `onCameraMove`.
2. **Timer-based icon swap:** Periodically re-render the marker at different pulse scales → `BitmapDescriptor.bytes()`.

**Recommendation: Option 1 (overlay widget)** — the animation is smooth and doesn't require re-rendering on a timer. The position update on camera move is straightforward.

---

### Phase 5: Controls & Bottom Sheet

**Files that should work as-is (no map package dependency):**
- `lib/ui/widgets/map_controls.dart` — floating buttons (search, recenter, zoom, reload)
- `lib/ui/widgets/map_bottom_sheet.dart` — draggable bottom sheet (3-state snap)
- `lib/ui/widgets/building_detail_card.dart`
- `lib/ui/widgets/poi_detail_card.dart`

**Files that need LatLng type migration only:**
- `lib/state/navigation_controller.dart` — uses `LatLng` for distance calculations (covered in Phase 2)
- `lib/state/space_provider.dart` — uses `LatLng` for distance calculations (covered in Phase 2)

---

### Phase 6: Cleanup

1. **Delete from `map_config.dart`:**
   - `cartoVoyagerUrlTemplate`
   - `cartoSubdomains`
   - `osmUrlTemplate`
   - `osmSubdomains`
   - `userAgentPackageName`
   - `maxNativeTileZoom`
   - Keep: `defaultZoom`, `focusedZoom`, `indoorFloorplanZoom`, `minZoom`, `maxZoom`

2. **Delete from `map_screen.dart`:**
   - `import 'package:flutter_map/flutter_map.dart'`
   - Entire `_animatedMapMove()` method
   - `MapController` → `GoogleMapController?`

3. **Remove unused imports** across all modified files

4. **Run `flutter pub get`** to resolve dependencies

5. **Build and test:**
   ```bash
   flutter build apk --debug
   # Install on device
   # Test: map loads, markers appear, routes render, floorplan overlays work
   ```

---

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Custom markers don't screenshot well at low DPI | Visual quality | Test on multiple devices, adjust pixel ratio |
| GroundOverlay doesn't georectify correctly | Floorplan misalignment | Verify `LatLngBounds` matches flutter_map's `OverlayImage` bounds |
| `onCameraMove` fires too frequently for user location overlay | Performance | Throttle position updates to 60fps max |
| Google Maps tile loading fails (same DNS issue as CartoDB) | No map tiles | Google Maps CDN is more reliable; if issue persists, check network security config |
| `BitmapDescriptor.fromBytes()` memory with many POI icons | Memory | Cache icons per type, not per instance |
| Polylines lose border/outline effect | Visual regression | Acceptable — Google Maps polylines are clean without borders |

---

## Testing Checklist

- [ ] Map loads and shows Google Maps tiles
- [ ] Building markers appear at correct positions
- [ ] Building markers are tappable and trigger selection
- [ ] POI markers appear when a floor is selected
- [ ] POI markers show correct icons per type
- [ ] User location marker shows blue dot (GPS) / teal dot (Wi-Fi)
- [ ] User location marker has heading arrow when available
- [ ] Outdoor route renders as dotted blue line
- [ ] Indoor route renders as solid red line
- [ ] Floorplan overlay appears at correct geographic bounds
- [ ] Floorplan overlay aligns with building markers
- [ ] Camera animated move works (tap building → center on it)
- [ ] Camera follow mode works during navigation
- [ ] Map tap deselects current selection
- [ ] Map pan exits follow mode
- [ ] Map controls (search, recenter, zoom) work
- [ ] Bottom sheet snaps correctly
- [ ] App does not crash on startup
- [ ] No regression in routing functionality
