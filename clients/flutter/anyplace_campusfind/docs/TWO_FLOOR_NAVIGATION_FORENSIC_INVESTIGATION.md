# Two-Floor Navigation — Forensic Investigation

## 1. Executive Summary

This document presents a forensic investigation of two-floor navigation in the E-JUST Interactive Map / Anyplace CampusFind codebase. The system **does support** multi-floor routing within a single building via Dijkstra across a whole-building POI graph. The backend calculates shortest paths through stair/elevator connections, and the frontend receives a flat list of waypoints with per-point floor numbers.

However, the implementation has **several confirmed critical issues**:

1. **`navigateSameBuilding()` omits `pois_type` from route response** (CONFIRMED) — the frontend cannot distinguish stairs from elevators from hallway points on a multi-floor route. This is a backend bug at `NavigationController.scala:270-278` where `NavResultPoint.pois_type` is never set.

2. **Route floor transition detection relies purely on coordinate proximity + WiFi evidence** — there is no explicit "connector reached" signal from the backend. The frontend infers transitions by checking if consecutive route points differ in floor number and whether the user is within 30m of the transition point.

3. **Floor transition has a positioning blackout** — during transition, the user's last indoor position is held (frozen marker), and a 3-consecutive-estimate stability gate must be satisfied before the new floor is confirmed. If WiFi doesn't report the new floor quickly enough, the transition times out after 30s and aborts.

4. **The route is NOT re-requested after a floor change** — instead, `_ensureIndoorGuidance()` requests a fresh indoor route from the nearest POI to the destination after confirming the new floor. This means the route segment on the new floor is derived from a NEW API call anchored at the nearest loaded POI, not from the original multi-floor Dijkstra result.

5. **Rendering is floor-safe** — the system filters route polylines by displayed floor during indoor emphasis, so cross-floor geometry is never drawn on the wrong floor. This is correctly implemented via `routePolylineSpecs()` and `segmentVisibility()`.

## 2. Current Architecture

The system has three layers:

```
┌─────────────────────────────────────┐
│  Flutter Client (Dart)              │
│  - UI (Google Maps + overlays)      │
│  - NavigationController (state m.)  │
│  - LocationProvider (GPS + WiFi)    │
│  - SpaceProvider (route store)      │
│  - CrossBuildingRouter              │
│  - Native Kotlin positioning engine │
├─────────────────────────────────────┤
│  Backend (Play 2.8 / Scala)         │
│  - NavigationController.scala       │
│  - Dijkstra.scala                   │
│  - MongoDB (POIs, Connections)      │
├─────────────────────────────────────┤
│  Native Android (Kotlin)            │
│  - KnnLocalizer (Wi-Fi fingerprint) │
│  - RadioMap loading                 │
└─────────────────────────────────────┘
```

**CONFIRMED** — Architecture from: `clients/flutter/anyplace_campusfind/lib/`, `server/app/controllers/NavigationController.scala`, `server/app/utils/Dijkstra.scala`, `android/app/src/main/kotlin/` (referenced in native_positioning_service.dart).

Key data stores in MongoDB:
- `pois` — Points of Interest (vertices in navigation graph)
- `edges` — Connections between POIs (edges in navigation graph)
- `floors` — Floor metadata
- `buildings` — Building/spaces metadata

## 3. Actual End-to-End Flow

The actual sequence for same-building, different-floor navigation:

```
1. User selects destination POI on floor 2 (currently on floor 1)
2. SpaceProvider.requestRouteToSelectedPoi() called
3. Strategy 1: fetchNavigationRouteFromCoordinates(lat, lon, floor="1", destPuid)
   → POST /api/navigation/route/coordinates
4. Backend: finds closest POI on floor 1, calls navigateSameBuilding()
5. Backend: loads ALL POIs across ALL floors + ALL connections (excl. outdoor)
6. Backend: runs Dijkstra on full building graph
7. Backend: returns flat list of NavResultPoint (lat, lon, puid, buid, floor_number)
   CRITICAL: pois_type NOT included in navigateSameBuilding response
8. Frontend: NavigationRouteModel.fromJson() parses points (poisType defaults to "None")
9. SpaceProvider: route.toSegmentedIndoor() wraps into single indoorRouting segment
10. SpaceProvider: _activeNavigationRoute set, notifyListeners()
11. User taps "Start Directions" → NavigationController.startActiveNavigation()
12. State: routePreview → activeOutdoor or activeIndoor (depends on WiFi)
13. Location updates flow via _onLocationChanged()
14. _checkFloorTransition() runs each tick:
    a. Checks route.floorTransitionIndices for connector proximity (30m)
    b. When near connector point where floor changes → _beginConnectorFloorTransition()
    c. State → floorTransition, position held, expected floor set
    d. WiFi evidence must confirm new floor (3 consecutive estimates)
    e. _completeFloorTransition() → floor confirmed, state → activeIndoor
15. _ensureIndoorGuidance() called → requests FRESH indoor route via
    requestIndoorRouteForSession() (API call from nearest POI to destination)
16. New route adopted, arrival anchor re-resolved
17. Navigation continues on new floor
18. _checkArrival() detects proximity to destination anchor
19. Arrival confirmed (2 consecutive ticks within 15m, identity match)
20. State → arrived
```

**CONFIRMED** — Trace from: `space_provider.dart:723-922`, `NavigationController.scala:111-280`, `navigation_controller.dart:530-570,1277-1450`.

## 4. Backend Route Calculation

### API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `POST /api/navigation/route` | POI-to-POI | Two-floor routing |
| `POST /api/navigation/route/coordinates` | GPS+floor → POI | Two-floor routing from position |

**CONFIRMED** — `server/conf/api.routes:1044-1140`, `NavigationController.scala:111-235`.

### Same-Building Different-Floor Routing

`navigateSameBuilding()` at `NavigationController.scala:263-280`:

```scala
private def navigateSameBuilding(from: JsValue, to: JsValue): util.List[JsValue] = {
  val graph = new Dijkstra.Graph()
  graph.addPois(pds.db.poisByBuildingAsMap(...))  // ALL POIs, ALL floors
  graph.addEdges(pds.db.connectionsByBuildingAsMap(...))  // ALL connections
  val routePois = Dijkstra.getShortestPath(graph, from_puid, to_puid)
  // ... builds NavResultPoint for each POI in path
  p.pois_type = poi.get(SCHEMA.fPoisType)  // LINE 277: NEVER SET for navigateSameBuilding
}
```

**CONFIRMED BUG**: `navigateSameBuilding()` does NOT set `p.pois_type` on the `NavResultPoint` objects. Compare with `navigateSameFloor()` at line 257: `p.pois_type = poi.get(SCHEMA.fPoisType)` which IS set. The `navigateSameBuilding` method at line 270-278 only sets lat, lon, puid, buid, floor_number — NOT pois_type.

### Graph Structure

The Dijkstra graph (`Dijkstra.scala:46-106`):
- **Vertices**: All POIs in the building (all floors)
- **Edges**: All connections (excluding outdoor type), bidirectional
- **Weights**: Haversine distance in km between connected POIs
- **Result**: Flat ordered list of POI HashMaps from source to destination

Floor transitions are represented implicitly: when a stair/elevator connection links a POI on floor 1 to a POI on floor 2, Dijkstra can traverse that edge. The resulting path naturally alternates between floor numbers.

**CONFIRMED** — `Dijkstra.scala:46-182`, `MongodbDatasource.scala:connectionsByBuildingAsMap`.

### Edge Types in Database

Connections have `edge_type`: "stair", "elevator", "hallway", "room", "outdoor". Outdoor connections are filtered out of routing. The edge type is NOT passed through to the frontend in the response — only the POI data (including `pois_type`) is returned.

**CONFIRMED** — `Connection.scala:43-48`, `MongodbDatasource.scala:760-771`.

## 5. Route Data Pipeline

### Backend → Frontend Data Flow

```
Backend NavResultPoint (JSON):
  {lat, lon, puid, buid, floor_number, pois_type}
                    ↓
Flutter NavigationRoutePoint.fromJson():
  {latitude, longitude, puid, buid, floorNumber, poisType, isOutdoor}
                    ↓
NavigationRouteModel {points: List<NavigationRoutePoint>}
                    ↓
SpaceProvider.requestRouteToSelectedPoi():
  route.toSegmentedIndoor() → wraps into RouteSegment.indoor()
                    ↓
NavigationRouteModel {points, segments: [RouteSegment.indoor]}
                    ↓
SpaceProvider._activeNavigationRoute = route
                    ↓
NavigationController reads _spaceScope.activeNavigationRoute
                    ↓
MapScreen._buildPolylines() → routePolylineSpecs() → Google Maps Polyline
```

**CONFIRMED** — `anyplace_api_client.dart:fetchNavigationRoute`, `navigation_route_model.dart:175-197`, `space_provider.dart:809-818`.

### Critical Data: `toSegmentedIndoor()`

When a same-building route is received, it's wrapped via `toSegmentedIndoor()` (`navigation_route_model.dart:263-289`). This creates a SINGLE `RouteSegment.indoor()` wrapping ALL points. The segment's `pointFloors` list carries per-point truthful floor numbers.

**CONFIRMED** — `navigation_route_model.dart:263-289`.

### Information Loss Points

1. **`pois_type` loss**: `navigateSameBuilding()` backend response omits `pois_type` → frontend `NavigationRoutePoint.poisType` defaults to `"None"` for ALL points. This means connector POIs (stairs, elevators) lose their type identity.

2. **No connector type preserved**: The `RouteSegment.connectorPoiId` field exists but is never populated for same-building indoor routes (only used by CrossBuildingRouter).

3. **Flat point list**: The backend returns a flat list, not segmented by floor. Frontend must detect floor changes by comparing consecutive `floor_number` values.

**CONFIRMED** — `NavigationController.scala:270-278` (no pois_type), `navigation_route_model.dart:87-89` (default "None").

## 6. Floor Transition Representation

### In Backend Response

Floor transitions are represented as **consecutive points with different `floor_number` values**. For example:
```json
[
  {"puid": "poi_1", "floor_number": "1", "lat": "...", "lon": "..."},
  {"puid": "poi_stair_bottom", "floor_number": "1", "lat": "...", "lon": "..."},
  {"puid": "poi_stair_top", "floor_number": "2", "lat": "...", "lon": "..."},
  {"puid": "poi_5", "floor_number": "2", "lat": "...", "lon": "..."}
]
```

The transition is points[1] → points[2] where floor_number changes from "1" to "2".

**CONFIRMED** — `Dijkstra.scala:166-175` (path reconstruction is ordered source→target), `NavigationController.scala:263-280`.

### In Frontend Model

`NavigationRouteModel.floorTransitionIndices` (`navigation_route_model.dart:310-319`):
```dart
List<int> get floorTransitionIndices {
  final indices = <int>[];
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i].floorNumber;
    final b = points[i + 1].floorNumber;
    if (a.isEmpty || b.isEmpty) continue;  // skip empty floors (outdoor)
    if (a != b) indices.add(i);
  }
  return indices;
}
```

Returns the index `i` where `points[i].floorNumber != points[i+1].floorNumber`. This is the "connector point" on the current floor.

**CONFIRMED** — `navigation_route_model.dart:310-319`.

### In NavigationController

`_checkFloorTransition()` (`navigation_controller.dart:1277-1356`):
1. Iterates `floorTransitionIndices`
2. For each transition index `idx`, checks if `points[idx].floorNumber == currentFloor`
3. Checks distance to `points[idx]` (the connector POI on current floor)
4. If within 30m (`connectorProximityThreshold`) → `_beginConnectorFloorTransition(points[idx+1].floorNumber)`

**CONFIRMED** — `navigation_controller.dart:1283-1304`.

## 7. Stairs / Elevator / Connectors

### Backend Representation

- **Stairs**: POI with `pois_type = "stair"` connected to another POI on a different floor via a Connection with `edge_type = "stair"`
- **Elevators**: POI with `pois_type = "elevator"` connected to another POI on a different floor via a Connection with `edge_type = "elevator"`
- **Connectors (generic)**: POI with `pois_type = "None"` — a sentinel value indicating a floor-transition point

**CONFIRMED** — `Poi.scala:46-48`, `Connection.scala:43-48`.

### Frontend Classification

`poi_classification.dart` (`utils/poi_classification.dart`):
```dart
static bool isConnector(String poisType) => poisType == 'None';
static bool isElevator(String poisType) => poisType.toLowerCase().contains('elevator');
static bool isStairs(String poisType) => poisType.toLowerCase().contains('stairs');
static bool isFloorTransition(String poisType) =>
    isConnector(poisType) || isElevator(poisType) || isStairs(poisType);
```

**CONFIRMED** — `poi_classification.dart`.

### Critical Issue: Frontend Cannot Distinguish Stairs vs Elevators

Because `navigateSameBuilding()` omits `pois_type` from the response, ALL points in a multi-floor route have `poisType = "None"` in the frontend. The frontend has **zero information** about whether a transition point is stairs or elevator.

**CONFIRMED** — `NavigationController.scala:270-278` (no pois_type assignment), `navigation_route_model.dart:87-89` (default "None").

### How Frontend Detects Transitions

The frontend detects floor transitions purely by:
1. Comparing consecutive `floor_number` values (via `floorTransitionIndices`)
2. Checking proximity to the transition point (30m threshold)
3. Waiting for WiFi floor evidence to confirm the new floor

The frontend does NOT look at `pois_type` or `connectorPoiId` to detect transitions — only at `floor_number` differences.

**CONFIRMED** — `navigation_controller.dart:1283-1304`.

### User Instructions

The UI shows "Moving to Floor N..." during transition (`NavigationConfig.transitionBlackoutMessage`). There is NO instruction like "Take stairs" or "Use elevator" because the connector type information is lost.

**CONFIRMED** — `navigation_config.dart:209`, `navigation_controller.dart:395-403`.

## 8. Route Segmentation

### How Segments Are Created

For same-building navigation, the route is wrapped into a **single** `RouteSegment.indoor()` by `toSegmentedIndoor()`. All points across all floors are in this one segment, with `pointFloors` carrying per-point floor numbers.

**CONFIRMED** — `navigation_route_model.dart:263-289`.

### Floor Filtering During Rendering

`routePolylineSpecs()` in `navigation_display.dart:225-277`:

For segmented indoor routes with `pointFloors`:
```dart
if (isIndoorLeg && displayedFloor != null && hasAlignedFloors &&
    seg.pointFloors.any((f) => f == displayedFloor)) {
  points = [
    for (var j = 0; j < seg.points.length; j++)
      if (seg.pointFloors[j] == displayedFloor) seg.points[j],
  ];
  if (points.length < 2) continue;  // skip if < 2 points on this floor
}
```

This correctly filters to only the displayed floor's points.

**CONFIRMED** — `navigation_display.dart:246-258`.

### Can Segments Lose Information?

YES. If fewer than 2 points exist on the displayed floor, that floor's route segment is **silently dropped** (`continue` at line 257). This could happen if a floor has very few POIs on the route.

**CONFIRMED** — `navigation_display.dart:257`.

### Segment Transition Detection

`_checkSegmentTransition()` (`navigation_controller.dart:1744-1804`):
- Checks proximity to current segment's endpoint
- Advances `_currentSegmentIndex` when reached
- Only applies to routes with `hasSegments` (cross-building routes)
- **Same-building routes have a single segment, so segment transitions don't apply**

**CONFIRMED** — `navigation_controller.dart:1744-1774`.

## 9. Route Rendering

### Rendering Pipeline

```
MapScreen.build()
  → Consumer2<SpaceProvider, LocationProvider>
    → GoogleMap(polylines: _buildPolylines(spaceProvider, navController))
      → routePolylineSpecs(route, displayedFloor, indoorEmphasis)
        → For each segment: segmentVisibility() → filter by floor → style by type
```

**CONFIRMED** — `map_screen.dart:_buildPolylines()` → `navigation_display.dart:225-313`.

### Floor-Safe Rendering

`segmentVisibility()` (`navigation_display.dart:59-85`):
- `outdoorWalking`: visible always, dimmed during indoor emphasis
- `indoorRouting` / `floorTransition`: visible only when `floor == displayedFloor` (during indoor emphasis)
- `exitTransition` / `entranceTransition`: visible when any floor displayed

**CONFIRMED** — `navigation_display.dart:59-85`.

### Cross-Floor Geometry Protection

The `pointFloors` filtering ensures only points matching `displayedFloor` are rendered. Lines are drawn only between same-floor points. If consecutive same-floor points exist, they form a connected polyline. If they don't (because intermediate points are on another floor), the resulting polyline has gaps — but those gaps are acceptable because the route on a different floor should not be visible.

**CONFIRMED** — `navigation_display.dart:246-258`.

### Can Wrong Floor Route Be Displayed?

NO — during indoor emphasis (activeIndoor state), only the displayed floor's points are rendered. However, during **preview** (`indoorEmphasis = false`), the FULL multi-floor route is visible. This is intentional — it shows the user where the journey leads.

**CONFIRMED** — `navigation_display.dart:76` (!indoorEmphasis → always visible).

## 10. NavigationController State Flow

### Complete State Machine

```
idle → routePreview → activeOutdoor
                   → activeIndoor
activeOutdoor → enteringBuilding → activeIndoor
             → rerouting → (back to previous)
             → paused → (back to previous)
             → arrived
activeIndoor → floorTransition → activeIndoor
            → exitingBuilding → activeOutdoor
            → rerouting → (back to previous)
            → paused → (back to previous)
            → arrived
floorTransition → activeIndoor (confirmed)
               → exitingBuilding (GPS evidence)
               → idle (end)
exitingBuilding → activeOutdoor (confirmed)
               → activeIndoor (WiFi re-engaged)
               → idle (end)
arrived → idle (user ends)
paused → idle (user ends)
rerouting → idle (user ends)
```

**CONFIRMED** — `navigation_state_model.dart:173-215` (allowed transitions table), `navigation_controller.dart:_transition()`.

### Floor-Related State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `_currentNavigatingFloor` | `String?` | Route-context bookkeeping: which floor the route says we're on |
| `_expectedNextFloor` | `String?` | Floor expected during floorTransition state |
| `_connectorInitiatedTransition` | `bool` | Whether transition was triggered by connector proximity vs organic drift |
| `_newFloorEstimateCount` | `int` | Consecutive WiFi estimates confirming new floor |
| `_lastFloorSwitchTime` | `DateTime?` | When last floor switch happened (for suppression) |
| `_transitionStartTime` | `DateTime?` | When floorTransition state began (for timeout) |
| `_lastIndoorPosition` | `UserLocation?` | Position held during transition blackout |
| `_exitConfirmationCounter` | `int` | GPS ticks confirming building exit |

**CONFIRMED** — `navigation_controller.dart:75-110`.

### State Consistency Risks

`_currentNavigatingFloor` is **route-context bookkeeping**, NOT physical floor evidence. It can become stale if:
- WiFi positioning reports a different floor than the route expects
- The user takes a different stairwell than the calculated route
- Floor detection oscillates

The system handles this via the `_expectedNextFloor` guard: if WiFi evidence doesn't match the expected floor, the counter resets.

**CONFIRMED** — `navigation_controller.dart:1326-1329`.

## 11. Positioning and Floor Detection

### Position Source Arbitration

`LocationProvider` (`location_provider.dart`) arbitrates between:
1. **GPS** (outdoor): via `GpsLocationService` using Geolocator
2. **Wi-Fi fingerprinting** (indoor): via `NativePositioningService` → Kotlin KnnLocalizer

Arbitration:
- Starts in outdoor (GPS) mode
- After 3 consecutive qualifying WiFi estimates → switches to indoor mode
- WiFi estimates must have ≥25% matched APs (`minMatchedRatio`)
- Indoor→outdoor switch: 3 consecutive bad/outlier cycles

**CONFIRMED** — `location_provider.dart:89-120`, `navigation_config.dart:127-133`.

### Floor Detection

Floor comes from `PositionEstimate.floor` — the native Kotlin engine reports which RadioMap (identified by buid+floor) was the best match for the WiFi fingerprint. The `PositionFix` (canonical published fix) only carries `buildingId` and `floor` after scope confirmation (3 consecutive consistent claims).

**CONFIRMED** — `position_estimate.dart:8-9`, `location_provider.dart:80-86` (scopeConfirmCount).

### RadioMap Loading

RadioMaps are loaded per-floor: `radiomap_cache.dart` stores files at `<appSupportDir>/radiomaps/<buid>/<floor>/`. The native engine can hold up to 4 resident RadioMaps simultaneously (`residentMapLimit = 4`). When the user is on floor 1, only floor 1's RadioMap is loaded. After a floor change, the NEW floor's RadioMap must be loaded before positioning works.

**CONFIRMED** — `radiomap_cache.dart`, `navigation_config.dart:123`.

### Critical: RadioMap Must Be Loaded Before Floor Detection Works

When the user changes floors, WiFi fingerprints from the NEW floor won't produce valid estimates until the NEW floor's RadioMap is loaded into the native engine. This creates a **chicken-and-egg problem**:
1. Floor change detection needs WiFi estimates from the new floor
2. WiFi estimates from the new floor need the new floor's RadioMap loaded
3. The RadioMap is loaded by SpaceProvider when the floor is selected

The NavigationController handles this by calling `_spaceScope.selectFloorForNavigation(targetFloor)` in `_beginConnectorFloorTransition()` (line 1389-1391), which triggers RadioMap loading. Then `_ensureIndoorGuidance()` waits up to 20s for RadioMap readiness before requesting a fresh indoor route.

**CONFIRMED** — `navigation_controller.dart:1387-1391`, `space_provider.dart:1426-1482`.

### Post-Floor-Switch Suppression

After a floor switch, there's a 10-second suppression period where positioning ticks are still processed but reroute checks are skipped (`postFloorSwitchSuppressSeconds = 10`). This prevents stale positioning from triggering immediate reroutes.

**CONFIRMED** — `navigation_controller.dart:1115-1122`, `navigation_config.dart:212`.

## 12. Map/UI Behavior

### What the User Sees During Two-Floor Navigation

1. **Route preview**: Full multi-floor route shown (all floors visible)
2. **Start navigation**: User sees route filtered to current floor only
3. **Approaching connector**: Status bar shows current floor indicator
4. **At connector (30m)**: 
   - State → floorTransition
   - Status shows "Moving to Floor 2..."
   - User marker FREEZES at last indoor position
   - Map may switch to new floor's floorplan
5. **On new floor (WiFi confirms)**:
   - Floor confirmed, state → activeIndoor
   - Fresh indoor route fetched
   - Route re-rendered for new floor
   - User marker resumes following WiFi position
6. **Arriving**: "Arrived at [destination]" banner

**CONFIRMED** — `navigation_display.dart:26-48`, `map_screen.dart:_onNavigationChanged()`.

### Floor Switch in Map

`_beginConnectorFloorTransition()` calls `_spaceScope.selectFloorForNavigation(targetFloor)` which:
- Selects the new floor in SpaceProvider
- Triggers floorplan loading for the new floor
- Triggers POI loading for the new floor
- Triggers RadioMap loading for the new floor

The map view changes to show the new floor's floorplan overlay.

**CONFIRMED** — `navigation_controller.dart:1387-1391`, `space_provider.dart:selectFloorForNavigation()`.

### No Stairs/Elevator Instruction

The UI does NOT show "Take stairs" or "Use elevator" because:
1. Backend `navigateSameBuilding()` doesn't return `pois_type`
2. Frontend connector classification depends on `pois_type`
3. The only instruction is "Moving to Floor N..."

**CONFIRMED** — `NavigationController.scala:270-278`, `navigation_config.dart:209`.

## 13. State Machine Reconstruction

### Implicit Floor Transition State Machine

```
[idle_floor]
  │
  │ (route has floorTransitionIndices)
  │ (user near connector point on current floor, <30m)
  ▼
[connector_approached]
  │
  │ (_beginConnectorFloorTransition)
  │ (enter floorTransition state)
  │ (hold position, cache last indoor fix)
  │ (select target floor, load floorplan/radiomap)
  ▼
[awaiting_evidence]
  │
  │ (WiFi estimates report new floor)
  │ (3 consecutive consistent estimates needed)
  │
  ├─(evidence matches expected floor)──→ [floor_confirmed]
  │                                        │
  │                                        │ (_completeFloorTransition)
  │                                        │ (update _currentNavigatingFloor)
  │                                        │ (sync selected floor)
  │                                        │ (ensureIndoorGuidance → fresh route)
  │                                        │ (state → activeIndoor)
  │                                        ▼
  │                                     [navigating_new_floor]
  │
  ├─(evidence doesn't match expected)──→ [evidence_rejected] → back to awaiting
  │
  ├─(timeout 30s)──→ [transition_aborted]
  │                    │
  │                    │ (reset expectedNextFloor)
  │                    │ (state → activeIndoor)
  │                    │ (evidence re-evaluates on subsequent ticks)
  │                    ▼
  │                 [back_to_old_floor_or_organic_detection]
  │
  └─(no WiFi evidence at all)──→ [stuck_in_transition] → eventually times out
```

### Organic Floor Transition (No Connector)

```
[active_indoor]
  │
  │ (WiFi evidence shows different floor, no connector proximity)
  │ (3 consecutive estimates)
  ▼
[_beginOrganicFloorTransition]
  │
  │ (immediately calls _completeFloorTransition)
  │ (no timeout, no waiting)
  ▼
[complete] → activeIndoor on new floor
```

**CONFIRMED** — `navigation_controller.dart:1396-1407`.

## 14. Async / Race Condition Analysis

### Race 1: Stale Route During Floor Transition

**Scenario**: Floor transition starts → `_ensureIndoorGuidance()` fires async API request → WiFi evidence arrives before API response → floor confirmed → new route committed → old API response arrives later.

**Protection**: `_isCurrent(sessionId: sid, revision: rev)` check at `navigation_controller.dart:557-561`. If session/revision changed, stale response is discarded.

**CONFIRMED** — `navigation_controller.dart:557-561`.

### Race 2: Floor Detection Oscillation

**Scenario**: WiFi alternates between floor 1 and floor 2 → `_newFloorEstimateCount` keeps resetting → transition never completes.

**Protection**: The `_expectedNextFloor` guard at line 1326-1329: if evidence doesn't match expected floor, counter resets. If no expected floor, organic drift can trigger. The 30s timeout (`_checkTransitionTimeout()`) is the ultimate fallback.

**CONFIRMED** — `navigation_controller.dart:1326-1329,1452-1481`.

### Race 3: Location Update During Transition Blackout

**Scenario**: During floorTransition state, `_onLocationChanged()` returns early at line 1112-1116 (if `_lastIndoorPosition != null`). But `_checkTransitionTimeout()` still runs. So timeout works even during blackout.

**CONFIRMED** — `navigation_controller.dart:1110-1118`.

### Race 4: Route Re-rendering During Floor Switch

**Scenario**: Floor selected → polylines rebuilt → floor plan changed → route filtered → display updated. All within same event loop tick (notifyListeners). Google Maps Flutter handles this via platform channel diffing.

**POSSIBLE**: No explicit protection against mid-render state changes, but Flutter's widget rebuild cycle makes this unlikely to be observable.

### Race 5: Multiple Floor Transitions in Quick Succession

**Scenario**: User rapidly changes floors (e.g., in an elevator) → multiple floor transitions fire.

**Protection**: The `floorTransition` state prevents new connector-initiated transitions (line 1360: `if (_state != NavigationState.activeIndoor) return`). Only organic drift or timeout can interrupt. Timeout is 30s. Post-switch suppression is 10s.

**CONFIRMED** — `navigation_controller.dart:1360`.

### Race 6: GPS While Indoor

**Scenario**: Indoor WiFi positioning is primary, but GPS also reports. GPS could report a position outside the building while WiFi says inside.

**Protection**: The arbiter switches between GPS and WiFi with hysteresis (3 ticks to enter/exit). `_checkBuildingExit()` requires WiFi to be inactive AND GPS to be accurate AND outside building AND 3 consecutive confirmations.

**CONFIRMED** — `navigation_controller.dart:1491-1522`.

## 15. Geometry / Coordinate Analysis

### Cross-Floor Geometry Safety

When `pointFloors` are used for filtering, only points matching the displayed floor are included in the rendered polyline. If points A (floor 1), B (floor 1), C (floor 2), D (floor 2):
- Floor 1 view: renders [A, B] — a connected line segment
- Floor 2 view: renders [C, D] — a connected line segment
- No line is drawn between B and C (cross-floor)

**CONFIRMED** — `navigation_display.dart:246-258`.

### Without pointFloors (Legacy Fallback)

If `pointFloors` is empty (which shouldn't happen for same-building routes since `toSegmentedIndoor()` populates it), the entire segment is shown/hidden as a unit based on the segment's `floorNumber`. For a single-segment route with all points, this would mean the ENTIRE route shows or hides.

**CONFIRMED** — `navigation_display.dart:246-258`.

### Connector Coordinates Between Floors

The backend's stair/elevator connections link POIs on different floors. Each POI has its own coordinates. For example:
- Stair bottom POI: lat=30.866, lon=29.583, floor=1
- Stair top POI: lat=30.866, lon=29.583, floor=2

Same lat/lon is common for stairs (vertical). Different lat/lon for escalators connecting different locations. The coordinates are geographic (WGS84), not local.

**POSSIBLE**: Without seeing actual database records, the exact coordinate relationship between floor-transition POIs is inferred from the model design. Backend `getConnectionWeight()` uses Haversine distance, which could produce very small weights for same-location cross-floor connections.

### Can Lines Be Drawn Between Floors?

No — the rendering pipeline filters by `displayedFloor`. Points from different floors are never in the same rendered polyline during indoor emphasis.

**CONFIRMED** — `navigation_display.dart:246-258`.

## 16. Edge Cases

### A. Floor 1 → Floor 2
**SUPPORTED** — Standard case. Backend Dijkstra finds path through stair/elevator connection. Frontend detects floor transition via `floorTransitionIndices`, triggers `floorTransition` state, waits for WiFi evidence.

### B. Floor 2 → Floor 1
**SUPPORTED** — Same mechanism as A. Direction doesn't matter to Dijkstra or the frontend.

### C. Floor 1 → Floor 3
**SUPPORTED (IF connections exist)** — Dijkstra finds shortest path through floor 2 connections if direct floor 1→3 connection doesn't exist. Multiple floor transitions possible.

### D. Floor 3 → Floor 1
**SUPPORTED (IF connections exist)** — Same as C, reversed.

### E. Multiple Floor Transitions (Floor 1 → Floor 2 → Floor 3)
**PARTIALLY SUPPORTED** — Backend can calculate this path. Frontend handles each transition sequentially via `floorTransition` state. However:
- After first transition (1→2), `_ensureIndoorGuidance()` requests a NEW route from nearest POI on floor 2 to destination
- This new route is a separate API call, not a continuation of the original multi-floor route
- The second transition (2→3) depends on the new route having floor transition indices
- **Risk**: If the new route doesn't include the floor 2→3 connection (e.g., different path chosen), the user could be left without guidance

**POSSIBLE** — `navigation_controller.dart:540-570`.

### F. Stairs
**SUPPORTED (without type distinction)** — Stairs are traversed in the Dijkstra graph. Frontend detects floor change but doesn't know it's stairs vs elevator.

### G. Elevator
**SUPPORTED (without type distinction)** — Same as F.

### H. User Starts Near Connector
**SUPPORTED** — If user is within 30m of connector on the current floor, the transition triggers immediately. `_beginConnectorFloorTransition()` enters floorTransition state.

### I. User Starts Far from Connector
**SUPPORTED** — Route guides user to connector, then transition triggers on proximity.

### J. User Changes Floors But Positioning Still Reports Old Floor
**HANDLED** — The `_expectedNextFloor` guard blocks evidence from the wrong floor. Timeout (30s) eventually aborts. The system stays in `floorTransition` state with held position.

**CONFIRMED** — `navigation_controller.dart:1326-1329`.

### K. User Changes Floors But Floor Detection Changes Too Early
**HANDLED** — Organic floor transitions can fire immediately via `_beginOrganicFloorTransition()` which calls `_completeFloorTransition()` without waiting. This handles premature detection.

### L. User Manually Changes Floor in UI
**POTENTIALLY BROKEN** — `selectFloorForNavigation()` changes the displayed floor and loads its floorplan/radiomap, but does NOT update `_currentNavigatingFloor` in NavigationController. The route context floor and the displayed floor can diverge. The route rendering uses `displayedFloor` from SpaceProvider, while floor transition detection uses `_currentNavigatingFloor` from NavigationController.

**POSSIBLE** — Requires further investigation of whether `selectFloorForNavigation` and `_currentNavigatingFloor` can diverge in practice.

### M. User Changes Floor While Navigation Is Active
**PARTIALLY SUPPORTED** — Same as L. The map shows the new floor, but the navigation state may not follow if the manual change doesn't match WiFi evidence.

### N. User Goes to Wrong Floor
**PARTIALLY SUPPORTED** — WiFi evidence would report the wrong floor. If it doesn't match `_expectedNextFloor`, the transition counter resets. If there's no expected floor, organic drift could trigger. Eventually, the user would need to reroute.

### O. User Takes Different Connector Than Calculated Route
**PARTIALLY SUPPORTED** — If user walks to a connector NOT on the route, `_checkFloorTransition()` won't find it in `floorTransitionIndices`. However, organic drift via WiFi evidence could still trigger `_beginOrganicFloorTransition()`. The route would need rerouting.

### P. User Goes Backwards
**SUPPORTED** — `_checkDeviationAndReroute()` detects deviation from the route polyline (>15m for 2 consecutive ticks) and triggers rerouting.

### Q. User Leaves Calculated Route
**SUPPORTED** — Same as P. Rerouting triggers after deviation threshold.

### R. User's Position Jumps to Another Floor
**HANDLED** — Outlier jump guard in LocationProvider (30m threshold). If WiFi estimates jump, they're held until scope confirms. In NavigationController, the `_newFloorEstimateCount` requires 3 consecutive consistent estimates.

### S. Route Recalculation After Floor Change
**SUPPORTED** — `_ensureIndoorGuidance()` requests fresh route after floor confirmation.

### T. App Restart During Multi-Floor Navigation
**UNSUPPORTED** — Navigation state is in-memory only. No persistence. App restart = `NavigationState.idle`. Route lost.

**UNKNOWN** — No evidence of state persistence in `navigation_controller.dart`.

## 17. Existing Tests

### Directly Relevant to Two-Floor Navigation

| Test File | Lines | What It Tests | What It Does NOT Test |
|-----------|-------|---------------|----------------------|
| `floor_transition_test.dart` | 818 | Floor transition lifecycle (EXPECTED→DETECTED→CONFIRMED→ABORTED), position hold, post-switch suppression | Does NOT test actual route rendering after transition, does NOT test fresh route fetch, does NOT test multi-transition sequences |
| `navigation_state_machine_test.dart` | 1193 | State transitions, route lifecycle, session management | Does NOT test floor-specific state transitions in detail |
| `route_rendering_representation_test.dart` | 320 | routePolylineSpecs projection, segment styles | Does NOT test floor-filtered rendering of multi-floor routes |
| `rendering_consistency_test.dart` | 122 | segmentVisibility rules | Tests rules only, not actual rendering |
| `same_building_route_representation_test.dart` | 358 | Same-building route renders as indoorRouting | Does NOT test multi-floor same-building routes |
| `arrival_test.dart` | 720 | Arrival detection, proximity, identity matching | Does NOT test arrival on different floor from start |
| `navigation_baseline_characterization_test.dart` | 626 | Pins known-broken behaviors | Regression anchors only |
| `handoff_guidance_test.dart` | 545 | Outdoor→Indoor handoff | Does NOT test same-building floor transitions |

### Tests NOT Existing

- **No end-to-end two-floor navigation test** (Floor 1 → Floor 2 complete flow)
- **No test for route re-fetch after floor change**
- **No test for multi-transition sequences** (Floor 1 → 2 → 3)
- **No test for connector proximity detection** in the context of a real multi-floor route
- **No test for rendering after floor change** (polyline filtering with real multi-floor route)
- **No backend integration test** for `navigateSameBuilding()` response format
- **No test for pois_type omission** in same-building routes

## 18. Missing Test Coverage

Critical missing tests for two-floor navigation:

1. **Multi-floor route end-to-end**: Request route Floor 1 → Floor 3, verify floorTransitionIndices has correct values, verify polylinePointsForFloor returns correct subsets
2. **Floor transition rendering**: Verify that when displayedFloor="1", only floor 1 points are rendered; when displayedFloor="2", only floor 2 points are rendered
3. **Connector proximity detection**: Mock position near a connector point, verify floorTransition state entered
4. **Floor evidence confirmation**: Mock WiFi estimates switching floors, verify floor transition completes
5. **Transition timeout**: Mock WiFi that never confirms new floor, verify 30s timeout aborts transition
6. **Fresh route after transition**: Verify _ensureIndoorGuidance() fetches and commits new route
7. **Multi-transition sequence**: Floor 1 → 2 → 3, verify each transition works independently
8. **Reroute after floor change**: Verify rerouting works correctly on the new floor
9. **Arrival on different floor**: Verify arrival detection works when destination is on a different floor from start
10. **pois_type omission impact**: Verify that missing pois_type doesn't break any rendering or transition logic

## 19. Confirmed Problems

### Bug 1: `navigateSameBuilding()` Omits `pois_type`

**Problem**: The backend's `navigateSameBuilding()` method does NOT set `pois_type` on `NavResultPoint` objects.

**Exact Location**: `server/app/controllers/NavigationController.scala:270-278`

**Evidence**: 
- `navigateSameFloor()` line 257: `p.pois_type = poi.get(SCHEMA.fPoisType)` ← SET
- `navigateSameBuilding()` lines 270-278: Only sets lat, lon, puid, buid, floor_number ← NOT SET

**Why it can happen**: Copy-paste error or intentional omission during original development.

**Observable consequence**: All points in a multi-floor route have `poisType = "None"` in the frontend. Connector type (stairs vs elevator) is lost.

**Severity**: MEDIUM — The app still navigates correctly (floor transitions work via floor_number comparison), but the user gets no instruction about connector type.

**Confidence**: CONFIRMED

### Bug 2: No User Instruction for Connector Type

**Problem**: The UI shows only "Moving to Floor N..." without indicating stairs vs elevator.

**Exact Location**: `navigation_config.dart:209`, `navigation_controller.dart:395-403`.

**Evidence**: The `transitionBlackoutMessage` is hardcoded to "Moving to Floor". No code reads connector type.

**Why it can happen**: Depends on Bug 1 (pois_type missing). Even if pois_type were present, no code uses it for user instructions.

**Observable consequence**: User doesn't know whether to look for stairs or elevator.

**Severity**: LOW — UX inconvenience, not a functional bug.

**Confidence**: CONFIRMED

### Bug 3: Single Indoor Segment Wraps All Floors

**Problem**: `toSegmentedIndoor()` wraps the entire multi-floor route into a single `RouteSegment.indoor()`. This means floor transition information is carried only in `pointFloors`, not as separate segments.

**Exact Location**: `navigation_route_model.dart:263-289`

**Evidence**: The method creates one `RouteSegment.indoor()` with all points and `pointFloors`.

**Why it can happen**: Design choice — the segment model was designed for cross-building navigation, not same-building multi-floor.

**Observable consequence**: `RouteSegment.floorTransition` type is never used for same-building floor transitions. The segment-based rendering path treats the entire route as one indoor leg.

**Severity**: LOW — Rendering still works correctly via `pointFloors` filtering. But the `floorTransition` segment type is unused.

**Confidence**: CONFIRMED

## 20. Potential Problems

### Potential Bug 1: Fresh Route May Not Include Next Floor Transition

**Problem**: After a floor change, `_ensureIndoorGuidance()` fetches a new route from the nearest POI to the destination. This new route is from a POI-to-POI API call. The backend's `navigateSameFloor()` (called when source and dest are on the same floor) loads only source-floor POIs but ALL building connections. Cross-floor edges exist but their endpoint POIs from other floors aren't vertices, so those edges are dead.

**Exact Location**: `NavigationController.scala:242-261` (`navigateSameFloor` loads only floor POIs)

**Evidence**: `navigateSameFloor()` calls `poisByBuildingFloorAsMap()` (one floor only) but `connectionsByBuildingAsMap()` (all building connections). Cross-floor edges will reference POIs not in the graph, so they'll be silently ignored in `Dijkstra.Graph.addEdges()`.

**Why it can happen**: If the fresh route's source POI is on the same floor as the destination POI (both now on floor 2), `navigateSameFloor()` runs, which only loads floor 2 POIs. This is correct — the route stays on floor 2.

**Observable consequence**: For same-floor segments, this is correct. For multi-floor destinations, the fresh route should use `navigateSameBuilding()`. But the API call from `requestIndoorRouteForSession()` uses `getRouteBetweenPois()` which the backend dispatches based on the POIs' floor numbers.

**Severity**: LOW — Backend correctly handles same-floor vs multi-floor via POI floor comparison.

**Confidence**: POSSIBLE

### Potential Bug 2: Floor Transition Event History Overflow

**Problem**: `_floorTransitionEvents` is bounded by `floorTransitionEventHistoryLimit = 8`. Events are dropped from the front. If a long journey has many floor transitions, early events are lost.

**Exact Location**: `navigation_controller.dart:207-215`

**Evidence**: `if (_floorTransitionEvents.length > limit) { _floorTransitionEvents.removeRange(0, _floorTransitionEvents.length - limit); }`

**Observable consequence**: In a building with 8+ floors, early transition events would be lost for UI display. Not a functional bug.

**Severity**: LOW — Cosmetic only.

**Confidence**: CONFIRMED

### Potential Bug 3: Post-Floor-Switch Suppression May Block Legitimate Reroutes

**Problem**: After a floor switch, reroute checks are suppressed for 10 seconds (`postFloorSwitchSuppressSeconds`). If the user goes in the wrong direction immediately after a floor change, rerouting is delayed.

**Exact Location**: `navigation_controller.dart:1115-1122`

**Evidence**: The suppression timer prevents deviation detection during the cooldown period.

**Observable consequence**: 10s delay in detecting wrong-direction movement after floor change.

**Severity**: LOW — The user would likely be near the connector and not moving far in 10s.

**Confidence**: CONFIRMED

### Potential Bug 4: WiFi Re-engagement During Exit Cancels Exit

**Problem**: In `_maintainDwell()` during `exitingBuilding` state, if WiFi re-engages (fix?.source == PositionSource.wifi), the state reverts to `activeIndoor`. If the user is near a window on a different floor where WiFi briefly connects, this could prevent exiting.

**Exact Location**: `navigation_controller.dart:1057-1062`

**Evidence**: `if (fix?.source == PositionSource.wifi) { _transition(NavigationState.activeIndoor); return; }`

**Observable consequence**: User trying to exit building could be stuck in indoor state if WiFi signal persists near exits.

**Severity**: LOW — Normal behavior (WiFi near exit = still indoors).

**Confidence**: POSSIBLE

## 21. Unknowns / Missing Evidence

1. **Actual RadioMap loading timing during floor transitions** — Whether the native Kotlin engine loads the new floor's RadioMap fast enough for WiFi evidence to arrive within the 30s timeout.

2. **Real-world WiFi floor detection accuracy** — Whether the KnnLocalizer correctly distinguishes floors in practice, especially for adjacent floors.

3. **Backend database state** — Whether stair/elevator connections actually exist in the MongoDB database for E-JUST buildings.

4. **Multi-transition behavior** — Whether a Floor 1 → 2 → 3 journey works end-to-end with fresh route fetches.

5. **User manual floor change interaction** — Whether manually switching floors in the UI during navigation causes issues (code suggests potential divergence between displayed and navigating floor).

6. **App restart state** — Whether any navigation state survives process death (evidence suggests no persistence).

## 22. Historical / Git Findings

Without access to git history, I cannot determine:
- Previous implementations of multi-floor navigation
- Whether `pois_type` was ever included in `navigateSameBuilding()`
- Whether floor transition logic has changed
- Regression history

**UNKNOWN** — Git history not investigated in this pass.

## 23. End-to-End Sequence Diagram

```
User (Floor 1)                    Flutter Client                    Backend                    Native WiFi
     │                                  │                              │                           │
     │──"Navigate to Room 201"──→       │                              │                           │
     │                                  │                              │                           │
     │                    requestRouteToSelectedPoi()                   │                           │
     │                    Strategy 1: getRouteFromCoordinates()         │                           │
     │                                  │──POST /api/navigation/route/coordinates──→              │
     │                                  │                              │                           │
     │                                  │              navigateSameBuilding()                     │
     │                                  │              Dijkstra(all POIs, all edges)              │
     │                                  │              Returns: [poi_f1, stair_bottom, stair_top,  │
     │                                  │                       poi_f2, room_201]                 │
     │                                  │              (NO pois_type in response)                 │
     │                                  │←──{pois: [{floor:"1"},{floor:"1"},{floor:"2"},{floor:"2"}]}──│
     │                                  │                              │                           │
     │                    toSegmentedIndoor()                           │                           │
     │                    → single indoorRouting segment               │                           │
     │                    → pointFloors: ["1","1","2","2"]             │                           │
     │                    activeNavigationRoute = route                │                           │
     │                                  │                              │                           │
     │──"Start Directions"──→           │                              │                           │
     │                    startActiveNavigation()                      │                           │
     │                    state → activeIndoor (WiFi)                  │                           │
     │                                  │                              │                           │
     │←──[Route on Floor 1 shown]──     │                              │                           │
     │                                  │                              │                           │
     │═════[User walks toward stair]════│══════════════════════════════│                           │
     │                                  │                              │                           │
     │                    _onLocationChanged()                         │                           │
     │                    _checkFloorTransition()                      │                           │
     │                    floorTransitionIndices → idx=1               │                           │
     │                    distance(points[1], user) < 30m             │                           │
     │                    points[1].floor="1", points[2].floor="2"    │                           │
     │                                  │                              │                           │
     │                    _beginConnectorFloorTransition("2")          │                           │
     │                    state → floorTransition                      │                           │
     │                    hold position, selectFloorForNavigation(2)   │                           │
     │                    load floorplan + radiomap for floor 2        │                           │
     │                                  │                              │                           │
     │←──["Moving to Floor 2..."]──     │                              │                           │
     │←──[Marker frozen]──              │                              │                           │
     │←──[Map switches to Floor 2]──    │                              │                           │
     │                                  │                              │                           │
     │═════[User takes stairs]══════════│══════════════════════════════│                           │
     │                                  │                              │                           │
     │                    _evidenceFloor() returns "2"                 │                    WiFi reports
     │                    _newFloorEstimateCount = 1                   │                    floor "2" (×3)
     │                    _newFloorEstimateCount = 2                   │                    consecutive
     │                    _newFloorEstimateCount = 3                   │                    estimates
     │                                  │                              │                           │
     │                    _completeFloorTransition("2")                │                           │
     │                    _currentNavigatingFloor = "2"                │                           │
     │                    state → activeIndoor                         │                           │
     │                                  │                              │                           │
     │                    _ensureIndoorGuidance()                      │                           │
     │                    requestIndoorRouteForSession()               │                           │
     │                    (waits for radiomap ready)                   │                           │
     │                                  │──POST /api/navigation/route──→                           │
     │                                  │   (from nearest POI on f2 to dest POI)                  │
     │                                  │←──{pois: [{floor:"2"},...,{floor:"2"}]}──│              │
     │                                  │                              │                           │
     │                    adoptNavigatedRoute(fresh route)             │                           │
     │                                  │                              │                           │
     │←──[Route on Floor 2 shown]──     │                              │                           │
     │                                  │                              │                           │
     │═════[User walks to destination]══│══════════════════════════════│                           │
     │                                  │                              │                           │
     │                    _checkArrival()                              │                           │
     │                    distance < 15m, identity matches             │                           │
     │                    _arrivalConfirmationCounter = 2              │                           │
     │                                  │                              │                           │
     │                    state → arrived                              │                           │
     │←──["Arrived at Room 201"]──      │                              │                           │
```

## 24. Data Flow Diagram

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  MongoDB     │     │  Backend     │     │  HTTP API    │     │  Flutter     │
│             │     │  (Scala)     │     │  Response    │     │  Client      │
│  POIs       │────→│  Dijkstra    │────→│  {pois:[...]}│────→│  .fromJson() │
│  (all floors│     │  Algorithm   │     │  flat list   │     │  → Points    │
│   in graph) │     │              │     │  per-point   │     │    list      │
│             │     │              │     │  floor_number│     │              │
│  Edges      │────→│  Graph       │     │  NO pois_type│     │  .toSegmented│
│  (stair,    │     │  Traversal   │     │  for same-   │     │  Indoor()    │
│  elevator,  │     │              │     │  building    │     │  → Segment   │
│  hallway)   │     │              │     │  routes      │     │    list      │
└─────────────┘     └──────────────┘     └──────────────┘     └──────┬──────┘
                                                                     │
                                                            ┌────────▼────────┐
                                                            │  Navigation     │
                                                            │  Controller     │
                                                            │                 │
                                                            │  floorTransition│
                                                            │  Indices        │
                                                            │  → proximity    │
                                                            │    check        │
                                                            │  → state machine│
                                                            └────────┬────────┘
                                                                     │
                                                            ┌────────▼────────┐
                                                            │  Navigation     │
                                                            │  Display        │
                                                            │                 │
                                                            │  segmentVisible │
                                                            │  → floor filter │
                                                            │  → style by     │
                                                            │    segment type │
                                                            └────────┬────────┘
                                                                     │
                                                            ┌────────▼────────┐
                                                            │  Google Maps    │
                                                            │  Polyline       │
                                                            │                 │
                                                            │  Only current   │
                                                            │  floor points   │
                                                            └─────────────────┘
```

## 25. Floor Transition Diagram

```
                    ┌──────────────────────────────────────┐
                    │         FLOOR TRANSITION              │
                    │         STATE MACHINE                 │
                    └──────────────────────────────────────┘

    ┌──────────────┐
    │ activeIndoor │ ← User is navigating, WiFi reports current floor
    │ floor = "1"  │
    └──────┬───────┘
           │
           │ User approaches connector (distance < 30m)
           │ Connector found in floorTransitionIndices
           │ points[idx+1].floorNumber != currentFloor
           ▼
    ┌──────────────────┐
    │ floorTransition   │ ← _beginConnectorFloorTransition("2")
    │ expectedFloor="2" │
    │ holdPosition = ✓  │ ← Last indoor position frozen
    │ selectedFloor → 2 │ ← Map switches to Floor 2
    └──────┬───────────┘
           │
           ├── WiFi evidence matches "2" (3 consecutive)
           │   _evidenceFloor() == "2"
           │   _newFloorEstimateCount reaches stabilityMinEstimates (3)
           │
           │   ┌──────────────────────────────────────┐
           │   │  _completeFloorTransition("2")        │
           │   │  _currentNavigatingFloor = "2"        │
           │   │  selectedFloor → 2 (sync)             │
           │   │  _ensureIndoorGuidance()              │
           │   │  → Fresh route fetched                │
           │   │  → adoptNavigatedRoute()              │
           │   └──────────────┬───────────────────────┘
           │                  │
           │                  ▼
           │         ┌──────────────┐
           │         │ activeIndoor │ ← Now on Floor 2
           │         │ floor = "2"  │
           │         └──────────────┘
           │
           ├── WiFi evidence does NOT match "2"
           │   _newFloorEstimateCount resets to 0
           │   (stays in floorTransition, waiting)
           │
           └── Timeout (30s)
               _checkTransitionTimeout()
               ┌──────────────────┐
               │ ABORTED          │
               │ Reset expected   │
               │ state → active   │
               │ (re-evaluate     │
               │  on next tick)   │
               └──────────────────┘

    ORGANIC PATH (no connector proximity):

    ┌──────────────┐
    │ activeIndoor │ ← WiFi evidence drifts to different floor
    │ floor = "1"  │   (no connector proximity needed)
    └──────┬───────┘
           │ WiFi reports "2" (3 consecutive)
           │ _expectedNextFloor is null → organic path
           ▼
    ┌────────────────────┐
    │ _beginOrganic...   │ ← Immediately calls _completeFloorTransition
    │ FloorTransition    │   No timeout, no waiting
    └────────┬───────────┘
             │
             ▼
    ┌──────────────┐
    │ activeIndoor │ ← Now on Floor 2
    │ floor = "2"  │
    └──────────────┘
```

## 26. Final Assessment

### 1. Does the current system truly support navigation between two floors?

**YES (PARTIALLY)** — The backend correctly calculates multi-floor routes via Dijkstra across the full building graph. The frontend detects floor transitions and updates state accordingly. However, the fresh route re-fetch after each floor change means the original multi-floor route is NOT carried forward — it's replaced by a new single-leg route. This works for simple cases but may break for complex multi-transition journeys.

### 2. Is the route calculated correctly across floors?

**YES** — Dijkstra on the full building graph finds shortest paths through stair/elevator connections. Edge weights are Haversine distances. The route is a valid shortest path.

### 3. Is the floor transition represented correctly?

**YES (partially)** — Floor transitions appear as consecutive points with different `floor_number` values. `floorTransitionIndices` correctly identifies these. However, the transition point information is degraded (no `pois_type`).

### 4. Are stairs/elevators represented correctly?

**NO (CONFIRMED BUG)** — `navigateSameBuilding()` omits `pois_type` from the response. All points default to `"None"`. The frontend cannot distinguish stairs from elevators from regular hallway points.

### 5. Can the frontend reliably identify the transition point?

**YES (partially)** — Via `floorTransitionIndices` (floor_number changes between consecutive points). But it cannot identify the connector TYPE (stairs vs elevator).

### 6. Does the frontend preserve all required connector information?

**NO (CONFIRMED)** — `pois_type` is lost. `connectorPoiId` is never populated for same-building routes. The only preserved information is `floorNumber` and coordinates.

### 7. Is route segmentation correct?

**YES (for rendering)** — The single `indoorRouting` segment with `pointFloors` correctly enables floor-filtered rendering. The `pointFloors` mechanism works.

### 8. Is route rendering floor-safe?

**YES (CONFIRMED)** — `routePolylineSpecs()` with `pointFloors` filtering ensures only the displayed floor's points are rendered during indoor emphasis. No cross-floor lines.

### 9. Can the app accidentally draw a route between two different floors?

**NO** — The rendering pipeline prevents this during indoor emphasis. During preview, the full multi-floor route is visible (intentional).

### 10. Does positioning correctly detect the new floor?

**PARTIALLY DEPENDS ON DATABASE** — The native KnnLocalizer matches WiFi fingerprints against resident RadioMaps. If the new floor's RadioMap is loaded and has sufficient fingerprint coverage, detection works. This is a runtime dependency on database quality.

### 11. Can positioning and navigation disagree about the current floor?

**YES** — `_currentNavigatingFloor` is route-context bookkeeping, not physical evidence. They can diverge if the user takes an unplanned route. The system handles this via organic floor transitions and rerouting.

### 12. Does changing floors automatically resume navigation?

**YES** — `_completeFloorTransition()` → `activeIndoor` → `_ensureIndoorGuidance()` fetches fresh route → navigation continues on new floor.

### 13. What happens if the user changes floors manually?

**POSSIBLE ISSUE** — Manual floor selection via `selectFloorForNavigation()` changes the displayed floor but does NOT update `_currentNavigatingFloor` in NavigationController. The route context and display context can diverge.

### 14. What happens if the user takes the wrong connector?

**PARTIALLY HANDLED** — The wrong-floor WiFi evidence won't match `_expectedNextFloor`, so the transition counter resets. The user stays in `floorTransition` state until timeout (30s), then reverts to `activeIndoor`. Organic drift could eventually trigger a floor change, and rerouting would recalculate.

### 15. What happens if the user changes floors before reaching the connector?

**HANDLED** — Organic floor transition fires immediately via `_beginOrganicFloorTransition()`. The system adapts to the new floor without waiting for connector proximity.

### 16. What happens if the user goes to the wrong floor?

**PARTIALLY HANDLED** — WiFi evidence reports the wrong floor. If it matches `_expectedNextFloor` (which is set by the route's connector), the transition completes and the user is on the wrong floor. `_ensureIndoorGuidance()` would then fetch a route from the wrong floor to the destination, which might fail or produce a poor route.

### 17. What happens if the user's floor estimate is temporarily wrong?

**HANDLED** — The 3-consecutive-estimate stability gate prevents single wrong estimates from triggering transitions. The outlier jump guard (30m) also helps.

### 18. Are there confirmed bugs?

**YES** — See Section 19:
- Bug 1: `navigateSameBuilding()` omits `pois_type` (CONFIRMED)
- Bug 2: No connector type instruction (CONFIRMED)
- Bug 3: Single indoor segment wraps all floors (CONFIRMED)

### 19. Are there potential bugs?

**YES** — See Section 20:
- Potential Bug 1: Fresh route after floor change may not include next transition
- Potential Bug 2: Floor transition event history overflow (cosmetic)
- Potential Bug 3: Post-switch suppression may delay rerouting
- Potential Bug 4: WiFi re-engagement during exit cancels exit

### 20. What information is currently missing from the system?

- Connector type (stairs vs elevator) in multi-floor routes
- User instructions for connector usage
- Backend test data for E-JUST buildings (do stair/elevator connections exist?)
- Actual WiFi floor detection accuracy in production
- Whether multi-transition (Floor 1 → 2 → 3) sequences work end-to-end

### 21. What are the highest-risk parts of two-floor navigation?

1. **WiFi floor detection reliability** — If WiFi doesn't reliably distinguish floors, the transition state machine stalls or misfires
2. **RadioMap loading timing** — If the new floor's RadioMap isn't loaded fast enough, WiFi evidence is delayed
3. **Fresh route after transition** — The new route from nearest POI may not be optimal or may not include the next floor transition
4. **pois_type loss** — No connector type info means no user guidance

### 22. What should be fixed FIRST, based on evidence?

1. **FIX: `navigateSameBuilding()` must include `pois_type`** — One line change in `NavigationController.scala:277`. This unblocks connector type information.
2. **FIX: Add user instruction for connector type** — After fix #1, use `pois_type` to show "Take stairs to Floor 2" or "Take elevator to Floor 2".
3. **TEST: End-to-end two-floor navigation test** — Currently zero coverage.
4. **INVESTIGATE: Multi-transition sequence** — Verify Floor 1 → 2 → 3 works with fresh route fetches.

---

# Bottom Line

## What Works
- Backend Dijkstra correctly calculates multi-floor shortest paths within a building
- Frontend correctly detects floor transitions via `floorTransitionIndices`
- Floor transition state machine (EXPECTED → DETECTED → CONFIRMED) with timeout
- Floor-safe rendering via `pointFloors` filtering
- Position hold during transition (marker doesn't jump)
- Fresh route re-fetch after floor confirmation
- Arrival detection on destination floor

## What Does Not Work
- **Connector type information is completely lost** in same-building multi-floor routes (Backend bug: `navigateSameBuilding()` omits `pois_type`)
- **No user instruction for stairs vs elevator** — user only sees "Moving to Floor N..."
- **Multi-transition sequences** (Floor 1 → 2 → 3) rely on fresh route re-fetches that may not include subsequent transitions

## Confirmed Bugs
1. `navigateSameBuilding()` omits `pois_type` — `NavigationController.scala:270-278`
2. No connector type UI instructions — `navigation_config.dart:209`
3. Single indoor segment wraps all floors — `navigation_route_model.dart:263-289`

## Highest-Risk Unknowns
1. WiFi floor detection accuracy in real buildings
2. RadioMap loading timing during floor transitions
3. Multi-transition journey reliability
4. Manual floor change interaction during navigation

## Most Important Next Investigation/Fix
**Fix `navigateSameBuilding()` to include `pois_type`** — This is a one-line fix (`NavigationController.scala:277`) that unblocks connector-type-aware navigation. Then add end-to-end two-floor navigation tests.
