# COMPLETE NAVIGATION SYSTEM — MASTER IMPLEMENTATION PLAN

| | |
|---|---|
| **Target** | `clients/flutter/anyplace_campusfind` |
| **Branch / HEAD** | `campusfind-migration` @ `2856a4b7` |
| **True baseline** | **Working tree** (uncommitted changes on top of HEAD — see §2) |
| **Supersedes** | `docs/# Complete Navigation System — Full.md` (partially stale), plus `COMPLETE_NAVIGATION_SYSTEM.md`, `NAVIGATION_SYSTEM_ANALYSIS.md`, `INDOOR_NAVIGATION_SYSTEM.md`, `OUTDOOR_NAVIGATION_SYSTEM.md`, `NAVIGATION_IMPLEMENTATION_HISTORY.md` |
| **Status** | PLAN ONLY — no code changed yet |
| **Verification method** | Every claim below was re-verified against the current working tree by direct inspection. Line numbers refer to working-tree files at time of writing. Shorthands: **SP** = `lib/state/space_provider.dart`, **NC** = `lib/state/navigation_controller.dart`, **LP** = `lib/state/location_provider.dart`, **M** = `lib/ui/screens/map_screen.dart`, **MS** = `lib/screens/main_shell.dart`, **NSM** = `lib/state/navigation_state_model.dart`, **CBR** = `lib/data/repositories/cross_building_router.dart`, **NRM** = `lib/data/models/navigation_route_model.dart`, **RS** = `lib/data/models/route_segment.dart`. |

---

## 1. Purpose

This document is the single authoritative plan for making outdoor GPS navigation, indoor Wi-Fi fingerprint navigation, cross-mode handoffs, floor transitions, cross-building routing, rerouting, rendering, camera, heading, radiomap lifecycle, session lifecycle, async safety, termination, and error recovery behave as **one coherent navigation experience**:

> select destination → route calculated → navigation started → outdoor GPS guidance → destination building detected → indoor positioning prepared → user enters → Wi-Fi positioning takes over → correct floor loads → indoor route continues → floor transitions work → route stays visible → exit → GPS resumes → outdoor continues → rerouting on deviation → reliable arrival → End completely cleans up.

It replaces all previous navigation planning documents, which are retained only as history. Where they conflict with this plan, **this plan wins**: every claim here was re-derived from current code.

Execution rules:

1. Execute phases strictly in order (§9). No skipping.
2. Never proceed past a phase whose acceptance criteria are unmet or whose tests are red.
3. Never re-implement anything listed in §4 (Already Implemented — Do Not Redo).
4. Preserve the verified indoor Wi-Fi pipeline (§4 items 4–6) unless a phase explicitly modifies it.
5. If code reality diverges from this plan during execution, stop and update the plan first.
6. Do not modify backend (`server/`) behavior; all fixes are client-side.

---

## 2. Current Code Baseline

### 2.1 Repository state (verified)

```
HEAD:      2856a4b7  fix(campusfind): stabilize floorplan ground overlay lifecycle and loading
Branch:    campusfind-migration
Worktree:  DIRTY — 15 modified files, +1764/−1007 lines, plus untracked docs/
```

The uncommitted diff touches exactly the navigation core:

| File | Diff |
|---|---|
| `lib/state/navigation_controller.dart` | ±1072 lines |
| `lib/state/location_provider.dart` | +510 |
| `lib/ui/screens/map_screen.dart` | ±136 |
| `lib/data/models/navigation_route_model.dart` | ±113 |
| `lib/config/navigation_config.dart` | +77 |
| `android/.../positioning/*.kt` (Engine, Bridge, KnnLocalizer, WifiScanner) | ~330 |
| `lib/data/datasources/native_positioning_service.dart` | +30 |
| `lib/state/space_provider.dart` | ±42 |

**Consequence:** the previous plan claimed baseline = commit `2856a4b7`; in practice live code is far ahead of that commit. All analysis here was performed against the **working tree**, the only valid source of truth. Phase 0 freezes this tree so line references stay meaningful and rollback is possible (§14).

### 2.2 Toolchain (verified)

- Flutter 3.44.9 stable / Dart 3.12.2 (matches pubspec `sdk: ^3.12.2`)
- `flutter analyze`: **0 errors**, 3 warnings, 27 infos (23× `avoid_print` in CBR)
- Deps: `google_maps_flutter ^2.10.0`, `geolocator ^13.0.2`, `provider ^6.1.2` (state) + `flutter_riverpod ^2.6.1` (DI), `http ^1.6.0`, `archive ^3.6.1`
- Tests: **16 files** under `test/` (inventoried §12)

### 2.3 Component map

| Component | File | Role today |
|---|---|---|
| SpaceProvider | SP (2096 ln) | Buildings/floors/POIs/floorplans/radiomaps; **initial route cascade**; owns `_activeNavigationRoute` — the only route the map renders (M:851, M:686) |
| NavigationController | NSM (196 ln) + NC (1468 ln) | 10-state machine; private `_activeRoute` evaluation copy; deviation/reroute/arrival/floor transitions/handoff dwells/camera follow flags |
| LocationProvider | LP (~735 ln) | GPS↔Wi-Fi arbiter; canonical `PositionFix.currentFix`; mature indoor quality pipeline; **no outdoor quality pipeline** |
| MapScreen | M (~1300 ln) | Renders scope route only; camera/follow/marker/heading presentation |
| CrossBuildingRouter | CBR (1059 ln) | Composes exit→outdoor→entrance; 5-tier outdoor leg; connector relays; entrance scoring |
| CustomRoute/KMZ stack | `custom_route_repository/graph`, `kmz_loader` | Campus KMZ graph routing, snap/off-route progress |
| NavigationRepository / API client | `navigation_repository.dart`, `anyplace_api_client.dart` | Backend `/api/navigation/route*`; direct public OSRM foot-routing calls |
| Native positioning engine | `android/.../positioning/*.kt` | Resident-radiomap KNN engine (verified working — do not rewrite) |
| MainShell | MS | Tabs; explicitly kills navigation when leaving Map tab (MS:35–47) |

### 2.4 Key data flow today (as-built)

```
Initial route:  UI → SpaceProvider.requestRouteToSelectedPoi/requestRouteToBuilding
                cascade: cross-building router → backend coordinate route → backend POI route
                → KMZ graph → hybrid edge-snap → OSRM(+splice) → straight-line fallback
                writes SP._activeNavigationRoute   (guarded by _navigationRouteRequestId)

Preview/start:  MapBottomSheet → navController.startRoutePreview(pulls scope route)
                              → navController.startActiveNavigation()

Tick pipeline:  LocationProvider fix → NC._onLocationChanged:
                held-transition check → post-switch suppression → segment transition
                → arrival → handoff dwell checks → floor transition → custom-route progress
                → deviation+reroute (NC:476) → … → GPS-loss pause (NC:483)

Rendering:      MapScreen reads ONLY spaceProvider.activeNavigationRoute
Evaluation:     controller reads its own _activeRoute copy (synced scope→controller only)
```

---

## 3. Current Gap Analysis

Classification: **A** = ALREADY IMPLEMENTED AND VERIFIED · **B** = PARTIALLY IMPLEMENTED — NEEDS MODIFICATION · **C** = NOT IMPLEMENTED · **D** = BUGGY — EXISTS BUT INCORRECT. All previously-UNKNOWN items were investigated and resolved; none remain.

| # | Area | Class | Evidence (working tree) | Fix |
|---|---|---|---|---|
| 1 | Navigation state machine (10 states, edge table) | A | NSM:129–171; pure legality test in `navigation_state_machine_test.dart` | — |
| 2 | Arrival 2-tick confirmation | A | NC:1402–1407; `arrival_test.dart` exhaustive | — |
| 3 | Indoor arrival identity gating (building+floor) | A | NC:1379–1388; wrong-floor/building tests pass | — |
| 4 | Arrival anchor resolution (POI tier → route final point) | A | NC:1339–1365 | — |
| 5 | Outdoor arrival quality/freshness gate | C | Proximity-only outdoors; stale/bad fix can confirm (NC:1391–1407) | Ph13 |
| 6 | Floor transition event lifecycle EXPECTED/DETECTED/CONFIRMED/ABORTED | A | NC:804–996; `floor_transition_test.dart` | — |
| 7 | Position hold during floor transition | A | NC:455–461,901,939; `navigation_display.dart:39–46` | — |
| 8 | Post-floor-switch reroute suppression (10 s) | A | NC:463–471; cfg L170 | — |
| 9 | Floor-transition timeout/abort recovery (30 s) | A | NC:968–996 | — |
| 10 | Connector-proximity auto floor pre-select | D | Works, but calls browsing `selectFloor` → destroys rendered route (NC:909,945,1196→SP:499) | Ph2/3/9 |
| 11 | Unbounded `points[idx+1]` in transition detection | D | NC:819 | Ph9 |
| 12 | Reroute cooldown 15 s | B | Exists but raw `DateTime.now()` (NC:628,705); burned even on rejected transition (705 precedes 706) | Ph6 |
| 13 | Reroute retries + backoff (3× exponential) | B | NC:760–779; uncancellable `Future.delayed` | Ph14 |
| 14 | Deviation hysteresis (consecutive evidence) | C | Single tick fires reroute (NC:644–648) | Ph6 |
| 15 | Tick order: deviation before GPS-quality pause | D | NC:476 vs NC:483 — garbage fix can reroute before pause sees it | Ph6 |
| 16 | Reroute destination/session revalidation after awaits | C | Only `_state.isSessionLive` gates commit (NC:766–771); captured `_destinationPuid!` reused post-await (NC:764) | Ph1/6 |
| 17 | Outdoor rerouting floor context `_currentNavigatingFloor ?? '0'` | D | NC:756 sends stale indoor floor outdoors | Ph6 |
| 18 | Building-entry corroboration (20 s dwell, identity-aware Wi-Fi) | A | NC:538–564; foreign building never confirms (tested) | — |
| 19 | Entry re-trigger cooldown (15 s) | A | NC:1167–1173 | — |
| 20 | Building-exit corroboration (acc ≤15 m + outside ×3) | A | NC:557–571; silence stays indoors | — |
| 21 | Indoor Wi-Fi outlier rejection (30 m same-scope hold) | A | LP:330–343,285–294; tested | — |
| 22 | GPS staleness detection | C | `UserLocation.timestamp` exists (user_location.dart:11; gps svc L137) but never compared; `_buildGpsFix` consumes cached fix regardless of age (LP:482–494); unstamped `getLastKnownPosition()` fallback (gps svc L75–83) | Ph5 |
| 23 | GPS jump/outlier rejection (outdoor path) | C | `_isOutlierJump` false unless wifi source (LP:332) | Ph5 |
| 24 | GPS accuracy classification beyond 100 m pause | C | Confidence labels exist (LP:464–468) but nothing filters; single hardcoded pause NC:1421–1424 | Ph5/6 |
| 25 | Presentation-level GPS smoothing | C | Raw pass-through (LP:688); optional light EMA only for display | Ph5 |
| 26 | Geolocator displacement gate | D | Documented 0.3 m default truncated to int 0 → disabled (gps svc L89–99) | Ph5 |
| 27 | Dual route ownership | D | SP:124 + NC:59; one-way adoption sync (NC:487–499) | Ph2 |
| 28 | Reroute write-back to rendered route | C | Reroutes write controller field only (NC:742,769); next scope notify can revert controller to stale route | Ph2 |
| 29 | Navigation session identity | C | Zero sessionId/routeRevision tokens in navigation layer | Ph1 |
| 30 | Selection/navigation separation | D | All six browsing APIs null the route (SP:441/468/499/520/530/540); controller triggers these mid-navigation itself | Ph3 |
| 31 | Destination-change protocol mid-session | D | No retarget API; silent polyline swap w/o destination update → arrival & reroutes target OLD destination (adoption NC:490–497 vs destination write NC:336–337; anchor NC:1340–1342; reroute target NC:756–765) | Ph4 |
| 32 | Automatic floor selection preserving route | D | Same mechanism as #10; route nulled at every floor change (SP:499) | Ph2/3 |
| 33 | Radiomap acquisition lifecycle | A | Request-id + selection recheck, disk cache, native load, targeted eviction, unsupported-vs-error (SP:1612–1716) | — |
| 34 | Radiomap eviction scope on exit | B | `_resetRadioMapState` → `clearRadioMap()` wipes ALL resident maps incl. useful ones (SP:1898–1905) | Ph11 |
| 35 | Cross-building composition core | A | CBR:49–172,306–431,445–561,935–1030 | — |
| 36 | Six-segment cap behavior | D | Silent `removeRange(6,...)` no partial/warning (CBR:160–162); dead code today (max 3 top-level segments) but latent trap | Ph7 |
| 37 | Outdoor point metadata truthfulness | D | Hybrid outdoor points stamped destination `buid`+`floorNumber` (SP:909–914); router outdoor segments stamped `buildingId: targetBuid` (CBR:461…557); `fromJson` never sets `isOutdoor` (NRM:64–93) → floor-filtered outdoor deviation silently disabled (NC:653–666 returns infinity when filter empty) and phantom floorTransitionIndices (''↔'0') (NRM:240–248) | Ph7 |
| 38 | Partial-route semantics | B | Straight-line fallbacks mark incomplete ✓ (CBR:295/559/900) but centroid `RouteSegment.fallback` sets only isFallbackLocation, not isIncomplete (RS:200–219; CBR:257,807) | Ph7 |
| 39 | Rendering source consistency | D | Map renders scope route exclusively (M:851,686); instruction strip reads controller segments → divergence after scope resets | Ph2 |
| 40 | Per-floor route visibility | C | ALL segments of ALL floors render simultaneously whenever a route object exists (M:855–872) | Ph12 |
| 41 | Custom KMZ overlay gating | D | Always drawn despite comment claiming "when no active navigation" (M:825–849) | Ph12 |
| 42 | Fit-bounds zoom | D | Clamped `(19.0…19.0)` — pinned to 19 regardless of span (M:720–723) | Ph12 |
| 43 | Follow mode pan/recenter | B | Core works (M:1065–1072,1229–1236); spurious exits from inertia after programmatic animation (`_isProgrammaticMove` cleared at animation end M:543) | Ph12 |
| 44 | Heading pipeline | B | Presentation-only ✓ (M:409–469); compass branch dead because `currentLocation` never carries heading (LP:156–165; user_location heading default 0.0); marker holds position during transitions while heading still updates (M:351–363) | Ph12 |
| 45 | Camera coalescing/thresholds | A | M:499–558 | — |
| 46 | Sensing independence from navigation End | A | `stopTracking()` zero production callers by design; LocationProvider app-scoped | keep |
| 47 | Tab-leave policy (kills navigation) | A (decision) | MS:35–47 explicit; keep as documented policy | Ph15 doc |
| 48 | Canonical teardown API | C/D | `endNavigation` thorough for controller (NC:381–405) but scope clear left to callers; inconsistent sites — `map_bottom_sheet.dart:201` calls endNavigation() only → ghost preview route | Ph15 |
| 49 | SpaceProvider async guards | A | Request-id counters for route/radiomap/floorplan/POI loads (SP:682,1622,1731,1838) | — |
| 50 | NavigationController async guards | C | State predicates only; no tokens | Ph1/14 |
| 51 | Indoor route availability after entry corroboration | C | Comment promises deferred refresh (NC:1203); nothing ever fetches it — indoor guidance continues on outdoor-built polyline | Ph8 |
| 52 | Structured navigation logging | C | Scattered debugPrint only | Ph15 |
| 53 | Clock discipline | B | `debugNowOverride` used everywhere except rerouting paths (NC:146,628,705) | Ph6 |
| 54 | Recovery: radiomap/floorplan/POI classified failures + retry | A | SP loaders + `_withRetry(maxRetries:1)` | — |
| 55 | Recovery: backend/OSRM/KMZ failures in initial cascade | A/B | Cascade falls through tiers ✓; per-strategy catches ✓; OSRM helpers swallow errors ✓; message hardening only | Ph7 minor |
| 56 | Background/resume camera recenter | A | M:312–333 | — |

Race-condition status (full closure matrix in Phase 14):

| Race | Status today |
|---|---|
| R1 route A finishes after route B | Guarded in SP cascade by request-id; unguarded in controller reroutes |
| R2 reroute finishes after End | Caught by `isSessionLive` predicate |
| R3 destination changes during routing | **Unguarded** — BUG-3 |
| R4/R5 floor/building changes during routing | Unguarded in controller commits |
| R6 reroute finishes after destination change | **Unguarded** |
| R7 positioning source flips during routing | Belief handled by arbiter; route fetch unaffected (acceptable) |
| R8 End while initial route request running | Guarded by SP request-id + preview state guard |
| R9 external route replacement during active navigation | **Divergent copies** — RC1 |
| R10 radiomap completes after leaving floor/building | Guarded (SP:1644–1651) |
| R11 old async callback after new session starts | Partially guarded (`isSessionLive`) |
| R12 tab/lifecycle changes during async work | Navigation killed on tab leave (policy); dispose-safe streams tested |

---

## 4. Already Implemented — Do Not Redo

These subsystems are verified working and covered by tests. Later phases may **integrate** with them but must not alter their internal contracts without explicit justification in that phase.

1. **State machine core** — enum, audited static edge table, dynamic overlay restore edges (`paused`/`rerouting` → `_previousActiveState`), `isActivity`/`isSessionLive`, illegal-transition rejection logging (NSM:129–177; NC:154–185).
2. **Arrival evidence model** — anchor resolution tiers, 2-consecutive-tick confirmation, indoor building+floor identity gating, counter resets on identity failure/exit radius, manual hook, inertness after arrival (NC:1339–1415; `arrival_test.dart`).
3. **Floor transition lifecycle** — connector-proximity detection, organic drift detection, evidence-gated confirmation (3 consecutive consistent identity ticks), position hold, post-switch suppression, 30 s timeout with ABORTED recovery, bounded event history limit 8 (NC:804–996; `floor_transition_test.dart`).
4. **GPS↔Wi-Fi arbitration** — qualification gate (matchedAps ≥ 2, ratio ≥ 0.25, valid non-empty ids), entry hysteresis 3 consecutive, exit hysteresis 3 bad cycles OR 10 s stale timer, scope confirmation 3-run atomic switch, outlier-jump hold 30 m same-scope with fix-hold semantics, confidence scoring 0.45 ratio / 0.25 spread / 0.30 stability, Wi-Fi accuracy clamp [2,30] m (LP:245–591; `location_provider_arbitration_test.dart`; native Kotlin engine).
5. **Building-entry dwell** — 20 s corroboration window, identity-aware Wi-Fi acceptance (foreign building never confirms), timeout revert to ACTIVE_OUTDOOR, 15 s re-trigger cooldown (NC:538–564, 1150–1210).
6. **Building-exit dwell** — GPS accuracy ≤ 15 m + outside-building + `exitConfirmationCount = 3`, silence defaults to staying indoors (NC:557–571).
7. **Preload cascade** — tiered floor resolution (segment-derived > point-projected > legacy '0' > lowest numeric), distance cancel/re-arm, one-shot latch (NC:1084–1110).
8. **Radiomap acquisition** — request-id + selection-recheck stale protection, disk cache, native-engine load, targeted eviction on failure, unsupported-vs-error classification (SP:1612–1716).
9. **Campus KMZ routing stack** — graph build/junctions, snap/off-route progress, hybrid edge-snap, OSRM splice; integration-tested against real asset `assets/navigation/university roads.kmz` (`custom_routes_test.dart`, `custom_routes_integration_test.dart`).
10. **SpaceProvider async guards** — per-resource generation counters discard stale responses for route/floorplan/radiomap/POI loads.
11. **Camera mechanics** — follow coalescing (0.3 m / 1.5° thresholds), lower-third offset 0.67, indoor zoom 19 / outdoor zoom 17, resume recenter, floorplan-center camera gate (M:499–682).
12. **Sensing lifecycle separation** — LocationProvider streams run app-wide; navigation ending does not kill tracking; heading stream independent.
13. **Navigation UI projections** — status bar labels incl. transition blackout text, instruction strip i/n advancement, arrival banner Done flow (`navigation_display.dart`, widget tests).
14. **Initial activity choice from positioning belief**, never from destination (NC:362–378).

---

## 5. Verified Bugs

Ordered by user impact; IDs referenced by phases.

| ID | Bug | Impact | Evidence |
|---|---|---|---|
| BUG-1 | Route invisible during navigation: any floor change / building browse / POI tap / building exit nulls the scope route the map renders while the controller keeps evaluating its private copy. Happens on **every guided floor transition** because the controller itself calls `selectFloor`. | Critical | SP:441/468/499/520/530/540 → SP:1920–1925; controller triggers NC:909/945/1066/1107/1196 |
| BUG-2 | Rerouted route never reaches the map; next unrelated scope notification makes the controller **revert** to the stale scope route (ping-pong) | Critical | Write gap NC:742/769; revert path NC:490–491 |
| BUG-3 | New destination mid-session silently swaps polyline but keeps old `_destinationPuid`/anchor → arrival fires at old room; reroutes recalculate to old destination | Critical | Adoption NC:490–497 vs destination write NC:336–337; anchor NC:1340–1342; reroute target NC:756–765 |
| BUG-4 | Outdoor waypoints lie about identity: hybrid outdoor points stamped destination `buid`+`floorNumber` (SP:909–914); router outdoor segments stamped `buildingId: targetBuid` (CBR:461…557); server-route points get `isOutdoor=false` forever (NRM fromJson). Floor-filtered outdoor deviation silently disabled (empty filter → infinity, NC:653–666); phantom floorTransitionIndices ('' ↔ '0') | High | NRM:64–93,195–222,240–248 |
| BUG-5 | One noisy GPS tick triggers reroute (no consecutive evidence); deviation evaluated **before** GPS-quality pause in same tick | High | NC:644–648 vs order NC:476→483 |
| BUG-6 | Outdoor GPS has zero quality pipeline: no staleness, no jump rejection, no accuracy rejection; unstamped `getLastKnownPosition()` fallback; displacement gate disabled by int truncation | High | LP:332,482–494,688; gps svc L75–99 |
| BUG-7 | Promised indoor route refresh after entry corroboration does not exist — indoor guidance continues on outdoor-built polyline | High | Comment NC:1203; no fetch code anywhere |
| BUG-8 | Ghost preview route: closing POI preview calls `endNavigation()` without clearing scope route | Medium | map_bottom_sheet.dart:201 |
| BUG-9 | Map renders all floors' segments simultaneously (future-floor geometry overlays current floor); custom KMZ layer always drawn during active navigation | Medium | M:825–872 |
| BUG-10 | Fit-bounds zoom pinned to 19 → long outdoor routes framed absurdly close | Medium | M:720–723 |
| BUG-11 | Spurious follow-mode exits from scroll inertia after programmatic animations | Medium | M:543,1065–1072 |
| BUG-12 | Outdoor reroute sends stale indoor floor (`_currentNavigatingFloor ?? '0'`) to backend | Medium | NC:756 |
| BUG-13 | Rerouting clock leaks raw `DateTime.now()`; cooldown burned before transition validation | Low/Med | NC:146,628,705–706 |
| BUG-14 | Centroid-fallback segments don't mark route partial; six-segment cap would truncate silently if ever hit | Low (latent) | RS:200–219; CBR:160–162,257,807 |
| BUG-15 | Unbounded `idx+1` read in transition detection; segment exhaustion logs only (no state change/notification); unused `destinationFloorNumber` param in `startRoutePreview` | Low | NC:819,1276–1280,324 |
| BUG-16 | Heading compass branch dead (`currentLocation` never carries heading); marker holds position during transitions while heading still updates (mismatch) | Low/cosmetic | LP:156–165; user_location.dart:18; M:351–363,401–420 |

---

## 6. Architectural Root Causes

**RC1 — Two route stores with one-way sync.**
`SpaceProvider._activeNavigationRoute` (rendered) and `NavigationController._activeRoute` (evaluated) diverge by design: sync flows scope→controller only via object-identity adoption with no revision token; reroutes flow controller→nothing. *Resolution:* collapse to ONE store (scope) + controller write-through (Phase 2).

**RC2 — No session identity.**
Only state predicates guard async commits; they catch End-Navigation races but cannot detect destination changes or superseded reroutes. *Resolution:* `NavigationSession {sessionId, routeRevision}` threaded through every commit (Phases 1, 14).

**RC3 — Browsing and navigation share mutable fields.**
Selection APIs mutate navigation fields directly, including when the controller itself calls them mid-navigation. *Resolution:* browsing APIs refuse to touch navigation fields while a session is live; navigation-driven selection uses navigation-safe variants (Phase 3).

**RC4 — Route metadata lies about the world.**
Points don't truthfully encode outdoor/indoor/building/floor; everything downstream inherits the lies. *Resolution:* metadata truthfulness enforced at construction time (Phase 7).

**RC5 — Asymmetric quality pipelines.**
Indoor estimates pass qualification/outlier/staleness/confidence gates; outdoor fixes are believed unconditionally. *Resolution:* mirror the indoor gate pattern for GPS ingestion (Phase 5); feed decisions (Phases 6, 13).

---

## 7. Target Architecture

### 7.1 Ownership contract

```
┌──────────────────────────────┐        ┌──────────────────────────────────┐
│ SpaceProvider (browsing)     │        │ NavigationController (session)   │
│──────────────────────────────│        │──────────────────────────────────│
│ buildings/floors/POIs        │        │ NavigationSession                │
│ floorplans                   │        │   sessionId · destination*       │
│ radiomap loading             │        │   routeRevision                  │
│                              │◄─write-through─ startRoutePreview/Active │
│ ROUTE STORE (single):        │        │ evaluate: deviation/progress     │
│  activeNavigationRoute       │        │ reroute → validate → atomic      │
│                              │        │ transitions · arrival            │
│ browsing selections          │        │ retargetDestination()            │
│  NEVER touch route fields    │        │ terminateNavigation()            │
│  while a session is live     │        │                                  │
└────────────┬─────────────────┘        └───────────────┬──────────────────┘
             ▼                                          ▼
   MapScreen renders store                    LocationProvider.currentFix
   (= evaluated route by construction)        canonical fix · GPS quality gates
                                              · Wi-Fi arbiter (untouched)
```

Rules:

- **One store.** The route object lives ONLY in SpaceProvider. `NavigationController.activeRoute` becomes a delegating getter; the second field is deleted. Evaluation reads the store; commits write the store.
- **One writer during session.** Between preview-seed and termination only the controller writes the route field, via `NavigationRouteScope.adoptNavigatedRoute(route)` + revision increment. Browsing APIs are forbidden from writing it.
- **One identity.** Every async commit validates `(sessionId, routeRevision, destinationPuid)` before mutating. Stale results are dropped silently (log + return), never committed, never notify.
- **Position truth.** `LocationProvider.currentFix` remains the sole position input. Phase 5 wraps GPS ingestion in quality gates; arbitration internals unchanged.
- **Rendering truth.** MapScreen keeps reading `spaceProvider.activeNavigationRoute`; after Phase 2 that IS the evaluated route.

### 7.2 Session model

```dart
class NavigationSession {
  final String sessionId;          // monotonic counter is sufficient
  String? destinationPuid;
  SpaceModel? destinationSpace;
  String? destinationFloorNumber;
  int routeRevision;               // bump on preview seed and every committed reroute
}
```

Created at `startRoutePreview`; replaced wholesale by `retargetDestination(...)` (new sessionId); destroyed by `terminateNavigation()`. The controller's loose `_destinationPuid/_destinationSpace` fields become delegates to the session and are then removed.

### 7.3 Component responsibilities

| Concern | Owner | Notes |
|---|---|---|
| Route storage | SpaceProvider | single field, name unchanged |
| Route mutation (session) | NavigationController | `adoptNavigatedRoute` write-through |
| Route mutation (idle/preview) | SpaceProvider cascade | existing request-id guards |
| Destination identity | Controller's NavigationSession | UI reads mirrored getters |
| Position + quality | LocationProvider | GPS gates added Phase 5 |
| Mode belief (GPS/Wi-Fi) | LocationProvider arbiter | untouched |
| Transitions/dwells/handoffs | NavigationController | verified logic reused |
| Rendering/camera/heading | MapScreen | presentation only |
| Sensing lifecycle | app-scoped LocationProvider | navigation never stops tracking |

---

## 8. Navigation Invariants

Global gates asserted permanently by tests. Each phase lists which ones it establishes.

- **INV-1 Single store.** Exactly one route field exists anywhere; any second cache of route data is a defect.
- **INV-2 Visible == Evaluated.** The rendered polyline equals the route used for deviation/progress/arrival at every tick, except inside an atomic replacement transaction.
- **INV-3 Session fencing.** An async result commits only if its captured `(sessionId, routeRevision, destinationPuid)` all equal current values.
- **INV-4 Browsing neutrality.** The six browsing APIs never mutate navigation route/session/destination fields while `isSessionLive`.
- **INV-5 Navigation-driven selection safety.** Controller-initiated floor/building selection preserves route, destination, and revision.
- **INV-6 Atomic replacement.** A reroute fully commits (store + revision bump + single notify) or leaves the old route untouched; intermediate states are unobservable.
- **INV-7 Metadata truth.** `isOutdoor ⇒ buildingId==null && floorNumber==null`; indoor points carry real building+floor; server-derived points derive `isOutdoor` from segment origin/poisType, never default false.
- **INV-8 Quality-gated decisions.** Reroute, arrival, and mode handoffs consume only fixes passing the source-quality gate; a single bad tick alone can never fire them (hysteresis N≥2 where specified).
- **INV-9 Exit preservation.** Building exit releases indoor context (browsing floor/floorplan/radiomap) but never route, destination, or session.
- **INV-10 Termination totality.** One API tears down any session from any state; afterwards: no ghost route, no pending-result side effects, idle UI, sensing continues.
- **INV-11 Responsive positioning.** No throttling below device-provided rate (~2 Hz); smoothing applies to presentation only; raw fixes preserved.

---

## 9. Canonical Implementation Phases

Single numbering system. Dependencies are hard gates.

| Phase | Name | Establishes | Depends on |
|---|---|---|---|
| 0 | Baseline freeze & characterization | safety net | — |
| 1 | Session identity & lifecycle contract | INV-3 core | 0 |
| 2 | Single route ownership & write-through | INV-1, INV-2, INV-6 | 1 |
| 3 | Browsing/navigation separation | INV-4, INV-5 | 2 |
| 4 | Route lifecycle & destination-change protocol | BUG-3 closure, ghost cleanup | 2 |
| 5 | Outdoor GPS quality pipeline | INV-8 inputs, INV-11 | 0 |
| 6 | Outdoor rerouting correctness | INV-6/8 decisions; BUG-5,12,13 | 1,2,5 |
| 7 | Route composition & metadata truth | INV-7; BUG-4,14 | 2 |
| 8 | Outdoor→Indoor handoff completion | BUG-7 closure | 2,3 |
| 9 | Floor-transition hardening & continuity | BUG-15; route visible across floors | 2,3 |
| 10 | Indoor→Outdoor handoff completion | INV-9 full | 3,11 |
| 11 | Radiomap lifecycle contract | scoped eviction | 3 |
| 12 | Rendering & camera consistency | BUG-9,10,11,16; floor-scoped render | 7 |
| 13 | Arrival correctness | INV-8 for arrival | 5,7 |
| 14 | Async/race hardening R1–R12 | INV-3 exhaustive | 1–13 |
| 15 | Termination canonicalization & instrumentation | INV-10; structured logs | all |
| 16 | Integration, regression & device validation | DoD | all |

**Gate rule: do not start Phase N+1 until Phase N acceptance criteria pass AND `flutter analyze` reports 0 errors AND the full test suite is green.**

---

## 10. Phase-by-Phase Implementation Plan

---

### PHASE 0 — Baseline Freeze & Characterization

**Objective.** Make the current tree reproducible; record what passes today.

**Why.** The tree is 1760+ lines ahead of HEAD. Without a freeze, rollback (§14) is impossible and line references rot.

**Current state.** Dirty worktree (§2.1); 16 test files; analyze 0 errors.

**Changes required.** Git hygiene + characterization tests only. No behavior change.

**Files affected.** `test/` only (+ baseline doc).

**Tasks.**
1. Commit working tree verbatim: `chore(nav): working-tree snapshot pre master-plan` (or tag a stash if committing is disallowed).
2. Run `flutter analyze` and `flutter test`; write results to `docs/NAVIGATION_MASTER_PLAN_BASELINE.md` per-file.
3. Add characterization tests locking known-broken behaviors that later phases flip (annotate each `// CHARACTERIZATION: flips in Phase N`):
   - scope route nulled by each of the six browsing APIs while controller state live (BUG-1);
   - reroute does not reach scope route object (BUG-2);
   - hybrid outdoor points carry destination floor metadata at model level (BUG-4).
4. Confirm KMZ real-asset integration test passes on this machine.

**Tests added.** 3–5 characterization tests.

**Acceptance criteria.**
- [ ] Snapshot commit exists; clean `git status`.
- [ ] Analyze 0 errors; full suite green or pre-existing reds documented.
- [ ] Characterization failures match §5 exactly.

**Rollback.** None needed.
**Dependencies.** —

---

### PHASE 1 — Navigation Session Identity & Lifecycle Contract

**Objective.** Every navigation run gets an explicit identity; every async result proves membership before committing.

**Why.** RC2. State predicates alone cannot detect destination swaps, superseded reroutes, or retarget races (R3, R6, R11).

**Current state.** Zero session tokens in the navigation layer; SpaceProvider's per-resource request ids are the in-repo precedent to imitate.

**Changes required.**

1. Add `NavigationSession` value class to NSM (fields §7.2).
2. Controller creates the session in `startRoutePreview`; destination fields become session delegates; delete the unused `destinationFloorNumber` parameter (BUG-15c) and populate it from the POI instead.
3. Add `routeRevision`; increment on preview seed and every committed replacement.
4. Add guard helper used by all await sites:
   ```dart
   bool _isCurrent({required String sessionId, required int revision}) =>
       _session != null &&
       identical(_session!.sessionId, sessionId) &&
       _session!.routeRevision == revision;
   ```
5. Apply capture-and-validate to: `_triggerReroute` both branches, building-preload completion, entrance-preload floor load, backoff continuations.
6. Expose `String? get sessionId`.

**Architectural rule.** INV-3 core: *no async continuation may mutate navigation state unless its captured identity equals current identity.*

**Files affected.** NSM, NC; (interface groundwork for Phase 2).

**Tasks.**
1. Implement class + wiring.
2. Replace `_destinationPuid!` reuse after awaits (NC:756–765) with validated session reads.
3. Convert reroute timestamps to injectable clock (`_now()`); move `_lastRerouteTime = _now()` AFTER successful `_transition(rerouting)` so rejected transitions stop burning cooldown (BUG-13).
4. Emit `SESSION_START/SESSION_END` tagged logs (full convention lands Phase 15).

**Tests.**
- Unit: session created/destroyed on preview/end; stable id across states; new id after End→Start; late old-session reroute result mutates nothing; revision bump mid-flight discards result; rejected transition does not consume cooldown.
- Update journey-script test in `navigation_state_machine_test.dart` for session assertions.

**Acceptance criteria.**
- [ ] Grep audit: no bare `await … ; <state mutation>` pattern without identity check remains in NC.
- [ ] R1/R2-style races provably inert beyond previous `isSessionLive` behavior.
- [ ] Full suite green.

**Rollback.** Single revert; additive class.
**Dependencies.** Phase 0.

---

### PHASE 2 — Single Route Ownership & Write-Through

**Objective.** One route store; rendered == evaluated by construction; reroutes become visible atomically.

**Why.** RC1 / BUG-1 / BUG-2. Highest-leverage fix in the plan: kills "invisible navigation" during guided floor transitions and stale-polyline-after-reroute with its revert ping-pong.

**Current state.** Scope field SP:124 (rendered by M:851/686); private copy NC:59 (evaluated); adoption listener NC:487–499 one-way, object-identity compared; reroutes bypass scope entirely.

**Changes required.**

1. Delete `NavigationController._activeRoute`; replace with delegating getter:
   ```dart
   NavigationRouteModel? get activeRoute => _spaceScope.activeNavigationRoute;
   ```
   Mechanical rewrite of internal reads (~20 sites: deviation, segments, transitions, arrival, getters).
2. Extend `NavigationRouteScope` interface:
   ```dart
   void adoptNavigatedRoute(NavigationRouteModel route);
   ```
   SpaceProvider implementation: sets `_activeNavigationRoute`, `_navigationRouteStatus = ready`, clears error, single `notifyListeners()`. Does NOT touch `_navigationDestinationPuid` (session-owned since Phase 1) and does NOT touch radiomap/floorplan/poi state.
3. Gut `_onSpaceProviderChanged`: remove blind adoption (and its anchor re-resolution). With one store there is nothing to sync. Arrival-anchor re-resolution moves into commit paths explicitly.
4. Reroute commits (KMZ branch NC:742, API branch NC:769): validate identity → `_spaceScope.adoptNavigatedRoute(newRoute)` → `_session.routeRevision++`. Sequence is atomic from observers' perspective (single notify).
5. `startRoutePreview` keeps pulling the cascade-produced route from scope; records `routeRevision = 0` in session.
6. `endNavigation` additionally calls `_spaceScope.clearNavigationRoute()` itself (idempotent; caller-side clears remain harmless until Phase 15 removes them).

**Architectural rule.** INV-1, INV-2, INV-6: *exactly one store; during a live session only the controller writes it, always through adoptNavigatedRoute with a revision increment.*

**Files affected.** NC, NSM (interface), SP (implementation), all test fakes implementing the scope.

**Tasks.**
1. Interface + implementation + delegation.
2. Remove adoption listener body; drop listener registration if unused.
3. Rewire both reroute commits + preview seed.
4. Grep audit: zero second-cache writes remain; `navController.activeRoute` consumers unaffected via getter.
5. Delete dead adoption comment block.

**Tests.**
- Update fakes to record `adoptNavigatedRoute` calls.
- New *reroute write-through*: stub repo → trigger deviation reroute → scope received new object; getter returns it; revision incremented exactly once; map-facing read sees it.
- New *no ping-pong*: fire unrelated scope notify after reroute → controller evaluation route unchanged.
- New *preview seed* records revision 0.
- Flip Phase-0 characterization tests (BUG-1/BUG-2 locks) to assert corrected behavior.
- `arrival_test.dart` and instruction-strip flows pass unchanged through getters.

**Acceptance criteria.**
- [ ] Exactly one route field exists in the codebase (grep `_activeRoute` → scope only).
- [ ] After a committed reroute, MapScreen-visible route == evaluation route (widget-level assertion via provider read).
- [ ] Guided floor transition no longer blanks the polyline (selectFloor reset removed in Phase 3 — interim: verify no NEW regressions; full fix lands next phase).
- [ ] Suite green.

**Rollback.** Revert commit; interface addition is backward-compatible (fakes updated in same commit).
**Dependencies.** Phase 1.

---

### PHASE 3 — Browsing/Navigation Separation

**Objective.** Browsing another building/floor/POI can never destroy an active session; navigation-driven selection cannot corrupt browsing state expectations.

**Why.** RC3 / BUG-1 root cause / INV-9 precondition. Today even the controller destroys its own route mid-guidance.

**Current state.** SP:441/468/499/520/530/540 call `_resetNavigationRouteState()` (SP:1920–1925: nulls status/route/error/destinationPuid). Controller calls these APIs at NC:909, 945 (floor transitions), 1066 (exit clearSelection), 1107 (approach selectSpace), 1196 (entrance preload).

**Changes required.**

1. Guard clause contract in SpaceProvider — extract one helper:
   ```dart
   bool get _navigationOwnsRouteFields =>
       _navigationControllerSessionLive; // injected via constructor or settable flag
   ```
   Practical mechanism: SpaceProvider gains `bool Function()? isNavigationSessionLive;` wired in composition root to `navController.isSessionLive`. Each of the six APIs becomes:
   ```dart
   if (!(isNavigationSessionLive?.call() ?? false)) {
     _resetNavigationRouteState();          // legacy idle behavior preserved
   }
   // ... proceed with selection change (floors/POIs/etc.) regardless
   ```
   Selection semantics themselves unchanged; ONLY the navigation-field side effects are suppressed during sessions.
2. Add explicit navigation-safe variants used by controller code (clear intent + immune to future drift):
   ```dart
   void selectFloorForNavigation(FloorModel f);  // sets _selectedFloor, triggers loaders; never resets nav fields
   void selectSpaceForNavigation(SpaceModel s);  // same for building preload
   ```
   Controller switches to these at NC:909/945/1107/1196.
3. Building-exit path (NC:1066 `clearSelection`) replaced by new scoped method `releaseIndoorContextForNavigation()` that clears radiomap/floorplan/POI browsing state WITHOUT touching route/session (full policy in Phases 10–11; land the route-safety now).
4. `navigateToPoi` (SP:547) keeps legacy behavior when idle; when a session is live it MUST route through the Phase-4 retarget protocol instead of silently destroying (temporary bridge: it may end+restart cleanly via public API; permanent protocol in Phase 4).

**Architectural rule.** INV-4, INV-5: *browsing selections mutate browsing state only; navigation fields are writable solely by the owning session.*

**Files affected.** SP, NC, composition root (main.dart/providers wiring), tests' fakes.

**Tasks.**
1. Inject liveness callback; add guards to the six APIs.
2. Add two For-Navigation variants + `releaseIndoorContextForNavigation()`; switch controller call sites.
3. Bridge `navigateToPoi` behavior for live sessions.
4. Characterization tests from Phase 0 (route-nulling) now assert the OPPOSITE during live sessions and unchanged behavior when idle.

**Tests.**
- New *browsing neutrality*: with activeOutdoor session, tap other building / other floor / other POI / clearSelection / clearFloorSelection / clearSelectedPoi → route object, destination, session id, revision ALL unchanged; floors/POIs still load.
- New *idle parity*: with no session, all six behave exactly as before (existing quick-access/search flows keep passing).
- New *navigation-driven selection*: connector-triggered selectFloorForNavigation preserves route/revision (extends existing `floor_transition_test.dart`).
- Existing `quick_access_test.dart` cross-building navigation must stay green (it runs idle).

**Acceptance criteria.**
- [ ] INV-4/INV-5 tests green.
- [ ] Guided multi-floor journey keeps polyline visible across the whole trip (manual smoke on emulator acceptable here).
- [ ] Suite green.

**Rollback.** Revert; guards are additive conditionals around existing calls.
**Dependencies.** Phase 2.

---

### PHASE 4 — Route Lifecycle & Destination-Change Protocol

**Objective.** Explicit lifecycle for destination changes; no silent retargets; no ghost previews.

**Why.** BUG-3 (arrival/reroute target old destination), BUG-8 (ghost preview route). Completes RC2.

**Current state.** No retarget method; `startRoutePreview` refuses when live (NC:326–329); scope-route adoption previously masked inconsistency (removed in Phase 2); `map_bottom_sheet.dart:201` leaks preview route.

**Changes required.**

1. Define the canonical route lifecycle (documentation + code comments at each stage):
   ```
   REQUESTED → GENERATED(cascade) → COMMITTED(preview seed) → PREVIEW
   → ACTIVE(startActiveNavigation) ⇄ REROUTING(overlay)
   → SEGMENT_ADVANCED* → ARRIVED → TERMINATED
   Invalidations: End anywhere; retarget replaces session wholesale;
   failed validation discards candidate, old route persists.
   ```
2. Implement `retargetDestination(PoiModel newTarget)` on the controller:
   - Requires `isSessionLive`; captures old sessionId; creates NEW session (new id, revision 0) with new destination;
   - Fires SpaceProvider route request for the new target **reusing the existing cascade request-id machinery** (call `requestRouteToSelectedPoi` after selecting target context via For-Navigation variants);
   - On completion validates `(newSessionId, requestOk)` before seeding preview-equivalent state and transitioning back to the user's prior activity state (or routePreview if they hadn't started);
   - Any in-flight work from the OLD session fails identity checks and is dropped (Phase 1 mechanics make this free);
   - UI affordance: bottom-sheet "Navigate here" during active navigation triggers this instead of being refused.
3. Fix ghost preview (BUG-8): `map_bottom_sheet.dart:201` closes preview via the paired cleanup (`endNavigation` + `clearNavigationRoute`) — interim until Phase 15 collapses them into `terminateNavigation()`.
4. `selectPoi`/`clearSelectedPoi` guards (Phase 3) mean selecting a POI no longer mutates anything navigation-related; document that "Navigate here" is the ONLY retarget entry point.

**Architectural rule.** *Destination changes are transactions: new session identity first, then content; old-session artifacts can never interleave.* Extends INV-3 to destination dimension fully.

**Files affected.** NC, SP (bridge), `map_bottom_sheet.dart`, `poi_detail_card.dart` (affordance wiring), tests.

**Tasks.**
1. Lifecycle documentation block in NSM header.
2. `retargetDestination` implementation + state handling.
3. Ghost-preview pairing fix.
4. Wire UI entry point(s).

**Tests.**
- New *retarget mid-outdoor*: A active → retarget to B → new sessionId; polyline becomes B's; reroute triggered en route targets B (assert repository called with B puid); arrival anchor resolves B; old-A async result discarded (stub delay).
- New *retarget during rerouting*: pending A-reroute completes after retarget → discarded; B flow unaffected.
- New *preview close* leaves no route object.
- Matrix tests H/I from §11 (unit-level versions).

**Acceptance criteria.**
- [ ] Selecting Navigate-here on another POI mid-trip retargets cleanly; no delayed old-destination route ever appears (test-proven).
- [ ] Closing a preview leaves zero route residue.
- [ ] Suite green.

**Rollback.** Revert; feature isolated behind one new method + one call site.
**Dependencies.** Phase 2 (uses write-through; needs Phase 1 identity).

---

### PHASE 5 — Outdoor GPS Quality Pipeline

**Objective.** Mirror the indoor quality-gate pattern for GPS ingestion: staleness, jump rejection, accuracy classification — without throttling or altering the arbiter.

**Why.** RC5 / BUG-6. Every downstream decision (deviation, reroute, arrival, handoffs) currently consumes unfiltered GPS. INV-8's inputs don't exist outdoors.

**Current state.** `UserLocation.timestamp` populated but never compared (LP:482–494); `_isOutlierJump` wifi-only (LP:332); confidence labels never filter (LP:464–468); raw assignment LP:688; `getCurrentPosition` falls back to unstamped `getLastKnownPosition()` (gps svc L75–83); distanceFilter 0.3 m truncated to int 0 (gps svc L89–99); single hardcoded 100 m pause in NC.

**Changes required.**

1. New config block in `NavigationConfig`:
   ```dart
   gpsStaleAfterSeconds          = 10   // reject fixes older than this at consumption
   gpsRejectAccuracyMeters       = 50   // > this = invalid, ignore fix entirely
   gpsPoorAccuracyMeters         = 30   // poor band: usable for display, not decisions
   gpsGoodAccuracyMeters         = 15   // aligns with exitAccuracyThreshold
   gpsMaxImpliedSpeedMps         = 25   // ~90 km/h; above → outlier on campus
   gpsOutlierHoldTicks           = 1    // hold previous position for N ticks on outlier
   ```
2. LocationProvider gains a GPS ingestion filter applied where `_gpsLocation` is consumed to build fixes (`_buildGpsFix` path and stream listener):
   - **Staleness:** if `DateTime.now().difference(fix.timestamp) > gpsStaleAfterSeconds` → do not update canonical fix from GPS; expose status via existing `PositionFixStatus.stale`.
   - **Accuracy bands:** accuracy ≤ good → normal; ≤ poor → accepted but flagged low-confidence (existing confidence mapping extended with the band); > reject → invalid, ignored.
   - **Jump rejection:** if last accepted GPS exists and haversine(last, new)/Δt > gpsMaxImpliedSpeedMps AND new.accuracy is not good → treat as outlier: hold previous fix one tick (same semantics as indoor `_holdWifiFix`), increment a counter; two consecutive outliers accept (real fast movement).
   - Keep RAW value stored separately (`_lastRawGps`) for debugging; INV-11 preserved — filtering is per-fix acceptance, not rate reduction.
3. Fix service-level defects:
   - Stamp `getLastKnownPosition()` results with an explicit "age" check against staleness threshold before use.
   - Distance-filter: pass integer meters ≥ 1 (use 1) and document that sub-meter gating is unsupported by geolocator types.
4. NC pause logic switches from hardcoded 100 to config-driven bands: enter PAUSED when recent fixes are all in poor/invalid band for `stabilityWindowSeconds`; resume when good-band returns (replaces NC:1418–1433 internals, same observable states).

**Architectural rule.** INV-8 inputs, INV-11: *every fix carries machine-readable quality; invalid fixes never become canonical; decisions consume only qualifying fixes.*

**Files affected.** LP, `navigation_config.dart`, `gps_location_service.dart`, NC (pause thresholds only).

**Tasks.**
1. Config constants.
2. Ingestion filter + hold semantics + raw preservation.
3. Service stamping + distance-filter fix.
4. Pause-band rewiring.

**Tests.**
- Extend `location_provider_lifecycle_test.dart`: stale timestamp rejected after N s; old getLastKnown rejected; accuracy bands classify correctly; implied-speed outlier holds then accepts on repeat; raw fix still recorded.
- Update arbitration tests unaffected (indoor path untouched).
- NC pause tests: poor-band sequence pauses; recovery resumes; no route corruption mid-sequence (extends §11 Test N).

**Acceptance criteria.**
- [ ] Stale/outlier/invalid fixtures provably never reach `currentFix`.
- [ ] Update rate unchanged (~500 ms interval stream intact).
- [ ] Indoor pipeline byte-for-byte behavior (suite green).

**Rollback.** Revert; gates are additive around ingestion points.
**Dependencies.** Phase 0 (can run parallel to Phases 1–4 but must land before 6).

---

### PHASE 6 — Outdoor Rerouting Correctness

**Objective.** Reroutes fire on persistent evidence with validated context and commit atomically to the visible store.

**Why.** BUG-5 (single-tick false reroutes; ordering), BUG-12 (stale floor sent outdoors), remainder of BUG-13; completes INV-6/INV-8 for rerouting.

**Current state.** Trigger NC:621–649 (single tick, KMZ branch first); deviation floor-filter can be empty→infinity (BUG-4 interplay); API branch sends `_currentNavigatingFloor ?? '0'` (NC:756); commit validates only session liveness; clock leaks fixed partially in Phase 1.

**Changes required.**

1. **Tick order:** within `_onLocationChanged`, evaluate GPS-quality/pause BEFORE deviation/reroute. Concretely move `_checkGpsLoss` ahead of `_checkDeviationAndReroute` and make deviation skip when current fix is below decision quality (Phase 5 flags).
2. **Hysteresis:** deviation-triggered reroute requires `rerouteDeviationConfirmTicks = 2` consecutive qualifying ticks beyond threshold (config). Reset counter when back within `customRouteOnThreshold`-style margin. KMZ off-route evidence (`!isOnRoute`) keeps its existing semantic but ALSO requires 2 consecutive ticks. Cooldown unchanged (15 s).
3. **Context validation before fetch:**
   - Outdoor sessions send `floorNumber: null` (extend repository signature to nullable) instead of `'0'` (BUG-12). Indoor sends confirmed navigating floor.
   - Capture `(sessionId, revision, destinationPuid)`; revalidate post-await (Phase 1 helper) before ANY mutation.
4. **Atomic commit:** candidate validated (`hasRenderablePath`, destination match) → `adoptNavigatedRoute` + revision bump (Phase 2 write-through). On failure: restore origin state, keep old route, surface `rerouteFailed=true` (transient flag cleared on next success or End; shown in status bar as "Recalculation failed — retrying soon").
5. **Clock:** remaining raw `DateTime.now()` in rerouting converted to `_now()`; snapshot timestamps too.
6. **Magic numbers to config:** snapThreshold 100.0 (NC:728) → `rerouteKmzSnapThreshold`; segment-endpoint advance 10.0 (NC:1260) → `segmentAdvanceThresholdMeters`.

**Architectural rule.** INV-8 decisions: *no single bad tick fires a reroute; every reroute proves identity+destination+quality before committing; failed reroute preserves the valid old route and is visible to the user.*

**Files affected.** NC, `navigation_config.dart`, `navigation_repository.dart` (nullable floor), `navigation_status_bar.dart`/`navigation_display.dart` (failed flag), SP (nothing).

**Tasks.**
1–6 as listed.

**Tests.**
- Unit: single out-of-band tick does NOT reroute; two consecutive do; cooldown respected; rejected-transition no longer burns cooldown; outdoor fetch called with null floor; destination mismatch discards result; failure keeps old route + sets flag; flag clears on success/End.
- Matrix F (outdoor off-route→reroute→continue, unit version), I-race variant.
- Existing `arrival_test.dart`/machine tests stay green.

**Acceptance criteria.**
- [ ] Hysteresis + ordering tests green.
- [ ] Wire-format audit: backend never receives `'0'` during activeOutdoor reroutes.
- [ ] Suite green.

**Rollback.** Revert; behavior flags isolated.
**Dependencies.** Phases 1, 2, 5.

---

### PHASE 7 — Route Composition & Metadata Truth

**Objective.** Route models truthfully describe the journey; composition cannot silently truncate; partiality is explicit.

**Why.** BUG-4 (metadata lies breaking floor-filtered deviation + phantom transitions), BUG-14. Enables correct per-floor rendering (Ph12) and reliable outdoor deviation (Ph6 depends conceptually).

**Current state.** Hybrid outdoor points stamped destination buid+floorNumber (SP:909–914); router stamps buildingId on outdoor segments (CBR:461…557); `fromJson` leaves isOutdoor=false (NRM:64–93); floorTransitionIndices derived from any floor-string change incl. ''↔'0' (NRM:240–248); silent 6-cap (CBR:160–162); fallback segments not partial (RS:200–219).

**Changes required.**

1. **Model truth rules** (NRM):
   - `NavigationRoutePoint.outdoor` factory stops requiring/storing buid/floorNumber → stores null/null (breaking change internal to app; callers updated).
   - `fromJson` derives `isOutdoor` from `poisType == 'outdoor' || puid == '__outdoor__'` (and future server field if added); server POI waypoints remain indoor-flagged with their real ids.
   - `floorTransitionIndices` counts ONLY changes between two non-null floors (null↔value is entrance/exit boundary, represented by segment types already).
   - Add convenience `entranceExitIndices` if rendering needs them (derive from poisType entrance/exit markers).
2. **Router/composer updates** (CBR + SP cascade hybrid builders):
   - All outdoor point constructions drop destination metadata (SP:909–914, CBR outdoor factories).
   - Six-cap replaced by explicit assertion-style guard: if `validSegments.length > kMaxComposedSegments (=8)` → log error, mark route `partial` with warning "journey truncated", and keep FIRST+LAST segments (never silently drop destination end). Today unreachable; trap defused.
   - Centroid-fallback paths set `isIncomplete: true` (CBR:257, 807) so partiality reflects reality; update `RouteSegment.fallback` doc.
3. **Downstream consumers audited & fixed:** deviation floor-filter (NC:653–666) now also uses outdoor geometry explicitly: when navigating outdoors, compute min-deviation over `outdoorPolylinePoints` regardless of floor bookkeeping (kills the empty-filter infinity path permanently); legacy polyline splits in M continue working (they filter by isOutdoor which becomes MORE correct).

**Architectural rule.** INV-7.

**Files affected.** NRM, RS (docs + fallback flag), CBR, SP (hybrid builders), NC (deviation source selection), `route_model_test.dart` expectations.

**Tasks.**
1–3 as listed; run full suite; fix all model-level test expectations that asserted stamped metadata (characterization flips).

**Tests.**
- Model: outdoor factory yields null/null/isOutdoor-true; fromJson derivation matrix; floorTransitionIndices ignores null boundaries; hybrid merge preserves truth.
- Deviation: outdoor navigation computes finite deviation over outdoor geometry even with zero indoor-floor points; indoor unchanged.
- Router: cap-guard unit (fabricated 9 segments → partial + warning + endpoints retained); centroid-fallback marks partial.
- Matrix P/Q/R unit-level seeds here; full versions Phase 16.

**Acceptance criteria.**
- [ ] No production code path constructs an outdoor point carrying non-null building/floor (grep + test).
- [ ] Outdoor deviation never returns infinity due to empty floor filter (test).
- [ ] Suite green.

**Rollback.** Revert; contained to data layer + one deviation source switch.
**Dependencies.** Phase 2 (write-through exists so composer changes propagate visibly).

---

### PHASE 8 — Outdoor→Indoor Handoff Completion

**Objective.** When entry corroboration confirms ACTIVE_INDOOR, guidance geometry becomes genuinely indoor: fetch/refresh the indoor route for the destination.

**Why.** BUG-7. The dwell/corroboration/preload machinery is verified (§4 items 5,7); the missing piece is route content refresh — a comment promises it (NC:1203) and nothing implements it.

**Current state.** Entrance approach preloads building+ground floor (NC:1194–1210); corroboration confirms identity; afterwards NO indoor route request ever occurs. User follows the outdoor-built polyline inside.

**Changes required.**

1. On transition into `activeIndoor` (both entrance-dwell confirmation and organic belief-flip paths), controller invokes new method `_ensureIndoorGuidance()`:
   - Guarded by session identity + once-per-session latch (`_indoorGuidanceEnsured` reset on retarget/End);
   - If current route already contains a usable indoor segment ending at destination for the confirmed floor (check `hasIndoorSegment` + final-point puid == destinationPuid + floor match) → no-op;
   - Else requests indoor route from best available anchor to destination via existing repository methods (POI-to-POI from nearest known POI of this building/floor, else coordinate-based using current fix), through SpaceProvider's guarded request machinery (request-id discipline reused) BUT committed via `adoptNavigatedRoute` write-through with revision bump;
   - Failure policy: keep old route (still renders; possibly imprecise indoors), surface status-bar hint "Indoor route unavailable — following general path"; retry on next floor confirmation.
2. Radiomap readiness gate: `_ensureIndoorGuidance` runs only after `radioMapStatus.ready` for confirmed (building,floor); if loading, defer until SpaceProvider notifies completion (one-shot listener hook), timeout 20 s then proceed-with-old-route + hint.
3. Remove the misleading comment (NC:1203) once real behavior matches.

**Architectural rule.** *Handoff completeness: mode transitions guarantee guidance content appropriate to the new mode, without inventing geometry.* Preserves §4 items 5/7 untouched.

**Files affected.** NC, SP (expose a narrow `requestIndoorRouteForSession(...)` wrapper reusing cascade pieces), `navigation_status_bar` hint.

**Tasks.**
1–3 as listed.

**Tests.**
- New: enter building (scripted dwell+corroboration) → repository receives exactly one indoor route request anchored at confirmed building/floor; committed via write-through; revision bumped; latch prevents duplicates; failure keeps old route + hint flag; retarget resets latch.
- Matrix B/C/D indoor-side assertions build on this.

**Acceptance criteria.**
- [ ] After scripted O→I handoff, rendered+evaluated route contains destination-floor indoor segment (or documented degradation hint).
- [ ] Entry dwell/corroboration tests unchanged-green.
- [ ] Suite green.

**Rollback.** Revert; feature is additive post-corroboration hook.
**Dependencies.** Phases 2, 3.

---

### PHASE 9 — Floor-Transition Hardening & Rendering Continuity

**Objective.** Close remaining transition defects; guarantee route visibility across the entire transition lifecycle.

**Why.** BUG-15 (unbounded index; silent exhaustion); Phases 2–3 already restored visibility — this phase hardens the edge cases and formalizes continuity tests.

**Current state.** Verified core (§4 item 3). Remaining: NC:819 unbounded `points[idx+1]`; `_advanceToNextSegment` exhausted branch logs only (NC:1276–1280) leaving completion semantics implicit; connector-as-last-point undefined; organic-drift zero-dwell path (NC:925) is intentional but undocumented in tests.

**Changes required.**

1. Bounds-guard NC:819 (`idx + 1 < points.length` else skip connector with warning log).
2. Segment exhaustion: when last segment's end is within arrival-proximity of the anchor, treat as normal (arrival owns completion); otherwise set `routeIncomplete` transient flag + hint, keep session alive (matches Phase 6 failure philosophy).
3. Extract `segmentAdvanceThresholdMeters` config (done in Ph6 task 6 — verify + document here).
4. Formalize continuity contract as tests: at every transition event (EXPECTED/DETECTED/CONFIRMED/ABORTED), scope route object identity is unchanged and non-null (given Phases 2–3 this is structural; test pins it against regressions).

**Architectural rule.** *Transitions change which geometry is emphasized, never whether guidance exists.*

**Files affected.** NC, tests.

**Tasks.**
1–4 as listed.

**Tests.**
- Connector-last-point fixture no longer crashes/misfires.
- Exhausted-segments-without-anchor sets flag; with-anchor defers to arrival.
- Continuity pin across scripted multi-floor journey (extends `floor_transition_test.dart`).
- Matrix D unit version complete.

**Acceptance criteria.**
- [ ] All four tasks' tests green; suite green.
- [ ] Manual emulator smoke: 2-floor guided walk shows continuous route, hold marker, no blackout beyond designed suppression.

**Rollback.** Revert.
**Dependencies.** Phases 2, 3.

---

### PHASE 10 — Indoor→Outdoor Handoff Completion

**Objective.** Exit releases ONLY indoor context; outdoor continuation keeps everything.

**Why.** INV-9 full closure. Exit dwell machinery verified (§4 item 6); today `clearSelection()` at confirmed exit (NC:1066) also nulls browsing floor/POIs AND (pre-Phase-3) the route.

**Current state.** Post-Phase-3 exit uses `releaseIndoorContextForNavigation()` (route-safe). Remaining policy decisions: what exactly gets released, radiomap eviction scope (delegates to Phase 11), and post-exit re-preload if journey returns indoors.

**Changes required.**

1. Define release matrix (implemented in `releaseIndoorContextForNavigation`, SP):
   - RELEASED: selectedFloor→null? NO — keep last floor for map context; clear floorplan overlay browsing selection only if it belongs to exited building; POI selection cleared; radiomap handling per Phase 11 policy (targeted removal of exited building's maps after grace period, not global wipe);
   - PRESERVED: route, destination, session, revision, navigating-floor bookkeeping (becomes stale but harmless; recomputed on reroute/next indoor leg), custom-route progress source switches to outdoor automatically via existing state gate (NC:598–615).
2. Re-entry support: existing entrance dwell logic already handles returning indoors mid-session; add test proving second entry triggers preload+corroboration again without new session.
3. Document the matrix in NSM header next to state docs.

**Architectural rule.** INV-9: *exit clears positioning/browsing context for the building left; navigation content survives.*

**Files affected.** SP (release method finalization), NC (call-site confirmation), docs-in-code, tests.

**Tasks.**
1–3 as listed.

**Tests.**
- Scripted I→O→(same or another building)→I double-handoff: session id constant; route persists through both transitions; radiomaps per Phase 11 policy.
- Matrix E unit version.

**Acceptance criteria.**
- [ ] Double-handoff test green; no route loss at either boundary.
- [ ] Suite green.

**Rollback.** Revert.
**Dependencies.** Phases 3, 11 (policy alignment; can land same window).

---

### PHASE 11 — Radiomap Lifecycle Contract

**Objective.** Navigation-aware radiomap residency: preload for approach, retain during multi-building trips, targeted eviction, browsing never sabotages navigation sensing.

**Why.** Gap #34: `_resetRadioMapState` wipes ALL resident maps (SP:1904) — hostile to A→B→A trips and to return journeys; acquisition itself is verified (§4 item 8).

**Current state.** Native engine enforces LRU resident limit 4 (documented-only constant in Dart cfg). SpaceProvider loads on selection; clears globally on selection resets; controller preloads via For-Navigation selection (Phase 3).

**Changes required.**

1. Policy doc (code comment block in SP near radioMap section):
   - LOAD: on browsing selection AND on navigation preload (existing paths);
   - RETAIN: while its building could be re-entered later in the active session (heuristic: building present in current route segments OR was exited < 10 min ago) — enforced by NOT calling global clear during sessions;
   - EVICT: targeted `removeRadioMap(buid, floor)` when (a) load fails (exists), (b) session End with no nearby-building need (keep simple: on End, leave LRU to manage naturally — no explicit wipe), (c) explicit user "clear offline data" (out of scope);
   - Global `clearRadioMap()` reserved for app-level reset only (logout/storage reset), never from selection APIs.
2. Replace `_resetRadioMapState`'s native wipe with status-field reset only; add separate `resetAllRadiomaps()` for true global use; audit callers (selection APIs call the former).
3. Browsing-during-navigation: selecting another building loads ITS maps (LRU evicts oldest) — acceptable by design; assert in tests that the NAVIGATING building's map is re-loadable instantly upon return (disk cache hit path exists).

**Architectural rule.** *Radiomap residency serves both browsing and navigation; neither may destroy the other's requirements.*

**Files affected.** SP (split reset vs wipe), callers audit, tests.

**Tasks.**
1–3 as listed.

**Tests.**
- Unit: selection-reset during session does NOT remove native maps (fake service records calls); End does not wipe; failure still evicts targeted map.
- Matrix O (Wi-Fi wrong building/floor) interplay unchanged.

**Acceptance criteria.**
- [ ] Fake-native assertions prove scoped behavior.
- [ ] Suite green.

**Rollback.** Revert.
**Dependencies.** Phase 3.

---

### PHASE 12 — Rendering & Camera Consistency

**Objective.** Map shows exactly the relevant geometry for current context; camera behaves predictably across modes/transitions/reroutes.

**Why.** BUG-9/10/11/16; completes §1 experience for the visual channel.

**Current state.** All-floor simultaneous rendering (M:855–872); KMZ layer ungated (M:825–849); fit-zoom pinned (M:720–723); inertia follow-exits (M:543,1065–1072); dead compass branch (M:401–420 due LP:156–165).

**Changes required.**

1. **Floor-scoped segment rendering** (M `_buildPolylines`): render rules —
   - outdoorWalking segments: always visible outdoors OR when route has no indoor emphasis; hidden while actively inside a building EXCEPT keep dimmed outline for orientation;
   - indoorRouting segments: visible iff segment.floorNumber == currently displayed floor (browsing-aware: use `_selectedFloor.floorNumber`, not navigating bookkeeping — they converge post-Phase 3 anyway);
   - floorTransition segments: visible connecting the two floors' displayed geometries when either side is displayed;
   - entrance/exitTransition: visible adjacent to their outdoor/indoor neighbor visibility;
   - Implementation: extend per-segment style map with a visibility predicate consuming (displayedBuid, displayedFloorNumber, fix.hasScope).
2. **KMZ layer gating:** honor the comment — draw campus KMZ polylines only when `!navController.isSessionLive` OR route lacks outdoor coverage (config flag `showCampusRoutesDuringNavigation = false` default).
3. **Fit-bounds zoom:** compute from bounds span like standard fit; replace pinned clamp with `zoomForSpan(maxSpan)` mapping (e.g., >2000 m→14, >800→15.5, >300→17, else 19) clamped `[MapConfig.indoorFloorplanZoom .. 17]` for outdoor spans; keep centering logic.
4. **Follow-exit robustness:** track programmatic-animation tail: keep `_isProgrammaticMove` true until `onCameraIdle` following an animated move (or add 350 ms grace timestamp comparison) so inertia doesn't exit follow; user-initiated drags still exit immediately (they produce moves without pending-programmatic tail).
5. **Heading cleanup:** remove dead compass-from-location branch (LP never supplies heading); rely on device-heading stream + movement bearing (existing EMA); during position-hold, freeze heading smoothing input too (pass held-fix velocity 0) so marker arrow matches held marker (BUG-16b).
6. Status/instruction strip source unification: instruction strip continues reading controller getters — now guaranteed identical object (Phase 2); add widget assertion test pinning equality.

**Architectural rule.** *Rendering is a pure projection of (route store, display context); camera is presentation-only; no rendering rule mutates navigation state.*

**Files affected.** M, `navigation_display.dart`, cfg (flags/thresholds), widget tests.

**Tasks.**
1–6 as listed.

**Tests.**
- Widget: given 3-floor hybrid route + displayed F1 → only F1-indoor + connectors + outdoor-per-rule polylines present (assert polyline ids).
- KMZ gating toggle behaves per flag/session state.
- Fit-bounds zoom table test (pure function extracted).
- Follow-exit: simulated inertia sequence retains follow; real gesture exits.
- Heading-hold consistency test.

**Acceptance criteria.**
- [ ] Visual smoke script (§13 walk-throughs) shows correct layer visibility at every stage.
- [ ] No camera jump on reroute commit (follow continues; no refit) — asserted by absence of fit-bounds invocation post-commit (test).
- [ ] Suite green.

**Rollback.** Revert; purely presentational.
**Dependencies.** Phase 7 (truthful metadata makes predicates reliable).

---

### PHASE 13 — Arrival Correctness

**Objective.** Outdoor arrival demands evidence quality symmetric with indoor identity gating.

**Why.** Gap #5 / INV-8 closure for arrival.

**Current state.** Indoor path fully gated (identity + proximity + 2 ticks). Outdoor: any two consecutive fixes within 15 m confirm — including poor/stale ones pre-Phase-5; Phase 5 flags now available.

**Changes required.**

1. `_checkArrival` outdoor branch requires: fix passes decision-quality band (good accuracy, not stale, not outlier-held) for BOTH confirming ticks; counter resets on any non-qualifying tick (mirrors indoor identity reset).
2. Anchor stability: resolve anchor once per (sessionId, revision) — cache key tuple; re-resolve only on revision bump (prevents live-POI-list churn effects; complements §4 item 2 tiers).
3. Post-arrived policy (document + minimal code): stay `arrived`; banner Done → terminate (Phase 15 API); auto-cleanup timer explicitly OUT of scope (product choice recorded here).

**Architectural rule.** INV-8 for arrival: *arrival is evidence, never coincidence.*

**Files affected.** NC, tests.

**Tasks.**
1–3 as listed.

**Tests.**
- Poor-accuracy pair does NOT arrive; good pair does; stale tick resets counter; anchor cached across unrelated POI reloads; revision bump re-resolves.
- Extends `arrival_test.dart` (matrix A outdoor tail).

**Acceptance criteria.**
- [ ] New gates tested; existing arrival suite green.

**Rollback.** Revert.
**Dependencies.** Phases 5, 7.

---

### PHASE 14 — Async/Race Hardening (R1–R12 Closure)

**Objective.** Every listed race has a named guard and a test.

**Why.** INV-3 exhaustive; several races partially covered by earlier phases — this phase audits and closes gaps systematically.

**Current state.** R2/R8/R10 guarded; R1/R16 partial (Phases 1/2); R3–R6 closed by retarget protocol (Ph4) + reroute validation (Ph6); R7 acceptable-by-design; R9 structurally eliminated (single store); R11 covered by session fencing; R12 dispose-safety tested (boundary tests) + tab-leave policy explicit.

**Changes required.**

Audit pass producing `docs/NAVIGATION_MASTER_PLAN_RACE_AUDIT.md`: for each R# — mechanism, file:line guard, test reference. Implement anything discovered missing (anticipated leftovers):
- Cancellable backoff: replace bare `Future.delayed` with delay-then-recheck pattern (identity check AFTER delay before continuing loop) — NC reroute retries.
- Preload completion callback validation (entrance preload future resolves into changed session) — identity-gate the `.then`.
- Scope notification storm safety: `adoptNavigatedRoute` coalescing unnecessary (single notify) but assert no reentrant adoption loops (debug-mode reentrancy guard).

**Architectural rule.** INV-3 exhaustive with documented mapping.

**Files affected.** NC mostly; audit doc.

**Tasks.**
1. Write audit doc skeleton; fill per race.
2. Backoff recheck pattern.
3. Preload then-guard.
4. Reentrancy assertion (debug only).

**Tests.**
- One dedicated test per R# where not already existing (target: all 12 have explicit tests; many reuse earlier-phase ones by reference).
- Stress: rapid End/Start ×50 loop leaves zero listeners/timers leaked (extend lifecycle test patterns).

**Acceptance criteria.**
- [ ] Race audit complete; 12/12 mapped to tests.
- [ ] Stress loop green.

**Rollback.** N/A (audit + small guards).
**Dependencies.** Phases 1–13.

---

### PHASE 15 — Termination Canonicalization & Instrumentation

**Objective.** One teardown API from every state; structured event log for field diagnosis.

**Why.** INV-10; gap #48/#52; ghost-preview class bugs (BUG-8 fixed narrowly in Ph4) eliminated categorically.

**Current state.** `endNavigation` thorough internally (NC:381–405) but scope-clear externalized; five call sites with inconsistent pairing (M:1276, MS:44, bottom_sheet:206/219/381, building_detail_card:306, plus :201 leak fixed in Ph4).

**Changes required.**

1. Rename/extend to `terminateNavigation()` on controller:
   - performs existing internal cleanup list (kept verbatim),
   - calls `_spaceScope.clearNavigationRoute()` (idempotent),
   - emits `SESSION_END` log,
   - returns void; NEVER throws even if scope fake misbehaves (try/catch log).
2. Migrate ALL call sites to single-call form; delete paired manual clears; keep `clearNavigationRoute` public for genuine idle-route dismissal (preview discard without session).
3. Tab-leave policy documented in MS comment: leaving Map tab terminates session BY DESIGN (v1 product decision; revisit = product backlog note).
4. Structured logging convention (lightweight, debugPrint-based with stable prefixes parseable in CI logs):
   ```
   [NAV] EVENT=<NAME> sid=<id> rev=<rev> dst=<puid> bldg=<b|->> flr=<f|->> src=<gps|wifi> detail=<...>
   ```
   Events minimum set: SESSION_START/END, PREVIEW_SEED, ROUTE_COMMIT(source=initial|reroute-kmz|reroute-api), ROUTE_DISCARDED(reason), REROUTE_TRIGGER/FAILED, STATE(from→to), HANDOFF_ENTER_START/CONFIRM/TIMEOUT, HANDOFF_EXIT_*, FLOOR_EVENT(kind), GPS_QUALITY(verdict) sampled, ARRIVAL, TERMINATE(stage summary counts).
   Gate verbose ones behind `kDebugMode` except SESSION/TERMINATE/ARRIVAL.
5. Replace ad-hoc debugPrints in NC hot path with convention (mechanical; behavior-preserving).

**Architectural rule.** INV-10; observability contract.

**Files affected.** NC, NSM (docs), SP (nothing new), MS, M, bottom sheet, building card, status widgets (log lines optional).

**Tasks.**
1–5 as listed.

**Tests.**
- Terminate-from-every-state table test (idle excluded): each of 9 states → terminate → idle, zero residue assertions (route null, destination null, flags reset, fakes received scope-clear exactly once).
- Call-site grep test equivalent (manual checklist in PR template).
- Log-contract test: scripted journey produces required event sequence (capture debugPrint via adapter or injectable logger — introduce `NavigationLog` fn hook for tests).

**Acceptance criteria.**
- [ ] Single-call termination everywhere; paired-clear remnants deleted.
- [ ] Event-sequence test green.
- [ ] Suite green.

**Rollback.** Revert; mechanical.
**Dependencies.** All prior (final wiring phase before validation).

---

### PHASE 16 — Integration, Regression & Device Validation

**Objective.** Prove the whole system end-to-end; lock it.

**Why.** §1 objective is behavioral, not architectural checkboxing.

**Current state.** Strong unit base (16 files + additions from Ph0–15); zero device-loop automation.

**Changes required.**

1. Automated integration pack (emulator-friendly, fake services where hardware needed):
   - Full-journey scripted state test (idle→…→idle hitting every state exactly once — exists) EXTENDED with: write-through assertions at each commit point, session-id constancy, revision monotonicity, log-event sequence.
   - Race battery from Ph14 run in one suite.
   - Golden-model test: pure function replaying (fix stream, api stubs) → expected (state, store route hash, rendered polyline id set) snapshots for scenarios A–T unit-mappable subset.
2. Manual device protocol (§13) executed on physical Android; results appended to baseline doc.
3. Regression matrix finalized (§12): every existing test file mapped to owning phase; CI order fixed.
4. Performance sanity: profile cold start→map ready and tick-pipeline cost (<2 ms/tick budget) — record numbers; no regressions vs Phase 0 snapshot.
5. Final architecture audit vs §7 diagram: sign-off checklist in DoD.

**Acceptance criteria.**
- [ ] All automated suites green (analyze 0 errors; unit+integration full pass).
- [ ] Device protocol executed; anomalies filed or fixed.
- [ ] §16 DoD fully checked.

**Rollback.** Per-phase history intact (§14 strategy).
**Dependencies.** All.

---

---

## 11. End-to-End Test Matrix

Conventions: **State** = NavigationController state after Action settles. **Route** = scope store content (== rendered). **Source** = `currentFix.source`. Unit-automatable tests run in CI; device-only items marked 📱 (protocol in §13).

### TEST A — Outdoor → Building → Indoor → Arrival
- Initial: idle; GPS good; destination = indoor POI room 104 B/C floor 2; route via cascade (cross-building).
- Action: preview → start → walk to entrance → dwell confirm → walk to stairs → transition F1→F2 → approach room.
- Expected: state path activeOutdoor→enteringBuilding→activeIndoor→floorTransition→activeIndoor→arrived. Route: persists throughout, gains indoor segment post-corroboration (Ph8), revision bumps at each commit. Source: gps→wifi at confirm. UI: status transitions + blackout label during hold + arrival banner. Cleanup: none until End.
- No-regression: entry/exit/floor suites green.
- Coverage: unit-scripted full path (Ph8/9/13 tests) + 📱.

### TEST B — Wi-Fi unavailable inside building
- Initial: activeOutdoor en route; building radiomap absent/unloadable (unsupported).
- Action: enter; corroboration window expires / no qualifying estimates.
- Expected: enteringBuilding→(20 s)→activeOutdoor; route+session intact; hint shown; reroute still possible outdoors.
- Coverage: existing machine test extended with route-preservation assertion (Ph3) + 📱 airplane-mode Wi-Fi off.

### TEST C — Wrong-building Wi-Fi during approach
- Initial: approaching target C; user passes near wrong building D with resident maps.
- Action: D's estimates win locally but identity ≠ destination.
- Expected: no activeIndoor commit for D (identity-aware corroboration); timeout→activeOutdoor; preload of D allowed but harmless; route untouched.
- Coverage: existing foreign-building test + Ph10 double-handoff variant + 📱.

### TEST D — Floor 1 → Floor 2 mid-navigation
- Expected: EXPECTED→DETECTED→CONFIRMED; hold marker; suppression 10 s; route object identical across all events; post-confirm geometry emphasis switches; radiomap F2 loaded pre-switch (connector proximity).
- Coverage: floor_transition suite + Ph9 continuity pins + 📱.

### TEST E — Indoor → Exit → Outdoor continuation
- Expected: EXITING dwell (acc≤15 m outside ×3)→activeOutdoor; indoor context released per Phase-10 matrix; route/session preserved; outdoor deviation resumes immediately (suppression only for floors).
- Coverage: machine exit tests + Ph10 + 📱.

### TEST F — Outdoor off-route → reroute
- Injected: 2 consecutive ticks >15 m from outdoor geometry (post-Ph7 truthful metadata) with good accuracy.
- Expected: REROUTE_TRIGGER; candidate validated (identity+destination+quality)→atomic commit; revision+1; polyline swaps on screen same frame; cooldown armed AFTER successful transition.
- Coverage: Ph6 units + integration stub + 📱 walking detour.

### TEST G — Indoor off-route → reroute
- Injected: sustained wrong-floor/wrong-corridor evidence (Wi-Fi fixtures).
- Expected: floor-filtered deviation fires only with confirmed identity; reroute uses confirmed floor context (never `'0'` leak outdoors rule inverted indoors).
- Coverage: Ph6 units (indoor branch) + 📱.

### TEST H — Destination changed during navigation
- Action: retargetDestination(B) while navigating A.
- Expected: NEW sessionId instantly; old-session async inert; B route committed via write-through; anchor=B; UI shows B.
- Coverage: Ph4 units (unit-H) + 📱.

### TEST I — Destination changed while rerouting
- Action: trigger A-reroute (stub slow), retarget B before completion.
- Expected: A result discarded on identity check; exactly one B flow; no flicker of A polyline.
- Coverage: Ph4/Ph14 race tests.

### TEST J — End during initial route calculation
- Action: request route → End before completion.
- Expected: request-id invalidation in SP; controller never seeds; UI clean; no late notify side effects.
- Coverage: existing SP guard tests + new explicit pairing test.

### TEST K — End during rerouting
- Expected: isSessionLive gate drops result; restore-transition skipped (state already idle); no resurrect; backoff continuation identity-checked (Ph14).
- Coverage: existing machine end-mid-reroute test + Ph14 extension.

### TEST L — End during floor transition
- Expected: hold cleared, timers/context cleared (existing behavior), scope route cleared by canonical terminate (Ph15), history cleared.
- Coverage: floor_transition end-mid-dwell + Ph15 table test.

### TEST M — Old async result after NEW session starts
- Sequence: session1 reroute pending → End → immediate new session2 to different destination → session1 result arrives.
- Expected: dropped silently (log ROUTE_DISCARDED reason=stale-session); session2 unaffected anywhere (store/revision/state/UI).
- Coverage: Ph1 core test generalized + stress loop.

### TEST N — GPS stale / inaccurate / jump
- Fixtures: timestamp −30 s; accuracy 80 m; implied-speed 200 m/s jump; then recovery pair.
- Expected: each rejected/held per Phase-5 rules; marker never teleports; NO reroute/arrival/pause-flicker from single events; pause entered only on sustained poor band; recovery resumes.
- Coverage: LP filter units + NC band units + 📱 tunnel/elevator simulation.

### TEST O — Wi-Fi stale / wrong floor / wrong building (indoor)
- Expected: arbiter handles per verified hysteresis; navigation layer sees only confirmed identities; arrival gated accordingly.
- Coverage: arbitration suite (existing) + arrival identity tests.

### TEST P — Backend unavailable
- Stub: repository throws for both endpoints.
- Expected: cascade falls through cross-building→KMZ/OSRM hybrid tiers; final fallback straight-line marked partial+warning; preview allowed with warning surfaced; navigation permitted; reroutes degrade similarly keeping old route on failure.
- Coverage: SP cascade units (existing patterns) + warning surfacing test.

### TEST Q — OSRM unavailable (network fine otherwise)
- Expected: KMZ-first paths unaffected; OSRM-dependent tiers skip; splice skipped; straight-line fallback partial if nothing else; no crash/hang (timeout respected).
- Coverage: custom_routes units + cascade stubs.

### TEST R — KMZ unavailable/corrupt asset
- Expected: graph empty → findRoute/findHybrid null-safe skips → OSRM/backend paths serve; campus-layer rendering degrades silently; integration test's negative branch.
- Coverage: kmz_loader negative tests (existing) + cascade order test.

### TEST S — App background/resume
- Expected: on resume with followMode → recenter (existing); streams resume without duplicate subscriptions; session survives backgrounding (no lifecycle kill); stale-fix gate swallows the pre-background fix burst.
- Coverage: lifecycle suite + 📱 protocol step.

### TEST T — Leave Map tab during navigation
- Policy (documented Ph15): leaving tab terminates session deliberately (endNavigation + clearNavigationRoute via MS hook).
- Expected: on return: idle, no ghost route; tracking continued throughout (My Map live position intact); returning user re-navigates fresh.
- Coverage: MS widget test (exists shell_gate pattern) + explicit assertion of paired cleanup post-Ph15.

---

## 12. Regression Matrix

Existing 16 test files and their relationship to this plan:

| Test file | Protects | Touched by phases |
|---|---|---|
| `navigation_state_machine_test.dart` | edge table, journeys, dwells, preload tiers, end-from-any-state | Ph1 (session asserts), Ph15 (terminate rename) |
| `arrival_test.dart` | confirmation, identity gating, anchors | Ph13 (outdoor gates), Ph2 (getter reads) |
| `floor_transition_test.dart` | event lifecycle, holds, suppression, timeout | Ph9 additions; Ph3 (selection variant calls) |
| `location_provider_arbitration_test.dart` | belief/hysteresis/scope/outlier/stale-timer | Ph5 must NOT alter outcomes (guard tests) |
| `location_provider_lifecycle_test.dart` | subscribe/dispose/stale-timer basics | Ph5 extensions |
| `position_estimate_boundary_test.dart` | transport robustness | none (read-only dependency) |
| `custom_routes_test.dart` / `_integration_test.dart` | KMZ stack correctness | consumers of Ph7 truthfulness — verify pass-through unchanged |
| `route_model_test.dart` | segment derivation/scope flags | Ph7 expectations UPDATE (metadata flips) |
| `quick_access_test.dart`, `home_quick_access_test.dart` | browsing flows incl. cross-building nav | Ph3/Ph4 idle-parity must keep green |
| `search_filter_test.dart`, `shell_gate_test.dart`, `widget_test.dart` | app chrome | untouched |
| `navigation_ui_test.dart` | display projections/instruction strip/banner | Ph12 equality pin addition |
| `floorplan_overlay_cache_test.dart` | overlay cache | untouched |

Rule: any phase that flips a characterization expectation must update the corresponding row here in the same PR.

New permanent suites introduced: session identity (Ph1), write-through/store uniqueness (Ph2), browsing neutrality (Ph3), retarget protocol (Ph4), GPS quality (Ph5), rerouting correctness (Ph6), metadata truth (Ph7), handoff guidance refresh (Ph8), continuity pins (Ph9), release matrix (Ph10), radiomap scoping (Ph11), rendering predicates (Ph12), arrival gates (Ph13), race battery R1–R12 (Ph14), termination table + log contract (Ph15).

---

## 13. Manual Real-Device Testing Plan

Physical validation (Android device, campus grounds; requires built APK with server reachable or offline fixtures):

1. **Walk A (full journey):** Parking → Building C lobby → stairs to F2 room → exit → parking. Record: log stream (`[NAV]` lines), screenshots at each state, anomalies.
2. **Walk B (reroute):** deviate deliberately ~40 m mid-outdoor; confirm single reroute, visible swap, camera stability.
3. **Walk C (false-trigger resistance):** linger at entrance doorway 60 s (mixed evidence) → expect at most one clean handoff cycle, no flapping.
4. **Elevator ride:** F0→F2 fast; expect hold→confirm ≤ timeout; no frozen marker beyond designed blackout.
5. **GPS degradation spots:** identified campus canyons; expect pauses not teleport/reroute storms.
6. **Background/resume & tab-flap:** navigate, background 2 min, resume; leave/return Map tab ×3; verify policy behavior and clean state.
7. **Battery/thermal sanity (informational):** 30-min continuous navigation; note drain vs pre-plan build.

Results appended to `docs/NAVIGATION_MASTER_PLAN_BASELINE.md`; regressions filed against owning phase.

---

## 14. Rollback Strategy

- **Commit discipline:** one phase = one merge-request-sized changeset (may contain several commits, all phase-scoped). Tag each merged phase: `nav-phase-N`.
- **Per-phase revert:** every phase lists rollback feasibility; architecture phases (1–4) are strictly additive-or-deletable reverts; data-model phase 7 carries the widest blast radius — its MR includes the full expectation-update diff making revert mechanical.
- **Feature flags (minimal, temporary):**
  - `retargetDuringNavigationEnabled` (Ph4) — hide UI entry point if field issues;
  - `showCampusRoutesDuringNavigation` (Ph12, default false);
  - GPS quality gates behind `gpsQualityGatesEnabled` (Ph5) for emergency disable without revert.
  All flags removed in Phase 16 cleanup once validated.
- **Baseline snapshot (Phase 0)** is the ultimate rollback point; worktree never returns there except by explicit decision.
- **Invariant breach mid-phase:** stop; revert that phase entirely; do not hotfix forward across a gate.

---

## 15. Final Acceptance Criteria

1. §8 invariants INV-1…INV-11 each enforced by ≥1 named automated test.
2. §5 bugs BUG-1…BUG-16 each closed with a regression test proving the flip (or explicitly waived with rationale recorded here — currently zero waivers planned; BUG-16 heading-cosmetic portion resolved by cleanup, not behavior change).
3. Race matrix R1–R12 fully mapped (audit doc) with passing tests.
4. Test matrix A–T: automated subset green in CI; 📱 subset executed per §13 with results recorded.
5. `flutter analyze`: 0 errors; warnings not increased vs Phase 0 baseline count (3).
6. Existing 16-file regression set green throughout (expected flips limited to rows updated per §12).
7. Performance sanity numbers within budget (§10 Ph16 item 4).
8. Product policies documented in-code where implemented: tab-leave kill (MS), no-auto-dismiss-on-arrival (NC), sensing-independence (LP header), radiomap residency (SP).

---

## 16. Definition of Done

- [ ] Phase 0–16 sections above each checked complete with linked MRs/tags.
- [ ] INV tests exist and green (list in PR description of Ph16).
- [ ] Bug-flip tests exist and green (BUG-1..16).
- [ ] R1–R12 audit doc complete; battery green.
- [ ] A–T automated coverage green; manual protocol executed & recorded.
- [ ] Analyze/test gates green at HEAD; baseline doc finalized.
- [ ] Flags removed or defaulted-and-scheduled; audit notes updated.
- [ ] This document's §7 diagram matches shipped code (final audit sign-off).
- [ ] No backend/native-Kotlin behavioral changes without a dedicated justification note (target: zero).

---

## 17. Files Expected to Change

Primary:
- `lib/state/navigation_controller.dart` — Phases 1,2,3,4,6,8,9,10,13,14,15 (heaviest)
- `lib/state/navigation_state_model.dart` — Ph1 (NavigationSession), Ph2 (scope interface), docs
- `lib/state/space_provider.dart` — Ph2 (adopt impl), Ph3 (guards + For-Navigation variants + release method), Ph7 (hybrid builders), Ph11 (reset split)
- `lib/config/navigation_config.dart` — Ph5, Ph6, Ph12 constants/flags
- `lib/ui/screens/map_screen.dart` — Ph12 (rendering predicates, fit-zoom, follow robustness, heading cleanup)
- `lib/data/models/navigation_route_model.dart` — Ph7 (truth rules)
- `lib/data/models/route_segment.dart` — Ph7 (fallback partial flag, docs)
- `lib/data/repositories/cross_building_router.dart` — Ph7 (cap guard, fallback flags, outdoor metadata)
- `lib/state/location_provider.dart` — Ph5 (GPS ingestion gates)
- `lib/data/datasources/gps_location_service.dart` — Ph5 (stamp + distance-filter)

Secondary/UI:
- `lib/ui/widgets/navigation_status_bar.dart` + `lib/ui/utils/navigation_display.dart` — Ph6 failed-flag, Ph8 hint
- `lib/screens/main_shell.dart` — Ph15 policy comment (+ no logic change expected)
- `lib/widgets/map_bottom_sheet.dart` (and `ui/widgets/` equivalents), `building_detail_card.dart` — Ph4/Ph15 call-site migration
- composition root wiring (`main.dart` / providers file) — Ph3 liveness injection

Tests (new/updated): per §12 plus new files `test/session_identity_test.dart`, `test/route_store_test.dart`, `test/browsing_neutrality_test.dart`, `test/retarget_test.dart`, `test/gps_quality_test.dart`, `test/rerouting_correctness_test.dart`, `test/metadata_truth_test.dart`, `test/handoff_guidance_test.dart`, `test/race_battery_test.dart`, `test/termination_test.dart`.

Docs: `docs/NAVIGATION_MASTER_PLAN_BASELINE.md`, `docs/NAVIGATION_MASTER_PLAN_RACE_AUDIT.md`.

---

## 18. Files That Must NOT Be Changed Unless Necessary

- `android/app/src/main/kotlin/.../positioning/*` (PositioningEngine, KnnLocalizer, PositioningBridge, WifiScanner) — verified native engine; Dart-side plan requires zero Kotlin edits.
- `lib/data/datasources/native_positioning_service.dart` — boundary contracts covered by boundary tests; untouched.
- Arbitration internals in LP (`_handleOutdoorEvidence/_handleIndoorEvidence/_advanceClaim/_qualifies/_computeWifiConfidence/stability tracker`) — Phase 5 adds GPS-side filtering only.
- State-machine edge table NSM:129–171 — no edge additions/removals anticipated by any phase (dynamic edges already sufficient).
- `custom_route_repository.dart` / `custom_route_graph.dart` / `kmz_loader.dart` — consumed as-is; their tests are regression guards.
- `anyplace_api_client.dart` routing endpoints (except nullable-floor parameter plumbing in repository signature layer) — backend contract frozen per AGENTS invariant.
- Cache services, search, quick-access, shell gating — out of scope; protected by their suites.
- `pubspec.yaml` dependencies — no new packages required by any phase (logging convention uses debugPrint hooks, not a framework).

Any exception requires an explicit justification note in the phase's MR referencing this section.

---

## 19. Known Remaining Risks

1. **Public OSRM endpoint dependency** (`router.project-osrm.org`, direct client calls): availability/rate-limits outside our control; cascade mitigates; flagged EXTERNAL DEPENDENCY — self-hosting is a product decision, out of scope.
2. **First-indoor-fix scope lag** (by design: identity publishes one estimate after 3-run confirm): arrival gating during the very first seconds indoors relies on bookkeeping floor; acceptable, documented; revisit only with arbiter changes (forbidden here).
3. **Retarget UX scope**: Ph4 ships protocol + minimal affordance; rich "via-stop" or multi-waypoint journeys remain future work.
4. **Tab-leave kills navigation**: intentional v1 policy; changing it would require session persistence design (explicitly out of scope).
5. **Geolocator int distanceFilter**: sub-meter displacement gating impossible until upstream type change; mitigated by quality gates.
6. **Model truth change ripples**: Ph7 touches serialized-ish model semantics; mitigation = exhaustive expectation updates in same MR + characterization flips; residual risk low but non-zero for any consumer we have not found — grep audits mandated in tasks.
7. **Device-test variability** (Wi-Fi density, GPS multipath): manual protocol results may vary day-to-day; treat failures as investigation triggers, not automatic blockers, unless invariant-level.
8. **Log volume in release builds**: verbose events kDebugMode-gated; SESSION/ARRIVAL/TERMINATE always on (tiny).

---

## 20. Final Architecture Diagram

```
                        ┌────────────────────────────────────────────┐
                        │                MapScreen                   │
                        │  render(store.route · displayContext)      │
                        │  camera/follow · marker · heading(present) │
                        └───────────────▲─────────────▲──────────────┘
                          reads store   │             │ displayLocationFor(hold)
                                        │             │
        ┌───────────────────────────────┴───┐   ┌─────┴──────────────────────┐
        │ SpaceProvider                     │   │ LocationProvider           │
        │  browsing: buildings/floors/POIs  │   │  arbiter (verified)        │
        │  floorplans · radiomaps(policy)   │   │  currentFix = canonical    │
        │  ROUTE STORE (single field)       │   │  GPS ingestion quality     │
        │  guards: browsing ≠ navigation    │   │  gates (new)               │
        └──────△─────────────────────△──────┘   └─────▲──────────────▲───────┘
   For-Navigation│      adoptNavigatedRoute│            │wifi          │gps
   selection     │      (write-through)    │       qualified         filtered
        ┌────────┴─────────────────────────┴──┐   estimates (native engine)
        │ NavigationController                │
        │  NavigationSession{sid,dst,rev}     │
        │  state machine (10 states, table)   │
        │  evaluate: progress·deviation·      │
        │    arrival(gated)·transitions       │
        │  reroute: capture→validate(identity,│
        │    dst,quality)→atomic commit       │
        │  handoffs: dwell·corroborate·       │
        │    refresh-indoor-guidance          │
        │  terminateNavigation() [single API] │
        └─────────────────────────────────────┘

Journey invariants: visible==evaluated · fenced async · browsing-neutral ·
quality-gated decisions · metadata-truthful routes · exit-preserves-trip ·
total teardown · responsive fixes.
```

END OF PLAN
