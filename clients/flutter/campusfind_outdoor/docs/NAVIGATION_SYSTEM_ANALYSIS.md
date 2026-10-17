# CampusFind Navigation System — Current Implementation Analysis

> **Scope:** Audit of the navigation/positioning implementation as it exists in the
> Flutter client (`clients/flutter/anyplace_campusfind`) and its embedded native
> Android/Kotlin positioning engine. Written as the source-of-truth baseline for the
> next (unification) implementation phase.
>
> **Method:** Every claim below is traced to a file/class/function in the current
> codebase. Statements marked **[INFERRED]** are conclusions drawn from behavior not
> directly asserted by code or comments. No code was modified.

---

## Table of Contents

1. [Overall Navigation Architecture](#1-overall-navigation-architecture)
2. [Positioning System](#2-positioning-system)
3. [GPS + Wi-Fi Relationship (scenario walk-through)](#3-gps--wifi-relationship)
4. [Route / Navigation Logic](#4-route--navigation-logic)
5. [Floor Navigation](#5-floor-navigation)
6. [Building Entrance / Exit Logic](#6-building-entrance--exit-logic)
7. [Navigation State Machine (actual)](#7-navigation-state-machine-actual)
8. [Complete Example Trace](#8-complete-example-trace)
9. [Architecture Diagram (actual)](#9-architecture-diagram-actual)
10. [Current Navigation Gaps](#10-current-navigation-gaps)
11. [Final Verdict](#11-final-verdict)

---

## 1. Overall Navigation Architecture

### 1.1 Components

| Layer | Component | File | Role |
|---|---|---|---|
| App wiring | `main()` | `lib/main.dart:15-44` | Constructs one app-lifetime `LocationProvider`, `SpaceProvider`, `NavigationController`; registers all three as `provider` `ChangeNotifierProvider`s. |
| Shell | `MainShell` | `lib/screens/main_shell.dart` | Bottom-tab shell; Map tab = `MapScreen`. Leaving the Map tab force-stops navigation (`_stopNavigationOnTabLeave`, lines 35–47). |
| Screen | `MapScreen` | `lib/ui/screens/map_screen.dart` | Google Maps rendering (buildings, POIs, floorplan ground overlays, route polylines, user marker), camera follow, navigation status bar (lines 1227–1299). Binds `SpaceProvider.setLocationProvider(...)` in `initState` (lines 105–129). |
| Sheet | `MapBottomSheet` | `lib/ui/widgets/map_bottom_sheet.dart` | Hosts `PoiDetailCard` / `BuildingDetailCard`; hosts "Route Here" / "Start Directions" / "End Navigation" buttons (lines 195–250, 298–399). |
| Cards | `PoiDetailCard`, `BuildingDetailCard` | `lib/ui/widgets/poi_detail_card.dart`, `building_detail_card.dart` | Trigger `requestRouteToSelectedPoi()` / `requestRouteToBuilding()` ("Route Here") and `startRoutePreview` + `startActiveNavigation` ("Start Directions"). |
| State | `NavigationController` | `lib/state/navigation_controller.dart` | Navigation lifecycle, sub-state machine, deviation/reroute, floor transitions, building exit/entry detection, segment advancement. |
| State | `LocationProvider` | `lib/state/location_provider.dart` | Runs GPS stream + native Wi-Fi stream concurrently; arbitrates a single effective position (`currentLocation`) + `positionSource`. |
| State | `SpaceProvider` | `lib/state/space_provider.dart` | Buildings/floors/RadioMap/floorplan/POI state; owns route generation cascade, `CrossBuildingRouter`, `CustomRouteRepository`. |
| Data | `GpsLocationService` | `lib/data/datasources/gps_location_service.dart` | `geolocator` wrapper (permission + fix + stream). |
| Data | `MethodChannelNativePositioningService` | `lib/data/datasources/native_positioning_service.dart` | Dart side of the Kotlin positioning platform channels. |
| Data | `AnyplaceApiClient` | `lib/data/datasources/anyplace_api_client.dart` | Anyplace server endpoints + OSRM outdoor routing. |
| Data | `CustomRouteRepository` / `CustomRouteGraph` | `lib/data/repositories/custom_route_repository.dart`, `custom_route_graph.dart` | Bundled KMZ campus walking-route graph: snapping, shortest path, progress tracking. |
| Data | `CrossBuildingRouter` | `lib/data/repositories/cross_building_router.dart` | Composes multi-segment indoor→outdoor→indoor routes at request time. |
| Native | `PositioningBridge`, `PositioningEngine`, `WifiScanner`, `KnnLocalizer`, `RadioMap` | `android/app/src/main/kotlin/eg/edu/ejust/anyplace_campusfind/positioning/*.kt` | WKNN Wi-Fi fingerprint localization engine (see §2). |
| Backend | Anyplace Play server | `server/` (repo root) | Spaces/floors/POIs/RadioMaps/floorplans/indoor graph routing REST APIs. |
| External | OSRM demo server | hard-coded in `anyplace_api_client.dart:793,884` (`http://router.project-osrm.org/route/v1/foot/...`) | Public-road walking routes. |

### 1.2 End-to-end flow (destination selection → arrival)

1. **Destination selected** — map POI tap (`map_screen.dart:731-735`), search result
   (`detail_navigation.dart:11-37` → `SpaceProvider.navigateToPoi`), or Quick Access.
   This runs `SpaceProvider._navigateToIdentifier` (`space_provider.dart:593-629`):
   `selectSpace → loadFloors → selectFloor → loadPois → selectPoi`.
   Selecting a floor also triggers RadioMap download + load into the native engine
   (`selectFloor` → `loadRadioMapForSelectedFloor`, `space_provider.dart:470-501,
   1608-1708`).
2. **"Route Here"** (`poi_detail_card.dart:241`, `building_detail_card.dart:311`) →
   `SpaceProvider.requestRouteToSelectedPoi()` / `requestRouteToBuilding()`
   (`space_provider.dart:649 / 1283`). Route generation cascade (§4).
   Result stored as `_activeNavigationRoute`.
3. **"Start Directions"** (`map_bottom_sheet.dart:208-216` → `poi_detail_card.dart:198`)
   → `NavigationController.startRoutePreview(...)` immediately followed by
   `startActiveNavigation()` (`navigation_controller.dart:146-183`). Preview phase is
   effectively skipped in this path (both calls happen back-to-back).
4. **Active navigation loop** — every `LocationProvider` notification invokes
   `NavigationController._onLocationChanged()` (`navigation_controller.dart:224-261`),
   which runs in fixed order:
   `_evaluateSubState` → `_updateCustomRouteProgress` → `_checkDeviationAndReroute`
   → `_checkFloorTransition` → `_checkBuildingExit` → `checkBuildingApproach`
   → `checkEntranceProximity` → `_checkSegmentTransition` → `_checkGpsLoss`.
5. **UI reaction** — `MapScreen._onNavigationChanged` (`map_screen.dart:311-337`)
   drives follow-mode camera (`_followUserPosition`, zoom 19 indoor / 17 outdoor per
   `navigation_config.dart:74-77`); status bar shows `positioningStatus` and
   rerouting indicator (`map_screen.dart:1227-1299`,
   `map_bottom_sheet.dart:_buildNavigationHeader:298-399`).
6. **Termination** — only via explicit user action: End button
   (`map_bottom_sheet.dart:380-382`, `building_detail_card.dart:308`) or leaving the
   Map tab (`main_shell.dart:42-46`). There is **no automatic arrival detection**
   (§8 step 13).

### 1.3 Flow diagram

```
 User taps POI / building
        │
        ▼
 SpaceProvider.selectPoi / navigateToPoi          (space_provider.dart)
        │  selectSpace → selectFloor → loadPois
        │        └─ selectFloor ──► loadRadioMapForSelectedFloor
        │                              └─► NativePositioningService.loadRadioMap(text,buid,floor)
        │                                    └─► [MethodChannel] PositioningEngine.loadRadioMapText
        │                                          └─► WifiScanner.startScanning()
        ▼
 "Route Here"
        ▼
 SpaceProvider.requestRouteToSelectedPoi / requestRouteToBuilding
        │  ① CrossBuildingRouter.composeRoute   (if user ≠ target building)
        │  ② Anyplace coordinate-based route    (/api/navigation/route/coordinates)
        │  ③ POI→POI route                      (/api/navigation/route)
        │  ④ Outdoor cascade: KMZ graph → hybrid → OSRM→custom → OSRM+splice → OSRM → straight line
        │     (+ optional indoor tail from entrance POI via API/connectors)
        ▼
 _activeNavigationRoute : NavigationRouteModel (flat points [+ segments])
        │
        ▼
 "Start Directions" ──► NavigationController.startRoutePreview() + startActiveNavigation()
        │
        ▼  (per location update from LocationProvider.currentLocation)
 NavigationController._onLocationChanged pipeline:
   sub-state eval → custom-route progress → deviation/reroute → floor transition
   → building exit → building approach → entrance proximity → segment advance → GPS-loss pause
        │
        ├── reroute? ──► custom graph route OR repository.getRouteFromCoordinates(...)
        ▼
 notifyListeners()
        │
        ▼
 MapScreen: user marker (currentLocation), route polylines, follow-camera, status bar
```

### 1.4 Responsibility split (who decides what)

| Decision | Owner | Code |
|---|---|---|
| Which position source wins right now | `LocationProvider._evaluatePositionPolicy` | `location_provider.dart:212-236` |
| Which buid/floor scope Wi-Fi estimates must match | `SpaceProvider` via `setActiveIndoorFloor` (selection state) | `space_provider.dart:202-207`, `location_provider.dart:184-206` |
| When to generate a route & which strategy | `SpaceProvider.requestRouteTo*` | `space_provider.dart:649/1283` |
| How a cross-building journey is decomposed | `CrossBuildingRouter.composeRoute` | `cross_building_router.dart:49-184` |
| When navigation starts/ends | User buttons → `NavigationController.start*/end*` | `navigation_controller.dart:143-205` |
| Indoor vs outdoor sub-state during nav | `NavigationController._evaluateSubState` | `navigation_controller.dart:276-289` |
| Floor changes during nav | `NavigationController._checkFloorTransition/_confirmFloorTransition` | `navigation_controller.dart:472-569` |
| Building exit / entry during nav | `_checkBuildingExit`, `checkEntranceProximity` | `navigation_controller.dart:573-737` |
| Deviation → reroute | `_checkDeviationAndReroute` / `_triggerReroute` | `navigation_controller.dart:319-468` |

---

## 2. Positioning System

### 2.1 GPS / outdoor location

- **Implementation:** `GpsLocationService` (`gps_location_service.dart`) wrapping the
  `geolocator` plugin.
- **Permission & first fix:** `LocationProvider.requestAndCenter()` (`location_provider.dart:291-356`)
  — service check → permission → `getCurrentPosition` (high accuracy, 15 s time limit,
  falls back to last-known) → `startTracking()`. Called once from `MapScreen.initState`
  (`map_screen.dart:113`) and from the re-center button.
- **Stream:** `getPositionStream({distanceFilter = 0.3})` (`gps_location_service.dart:89-114`).
  On Android: `LocationAccuracy.high`, `distanceFilter <1 → 0` (gate disabled),
  `intervalDuration: 500 ms` — i.e. up to ~2 fixes/sec while the fused provider emits.
- **Output:** `UserLocation(lat, lng, accuracy, altitude, heading, speed, timestamp)`
  (`user_location.dart`). Real GPS accuracy values flow through unmodified.

### 2.2 Wi-Fi fingerprinting (native Kotlin)

Pipeline (all inside `android/app/src/main/kotlin/eg/edu/ejust/anyplace_campusfind/positioning/`):

1. **Scan trigger** — `WifiScanner` (`WifiScanner.kt`): event-driven. Registers for
   `WifiManager.SCAN_RESULTS_AVAILABLE_ACTION` (any requester's scans count) plus a
   lazy 10 s fallback re-trigger of `startScan()` respecting the ~4 scans/2 min throttle.
2. **Localization** — `PositioningEngine.processScanResults` (`PositioningEngine.kt:81-109`)
   → `KnnLocalizer.localize(scanResults, radioMap)` (`KnnLocalizer.kt:28-93`):
   Weighted KNN, k=4, Euclidean RSS distance over shared BSSID space, inverse-distance
   weights (0-distance weight = 1000). Returns `LatLng?` + matchedAps.
3. **RadioMap** — single-slot singleton: `loadRadioMapText` atomically replaces
   `activeRadioMap` (`PositioningEngine.kt:43-58`); `clearRadioMap` nulls it.
   `RadioMap.kt` parses the Anyplace mean-RSS plaintext (`# NaN -110` header, MAC list,
   fingerprint rows). **One floor's radiomap at a time.**
4. **Dispatch to Flutter** — `PositioningBridge` (`PositioningBridge.kt`) posts estimate
   maps `{latitude, longitude, buid, floor, matchedAps, totalAps, durationMs, timestamp, status}`
   over EventChannel `eg.edu.ejust.anyplace_campusfind/position_stream`.
5. **Dart reception** — `MethodChannelNativePositioningService.positionStream`
   (`native_positioning_service.dart:48-57`) → `PositionEstimate` model
   (`position_estimate.dart`; `isValid` requires `status == 'success'`, finite non-zero
   coords, `matchedAps > 0`).

Scanning lifecycle is tied to RadioMap loading: `loadRadioMap` success starts
`WifiScanner.startScanning()`; `clearRadioMap` stops it (`PositioningBridge.kt:64-87`).
Flutter triggers both from `SpaceProvider.loadRadioMapForSelectedFloor` /
`_resetRadioMapState` (`space_provider.dart:1651,1896`).

### 2.3 Arbitration into ONE effective position

`LocationProvider` keeps both inputs alive and computes a single output:

- `_gpsLocation` — updated by the GPS stream listener (`location_provider.dart:369-383`).
- `_latestIndoorEstimate` — updated by the native stream listener (:124-154); expires
  after **10 s** without refresh (`_scheduleIndoorStaleTimer`, :156-179).
- **Precedence rule** — `_evaluatePositionPolicy()` (:212-236):
  1. If the latest estimate is valid **and** `estimate.buid == _activeIndoorBuid`
     **and** `estimate.floor == _activeIndoorFloor` → source `indoorWifi`,
     `currentLocation` built from it with **hardcoded `accuracy: 3.0`**.
  2. Else if GPS exists → source `gps`, `currentLocation = gpsLocation`.
  3. Else → `none`, `currentLocation = null`.
- The required buid/floor scope is set by **map-selection state**, not by detection:
  `SpaceProvider._syncLocationProvider()` (`space_provider.dart:202-207`) forwards every
  space/floor selection change to `LocationProvider.setActiveIndoorFloor(buid, floor)`
  (`location_provider.dart:184-206`), which also resets the stability window on change.
- A rolling **stability tracker** exists (5 s window, ≥3 entries, ≥2 matched APs each,
  ≤15 m consecutive delta → `stable`; `location_provider.dart:239-288` +
  `navigation_config.dart:60-69`) but its output `positioningStability` is **not read by
  any widget** (verified by grep — definitions only).

### 2.4 Update frequency & delivery to UI

- GPS fixes ≈ every 500 ms (Android interval) → `_evaluatePositionPolicy` →
  `notifyListeners`.
- Wi-Fi estimates ≈ at scan-result rate (typically 1–5 s depending on system-wide scan
  activity) → same path.
- UI: `MapScreen.build` is a `Consumer2<SpaceProvider, LocationProvider>`; user marker
  rendered from `locationProvider.currentLocation` (`_buildUserMarker`,
  `map_screen.dart:753-774`). Camera follow reacts to `NavigationController` events.

### 2.5 Verdict: A, B, or C?

**Answer: B) Partially integrated.**

Evidence:

- There **is** a single unified output point — everything downstream (marker, camera,
  controller logic, rerouting) consumes exactly one `LocationProvider.currentLocation`
  with an explicit `positionSource` enum (`location_provider.dart:14-23,97-110`).
  That disqualifies "two completely separate systems with explicit switching" (A):
  no component outside `LocationProvider` chooses between GPS and Wi-Fi.
- But it is **not** a unified positioning system (C): there is no sensor fusion, no
  smoothing/filtering across sources, no blended covariance. The two engines run
  independently and the switch is a hard binary override with heuristics:
  - Wi-Fi wins purely because a fresh estimate matches the *manually selected*
    buid/floor — not because of any environment inference;
  - accuracy for indoor fixes is fabricated (`accuracy: 3.0`,
    `location_provider.dart:224`);
  - when the gate flips, the marker teleports between the last Wi-Fi fix and the GPS
    fix with no interpolation (no code addresses this anywhere);
  - GPS scanning continues indoors and Wi-Fi scanning continues outdoors (both loops
    are stopped only together via radiomap clear/load) — no duty-cycling.

---

## 3. GPS + Wi-Fi Relationship

Mechanics that apply to every case below:

- Both engines run whenever they can. GPS runs from app start (`requestAndCenter`);
  Wi-Fi scanning runs whenever *some* floor's RadioMap is loaded in the native engine.
- The effective position is chosen per-update by `_evaluatePositionPolicy`
  (`location_provider.dart:212-236`).
- During **active navigation**, `NavigationSubState` is recomputed from the *source*:
  indoor ⇔ `source == indoorWifi && currentNavigatingFloor != null`
  (`navigation_controller.dart:276-289`).
- All transitions below are silent mode switches. There is no user prompt anywhere in
  the navigation path (grep confirms no dialogs/toasts tied to these transitions).

| Scenario | Active source | Other source | Decision logic | Transition quality |
|---|---|---|---|---|
| **A. Outside a building** | GPS | Wi-Fi scanning may still be running if any floor was previously selected (radiomap still loaded). Estimates either don't arrive (no match) or fail the buid/floor gate → ignored. | `positionSource = gps` by elimination. | n/a — stable GPS mode. |
| **B. Approaching an entrance** | GPS | Same as A. | `NavigationController.checkBuildingApproach`: within **100 m** of destination-building centroid → preloads building data (`selectSpace` → floors) (`navigation_controller.dart:641-667`). Within **25 m** of an entrance POI (or **30 m** of centroid fallback) → `_triggerIndoorTransition` (:671-737): selects ground floor `'0'`, sets subState `indoor`, triggers reroute. | **Mode switch**, not seamless: subState flips to `indoor` *before* any Wi-Fi fix exists; positioning actually remains GPS until a valid matching estimate arrives (which requires the ground-floor radiomap to finish downloading/loading — async, no readiness check before declaring indoor). Position can visibly jump when the first Wi-Fi fix replaces the GPS fix. |
| **C. Entering a building** | Wi-Fi (once ground-floor radiomap loaded and estimates match scope) | GPS continues streaming; suppressed by precedence. | Gate flip in `_evaluatePositionPolicy`. SubState already `indoor` since trigger. | Hard jump possible (GPS fix ↔ Wi-Fi fix distance unbounded). If radiomap missing for the floor, `RadioMapStatus.unsupported` → no Wi-Fi ever → user stays on GPS even deep indoors. |
| **D. Inside the building** | Wi-Fi | GPS running, ignored. | Stability window tracks quality (unused downstream). If estimates go stale >10 s or stop matching (e.g. wrong floor), source silently degrades to **GPS** — which indoors is usually poor — and `NavigationController` will eventually interpret sustained non-Wi-Fi as "exited building" (case F). | Degradation is implicit and unannounced. |
| **E. Moving between floors** | Wi-Fi against the *currently loaded* floor's radiomap | GPS ignored. | See §5: connector proximity (<30 m) → preload next floor → new radiomap replaces old (single slot) → ≥3 consecutive estimates on expected floor confirm switch. During transition `_lastIndoorPosition` is cached and location processing early-returns (`navigation_controller.dart:230-238`) — **but the UI never uses the cached hold** (`heldPositionDuringTransition` has zero widget references), so the marker follows whatever `LocationProvider` emits, including cross-floor jumps. | Discontinuous: brief blackout/jump period; 30 s timeout aborts back to prior floor. |
| **F. Exiting the building** | GPS (after Wi-Fi lost/stale) | Wi-Fi stops producing matching estimates (or radiomap cleared). | `_checkBuildingExit` (`navigation_controller.dart:573-605`): needs subState `indoor` AND source ≠ indoorWifi AND a GPS fix with accuracy ≤15 m AND position outside floorplan bounds (>80 m from centroid fallback), confirmed **3× consecutively** → `_handleBuildingExit` clears floor state and calls `SpaceProvider.clearSelection()` — which also clears the provider's copy of the active route and unloads the radiomap/scanning. | Mode switch with lag (needs 3 bad-ish GPS fixes indoors first). Because indoor GPS accuracy rarely ≤15 m, exit often triggers late or never; conversely a few good fixes near windows can trigger it falsely mid-building. |
| **G. Outdoors toward another building** | GPS | Wi-Fi idle (radiomap cleared at exit). | Custom-route progress + polyline deviation checks run (`navigation_controller.dart:298-347`). Approach detection re-arms only for the **destination** building. | Stable. Passing *through or near other buildings* does nothing special — entering an intermediate building gives no indoor coverage (its radiomap isn't loaded; estimates wouldn't match scope anyway). |
| **H. Entering the destination building** | Same mechanics as B/C. | — | `checkBuildingApproach` (preload) + `checkEntranceProximity` (transition) as above. | Same mode-switch caveats. |
| **I. Moving to another floor inside destination building** | Same as E. | — | Same machinery; note `_triggerReroute` after entry routed from the entrance area on ground floor, so the route itself contains the vertical leg only if the server produced a multi-floor path. | Same discontinuity caveats. |

**Summary:** there is one arbitration point (partial integration), but every
indoor⇄outdoor transition is a discrete heuristic-driven **mode switch** with real
potential for position jumps, delayed detections, and silent fallbacks.

---

## 4. Route / Navigation Logic

### 4.1 Indoor routes

Generated by the Anyplace server over the POI connector graph:

- Coordinate-based: `POST /api/navigation/route/coordinates`
  (`fetchNavigationRouteFromCoordinates`, `anyplace_api_client.dart:673-754`).
- POI-to-POI: `POST /api/navigation/route`
  (`fetchNavigationRoute`, :595-670).
- Client-side fallbacks when entrances/rooms lack graph edges
  (`space_provider.dart:_routeIndoorViaConnectors:999-1145`;
  `cross_building_router.dart:_routeViaConnectors:935-1030`): snap to nearest
  connector POIs (`pois_type == 'None'`), route connector→connector via server,
  pad ends with straight lines; final fallback fully straight-line.

### 4.2 Outdoor routes

Five-tier cascade (identical tiers used in three places:
`space_provider.dart:839-900 / 1434-1496`, `cross_building_router.dart:_generateOutdoorSegment:445-561`):

1. Pure bundled-KMZ graph route (`CustomRouteRepository.findRoute`).
2. Hybrid edge-snap route (`findHybridRoute`, snapThreshold 150 m).
3. OSRM (foot) from origin to a campus-graph *endpoint*, then graph shortest-path to
   destination vertex (`_buildOsrmToCustomRoute`).
4. OSRM full route with custom-graph tail splice (`spliceCustomTail` /
   `_spliceCustomTail`).
5. Plain OSRM foot route (`http://router.project-osrm.org`), then straight-line
   fallback.

### 4.3 One continuous route?

Two representations coexist:

- **Legacy flat hybrid:** `NavigationRouteModel.hybrid(outdoorPoints:, indoorRoute:)`
  concatenates outdoor waypoints + indoor waypoints into one `points` list
  (`navigation_route_model.dart:116-129`). Continuous geometrically, but carries no
  segment semantics; per-floor rendering uses `floorNumber` tagging and
  `floorTransitionIndices` (:255-263).
- **Segment model:** `CrossBuildingRouter` returns
  `NavigationRouteModel.fromSegments` with typed
  `RouteSegment`s (`route_segment.dart`): ordered
  `exitTransition → outdoorWalking → entranceTransition (+ indoorRouting /
  floorTransition)`. Status `partial` if any segment fell back
  (`isIncomplete`), capped at 6 segments.

So yes — indoor+outdoor **can be represented as one object**, and `MapScreen` renders
segmented routes with distinct styles per type (`map_screen.dart:812-829, 857-882`).
However the two representations are consumed differently and the segment metadata is
only partially exploited (§10).

### 4.4 Entrances & destination handling at generation time

- Entrance POIs identified by `is_building_entrance` flag or `pois_type` containing
  `"entrance"` (`utils/poi_classification.dart:41-43`).
- Exit POI selection loads **all** floors' POIs of the origin building and prefers
  ground-floor entrances; returns `candidates.first` — **not** the nearest to the user
  (`cross_building_router.dart:_selectExitPoi:211-241`).
- Destination entrance selection uses two-pass scoring: OSRM walking cost ×0.6 +
  approach-bearing angular penalty ×100×0.4 vs. centroid→entrance bearing
  (`_selectEntrancePoi:306-431`).
- The destination POI itself is the terminal point of the entrance/indoor segment
  (`targetPuid` threaded through `composeRoute` and `_generateEntranceSegment`).

### 4.5 Progress, intermediate points, deviation

- **Route progress** exists only for the custom KMZ graph outdoors:
  `RouteProgress` (`data/models/route_progress.dart`) computed by
  `CustomRouteRepository.getRouteProgress` (snap to nearest edge, traveled/remaining
  distance, on/off-route) — updated in `_updateCustomRouteProgress`
  (`navigation_controller.dart:298-315`), **only when `subState == outdoor`**.
- **Intermediate points:** segment advancement purely proximity-based — within 10 m of
  a segment endpoint (30 m for `floorTransition` segments) advances
  `_currentSegmentIndex` (`_checkSegmentTransition:770-800`). For legacy flat routes
  there is **no waypoint-level progress tracking at all**.
- **Deviation:** perpendicular min-distance to the active route's polyline on the
  current navigating floor (`_computeMinDeviation:351-364`); threshold 15 m
  (`deviationThreshold`); cooldown 15 s; retries ×3 with 1/2/4 s backoff
  (`_triggerReroute:391-468`). Outdoors with a loaded custom graph, off-custom-route
  (>30 m) takes precedence. Reroute rebuilds via custom graph (outdoor) or
  `/api/navigation/route/coordinates` using `currentNavigatingFloor ?? '0'`.

---

## 5. Floor Navigation

All logic lives in `NavigationController._checkFloorTransition` /
`_preLoadFloorIfNeeded` / `_confirmFloorTransition` (`navigation_controller.dart:472-569`)
plus thresholds in `navigation_config.dart:118-135`.

- **Where floor info comes from:**
  - The route: `NavigationRoutePoint.floorNumber` per waypoint;
    `floorTransitionIndices` marks indices where floor changes; `connectorPoints`
    exposes them; `nextFloorFrom(currentFloor)` (:301-308).
  - Positioning: `PositionEstimate.floor` — which equals the floor whose radiomap is
    currently loaded in the native engine (`PositioningEngine` stamps `map.floor`).
- **Detection of an upcoming change (arming):** during each location tick, for every
  transition index whose point is on the navigating floor, if user is within
  **30 m** (`connectorProximityThreshold`) → `_preLoadFloorIfNeeded(nextFloor)`:
  sets `_isTransitioningFloors`, caches `_lastIndoorPosition`, and calls
  `SpaceProvider.selectFloor(nextFloor)` → downloads next floorplan/POIs/**RadioMap**
  and hot-swaps the native engine's radiomap.
- **Confirmation of the change:** requires `isIndoorWifiActive` and
  `stabilityMinEstimates = 3` **consecutive** valid estimates whose floor equals
  `_expectedNextFloor` (mismatched-floor estimates reset the counter, :497-523).
  Then `_confirmFloorTransition` updates `_currentNavigatingFloor`, syncs
  `SpaceProvider.selectFloor`, sets a **10 s reroute-suppression** window
  (`postFloorSwitchSuppressSeconds`, checked at :241-249).
- **Automatic display change:** yes — `selectFloor` swaps the displayed floorplan/POIs;
  no user confirmation dialog exists anywhere in this path.
- **Timeout/abort:** `_checkTransitionTimeout` aborts after **30 s**, reverting flags
  (the previously selected floor is *not* programmatically restored — **[INFERRED]
  side effect: the map stays on the newly selected floor even though navigation did
  not confirm**, because `selectFloor` was already applied).
- **Vertical connectors representation:** stairs/elevators appear as ordinary route
  waypoints whose `floorNumber` differs across adjacent points; `RouteSegmentType.floorTransition`
  exists for segment-model routes, but the router never explicitly generates such
  segments — verticality comes implicitly from server paths crossing floors, or is
  absent entirely (straight-line fallbacks have a single floor tag).
- **Known limitation:** because the engine holds one radiomap, during arming the old
  floor's map is replaced immediately; estimates produced between swap and physical
  arrival are computed against the *new* floor's fingerprints and typically fail or
  mismatch — this is why confirmation demands 3 matches, and why the transition window
  is lossy.

---

## 6. Building Entrance / Exit Logic

### Identification

- Entrance: `isBuildingEntrance == true` **or** `poisType.toLowerCase().contains('entrance')`
  (`poi_classification.dart:41-43`; same predicate duplicated inline in
  `navigation_controller.dart:680-684`, `space_provider.dart:936-939,1353-1355`).
- Doors additionally flagged `is_door` (`poi_model.dart:15,79`); used only by
  `CrossBuildingRouter` candidate filtering (`isEntrance(p) || isDoor(p)`).
- The system has **no explicit notion of an entrance as a semantic indoor/outdoor
  boundary object** — entrances are just POIs used as (a) transition triggers by
  distance, (b) route endpoints for indoor legs. **[INFERRED]** The
  `entranceTransition`/`exitTransition` segment types imply the concept, but nothing
  keys runtime behavior off "user is AT the entrance".

### Runtime behavior

- **Reaching an entrance (outdoor→indoor):** nothing fires *at* the entrance itself;
  the trigger is generic proximity (25 m entrance / 30 m centroid) evaluated every GPS
  tick wherever the user is. On trigger (`_triggerIndoorTransition:719-737`):
  ground floor auto-selected, subState forced `indoor`, immediate reroute from current
  coordinates. **No user confirmation is requested.**
- **Exiting (indoor→outdoor):** passive detection per §3-F; **no user confirmation**;
  on confirm, `_handleBuildingExit` resets floor/subState and calls
  `SpaceProvider.clearSelection()` — note this also wipes
  `SpaceProvider._activeNavigationRoute` (via `_resetNavigationRouteState`) while
  `NavigationController` retains its own `_activeRoute` copy (re-synced only if the
  provider later produces another route, `_onSpaceProviderChanged:263-272`).
- **Positioning transition:** fully automatic but heuristic (§3-B/C/F) — no handshake,
  no readiness gating on radiomap load completion before declaring indoor.
- **Navigation state change:** subState flips `outdoor↔indoor`; `phase` never changes
  for transitions (stays `active`). There is no dedicated ENTERING/EXITING state — the
  closest is the transient boolean pair (`_buildingPreloaded`, `_exitConfirmationCounter`).

---

## 7. Navigation State Machine (actual)

The code defines exactly two enums plus ad-hoc booleans
(`navigation_controller.dart:18-68`):

```dart
enum NavigationPhase { idle, preview, active }            // line 19
enum NavigationSubState { outdoor, indoor, transitioning } // line 22
// Flags: _isTransitioningFloors, _isPaused, _isRerouting,
//         _buildingPreloaded, _followMode
```

There is **no** `CALCULATING_ROUTE`, `ENTERING_BUILDING`, `EXITING_BUILDING`,
`FLOOR_TRANSITION` (as a state; only the `transitioning` sub-state + booleans), and
**no** `ARRIVED` state. Route calculation status lives separately in
`SpaceProvider.NavigationRouteStatus { idle, loading, ready, unsupported, error }`
(`space_provider.dart:39`).

### Actual transition diagram

```
                    ┌────────────────────────────────────────────────────────┐
                    │                     NavigationPhase                     │
                    │                                                        │
   "Route Here"     │   idle ──(startRoutePreview, route ready)──► preview   │
   route loaded     │    ▲                                        │          │
                    │    └────────(endNavigation)──────┐           │ startActiveNavigation()
                    │                                  ▼           ▼
                    │                 (endNavigation / leave Map tab) active │
                    └────────────────────────────────────────────────────────┘
                                        │
        Within `active`, NavigationSubState is recomputed EVERY location tick
        by _evaluateSubState (navigation_controller.dart:276-289):

              ┌─────────────────────────────────────────────┐
              │ transitioning  ◄── _isTransitioningFloors   │
              │      │ confirm(3 estimates) or timeout 30s  │
              │      ▼                                      │
              │ indoor  ◄── source==indoorWifi && floor!=null│
              │      │ exit confirmed (Wi-Fi gone + good GPS │
              │      │      outside bounds ×3)               │
              │      ▼                                       │
              │ outdoor ◄── otherwise                        │
              │      │ entrance proximity (<25m/30m) triggers│
              │      │ indoor + reroute                      │
              │      └───────────────────────────────────────┘
              └─────────────────────────────────────────────┘

  Orthogonal flags (not states): _isRerouting (async reroute in flight),
  _isPaused (GPS accuracy >100 m; never surfaced in UI),
  _followMode (camera), _buildingPreloaded (one-shot approach latch).
```

Notable dead-ends in the actual machine:

- Segment exhaustion: `_advanceToNextSegment` logs
  *"All segments complete — navigation finished"* and **returns without changing
  phase** (`navigation_controller.dart:806-811`) — navigation stays `active` forever
  until manually ended.
- `preview` is reachable but in practice immediately superseded (UI chains
  `startRoutePreview(); startActiveNavigation();` — `map_bottom_sheet.dart:208-216`).

---

## 8. Complete Example Trace

Scenario: user inside **Building A** Floor 1 → destination POI inside **Building B**
Floor 1. Each step = what the current code actually does.

| # | Step | Current behavior | Code |
|---|---|---|---|
| 1 | Start inside A, F1; select POI in B/F1 (search) | Tab switches to Map; `navigateToPoi` selects Building **B**, its F1, and the POI. ⚠️ Side effect: selecting B's floor makes B/F1 the Wi-Fi scope — so although the user physically stands in A, the app now believes "indoor = B". Since A's radiomap is not loaded, position falls back to **GPS** while indoors in A. | `detail_navigation.dart:33-36`, `space_provider.dart:593-629` |
| 2 | Tap "Route Here" | `requestRouteToSelectedPoi`: user building detected via centroid distance (A, if within 100 m) ≠ target B → `CrossBuildingRouter.composeRoute` builds: exit segment (A: coordinate route to A's first ground-floor entrance — **origin floor taken from exit POI ('0'), not user's F1**), outdoor segment (custom KMZ/OSRM tiers), entrance segment (B: entrance-POI → target POI via server, else connector-hop chain, else straight line). Segmented partial/ready route stored. | `space_provider.dart:649-716`, `cross_building_router.dart:49-184` |
| 3 | Tap "Start Directions" | `startRoutePreview` + `startActiveNavigation` chained; `_evaluateSubState` initially yields `outdoor` (source is GPS) even though user is inside A. Camera frames route; follow-mode on. | `map_bottom_sheet.dart:208-216`, `navigation_controller.dart:143-183,276-289` |
| 4 | Move to Floor 0 of A | **NOT CURRENTLY SUPPORTED (as navigation-aware event).** The exit segment was generated assuming the exit-POI floor; there is no connector on the user's own floor to arm `_checkFloorTransition` for the origin building (transition indices exist only where the flat point list changes floor, which for the segmented route happens inside B's entrance segment). Displayed floor remains B/F1; user floor change inside A is invisible to the app. Position stays GPS. | `cross_building_router.dart:_generateExitSegment:248-298` |
| 5 | Reach A entrance | No event keyed on the entrance. Nothing changes until Wi-Fi/GPS conditions satisfy `_checkBuildingExit` — which requires `subState == indoor` first; here subState is `outdoor`, so **exit detection is skipped entirely** (guard at :574). Walking out the door is thus a no-op state-wise. | `navigation_controller.dart:573-576` |
| 6 | Exit A, walk outdoors on GPS | Already in `outdoor`; custom-route progress tracking + polyline deviation checks now genuinely apply. Reroutes use custom graph or coordinate API. | `:298-347,391-468` |
| 7 | Approach B (<100 m centroid) | `checkBuildingApproach` one-shot preloads: `selectSpace(B)` (already selected) + floor loads. | `:641-667` |
| 8 | Reach B entrance (<25 m of entrance POI) | `checkEntranceProximity` → `_triggerIndoorTransition`: forces **ground floor '0'** of B, subState := `indoor` (prematurely — no Wi-Fi yet), `_triggerReroute()` from current GPS coords with `floorNumber='0'` → Strategy-1 coordinate route likely fails (GPS point far from floor-0 graph) → retries → likely leaves stale outdoor route until a later deviation reroute once Wi-Fi stabilizes. | `:669-737,444-468` |
| 9 | Enter B — "appears on Ground Floor" | Once B/F0 radiomap finishes loading and estimates match scope, `positionSource` flips to `indoorWifi`; marker snaps from GPS to Wi-Fi fix (jump). Displayed floor is already '0' from step 8. | `location_provider.dart:212-236`, `space_provider.dart:1608-1708` |
| 10 | Move to Floor 1 of B | If the route contains a floor-change index near the stairs/elevator: within 30 m → arm transition, preload F1 (radiomap swap), require 3 consecutive F1 estimates → confirm; displayed floor flips automatically; 10 s reroute suppression. If the route had no usable vertical leg (fallback straight-lines), the user must **manually** pick Floor 1; navigation continues against stale floor context. | `:472-569` |
| 11 | Approach destination POI along route | Only polyline-deviation applies indoors; no turn-by-turn; segment index may advance if segmented route (10 m endpoint rule). | `:319-364,770-800` |
| 12 | Arrive at destination POI | **NOT CURRENTLY SUPPORTED.** No arrival radius/check exists; `_advanceToNextSegment` merely logs at segment exhaustion (:806-811). Phase remains `active`; user must press End. | `navigation_controller.dart:803-811` |

Steps that would fail outright in variants of this scenario:

- Starting **without** having B selected (e.g., pure map-tap on a POI of B while
  standing in A) works the same because selection always retargets the destination
  building — meaning **origin-building indoor positioning is always sacrificed** in
  cross-building trips. **[VERIFIED by control flow]** `setActiveIndoorFloor` holds a
  single `(buid, floor)` scope (`location_provider.dart:184-206`).
- Entering any **third (intermediate)** building outdoors: no handling — no radiomap,
  no scope match, GPS-only, possibly wild GPS drift indoors feeding deviation checks.

---

## 9. Architecture Diagram (actual)

The requested idealized diagram does not match reality: there is no "Unified
Positioning Layer" abstraction object, and route/map/floor data do not sit *below*
positioning. The actual architecture is:

```
                ┌──────────────────────────────────────────────────────┐
                │                      User                            │
                └───────────────▲──────────────────────┬───────────────┘
                                │ taps                 │ sees
                ┌───────────────┴──────────────────────▼───────────────┐
                │ Navigation UI (MapScreen + BottomSheet + cards)      │
                │  markers · polylines · follow-camera · status bar    │
                └───────────────▲──────────────────────┬───────────────┘
             notifyListeners()  │                      │ reads
                                │                      ▼
        ┌───────────────────────┴───────────────────────────────────────┐
        │ NavigationController  ◄── listens ── LocationProvider          │
        │  phase/substate · deviation · floors · exits/entries ·         │
        │  segments · pause                                              │
        └───────────────▲───────────────────────────────┬───────────────┘
                        │ route sync                    │ currentLocation+
                        ▼                               │ positionSource
        ┌───────────────────────────────────┐   ┌───────┴────────────────┐
        │ SpaceProvider                     │   │ LocationProvider       │
        │ spaces·floors·POIs·floorplans·    │   │  ARBITRATION           │
        │ radiomap status·activeRoute       │   │  wifi-if-scope-match   │
        │  route CASCADE:                   │   │  else-gps              │
        │   CrossBuildingRouter             │   └───┬───────────┬────────┘
        │   ├ Anyplace coord route          │       │           │
        │   ├ Anyplace poi→poi route        │   gps stream   wifi stream
        │   ├ outdoor tiers (KMZ/OSRM)      │       │           │
        │   └ straight-line fallbacks       │       │           │
        └───────┬──────────────┬────────────┘       │           │
                │ HTTP         │ MethodChannel      │           │ EventChannel
                ▼              │ load/clear         │           │ position_stream
   ┌────────────────────┐      │ radiomap           │           │
   │ Anyplace server   ◄──────┼──────┐             ▼           ▼
   │ /mapping/*         │      │      │    ┌───────────────┐ ┌──────────────────┐
   │ /radiomap*         │      │      │    │ geolocator    │ │ Kotlin engine    │
   │ /floorplans64      │      │      │    │ (Android      │ │ WifiScanner →    │
   │ /navigation/route* │      │      │    │  fused GPS)   │ │ PositioningEngine│
   └────────────────────┘      │      │    └───────────────┘ │ → KnnLocalizer   │
                               │      │                      │ (single RadioMap)│
   ┌────────────────────┐      │      │                      └──────────────────┘
   │ OSRM demo server  ◄──────┼──────┤
   │ (foot profiles)    │      │      │      ┌───────────────────────────────┐
   └────────────────────┘      │      └─────▶│ Bundled KMZ campus graph      │
                               │ loadRoutes  │ (CustomRouteRepository/Graph) │
                               │             └───────────────────────────────┘
```

Differences from the idealized target architecture (relevant for the next phase):

- Positioning arbitration is embedded in `LocationProvider` rather than an explicit
  unified-layer interface — functionally similar, structurally thinner.
- `NavigationController` reaches into `SpaceProvider` (route storage, floor selection,
  custom-repo access) instead of a clean route/map-data service boundary.
- Two parallel route representations (flat hybrid vs. segments) instead of one.

---

## 10. Current Navigation Gaps

### Missing functionality
1. **No arrival detection** — no radius/threshold to destination POI; segment
   exhaustion logs only (`navigation_controller.dart:806-811`); no `ARRIVED` state.
2. **No turn-by-turn instructions** — segment `instruction` strings exist
   (`route_segment.dart:48`) but no widget renders `currentSegment`/`nextSegment`
   (grep: zero UI references).
3. **No multi-floor origin handling in cross-building exits** — exit segment origin
   floor = exit-POI floor (`cross_building_router.dart:268-273`), ignoring user's
   actual floor; no connector leg generated from user → exit floor.
4. **No handling of intermediate buildings** during the outdoor leg.
5. **Position hold during floor transitions is computed but never rendered** —
   `heldPositionDuringTransition` unused by UI; marker follows raw
   `currentLocation` (`map_screen.dart:753-774`).
6. **Pause state invisible** — `_isPaused`/`pauseMessage` set by `_checkGpsLoss`
   (:858-868) but no widget consumes them; navigation logic doesn't gate on pause.
7. **Positioning-stability output unused** — `positioningStability` never read.
8. **Partial-route guard missing** — docs say partial routes disable active
   navigation (`navigation_route_model.dart:10-12`), but `startRoutePreview` checks
   only `hasRenderablePath` (`navigation_controller.dart:153-154`); `isFullyNavigable`
   is never consulted.

### Incorrect behavior
9. **Premature indoor declaration** — subState set `indoor` on entrance proximity
   before any valid Wi-Fi fix; positioning may remain GPS for minutes.
10. **Ground-floor assumption on entry** — `_triggerIndoorTransition` always picks
    floor `'0'` regardless of destination floor or actual entry level.
11. **Wrong-floor reroute origin** — `_triggerReroute` uses
    `currentNavigatingFloor ?? '0'` even when subState is `outdoor` post-exit
    (`navigation_controller.dart:445`), sending outdoor coordinates to an indoor
    floor graph.
12. **Exit-detection paradox** — requires GPS accuracy ≤15 m while still classified
    indoors; frequently never fires (deep indoors) or fires spuriously (near
    windows). Conversely `clearSelection()` on exit wipes the provider-side route.
13. **Transition timeout leaves wrong floor selected** — `_checkTransitionTimeout`
    aborts flags but doesn't restore the previous floor selection despite
    `selectFloor` already applied (:745-763).
14. **First-candidate exit POI** — `_selectExitPoi` returns `candidates.first`
    rather than nearest/most appropriate exit (`cross_building_router.dart:239-240`).

### Architectural problems
15. **Single-slot native RadioMap** — one floor loaded at a time; cross-floor and
    cross-building positioning impossible without hot-swap gaps
    (`PositioningEngine.kt:25,43-64`).
16. **Positioning scope driven by UI selection, not by inference** —
    `setActiveIndoorFloor` mirrors `SpaceProvider` selection; destination selection
    hijacks the indoor scope away from the user's actual building (§8 step 1).
17. **Two divergent route representations** (flat hybrid vs. segments) with
    different rendering and different consumption logic.
18. **Controller ↔ Provider coupling** — `NavigationController` mutates
    `SpaceProvider` (floor selection) and reads its repo directly; circular
    notification paths (`_onSpaceProviderChanged`).
19. **Hard dependency on public OSRM demo server over plain HTTP**
    (`anyplace_api_client.dart:793,884`) — availability/compliance risk.

### Positioning problems
20. **No fusion/smoothing across sources** — hard source flips cause position jumps
    (§3); nothing interpolates or confidence-weights GPS vs. Wi-Fi.
21. **Fabricated Wi-Fi accuracy (3.0 m)** hardcoded (`location_provider.dart:224`) —
    distorts every accuracy-gated heuristic (exit detection, GPS-loss pause).
22. **Both radios always on** — no power management/duty cycling; Wi-Fi scanning
    continues outdoors, GPS continues indoors.
23. **Wi-Fi freshness window (10 s) vs. scan cadence mismatch** — throttled Android
    scan quotas can exceed the window, causing periodic silent fallbacks to GPS
    indoors (`location_provider.dart:166`, `WifiScanner.kt:22-36`).

### Floor detection problems
24. **Floor identity == radiomap slot** — reported floor is whichever map is loaded,
    not sensed; arming the transition corrupts evidence (estimates computed against
    the destination floor before arrival).
25. **Connector arming depends on route geometry** — if the server returned a
    single-floor or straight-line fallback route, no floor transition can ever be
    armed automatically (§5, §8 step 10).
26. **Manual floor change mid-navigation desyncs controller** — user-selected floor
    changes `_syncLocationProvider` scope but not `_currentNavigatingFloor`, so
    deviation checks and reroute floor arguments diverge from displayed floor.

### Entrance/exit problems
27. **Entrances are not modeled as transition boundaries** — only distance triggers;
    passing within 25 m of an entrance *without entering* (e.g., walking past)
    triggers full indoor mode + reroute.
28. **Fallback centroid triggers** (30 m from building center) can fire through
    walls/plazas far from any door.
29. **No exit/entry confirmation UX**, and no hysteresis between entry and exit
    thresholds (25 m in vs. bounds+80 m out) — oscillation possible near doors.

### Routing problems
30. **Straight-line fallbacks presented as navigable routes** (marked
    `isIncomplete` only in segment model; legacy hybrid fallbacks carry no warning
    flag beyond text).
31. **Connector-hop chains ignore corridor topology** — nearest-connector straight
    lines can cut through walls (`space_provider.dart:1056-1068,1132-1144`).
32. **Deviation metric floor-scoped only** — `_computeMinDeviation` filters points by
    current floor; multi-floor legacy routes compare only same-floor slices, so
    vertical drift is invisible.
33. **Reroute retry storm potential** — 3 attempts × backoff per deviation event,
    cooldown only 15 s, no failure backoff memory across events.

### UI/state problems
34. **Rich controller outputs unexposed**: segment/instruction, progress, pause,
    stability, held-position — all computed, none rendered (grep-verified).
35. **Preview phase vestigial** — UI always chains straight into active; no preview
    affordances.
36. **Navigation killed by tab switch** (`main_shell.dart:42-46`) — backgrounding the
    phone is fine, but checking another tab cancels a journey.
37. **Status bar conflates concepts** — `positioningStatus` mixes floor info, source,
    and blackout messaging without exposing sub-state semantics beyond an icon.

---

## 11. Final Verdict

| # | Question | Answer |
|---|---|---|
| 1 | Is GPS integrated with Wi-Fi fingerprinting as ONE unified positioning system? | **No — partially.** There is a single arbitration point producing one effective position (`LocationProvider._evaluatePositionPolicy`, `location_provider.dart:212-236`), so downstream consumers see one source. But the engines are independent, unfused, with heuristic scope-based switching, fabricated indoor accuracy, and jump-prone hand-offs (§2.5, §10 items 20–23). |
| 2 | Seamless Indoor → Outdoor → Indoor? | **No.** Transitions exist but are heuristic mode switches: premature indoor declarations at entrances, unreliable exit detection (15 m GPS-accuracy requirement indoors), ground-floor assumptions, and origin-floor-blind exit routing (§3, §6, §8). |
| 3 | Seamless Floor → Floor? | **Partially, conditionally.** Automatic only when the active route contains detectable floor-change waypoints near connectors and Wi-Fi delivers ≥3 confirming estimates; otherwise manual. The single-slot radiomap design makes the transition inherently discontinuous (§5, §10 items 15, 24–26). |
| 4 | Does it understand entrances/exits as navigation transitions? | **Only weakly.** Entrances are plain POIs used as proximity triggers and route endpoints; there is no boundary semantics, no at-entrance event, no confirmation, and asymmetric hysteresis (§6, §10 items 27–29). |
| 5 | One continuous session across multiple buildings and floors? | **No.** A single session object exists, but: the indoor scope tracks exactly one (buid, floor); origin-building indoor positioning is abandoned when targeting another building; intermediate buildings are unsupported; arrival is undetected; the route representations fragment indoor/outdoor legs (§8, §10 item 16). |
| 6 | Minimum architectural change to achieve the intended unified system? | **[PROPOSAL-CATEGORY ANSWER — minimal set inferred from the audit, not a redesign]:** (a) make the positioning layer explicitly unified: multi-floor/multi-building RadioMap residency (or fast swap cache) in `PositioningEngine` + scope inference from estimates themselves instead of UI selection, replacing `setActiveIndoorFloor` gating; (b) introduce a real navigation state machine with ENTERING_BUILDING / EXITING_BUILDING / FLOOR_TRANSITION / ARRIVED states replacing scattered booleans; (c) unify on the segment route representation (make `CrossBuildingRouter` output the only route form, with per-segment floor/building metadata driving rendering, floor logic, and progress); (d) add entrance/exit boundary semantics with hysteresis + optional confirmation, and an arrival detector terminating the session. Items (a)+(b) are the true minimum: every other gap listed in §10 becomes tractable once position scope is self-declared by the positioning layer and transitions are first-class states. |

---

*End of analysis. This document reflects the codebase state at time of writing and is
intended as the baseline reference for the upcoming unification phase.*
