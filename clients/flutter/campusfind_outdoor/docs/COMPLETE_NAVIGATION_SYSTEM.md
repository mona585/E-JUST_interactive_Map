# Complete Navigation System — Actual Implementation Reference

**Scope:** the navigation system of `clients/flutter/anyplace_campusfind` as ONE system:
outdoor + indoor + everything that connects them. Companion documents:

| Document | Covers |
|---|---|
| `INDOOR_NAVIGATION_SYSTEM.md` | Wi-Fi positioning pipeline, indoor session internals |
| `OUTDOOR_NAVIGATION_SYSTEM.md` | GPS pipeline, outdoor session internals |
| **This document** | Ownership boundaries, lifecycles, handoffs, races, cross-component inconsistencies |

## Scope of Truth

Every claim below was verified against source at commit `2856a4b7` (branch
`campusfind-migration`). Where code comments disagree with behavior, this document
reports behavior and flags the discrepancy. No fixes proposed, no source modified.

Primary evidence files:

```
lib/main.dart                                   provider wiring (:20-44)
lib/state/location_provider.dart                canonical fix + arbitration (735 lines)
lib/state/navigation_controller.dart            session engine (1468 lines)
lib/state/space_provider.dart                   selection/route/radiomap owner (2096 lines)
lib/state/navigation_state_model.dart           state table
lib/data/models/{navigation_route_model,route_segment,route_progress,
                 position_fix,user_location}.dart
lib/data/repositories/{cross_building_router,custom_route_repository,
                       custom_route_graph,navigation_repository}.dart
lib/data/datasources/{gps_location_service,anyplace_api_client,
                      native_positioning_service}.dart
lib/ui/screens/map_screen.dart                  rendering/camera (1356 lines)
lib/ui/widgets/{navigation_status_bar,arrival_banner,map_bottom_sheet,
                building_detail_card}.dart
lib/screens/main_shell.dart                     tab-leave termination, startup loads
android/.../sensing/*                           heading bridge, Wi-Fi localizer
server/app/controllers/NavigationController.scala, server/app/utils/Dijkstra.scala
test/*.dart                                     behavioral evidence
```

## Table of Contents

1. Navigation System Overview
2. Navigation Lifecycle
3. Navigation State Machine
4. Location Ownership and Data Flow
5. Outdoor → Indoor Handoff
6. Indoor → Outdoor Handoff
7. Route Lifecycle
8. Route Composition Across Outdoor and Indoor
9. Routing Engine Orchestration
10. Rerouting Across Navigation Modes
11. Floor Transitions
12. Navigation + Radiomap Lifecycle
13. Navigation + Map UI Integration
14. Navigation + Heading
15. Navigation + GPS Quality
16. Navigation + Wi-Fi Quality
17. Async / Race Conditions
18. Navigation Termination and Cleanup
19. Failure and Recovery Matrix
20. Complete Cross-Mode Sequence Examples
21. Complete System Sequence Diagram
22. Ownership Matrix
23. System-Level Inconsistencies
24. What the COMPLETE Navigation System Actually Does
25. Final Navigation Architecture

---

## 1. Navigation System Overview

```text
User starts navigation
        ↓
Location acquisition     GpsLocationService (geolocator) ─┐
                         NativePositioningService (Wi-Fi) ┘→ LocationProvider
                              (arbitration → single believed PositionFix)
        ↓
Position arbitration     LocationProvider._evaluateArbitration :432
        ↓
Route creation           SpaceProvider.requestRouteToSelectedPoi :653
                         (cascade: composer → coord API → POI API → hybrid)
        ↓
Route preview            NavigationController.startRoutePreview :321
        ↓
Active navigation        startActiveNavigation :362 (evidence-chosen mode)
        ↓
O/I/Transition states    _onLocationChanged tick pipeline :439
        ↓
Route following          deviation :653 · KMZ progress :598 · segments :1239
        ↓
Building transitions     approach :1075 · entrance :1113 · exit :1005
        ↓
Rerouting                _triggerReroute :692 (KMZ first, API ×3)
        ↓
Arrival                  _checkArrival :1371 → _arrive :1411
        ↓
Termination              endNavigation :381 (+ scope clear at UI call sites)
```

### Ownership at a glance

| Question | Answer | Evidence |
|---|---|---|
| Who owns location? | `LocationProvider.currentFix` — single believed fix; raw GPS/Wi-Fi kept in parallel maps | location_provider.dart |
| Who owns navigation state? | `NavigationController._state` + `_previousActiveState`, table-enforced via `kAllowedNavigationTransitions` | navigation_state_model.dart; controller `_transition` |
| Who owns route state? | TWO copies: `SpaceProvider._activeNavigationRoute` (**scope route** — created AND rendered from here) and `NavigationController._activeRoute` (**evaluation copy**, private). One-way sync scope→controller. | space_provider.dart:124,:287; controller :487-499 |
| Who owns selected destination? | `SpaceProvider._selectedPoi` (+ `_navigationDestinationPuid`) | space_provider.dart:126,:526-534 |
| Who owns floor/building selection? | `SpaceProvider._selectedSpace/_selectedFloor` | space_provider.dart:476-506 |
| Who owns radiomap state? | `SpaceProvider` (status + request id) driving `NativePositioningService` load/clear | space_provider.dart:1622,:1898-1905 |
| Who owns camera state? | `MapScreen` local (`_isProgrammaticMove`, gating); follow *intent* flag on controller (`_followMode`) | map_screen.dart:1065; controller :421/:428 |
| Who triggers rerouting? | Controller only (:621 → :692) | navigation_controller.dart |
| Who determines arrival? | Controller only (:1371; identity-corroborated indoors) | navigation_controller.dart |
| Who renders navigation? | `MapScreen`: marker ← `locationProvider.currentLocation`; polylines ← `spaceProvider.activeNavigationRoute` ONLY; banners/status ← controller | map_screen.dart:851,:797,:1265-1284 |

Key structural fact: **the polyline the user sees is always the SpaceProvider copy**
(map_screen.dart:851, :686). The controller's `_activeRoute` is never rendered and can
silently diverge from it (see §23, I-1/I-2).

Wiring (main.dart:20-44): three app-lifetime singletons constructed in order
`LocationProvider()` → `SpaceProvider(cacheService)` → `NavigationController(spaceProvider,
locationProvider)`; controller subscribes to scope changes in its constructor (:125) and
unsubscribes in dispose (:1438). Providers are `.value`-wrapped — never recreated.

---

## 2. Navigation Lifecycle

| Stage | Entry condition | Owner | State changes / required data | UI behavior | Exit conditions | Failure states |
|---|---|---|---|---|---|---|
| idle | app start / End pressed | controller | `_state = idle` | plain campus map; KMZ overlay if loaded | Navigate tapped | none |
| destination selected | POI tapped → detail card | SpaceProvider | `_selectedPoi`; `_resetNavigationRouteState()` when destination changes (:527-531) | PoiDetailCard with Navigate button | POI cleared/changed | none |
| route calculation | `requestRouteToSelectedPoi()` :653 | SpaceProvider | status `loading`; requestId++; guards poi/floor/location (:734,:749) | spinner (`isLoadingRoute`) | assigns `_activeNavigationRoute` at :711/:742/:820/:993/:1323/:1390/:1544, or error status | no location; Strategy1 unsupported; all engines fail; stale guard discards |
| route preview | `startRoutePreview` :321 (idle/preview only) | controller | copies dest puid/space/floor; `_activeRoute = scope route` :331 | status bar NOT shown (`isActive == false`) | Start Directions / End / POI close (:201 ends preview) | missing route → silent early return |
| active navigation | `startActiveNavigation` :362 (preview only); mode from **current fix evidence only** :371-376 | controller | counters reset; `_followMode = true`; → activeOutdoor/activeIndoor | follow camera + marker + status bar appear | arrival/pause/End/tab-leave | — |
| transitions | evidence thresholds (§5/§6/§11) | controller | dwell states entering/exitingBuilding; floorTransition blackout | labels 'Entering building…'/'Leaving building…'; held position :290 | corroboration or timeout revert | 20 s timeout reverts safely |
| rerouting | deviation >15 m or KMZ off-route >30 m, cooldown ≥15 s | controller executes; result written to SCOPE then adopted back via :487 | dynamic state `rerouting`; scope route replaced (:1390 region) | red 'Recalculating route...' (status_bar:67-77) | adoption or failure | all engines fail → previous active state kept, stale route stays |
| paused | GPS accuracy >100 m hard-coded :1422 | controller | `_state = paused`, pauseReason set | amber gps_off icon; 'Paused • weak signal' | recovery ≤100 m :1428 restores `_previousActiveState` | stuck until better fix or End |
| arrival | ≤15 m of anchor ×2 ticks (identity-corroborated indoors) | controller | `_state = arrived`; evaluation halts | green check_circle; ArrivalBanner above status bar | End only | — |
| termination | End anywhere (banner/sheet/card/back/tab) | UI pairs `endNavigation` + `clearNavigationRoute()` | §18 | overlays removed; KMZ overlay persists | → idle | `endNavigation` alone leaves stale scope polyline (§23 I-3) |

Tab-leave is also a terminator: `MainShell._stopNavigationOnTabLeave`
(main_shell.dart:35-47) calls `endNavigation()` + `clearNavigationRoute()` whenever the
user leaves the Map tab with `isActive || isPreview`.

---

## 3. Navigation State Machine

All ten states implemented in `navigation_state_model.dart`:
`idle, routePreview, activeOutdoor, enteringBuilding, activeIndoor, floorTransition,
exitingBuilding, arrived, paused, rerouting`.

`_transition(target)` validates against `isAllowedNavigationTransition(origin, target)`
(table in the model). Illegal requests are dropped with a debugPrint in production and
asserted/throwing in tests. `rerouting` is a **dynamic overlay**: it may be entered from
any live session state and returns to `_previousActiveState` on completion.

### Transition table (actual producing methods)

| From → To | Trigger / method | Condition |
|---|---|---|
| idle → routePreview | `startRoutePreview` :321 | scope route renderable |
| routePreview → activeOutdoor/activeIndoor | `startActiveNavigation` :362 | fix.source wifi→indoor else outdoor |
| any-active → enteringBuilding | `_evaluateBeliefFlip` :508 | believed-Wi-Fi fix while activeOutdoor |
| activeOutdoor → buildingApproach path | `checkBuildingApproach` :1075 | ≤100 m of destination building center (preload latch) |
| activeOutdoor → enteringBuilding | `checkEntranceProximity` :1113 → `_triggerEntranceApproach` :1166 | ≤25 m of entrance (fallback ≤30 m), dwell cooldown respected |
| enteringBuilding → activeIndoor | `_maintainDwell` :526/:528-535 | corroborated Wi-Fi scope == destination building (`_entryCorroborated` :584) |
| enteringBuilding → activeOutdoor | dwell timeout | `enteringCorroborationTimeoutSeconds = 20` |
| activeIndoor → floorTransition | `_checkFloorTransition` :804 | connector-initiated or new-floor estimate streak ×3, suppress window 10 s |
| floorTransition → activeIndoor | same method completes | expected floor reached; held position released |
| activeIndoor → exitingBuilding | `_checkBuildingExit` :1005 | 3 consecutive GPS fixes acc≤15 m outside bounds/>80 m |
| exitingBuilding → activeOutdoor | `_maintainDwell` exit branch | one more qualifying GPS tick |
| exitingBuilding → activeIndoor | timeout revert | `exitingCorroborationTimeoutSeconds = 20` |
| active* → rerouting | `_triggerReroute` :692 | deviation/off-route + cooldown 15 s + retries <3 |
| rerouting → previousActiveState | completion/failure paths | always (success adopts new route first) |
| active*/paused → arrived | `_arrive` :1411 via `_checkArrival` :1371 | §arrival rules |
| activeOutdoor ↔ paused | `_pauseNavigation` :1303 / `_checkGpsRecovery` :1428 | accuracy >100 m / ≤100 m |
| ANY → idle | `endNavigation` :381 | user action — bypasses table, direct assignment |

### User-triggered vs automatic

- User-triggered: idle↔preview, preview→active, ANY→idle, follow-mode toggles.
- Automatic: everything else — driven exclusively by PositionFix ticks arriving through
  `LocationProvider.addListener → _onLocationChanged :439`.

---

## 4. Location Ownership and Data Flow

```text
GPS (geolocator stream, 500 ms interval, displacement filter disabled)
Wi-Fi (native EventChannel, scan-driven)
        ↓ raw values into parallel maps
LocationProvider._evaluateArbitration :432
        ↓ single believed PositionFix {lat,lng,accuracy,source,floor?,scope?}
NavigationController._onLocationChanged :439   (state machine input ONLY)
        ↓
MapScreen build/display  ← locationProvider.currentLocation (marker render)
```

- Canonical source: `LocationProvider.currentFix` — exactly ONE believed fix at any time;
  the loser's latest value is retained in `_latestGps`/`_latestWifi` but not surfaced.
- Raw GPS: overwritten unconditionally on each tick while outdoor is believed
  (`_buildGpsFix` :482) — no accuracy gate on GPS itself.
- Wi-Fi estimate: qualified by matched-ratio ≥0.25 and stability window; carries
  building/floor identity from the native localizer.
- Arbitration: asymmetric — 3 consecutive qualifying Wi-Fi scans to believe indoor;
  back to GPS after 3 bad Wi-Fi cycles or 10 s silence (`indoorStaleTimerSeconds`).
- Source changes: controller learns via `fix.source`; belief-flip shortcut :508.
- Timestamps/accuracy/confidence: carried on PositionFix; confidence mapping
  ≤5 m→0.9 / ≤15 m→0.7 / else 0.5 (display only).
- Stale fixes: NO staleness detection for GPS; Wi-Fi has the 10 s timer.
- Held fixes: during floorTransition, `heldPositionDuringTransition` :290 freezes marker.
- Scope identity: PositionFix.scope {buid,floor} set only for Wi-Fi fixes; drives all
  identity-corroborated decisions.

**Authoritative location source per navigation state**

| State | Authoritative source |
|---|---|
| idle | whatever arbiter believes (GPS by default outdoors) |
| routePreview | same |
| activeOutdoor | GPS (until arbiter flips; flip triggers entry flow) |
| enteringBuilding | believed fix may be either; corroboration requires wifi |
| activeIndoor | indoorWifi (arbiter-enforced; GPS-only stretches tolerated ≤3 cycles/10 s) |
| floorTransition | held last indoor position; new-floor estimates counted separately |
| exitingBuilding | GPS required to confirm |
| paused | GPS (paused because accuracy >100 m) |
| rerouting | previous active state's source continues feeding ticks |
| arrived | ticks ignored by controller; LocationProvider keeps updating |

---

## 5. Outdoor → Indoor Handoff

Full trace with actual thresholds:

1. **Building approach/preload** — activeOutdoor + destination building known:
   distance to building center ≤100 m (`buildingPrepThreshold`) → preload latch fires →
   `selectSpace(destinationSpace)` (floors load; POIs/radiomap NOT yet).
   ≥150 m (`buildingPrepCancelThreshold`) unlatches.
2. **Entrance detection** — ≤25 m of an entrance POI (`entranceTransitionThreshold`;
   straight-line fallback ≤30 m): `enteringBuilding` dwell starts
   (`_dwellStart`, cooldown 15 s prevents re-trigger flapping).
3. **Entrance dwell** — every tick re-checks `_entryCorroborated(fix)`:
   fix.source == wifi AND fix.scope.buid == destination buid. Identity REQUIRED.
4. **Floor selection** — on corroboration OR proximity path completion,
   `_routeArrivalFloor` (:1212) supplies target = route's arrival floor for the
   destination building; `selectFloor(floor)` loads floorplan + radiomap B|F + POIs and
   sets `_currentNavigatingFloor`.
5. **Wi-Fi positioning/corroboration → activeIndoor** — arbiter's 3-scan streak plus
   scope match ends dwell; camera zooms 17→19 via subState projection.
6. Marker: unchanged pipeline (position follows believed fix); label switches to
   'Indoor • Floor F' in positioningStatus.

### Explicit answers

- **Does the route get recalculated when entering?** NO. Nothing in the entry path calls
  requestRouteToSelectedPoi or mutates route geometry.
- **Does the outdoor route get trimmed?** NO trimming exists anywhere.
- **Does an indoor route replace the outdoor one?** Only if a segment-based hybrid was
  composed initially (entrance segment already indoors); plain routes keep their geometry.
- **How are entrance and indoor segments connected?** By segment ordering in the model +
  entranceTransition/exitTransition dashed polylines; no geometric stitching beyond that.
- **Wi-Fi available BEFORE reaching entrance?** Belief flip :508 fires the moment the
  arbiter believes Wi-Fi during activeOutdoor → jumps STRAIGHT to enteringBuilding,
  BYPASSING approach/entrance checks (documented shortcut). Dwell then demands identity.
- **Wi-Fi appears but wrong building?** Corroboration fails; dwell times out after 20 s →
  revert to activeOutdoor; cycle repeats if evidence persists (cooldown gates spam).
- **Wi-Fi disappears mid-handoff?** Dwell timeout reverts safely; no partial state left
  except preloaded space selection (which persists — see §23 I-4).

---

## 6. Indoor → Outdoor Handoff

Trace:

1. **GPS recovery** — arbiter needs 3 consecutive bad-Wi-Fi cycles (or 10 s silence) to
   re-believe GPS; controller sees fix.source == gps again.
2. **Exit detection** — `_checkBuildingExit` :1005 counts GPS fixes with accuracy ≤15 m
   AND outside selected-building bounds (>80 m margin) → 3 consecutive required.
3. **exitingBuilding dwell** — one more qualifying tick confirms; silence >20 s reverts
   indoors (no fabricated exits).
4. **Side effects on confirmation** — `_applyBuildingExitSideEffects` calls
   `_spaceScope.clearSelection()` which resets space/floor/POI/radiomap/floorplan AND
   `_resetNavigationRouteState()` — **the scope's copy of the ACTIVE ROUTE IS DESTROYED**
   (space_provider.dart:468,:1920-1925), and native `clearRadioMap()` wipes ALL loaded
   radiomaps mid-session (:1904).
5. **What survives**: controller's private `_activeRoute`, destination copies, state →
   activeOutdoor. Navigation CONTINUES geometrically, but:
   - route polyline VANISHES from the map (rendering reads scope :851),
   - Wi-Fi positioning loses its map (native wiped),
   - subsequent reroute Step2 targets floor bookkeeping of the old context.
6. **Camera/marker**: follow continues; zoom projects back to outdoor 17.
7. **Wi-Fi re-engagement**: possible later only if user enters ANOTHER building (fresh
   selectFloor reloads a radiomap).

**Does clearing indoor state break the remaining session?** Functionally it survives
(state machine + private route intact) but the session loses route rendering and any
Wi-Fi fallback — the exact mismatch documented as comparison-report issue #12. This is
REAL divergence between SpaceProvider lifecycle and NavigationController lifecycle.

---

## 7. Route Lifecycle

```text
destination selected → requested → generated → stored (scope) → previewed
→ activated (controller copy) → followed → replaced (reroute/external)
→ completed → cleared
```

**Where each copy lives**

| Copy | Field | Written by | Read by |
|---|---|---|---|
| Scope route | `SpaceProvider._activeNavigationRoute` :124 | request cascade assigns (:711/:742/:820/:993/:1323/:1390/:1544); reroute writes HERE first | MapScreen polylines :851 + fitBounds :686; building card :800; controller adoption |
| Evaluation copy | `NavigationController._activeRoute` (private) | preview seed :331; adoption :491; reroute success re-adopt via scope notify | deviation, segment transitions, arrival anchor |
| Segments/points | inside both models (shared instances after adoption — no deep copy) | factories | rendering + math |
| Destination puid | scope `_navigationDestinationPuid` :126 AND controller `_destinationPuid` | selectPoi/cascade; preview | guards; UI flags |

Sync mechanism: ONE listener `_onSpaceProviderChanged` :487-499. Adoption rule:
`route != null && !identical(route, _activeRoute) && hasRenderablePath` → replace +
re-resolve arrival anchor (session live only).

> **Can two components hold different versions simultaneously? YES — three ways:**
> 1. **Scope nulled, controller keeps old**: any of selectSpace/clearSelection/
>    selectFloor/clearFloorSelection/selectPoi(different)/clearSelectedPoi wipes the
>    scope route; the listener IGNORES nulls → controller navigates on invisibly.
> 2. **Reroute window**: `_triggerReroute` writes new route to SCOPE then awaits the
>    synchronous notify→adoption; during that microtask the copies differ.
> 3. **External replacement mid-session**: a fresh requestRouteToSelectedPoi while active
>    overwrites scope; controller silently adopts it (:490-497) WITHOUT user confirmation
>    — destination changes under a live session (Scenario H).

---

## 8. Route Composition Across Outdoor and Indoor

A full trip is one `NavigationRouteModel` with ordered `RouteSegment`s:

```text
outdoorWalking → exitTransition → indoorRouting → floorTransition → indoorRouting
               → entranceTransition → outdoorWalking …   (cap 6 segments)
```

- `RouteSegmentType`: outdoorWalking / indoorRouting / exitTransition /
  entranceTransition / floorTransition (+ connector variants used by composer relays).
- Flags: `isOutdoor` true ONLY for outdoorWalking (fromSegments factory).
- Metadata per segment: buid(s), floorNumbers, points, optional connectorId/puids,
  `isIncomplete`, `isFallbackLocation`, instruction text.
- Ordering: strictly sequential; `_currentSegmentIndex` walks them (:1239 endpoint rule:
  10 m regular, connector threshold for transition segments).
- Truncation: composer hard-caps at 6 segments (silently drops the rest).
- Incomplete/fallback segments: straight-line fillers flagged `isIncomplete`;
  composition still returns status `partial` (`isPartialRoute` exposed :244).
- Rendering ignores floors entirely (draws every segment always) — only deviation math
  filters by `_currentNavigatingFloor`.

**Metadata inconsistencies (actual):**
1. Hybrid factory stamps OUTDOOR waypoints with the DESTINATION POI's buid/floorNumber —
   so `polylinePointsForFloor(_currentNavigatingFloor)` can return empty outdoors and
   ∞ deviation indoors-of-wrong-floor (deviation check silently inert).
2. Legacy two-flag routes (hasOutdoorSegment/hasIndoorSegment) vs segment routes coexist;
   rendering branches on `hasSegments` first (:855) — mixed semantics survive.
3. Connector relay segments synthesized by the composer carry connectorIds; backend
   segments never do.

---

## 9. Routing Engine Orchestration

Decision cascade in `requestRouteToSelectedPoi` (:653):

```text
guards (poi+floor+location) → requestId++
├─ Stage 0: point-in-polygon says DIFFERENT building than destination?
│     └─ CrossBuildingRouter.composeRoute  (§8; internal 5-tier outdoor engine)
│        ├─ pure KMZ findRoute
│        ├─ KMZ findHybridRoute(150 m)
│        ├─ OSRM→graph-endpoint→Dijkstra→straight line
│        ├─ OSRM + _spliceCustomTail(150 m)
│        └─ OSRM-only
├─ Strategy 1: POST /api/navigation/route/coordinates
│     (ApiException 'not supported'/'no route found'/'not be connected' or 400/404 ⇒ fall through)
├─ Strategy 2: nearest loaded-floor POI → POST /api/navigation/route (POI Dijkstra)
└─ Strategy 3: hybrid — KMZ graph → OSRM last-mile → straight-line fallback
              + optional indoor tail via connectors (poisType == 'None')
```

| Engine | Input | Output | Timeout | Authoritative? |
|---|---|---|---|---|
| KMZ graph (local Dijkstra) | lat/lng snapped ≤50 m (vertex search 500 m) | point list along campus roads | none (sync) | yes within asset coverage |
| OSRM demo foot | from/to coords | geometry+distance+duration(bearing) | 10 s | yes when code=='Ok' |
| Backend coordinate route | two coords + floor bookkeeping | POI-graph polyline | HTTP 30 s | yes unless unsupported-class error |
| Backend POI route | puid pairs | NavResultPoints | 30 s | same-floor/same-building only |
| CrossBuildingRouter | buildings+POIs+KMZ+OSRM | ≤6-segment model, partial flag | sum of children | composite authority |

No engine result is cached across requests except the loaded KMZ graph itself.

---

## 10. Rerouting Across Navigation Modes

Single implementation: `_checkDeviationAndReroute` :621 → `_triggerReroute` :692.

| Mode | Trigger measured | Step 1 | Step 2 |
|---|---|---|---|
| Outdoor (KMZ-covered) | KMZ `getRouteProgress` off-route >30 m — single tick | local `findRoute/findHybridRoute(100 m hard-coded)` | if null → coordinate API ×3 (backoff 1/2/4 s) |
| Outdoor (uncovered) | polyline deviation >15 m vs floor-filtered points | skipped (not outdoor bookkeeping) | coordinate API ×3; sends `_currentNavigatingFloor ?? '0'` even outdoors |
| Indoor | deviation >15 m on indoor polyline | skipped | coordinate API ×3 with current floor |
| enteringBuilding / exitingBuilding | checks skipped during dwells (:621 guard) | — | — |
| floorTransition | skipped (blackout + 10 s suppress) | — | — |

- Cooldown stamped BEFORE work starts (`_lastRerouteTime = DateTime.now()`), retries
  capped `rerouteMaxRetries = 3`.
- Success: new route written to SCOPE → notify → adoption :491 re-resolves anchor;
  state restored to previous active.
- Total failure: previous active state restored, OLD route stays active (stale but
  consistent); retry possible after next cooldown.
- **End during rerouting**: adoption and the final transition are gated by
  `_state.isSessionLive`; ending mid-await leaves the HTTP to finish harmlessly, nothing
  adopted, no transition. PROTECTED.
- **Destination changed while rerouting**: selectPoi wipes scope route; reroute's later
  scope-write can still land (its own request context doesn't check destination puid) →
  a route for the OLD destination may be re-installed AFTER the user picked another POI
  (race R-6 in §17).
- Floor change mid-reroute: result targets old floor bookkeeping; no revalidation against
  current selection.

---

## 11. Floor Transitions

```text
activeIndoor → connector detection (segment type floorTransition OR connector POI
             within 30 m `connectorProximityThreshold`)
            → _beginConnectorFloorTransition → selectFloor(target)   [WIPES SCOPE ROUTE]
            → floorTransition blackout (held position render)
            → radiomap+floorplan+POIs load for new floor
            → new-floor estimates ×3 confirm → activeIndoor
            → 10 s post-switch suppression of further switches
```

- Stairs/elevators are NOT modeled; only connector POIs/segments.
- Automatic floor changes go through the SAME `selectFloor` as manual taps — including
  its `_resetNavigationRouteState()` (:499). Consequence documented in §23 I-1.
- Timeout: none aborts a stuck transition; only the arbiter continuing to emit
  qualifying new-floor estimates advances it. Wrong-floor Wi-Fi simply never confirms;
  user sees indefinite blackout text with held marker until evidence resolves or End.
- Route replacement: none — controller keeps evaluating against
  `polylinePointsForFloor(_currentNavigatingFloor)` of its private copy.
- Camera: zoom stays indoor 19; marker frozen at `_lastIndoorPosition` until confirm.

---

## 12. Navigation + Radiomap Lifecycle

| Event | Radiomap effect |
|---|---|
| app start | none loaded |
| selectSpace (incl. approach preload) | previous cleared (native clearRadioMap :1904), none loaded yet |
| selectFloor (any path: manual, entrance handoff, connector transition) | `loadRadioMapForSelectedFloor` :1622 requestId-captured → native startRadioMap B\|F |
| Wi-Fi estimates begin | immediately upon native map activation (arbiter consumes) |
| floor→floor transition | new load replaces old (requestId discards stale response :1644/:1680/:1703) |
| confirmed building EXIT | `_resetRadioMapState` via clearSelection → ALL maps wiped MID-SESSION (:1904) |
| rerouting | untouched |
| arrival | untouched |
| End navigation | UNTOUCHED — radiomap of last selected floor stays loaded & positioning continues |
| before navigation | loadable independently (selectFloor anytime) |

**State inconsistency**: navigation End does not stop Wi-Fi positioning or unload the
radiomap — background scanning persists after termination (intentional for browsing, but
it means "End" is not a full teardown of the sensing stack).

---

## 13. Navigation + Map UI Integration

| Element | Driven by | Evidence |
|---|---|---|
| User marker (position) | LocationProvider.currentLocation | map_screen build |
| Marker rotation | DeviceHeadingBridge EMA (≤2000 ms compass freshness) | _updateHeading :409 |
| Route polylines (ALL types) | SpaceProvider.activeNavigationRoute ONLY | :851 |
| Custom KMZ overlay | CustomRouteRepository loaded flag | :820 region |
| Fit-bounds at start | SpaceProvider.activeNavigationRoute | :686 |
| Follow camera | nav.isActive && followMode listener :335 | :471/:499 |
| Pan-exit follow | onCameraMove !_isProgrammaticMove | :1065 |
| Re-center button | resumeFollowMode :428 | :1230-1235 |
| Status bar visibility | context.select isActive | :1265 |
| Status label/icon/substate | NavigationController (navigationStatusLabel) | status_bar.dart:56,:88-106 |
| Instruction strip | currentSegment.instruction via NavigationInstructionStrip | status_bar import |
| Recalculating line | nav.isRerouting | status_bar:67-77 |
| Arrival banner | nav.isArrived; Done → end+clear | :1275-1280 |
| PoiDetailCard flags | spaceProvider loading/error/hasActiveRoute + navController.isPreview/isActive | map_bottom_sheet:196-236 |
| Building card route block | provider.activeNavigationRoute | building_detail_card:800 |

Lifecycle note: didChangeAppLifecycleState logs + re-centers camera on resume; tracking
is NOT paused/resumed with app lifecycle.

---

## 14. Navigation + Heading

Heading is PRESENTATION-ONLY. Verified non-effects:
- not used by LocationProvider arbitration or PositionFix content (stripped from
  currentLocation),
- not used by any routing engine,
- not used by route progress/KMZ projection,
- not used by off-route deviation math,
- not used by arrival confirmation,
- not used by any state transition.

Sole consumers: marker rotation (>0.5° hysteresis) and camera bearing during follow
(gate 1.5°). Movement-bearing fallback requires speed>0.2 m/s and ≥0.15 m displacement.

---

## 15. Navigation + GPS Quality

Actual mechanisms (complete list):

| Mechanism | Where | Behavior |
|---|---|---|
| accuracy field | GpsLocationService pass-through | unfiltered value into PositionFix |
| pause | controller :1422 | accuracy >100 m (hard-coded) → paused |
| recovery | :1428 | ≤100 m restores previous active state |
| confidence mapping | location_provider `_gpsConfidence` | ≤5 m .9 / ≤15 m .7 / else .5 (display-only) |
| cross-mode jump rejection | arbiter `_isOutlierJump` | believed-fix jump >30 m rejected (protects flips, not GPS stream itself) |
| smoothing | NONE for GPS | — |
| stale detection | NONE for GPS | last fix canonical indefinitely |
| accuracy gate on fixes | NONE in outdoor belief | `_buildGpsFix` unconditional |
| off-route interplay | deviation uses accuracy? NO — raw geometry only | thresholds fixed 15 m |
| building-exit interplay | exit REQUIRES acc ≤15 m per tick | quality-gated transition |
| arrival interplay | radius fixed 15 m regardless of accuracy | — |

---

## 16. Navigation + Wi-Fi Quality

Qualification chain (per scan): matched AP count/ratio ≥0.25 → stability window
(min 3 estimates) → candidate belief. Belief switch needs 3 consecutive qualifying
scans (`indoorEnterConfirmCount`); loss needs 3 bad cycles or 10 s staleness.
Scope (building+floor identity) confirmed separately over a 3-scan streak and attached
to PositionFix.scope. Outlier jumps >30 m between believed fixes discarded.
Effect on navigation: ALL identity-corroborated transitions (entry dwell, indoor
arrival, floor confirm) consume scope; unconfirmed-scope Wi-Fi keeps dwells waiting.

---

## 17. Async / Race Conditions

| # | Situation | Protection found | Verdict |
|---|---|---|---|
| R-1 | Route A finishes after B | `_navigationRouteRequestId` + selected-poi(+floor) checks before every assign (:734-838 region) | PROTECTED |
| R-2 | Reroute finishes after End | adoption + final transition gated by `_state.isSessionLive` | PROTECTED (HTTP runs to completion, result discarded) |
| R-3 | Destination changed during calculation | same requestId/puid guard → stale discarded; controller unaware (keeps old dest if active — divergence, not corruption) | PARTIAL |
| R-4 | Floor changed during calculation | guard includes floor check on Strategy paths; connector selectFloor mid-session bypasses request path entirely | PARTIAL |
| R-5 | Building/space selection changes during routing | NO check on `_selectedSpace` identity in guards | GAP |
| R-6 | Reroute completes after user picked new POI | reroute scope-write has no destination revalidation → old-destination route can overwrite fresh null scope | GAP (real) |
| R-7 | Wi-Fi source flips while route pending | no interlock between arbiter and request context | GAP by design; consequences bounded (§10) |
| R-8 | Navigation ends while API running | see R-2 pattern for reroute; initial cascade results land in scope even after End (scope is UI-owned; harmless polyline until cleared or adopted-never since controller idle ignores :494 gate... note: adoption requires sessionLive, so idle controller will NOT adopt) | PROTECTED for state; scope may briefly show a fresh polyline with no session |
| R-9 | Route replaced externally while controller active | intentional silent adoption :490-497 | BY DESIGN (risky, §23 I-2) |
| R-10 | Radiomap load completes after leaving building | clearSelection bumps `_radioMapRequestId` (:462) → late response discarded (:1644) AND native map was already cleared | PROTECTED |
| R-11 | Stale async overwrites newer state (general) | per-domain requestIds: radiomap :1622, floorplan, poi, navigation-route | PROTECTED where ids exist |
| R-12 | Timer source inconsistency | deviation/reroute cooldown uses `DateTime.now()` while dwell timers use injectable `_now()` | test-only inconsistency |

No cancellation primitives exist anywhere (no HTTP aborts): every in-flight request runs
to completion and relies on discard-guards.

---

## 18. Navigation Termination and Cleanup

`endNavigation` :381-405 — direct assignment to idle (bypasses table), then nulls:
destination puid/space, `_activeRoute`, floor bookkeeping, transition events, follow=true,
all counters/latches/anchors/dwell timestamps, segment tracking, custom progress.

What endNavigation does NOT touch: LocationProvider tracking, native positioning,
radiomap, SpaceProvider selections (space/floor/POI), scope route, camera position,
KMZ overlay, loaded floors.

Therefore UI call sites always pair it with `spaceProvider.clearNavigationRoute()`:

| Site | Order |
|---|---|
| ArrivalBanner Done (map_screen:1276-1279) | end → clear |
| PoiDetailCard.onEndNavigation (sheet:218-221) | end → clear |
| PoiDetailCard.onClearRoute (sheet:205-208) | clear → end |
| BuildingDetailCard (card:307-308) | clear → end |
| MainShell tab-leave (main_shell:44-45) | end → clear |

Per-starting-state comparison: identical code path from EVERY state (arrived, paused,
rerouting, dwells included). Differences are only side-effect residue:
- from arrived: banner disappears with status bar.
- from paused: nothing special.
- during rerouting: in-flight work discarded via isSessionLive gates.
- from dwells/transitions: held-position release, counters zeroed.
Residue common to all: last radiomap still loaded, Wi-Fi scanning continues, selected
space/floor/POI remain (detail sheet stays open), camera stays wherever it was, KMZ
overlay persists.

---

## 19. Failure and Recovery Matrix

| Failure | Actual behavior | Recovery | Remaining stale state |
|---|---|---|---|
| GPS permission denied | status permissionDenied; SnackBar guidance; no fixes | user grants in OS settings | none |
| GPS services off | serviceDisabled before permission ask | enable in OS | none |
| No first fix (15 s) | getLastKnownPosition fallback → error message | retry button/my-location | none |
| Poor accuracy (>100 m) | navigation paused, label 'Paused • weak signal' | auto ≤100 m | none |
| GPS jump | NOT detected within GPS stream (only arbiter cross-mode >30 m) | — | possible marker teleport render |
| GPS stale | undetected | — | frozen marker believed current |
| Wi-Fi unavailable outdoors | irrelevant (GPS believed) | — | — |
| Wi-Fi wrong building during entry dwell | corroboration fails; 20 s revert | cycle repeats | preloaded space selection persists |
| Wi-Fi wrong floor indoors | floor confirm streak never lands; floorTransition blackout continues | correct-floor scans | held marker frozen indefinitely |
| Radiomap unavailable | loadRadioMap error status; POIs may still load; positioning stays GPS-believed | reselect floor | error message until next attempt |
| Backend down | Strategy1→2 fail fast/timeout → hybrid KMZ/OSRM or straight-line partial | later Navigate tap retries | none beyond partial flag |
| OSRM down | tier falls through to straight-line incomplete segment | reroute may restore | isIncomplete flag on segment |
| KMZ asset missing/corrupt | graph empty; KMZ tiers skipped; overlay absent | app reinstall/rebuild asset | — |
| Route empty (<2 pts) | hasRenderablePath false: preview refused, adoption skipped, cascade falls through | alternate engines | none |
| Route partial | status partial; warning segments rendered dashed | none automatic | isIncomplete flags |
| Reroute total failure ×3 | previous active state restored; old geometry kept | next cooldown window | stale route |
| Floor load failure during transition | blackout persists; POIs/floorplan error states set separately | manual floor pick | held marker |
| Preload failure (approach selectSpace) | latch stays set? latch reset only on cancel distance; floors error surfaced | re-approach after 150 m unlatch | preload latch true |
| App backgrounded | tracking continues unpaused; on resume camera re-follows | — | battery/OS policy risk |
| Network timeout mid-cascade | per-call timeouts (30 s backend / 10 s OSRM) then next strategy | — | loading flag cleared at final failure |
| User Ends during async work | isSessionLive/requestId guards discard outcomes | — | none |

---

## 20. Complete Cross-Mode Sequence Examples

Format: State · LocationSource · Route(scope/controller) · UI

**A. Outdoor → Building → Indoor → Destination**
activeOutdoor(gps, S=C, C=C) → ≤100 m preload(S loads) → ≤25 m enteringBuilding(gps,
S=C,C=C, 'Entering building…') → corroborated → activeIndoor(wifi F1, S=C F1 loaded,
C=C) → ≤15 m×2 arrived(wifi, C=C, banner). Polyline visible whole way (hybrid segments).

**B. Outdoor → building → Wi-Fi fails → remains outdoor**
enteringBuilding(gps) → 20 s timeout → activeOutdoor(gps); repeats each pass; arrival
still possible via proximity-only outdoor rule if anchor reachable outdoors; scope+controller routes unchanged throughout.

**C. Indoor → floor transition → new floor**
activeIndoor(wifi F1, scope route WIPED at selectFloor :499, C=private copy intact)
→ floorTransition(held marker, blackout text) → loads B|F2 → ×3 estimates →
activeIndoor(wifi F2). **UI shows NO route polyline from the moment selectFloor fired**
(§23 I-1) though navigation math continues.

**D. Indoor → exit → outdoor, same destination**
exitingBuilding(gps ticks ×3) → confirmed → clearSelection wipes scope route + ALL
radiomaps; controller keeps private route → activeOutdoor(gps). Deviation now computed
against destination-stamped points of private copy (may be inert per §8); reroute Step2
available. Polyline invisible; session alive; arrival anchor = destination POI if its
floor's POIs were unloaded → fallback last-route-point anchor.

**E. Outdoor off-route → reroute → continue**
activeOutdoor(gps), KMZ on-route lost >30 m → cooldown ok → rerouting(state, red line)
→ findHybridRoute succeeds → scope replaced → adopted(:491) → activeOutdoor(new C=new S)
→ fitBounds NOT re-run (camera follows marker instead).

**F. Indoor off-route → reroute → continue**
deviation >15 m on F1 polyline → coordinate API ×N with floor 'F1' → success replaces
both copies → activeIndoor continues; failure keeps old indoor geometry silently.

**G. End during rerouting**
user taps End while HTTP in flight → idle immediately; completion hits isSessionLive=false
→ nothing adopted, no transition, HTTP result dropped. Scope cleared by handler. Any
later stray scope write would render a polyline with no session (cosmetic).

**H. Destination changed while active**
activeOutdoor(C→RoomX). User taps RoomY → selectPoi resets SCOPE route(dest mismatch
:527-531) → polyline vanishes; controller keeps navigating toward RoomX invisibly;
PoiDetailCard(RoomY) shows hasActiveRoute=false. If user taps Navigate: NEW cascade runs
(requestId fresh) and on success adoption :490 silently retargets live session to RoomY
(no preview, no confirmation). If reroute-in-flight for RoomX completes AFTER that, race
R-6 may re-install RoomX geometry.

---

## 21. Complete System Sequence Diagram

```text
User
 ↓ tap POI / Navigate
Map/UI (PoiDetailCard, MapBottomSheet)
 ↓ requestRouteToSelectedPoi
SpaceProvider ── requestId, guards
 ├─ CrossBuildingRouter (KMZ graph ⇄ OSRM demo HTTP)
 ├─ AnyplaceApiClient → Play backend
 │    └─ NavigationController.scala → Dijkstra (POI/Connection Mongo graph)
 └─ hybrid composer (+straight-line fallback)
 ↓ NavigationRouteModel (segments)
SpaceProvider._activeNavigationRoute  ←──── rendered by MapScreen polylines :851
 ↓ listener :487
NavigationController._activeRoute (evaluation copy)
 ↓ startRoutePreview/startActiveNavigation
STATE MACHINE (idle→preview→active…)
 ↑ every PositionFix tick
LocationProvider.currentFix
 ├── GpsLocationService (geolocator, 500 ms)
 └── NativePositioningService (Android Wi-Fi localizer; radiomap B|F loaded by SpaceProvider)
      └── android sensing: WifiScanner + RadioMapWorker (JNI) · DeviceHeadingBridge (~50 Hz)
 ↓ ticks
deviation/reroute · transitions · arrival · pause
 ↓ notifyListeners
MapScreen: marker(currentLocation) · polylines(scope route) · camera(followMode)
           · status bar/instruction/recalc line · ArrivalBanner
```

---

## 22. Ownership Matrix

| Responsibility | Actual Owner | Supporting | Source |
|---|---|---|---|
| GPS acquisition | GpsLocationService | geolocator plugin | datasources/gps_location_service.dart |
| Wi-Fi positioning | NativePositioningService → Android localizer | radiomap B\|F | datasources/native_positioning_service.dart |
| Canonical location | LocationProvider.currentFix | arbitration maps | location_provider.dart |
| Location arbitration | LocationProvider | — | :432 |
| Route creation | SpaceProvider cascade | router/OSRM/backend | space_provider:653 |
| Route storage (rendered) | SpaceProvider._activeNavigationRoute | — | :124 |
| Route storage (evaluation) | NavigationController._activeRoute | adoption :491 | controller |
| Navigation state | NavigationController._state | state table model | navigation_state_model.dart |
| Rerouting decision+execution | NavigationController | KMZ repo, API client | :621,:692 |
| Arrival determination | NavigationController | scope POIs | :1371 |
| Floor transition | NavigationController trigger → SpaceProvider selectFloor | native reload | :804 |
| Building transition | NavigationController dwells | arbiter evidence | :526,:1005,:1113 |
| Radiomap loading | SpaceProvider.loadRadioMapForSelectedFloor | NativePositioningService | :1622 |
| Radiomap clearing | SpaceProvider._resetRadioMapState | native clearRadioMap | :1898-1905 |
| Marker render | MapScreen | heading bridge | :797,:409 |
| Camera | MapScreen | controller followMode flag | :471,:1065,:421/:428 |
| Heading | DeviceHeadingBridge → MapScreen EMA | — | android sensing |
| Selected building/floor/POI | SpaceProvider | UI cards | :428-:543 |
| Destination | SpaceProvider destPuid + controller copy | preview seed | :126/:331 |
| Navigation cleanup (route) | UI call sites pairing both APIs | — | §18 table |
| Session teardown (sensing) | NOBODY fully — tracking+radiomap survive End | — | §18 |

---

## 23. System-Level Inconsistencies

**I-1 Floor selection destroys the visible route during navigation**
A: `selectFloor` unconditionally `_resetNavigationRouteState()` (:499).
B: connector floor-transition calls selectFloor mid-session (:804 path).
Disagree because: selection API doubles as transition mechanism with no session-awareness.
Consequence: polyline vanishes at the exact moment of floor change (Scenario C) while the
session continues on the invisible private copy.
Classification: REAL BUG (user-facing).

**I-2 Two route copies can silently diverge**
A: rendering reads ONLY scope (:851). B: evaluation uses ONLY controller copy.
Sync is one-way, null-ignoring (:487-499).
Consequence: scenarios C/D/H — map shows nothing or stale geometry while math proceeds;
silent retarget on external replacement.
Classification: ARCHITECTURAL FLAW surfaced as bugs (I-1, I-3, H).

**I-3 endNavigation alone leaves a ghost polyline**
Controller resets; scope untouched unless the caller remembers to clear. All five UI
sites pair them manually — any future caller may forget.
Classification: LATENT BUG (API design).

**I-4 Confirmed building exit wipes ALL radiomaps + scope route mid-session**
(:1904 via clearSelection :452-472). Controller survives; positioning fallback and route
rendering die. Matches comparison report issue #12.
Classification: REAL BUG.

**I-5 Hybrid outdoor waypoints carry destination floor metadata**
floor-filtered deviation becomes inert for those routes (§8).
Classification: REAL BUG (silent check disablement).

**I-6 Reroute targets floor bookkeeping outdoors** (`_currentNavigatingFloor ?? '0'`).
Coordinate reroute snaps onto last-known indoor context even when user is outside.
Classification: BUG (mild; often masked by Strategy1 coordinate success).

**I-7 KMZ overlay comment contradicts behavior** — code draws custom roads ALWAYS when
loaded; comment claims only-while-navigating. Rendering also ignores floors for ALL
segment types (draws future floors' lines immediately).
Classification: DOC/COMMENT DRIFT + intentional simplification.

**I-8 "Deferred indoor route refresh at entry" comment unimplemented.**
No recalculation exists in the entry path.
Classification: COMMENT DRIFT.

**I-9 Timer sources mixed**: DateTime.now() (cooldown) vs injectable _now() (dwells).
Classification: test-harness inconsistency only.

**I-10 Preview is ephemeral in production**: sheet's onStartDirections calls preview +
activation back-to-back (:209-217); routePreview exists meaningfully only when activation
early-returns (no fix) — yet tab-leave treats isPreview as terminable.
Classification: intentional but fragile coupling.

---

## 24. What the COMPLETE Navigation System Actually Does

### ACTUALLY DOES
- One believed PositionFix at all times via asymmetric GPS⇄Wi-Fi arbitration.
- Client-side composition of up to 6 segments across three engines; backend does
  POI-graph shortest paths only (≤5 km, same-building).
- A 10-state table-enforced machine driven solely by LocationProvider ticks.
- Identity-corroborated O↔I handoffs with safe-revert dwells (20 s).
- Reactive single-shot rerouting (KMZ-first outdoors, API×3) with cooldown/backoff and
  stale-route retention on failure.
- Fixed-threshold arrival (15 m ×2; identity indoors) and fixed pause (>100 m acc).
- Rendering strictly from the scope route copy; camera follow gated/coalesced.

### DOES NOT DO
- No trimming/recalculating at building entry; no turn-by-turn maneuvers or ETA UI;
  no Google Directions; no server cross-building routing; no GPS smoothing/staleness/
  accuracy gating; no cancellation of in-flight requests; no foreground service;
  no full sensing teardown on End; no stairs/elevator modeling beyond connectors;
  no post-reroute camera refit.

### PARTIALLY IMPLEMENTED
- Cross-building trips (works via composer, capped/truncated at 6 segments).
- Connector relays (entrance-side yes; arbitrary mid-route relay limited).
- Preview state (bypassed by immediate activation in the primary UI path).
- Multi-floor indoor trips (transition machinery exists; visible route dies at each
  automatic selectFloor — I-1).

### CURRENT RISKS
- Silent destination retarget under a live session (H/R-9).
- Ghost polylines from unpaired cleanup or post-End strays.
- Positioning quality cliff after confirmed exit (all maps wiped).
- Deviation inertness classes (I-5/I-6) remove the safety net exactly off-road.
- Demo OSRM over plain HTTP as a load-bearing dependency.

### ARCHITECTURAL INCONSISTENCIES
I-1…I-10 above; root causes: dual route ownership without a sync contract, selection
APIs overloaded for transition mechanics, and lifecycle boundaries drawn per-provider
rather than per-session.

### IMPORTANT UNKNOWNs
- Behavior under iOS (arbiter tuned/tested on Android evidence paths only).
- Battery/OS throttling effects on the never-stopped GPS stream in background.
- Server-side Connection weight semantics for outdoor-ish connectors (data-dependent).
- Whether straight-line fallback segments ever receive live traffic in the current
  campus dataset coverage.

---

## 25. Final Navigation Architecture

```text
                    ┌──────────────────┐
                    │      USER        │
                    └────────┬─────────┘
                             ↓
                    ┌──────────────────┐
                    │    Map / UI      │ MapScreen · sheets · cards
                    └────────┬─────────┘
                             ↓
                    ┌──────────────────┐
                    │  SpaceProvider   │ selection·route(scope)·radiomap
                    └────────┬─────────┘
                             ↓
                  ┌───────────────────────┐
                  │  Route Composition    │ composer · KMZ · OSRM · backend
                  └──────────┬────────────┘
                             ↓
                  scope route ──listener──► controller copy
                             ↓
                    ┌──────────────────┐
                    │   Navigation     │ 10-state machine · reroute · arrival
                    │   Controller     │
                    └────────┬─────────┘
                             ↑ ticks
                    ┌──────────────────┐
                    │ LocationProvider │ arbitration → ONE PositionFix
                    └───────┬───┬──────┘
                          GPS│   │Wi-Fi(radiomap B|F via native)
                            └─┬─┘
                              ↓
                      Building/Floor transitions
                              ↓
                          Rerouting
                              ↓
                           Arrival
                              ↓
                       End(+scope clear) → Idle
```

### The direct answer

> **From destination selection to termination, what actually happens?**

The user taps a POI; SpaceProvider stores it (wiping any prior route whose destination
differs) and shows the detail card. Navigate triggers `requestRouteToSelectedPoi`:
guards pass, a fresh requestId is taken, and one of four engines produces a
NavigationRouteModel that lands in `SpaceProvider._activeNavigationRoute` — this single
object is everything the map will ever draw. Start Directions seeds the controller's
private copy and immediately activates, choosing outdoor vs indoor purely from the
current fix's source. From then on EVERY PositionFix the arbiter believes (GPS raw
pass-through, or identity-bearing Wi-Fi estimates against whichever radiomap
SpaceProvider last loaded) is pumped through one pipeline: belief flips, KMZ progress,
15 m deviation→cooldown→KMZ/API×3 rerouting written to the scope and re-adopted,
connector-driven floor changes (which erase the visible route while math continues),
20-second corroborated building entries/exits whose confirmation side effects wipe all
radiomaps and the scope route, fixed-radius two-tick arrival that halts evaluation, and
a >100 m accuracy pause that merely suspends. Pressing Done/End — from any state — runs
the pair endNavigation()+clearNavigationRoute() (or tab-leave equivalent), returning the
machine to idle while GPS tracking, Wi-Fi scanning, the last radiomap, selections, and
the KMZ overlay all continue living underneath an idle system.

---

*Documentation-only artifact; reflects source at commit `2856a4b7`
(branch `campusfind-migration`). No source files were modified.*
