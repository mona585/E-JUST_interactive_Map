# Cross-Building Navigation — Implementation Plan

> **Status:** Approved
> **Date:** 2026-08-18
> **Device:** CPH2185 (YH65C6QWDYMNV8R4)
> **Campus:** EJUST

---

## Problem Statement

The existing Anyplace navigation routes users from their GPS location to a destination POI within a single building. We need to redesign it to support **indoor → outdoor → indoor** multi-building journeys (e.g., user starts inside Building A, exits, walks across campus, enters Building B, navigates to destination POI).

---

## Root Cause Analysis

1. **`requestRouteToBuilding()` ignores the user's current building.** It assumes the user is outdoors or near the target building.
2. **Strategy 1 (coordinate-based routing)** sends the user's GPS coordinates to the Anyplace backend with the *target building's* POIs. If the user is indoors at Building A, the coordinates don't match any indoor graph in Building B → fails.
3. **Strategy 2 (POI-to-POI)** picks a random interior POI in the target building as the *origin*. This makes no sense for cross-building routing.
4. **Strategy 3 (hybrid)** always runs and always produces a route. But it routes from GPS → target building entrance → interior. It doesn't know the user is inside another building, so it doesn't generate an exit segment from Building A.
5. **The Anyplace API only supports single-building indoor routing.** There's no cross-building endpoint.
6. **The `NavigationRouteModel` CAN represent multi-segment routes** but the routing logic never constructs routes with >2 segments.

---

## Architectural Decisions

### A1: Segment Types
5 types: `outdoorWalking`, `indoorRouting`, `floorTransition`, `exitTransition`, `entranceTransition`

### A2: Segment Fields
All fields: `type`, `points`, `floorNumber`, `buildingId`, `connectorPoiId`, `instruction`, `distance`

### A3: Segment Ordering
Strictly ordered: `exitTransition → outdoorWalking → entranceTransition → indoorRouting`

### A4: Empty Segments
Omit from route

### A5: Max Segments
Cap at 6

### B1: Indoor/Outdoor Detection
`isIndoor + polygon check`

### B2: Starting Building ID
`buildingBoundsCache polygon check`

### B3: No Building Detected
Treat as outdoor start

### B4: Exit POI Selection
Closest to indoor position (considering floor + distance)

### B5: Exit Segment Generation
Anyplace API if available, fallback to straight line

### B6: User Position Unavailable
Building centroid as fallback

### C1: Algorithm Location
New `CrossBuildingRouter` class in `lib/data/repositories/`

### C2: Cross-Building Trigger
Pre-cascade check: `isIndoor + different building`

### C3: Multi-Floor Exit
Part of exit segment

### C4: Outdoor Route
Single OSRM call from exit GPS to entrance GPS

### C5: Entrance Approach
Outdoor route direction (not user heading)

### C6: Entrance Selection
Angular difference from route bearing (corrected: actual OSRM final bearing)

### C7: Indoor Segment at Destination
Anyplace API POI-to-POI

### C8: Route Caching
Session-only in NavigationController

### D1: Exit Routing API
`/api/navigation/route/coordinates`

### D2: Outdoor Route API
Reuse existing `getOutdoorWalkingRoute()` + new `getOutdoorWalkingRouteWithMetadata()`

### D3: API Failure Handling
Show available segments with warning (partial route)

### D4: API Call Sequencing
Sequential (each depends on previous)

### E1: Segment Transition Detection
Proximity-based (10m endpoints, 30m floor transitions)

### E2: Floor Transition UX
Auto-detect via LocationProvider

### E3: Wrong Floor Rerouting
Yes, reroute

### E4: Wrong Exit Rerouting
Yes, if >30m from planned route

### E5: Outdoor Deviation
Yes, if >50m from path

### E6: Indoor Drift
Debounce 5 seconds

### F1: Segment Visual Style
5-color: blue/red/orange/green/purple

### F2: Segment Labels
Yes, text labels

### F3: Floorplan Overlay
Current floor only

### F4: Polyline Persistence
Current floor only

### G1: Building Change Mid-Route
Show notification with reroute option

### G2: Destination Locked
Yes, locked after navigation starts

### G3: GPS Loss Outdoor
Pause navigation, wait for GPS restore

### G4: No Indoor Position at Start
Use building centroid

### G5: No Entrance POIs
Centroid fallback

### G6: No Exit POIs
Centroid fallback

### G7: Same Building Bypass
Use existing 3-strategy cascade

### H1: Backward Compatibility
Transparent (existing API unchanged)

### H2: Unit Test Scenarios
All 8 scenarios

### H3: Integration Testing
Real API integration testing (no mocks)

### H4: Real Device Testing
Yes, CPH2185 device

---

## Adjustments Applied

### Adjustment 1: Entrance Selection (No Circular Logic)

**Problem:** Previous plan used centroid bearing to select entrance, then generated OSRM route to that entrance. This is circular.

**Solution:** Two-pass entrance selection:

1. **Pass 1 (cost estimation + bearing):** For each candidate entrance POI, call OSRM via `fetchOutdoorWalkingRouteWithMetadata()` from exit point to that entrance. Get route distance, duration, and **final bearing** from the last two geometry coordinates.
2. **Pass 2 (scoring):** For each candidate, compute approach angle between the candidate's final bearing and the vector from building centroid to entrance. Score: `distance * 0.6 + angularPenalty * 0.4`. Pick lowest.
3. **Final route:** Generate full OSRM route only once, to the selected entrance.

### Adjustment 2: Exit/Entrance Fallback (Internal Representation)

If no exit/entrance POI exists, use building centroid as a `FallbackLocation` (not a real connector POI). Represented via `isFallbackLocation = true` on `RouteSegment`.

### Adjustment 3: Connector/Entrance Classification (Real API Data)

**Actual classification from the codebase:**

| Role | Detection Rule | Source |
|------|---------------|--------|
| **Connector (floor-transition POI)** | `pois_type == "None"` (capital N) | `Poi.scala:46`, `PoiController.js:1291` |
| **Entrance** | `is_building_entrance == true` OR `pois_type.toLowerCase().contains('entrance')` | `space_provider.dart:661-663` |
| **Elevator** | `pois_type.toLowerCase().contains('elevator')` | `category_deriver.dart:147` |
| **Stairs/Staircase** | `pois_type.toLowerCase().contains('stairs')` OR `pois_type.toLowerCase().contains('staircase')` | `category_deriver.dart:150` |
| **Door** | `is_door == true` OR `pois_type.toLowerCase().contains('door')` | `poi_marker.dart:38-41` |

**Key insight:** `pois_type` is a **free-form string** (no backend validation). The Architect UI recommends Title Case values (`"Elevator"`, `"Stair"`, `"Entrance"`), but the server constants use lowercase (`"elevator"`, `"stair"`). The client must use **case-insensitive substring matching**.

### Adjustment 4: Partial Route Failure

Add `NavigationRouteStatus.partial` state:
- `ready` = all segments generated → full active navigation enabled
- `partial` = some segments failed → show available segments with warning, active navigation DISABLED
- `error` = no segments generated → show error message

When `partial`: show banner "⚠ Route incomplete — [missing segment description]". Mark failed segment with `isIncomplete = true`.

### Adjustment 5: Real Data Only

All implementation and testing must use real Anyplace API (`ap.cs.ucy.ac.cy`), real OSRM (`router.project-osrm.org`), real EJUST campus data. **No mocked API responses, fake POIs, fake buildings, fake routes, or mock location data.**

### Adjustment 6: Complete Cross-Building Route

The final route must always represent the complete journey:
```
User Location → [Indoor Route to Exit] → Exit Transition → [Outdoor Walking Route] → Destination Entrance → [Indoor Route to Destination]
```
If any segment fails, the route is marked `partial`. Never silently drop segments.

### Adjustment 7: Preserve Existing Behavior

- Same-building navigation: unchanged (existing 3-strategy cascade)
- Cross-building navigation: only activates when `isIndoor == true` AND user is inside a building different from destination

### Adjustment 8: Real-Device Validation

Test on CPH2185 device with real EJUST campus data.

---

## Implementation Phases

### Phase 1: PoiClassification Utility

**Goal:** Create a utility class that classifies POIs using the real Anyplace API classification rules.

**File to create:** `lib/utils/poi_classification.dart`

**Contents:**
- `PoiClassification` class with static methods:
  - `isConnector(PoiModel)` — checks `poisType == 'None'`
  - `isEntrance(PoiModel)` — checks `isBuildingEntrance` flag OR `poisType` contains 'entrance'
  - `isElevator(PoiModel)` — checks `poisType` contains 'elevator'
  - `isStairs(PoiModel)` — checks `poisType` contains 'stairs' or 'staircase'
  - `isFloorTransition(PoiModel)` — connector OR elevator OR stairs
  - `getGroundFloorEntrances(List<PoiModel>, String buildingBuid)` — returns entrance POIs on ground floor
  - `getFloorConnectors(List<PoiModel>, String floorNumber)` — returns connector POIs on a floor

**Update:** Replace hardcoded classification in `map_screen.dart:_isConnectorPoi()` with `PoiClassification.isConnector()`.

**Tests:** Unit tests with real POI type strings from the API ("None", "Elevator", "Stair", "Entrance", "Room", custom types).

---

### Phase 2: RouteSegment Model

**Goal:** Create the `RouteSegment` model representing one leg of a multi-segment journey.

**File to create:** `lib/data/models/route_segment.dart`

**Contents:**
- `RouteSegmentType` enum: `outdoorWalking`, `indoorRouting`, `floorTransition`, `exitTransition`, `entranceTransition`
- `RouteSegment` class:
  - Fields: `type`, `points: List<LatLng>`, `floorNumber?`, `buildingId?`, `connectorPoiId?`, `instruction?`, `distance`, `isIncomplete`, `isFallbackLocation`
  - Computed: `isEmpty`, `startPoint`, `endPoint`
  - Factory constructors: `RouteSegment.outdoor(...)`, `RouteSegment.indoor(...)`, `RouteSegment.exit(...)`, `RouteSegment.entrance(...)`, `RouteSegment.floorTransition(...)`
  - `RouteSegment.fallback(...)` — for centroid fallback when no entrance/exit POI exists

**Tests:** Unit tests for creation, isEmpty, computed properties, fallback flag.

---

### Phase 3: NavigationRouteModel Update

**Goal:** Update `NavigationRouteModel` to hold `List<RouteSegment>` alongside the existing flat `points` list for backward compatibility.

**File to modify:** `lib/data/models/navigation_route_model.dart`

**Changes:**
1. Add `List<RouteSegment> segments` field (default: empty list)
2. Add `NavigationRouteStatus status` field (`ready`, `partial`, `error`)
3. Add `String? partialRouteWarning` field for incomplete route messages
4. Add `List<NavigationRoutePoint> get flatPoints` getter that reconstructs flat list from segments
5. Update constructors to accept optional `segments` parameter
6. Add `get totalDistance`, `get estimatedDuration` computed from segments
7. Add `get currentSegment`, `get nextSegment` getters

**Tests:** Backward compatibility tests (flatPoints matches segments), constructor variants.

---

### Phase 4: OSRM Route Metadata Method

**Goal:** Create a method that returns the full OSRM response including distance, duration, and geometry — needed for entrance selection scoring.

**File to modify:** `lib/data/datasources/anyplace_api_client.dart`

**Add new class:**
```dart
class OsrmRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final double finalBearingDegrees;

  const OsrmRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.finalBearingDegrees,
  });
}
```

**Add new method:** `fetchOutdoorWalkingRouteWithMetadata()` — same as `fetchOutdoorWalkingRoute()` but returns `OsrmRouteResult`. Extracts:
- `routes[0]['distance']` → `distanceMeters`
- `routes[0]['duration']` → `durationSeconds`
- Last two coordinates → compute `finalBearingDegrees`

**Keep existing method:** `fetchOutdoorWalkingRoute()` unchanged for backward compatibility.

**Bearing computation helper:**
```dart
static double _computeBearing(LatLng from, LatLng to) {
  final dLon = _toRadians(to.longitude - from.longitude);
  final lat1 = _toRadians(from.latitude);
  final lat2 = _toRadians(to.latitude);
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  final bearing = atan2(y, x);
  return (_toDegrees(bearing) + 360) % 360;
}
```

**Tests:** Unit tests for bearing computation with known coordinates.

---

### Phase 5: CrossBuildingRouter — Core Algorithm

**Goal:** Create the `CrossBuildingRouter` class that detects cross-building scenarios and composes multi-segment routes.

**File to create:** `lib/data/repositories/cross_building_router.dart`

**Dependencies:**
- `AnyplaceApiClient` (for indoor routing API calls + OSRM with metadata)
- `LocationProvider` (for user position and indoor/outdoor status)
- `SpaceProvider` (for building data, POI lists)

**Algorithm — `composeRoute()`:**

```
1. DETECT: Is user indoors at a different building than target?
   - Check LocationProvider.isIndoor
   - Check user position against buildingBoundsCache polygons
   - If same building → return null (use existing cascade)

2. SELECT EXIT POI:
   - Get all POIs in user's building where PoiClassification.isFloorTransition(poi) == true
   - Filter to ground floor (floorNumber == '0') if user position unavailable
   - Sort by distance to user indoor position (or building centroid)
   - Pick closest
   - If none found → use building centroid as FallbackLocation

3. GENERATE EXIT SEGMENT:
   - If exit POI found: call Anyplace API /api/navigation/route/coordinates
     from user position → exit POI (same building, single-building routing)
   - If fallback: straight line from user position/centroid to building centroid
   - Include floor transitions if user is not on ground floor
   - Mark segment as exitTransition type

4. SELECT ENTRANCE POI (Two-pass, corrected approach direction):
   Pass 1 — OSRM cost + bearing estimation for each candidate:
   - Get all POIs in destination building where PoiClassification.isFloorTransition(poi) == true
   - If none found → use building centroid as FallbackLocation
   - For each candidate: call OSRM via fetchOutdoorWalkingRouteWithMetadata()
     from exit point to candidate entrance
   - Store: {entrance, distance, duration, finalBearing}

   Pass 2 — Score and select:
   - For each candidate:
     a. Compute approach angle: angleBetween(candidate.finalBearing,
        vectorFromBuildingCentroidToEntrance)
     b. Angular penalty: angularDifference * 100
     c. Composite score: candidate.distance * 0.6 + angularPenalty * 0.4
   - Select entrance with lowest composite score
   - If only one candidate → skip scoring

5. GENERATE OUTDOOR SEGMENT:
   - Call OSRM one final time: exit point → selected entrance
   - Use full geometry for the outdoor polyline
   - Mark segment as outdoorWalking type

6. GENERATE ENTRANCE SEGMENT:
   - If entrance POI found: call Anyplace API /api/navigation/route
     from entrance POI → destination POI (same building)
   - If fallback: straight line from building centroid to destination POI
   - Mark segment as entranceTransition type

7. ASSEMBLE ROUTE:
   - segments = [exitSegment, outdoorSegment, entranceSegment]
   - Filter out empty segments
   - Validate total segments ≤ 6
   - Set status: ready (all segments OK) or partial (some failed)

8. RETURN:
   - NavigationRouteModel with segments and flatPoints
   - Or null if cross-building detection failed
```

**Tests:** Unit tests with real POI data for exit/entrance selection, scoring, empty segment handling.

---

### Phase 6: SpaceProvider Integration

**Goal:** Integrate `CrossBuildingRouter` into the existing routing flow.

**File to modify:** `lib/state/space_provider.dart`

**Changes:**
1. Import `CrossBuildingRouter`
2. In `requestRouteToBuilding()` (line 621), add before the existing cascade:
   ```dart
   // Cross-building detection (Adjustment 7)
   if (_locationProvider?.isIndoor == true) {
     final userBuilding = _detectBuildingFromPolygon(currentLocation);
     if (userBuilding != null && userBuilding.buid != targetSpace.buid) {
       final crossRoute = await _crossBuildingRouter.composeRoute(
         userLocation: currentLocation,
         userBuilding: userBuilding,
         targetSpace: targetSpace,
         allBuildings: _campusBuildings,
       );
       if (crossRoute != null) {
         _navigationRouteStatus = crossRoute.status;
         _activeNavigationRoute = crossRoute;
         _navigationRouteErrorMessage = crossRoute.partialRouteWarning;
         notifyListeners();
         return;
       }
     }
   }
   // Existing 3-strategy cascade continues...
   ```
3. Add `_detectBuildingFromPolygon(LatLng position)` helper using `buildingBoundsCache`
4. Add `_crossBuildingRouter` field initialized in constructor

**Tests:** Integration tests for same-building bypass, cross-building trigger, fallback to cascade.

---

### Phase 7: NavigationController — Segment State Machine

**Goal:** Update `NavigationController` to track progress through route segments.

**File to modify:** `lib/state/navigation_controller.dart`

**Changes:**
1. Add `_currentSegmentIndex` field
2. Add segment transition detection (proximity-based):
   - 10m for segment endpoints
   - 30m for floor transitions (using `NavigationConfig.connectorProximityThreshold`)
3. Add `_onSegmentTransition()` callback:
   - Update floor plan overlay
   - Update polyline visibility
   - Update step-by-step instructions
4. Add rerouting logic per segment type:
   - Wrong exit: >30m from planned outdoor route → recompute outdoor segment
   - Wrong floor: current floor != expected floor → reroute within building
   - Outdoor deviation: >50m from path → recompute outdoor segment
5. Add GPS loss handling: pause navigation, show message, resume on restore
6. Add indoor drift debounce: outside building polygon for >5 seconds → reroute
7. Add partial route handling: don't activate active navigation for partial routes

**Tests:** Unit tests for segment transitions, rerouting triggers, GPS loss.

---

### Phase 8: Map Rendering — Segment Polyline Styling

**Goal:** Display different segment types with distinct visual styles.

**File to modify:** `lib/ui/screens/map_screen.dart`

**Changes:**
1. Segment type → polyline style mapping:
   - `outdoorWalking`: dotted blue (existing pattern)
   - `indoorRouting`: solid red (existing)
   - `exitTransition`: dashed orange
   - `entranceTransition`: dashed green
   - `floorTransition`: dotted purple
2. Update `_buildPolylines()` to iterate over `route.segments`
3. Add segment labels as markers or info windows
4. Update floorplan overlay: current floor only during indoor segments
5. Update polyline visibility: show only current segment when indoors
6. Handle `isFallbackLocation` flag on segments for different marker style

**Tests:** Visual verification on device.

---

### Phase 9: Navigation UI — Step-by-Step Panel

**Goal:** Update navigation bottom sheet for segment-aware instructions.

**File to modify:** `lib/ui/widgets/map_bottom_sheet.dart`

**Changes:**
1. Show current segment prominently with instruction text
2. Show subsequent segments dimmed below
3. Add segment type icons (door, walking, elevator, etc.)
4. Show "You are here" indicator within current segment
5. Show remaining distance/time per segment + total
6. Show partial route warning banner when `route.status == partial`

**Tests:** Visual verification on device.

---

### Phase 10: Error Handling & Edge Cases

**Goal:** Handle all edge cases (Adjustments 4, 6).

**Files to modify:**
- `lib/data/repositories/cross_building_router.dart`
- `lib/state/navigation_controller.dart`
- `lib/state/space_provider.dart`

**Edge cases:**
1. No exit POIs → centroid fallback with `isFallbackLocation = true`
2. No entrance POIs → centroid fallback with `isFallbackLocation = true`
3. API failure per segment → mark segment `isIncomplete`, set route status to `partial`
4. GPS loss → pause navigation, show message, resume on restore
5. Indoor position unavailable → use building centroid
6. Building change mid-route → show notification with reroute option
7. Destination locked → don't auto-reroute
8. Same building → bypass cross-building router
9. Max 6 segments → validate and truncate

---

### Phase 11: Real-Device Testing

**Goal:** End-to-end validation on CPH2185 with real EJUST data.

**Test scenarios:**
1. Same building navigation → verify existing cascade unchanged
2. Outdoor start → different building → outdoor + entrance + indoor
3. Indoor start at Building A → Building B → exit + outdoor + entrance + indoor
4. Indoor start, wrong exit → rerouting at >30m
5. Outdoor deviation → rerouting at >50m
6. GPS loss during outdoor → pause and resume
7. Floor transition → floorplan overlay switches
8. No entrance POIs → centroid fallback
9. No exit POIs → centroid fallback
10. User enters wrong building → notification appears
11. Partial route → warning banner shown, active navigation disabled

---

### Phase 12: Cleanup & Polish

1. Remove unused imports
2. Update documentation
3. Run `flutter analyze` — zero issues
4. Run full test suite — all passing
5. Manual smoke test on device

---

## Files Summary

| File | Action | Phase |
|------|--------|-------|
| `lib/utils/poi_classification.dart` | **Create** | 1 |
| `lib/data/models/route_segment.dart` | **Create** | 2 |
| `lib/data/models/navigation_route_model.dart` | Modify | 3 |
| `lib/data/datasources/anyplace_api_client.dart` | Modify | 4 |
| `lib/data/repositories/cross_building_router.dart` | **Create** | 5 |
| `lib/state/space_provider.dart` | Modify | 6 |
| `lib/state/navigation_controller.dart` | Modify | 7 |
| `lib/ui/screens/map_screen.dart` | Modify | 8 |
| `lib/ui/widgets/map_bottom_sheet.dart` | Modify | 9 |

---

## Corrections Log

| Issue | Before (Wrong) | After (Correct) |
|-------|----------------|-----------------|
| Phase 6 status | `crossRoute.status == partial ? ready : ready` | `_navigationRouteStatus = crossRoute.status` |
| Approach direction | Vector from exit → building centroid | Actual OSRM route's final bearing near destination |
| Entrance scoring | centroid angle * weight | finalBearing angle * weight |
| OSRM data needed | geometry only | geometry + distance + duration + finalBearing |
