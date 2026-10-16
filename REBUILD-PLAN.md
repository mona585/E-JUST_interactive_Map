# REBUILD PLAN — NEW APP = REFERENCE APP − INDOOR, IN STRICT MVVM

**Status:** Phase 0 (read-only discovery) COMPLETE. Implementation NOT started, per §6 / §21.
**Reference App:** `clients/flutter/anyplace_campusfind` — READ-ONLY, untouched.
**New App target:** `clients/flutter/ejust_campusfind` — current implementation to be DISCARDED (§8).

---

## 0. PRE-REBUILD REFERENCE INTEGRITY BASELINE

Captured before any change, excluding generated `build/`, `.dart_tool/`, `.gradle/`, `.kotlin/`.

| Metric | Value |
| --- | --- |
| Files hashed | **238** |
| Baseline file (original) | `%LOCALAPPDATA%\Temp\opencode\ref_baseline_phase0.txt` |
| Baseline SHA-256 (original) | `5355E9644A3CE5E81BFBFFD0147352FB47213229A758A94E7D3CDB7D11CE0530` |
| **Canonical baseline (use this going forward)** | `%LOCALAPPDATA%\Temp\opencode\ref_baseline_phase0_canonical.txt` |
| **Canonical baseline SHA-256** | `7665BA546F130D26E963C756305BE9FEACE578BF8B9D6BE61F827C54C8278B5E` |
| Dart files | 147 (96 in `lib/`, 50 in `test/`, 1 test helper) |
| Hash algorithm | SHA-256, line format `HASH␠␠relpath`, UTF-8, sorted by path |
| Exclusions | `build/`, `.dart_tool/`, `node_modules/` (generated) |

### 0.1 Integrity verification (performed after all discovery, before implementation)

Re-hashed the Reference tree and compared against the Phase 0 baseline:

| Check | Result |
| --- | --- |
| File count | 238 → 238 — **match** |
| SHA-256 hash **set** comparison | **0 added, 0 removed, 0 modified** |
| Path set comparison | 0 renames (1 cosmetic delta, see below) |
| **Verdict** | **Reference App is unchanged.** |

**Cosmetic delta, not a change:** `docs/# Complete Navigation System — Full.md` contains an em-dash
(U+2014) in its filename. The original baseline text file was written with a lossy encoding that stored it as
`-`, while a later ASCII re-check stored it as `?`. Both representations collide in a naive line diff, but the
underlying file hash is identical (`147243A26F6F90B6E26A060CC50F97DE11B0BDC89866EE27924AF38F8A8E4CC6`) in all
three. The canonical UTF-8 baseline above stores the true U+2014, which makes future comparisons exact.
**No Reference file was touched.**

Re-verify with the canonical file after the rebuild. Required result: **Reference App modified files = 0**.

---

## 1. THE HEADLINE FINDING

**The Reference App is already ~90% strict MVVM.** Its `lib/` tree already matches the §13 target
exactly:

```
lib/
├── config/        (4)   ├── models/         (15)
├── datasources/   (11)  ├── providers/      (5)   ← the only structural deviation
├── repositories/  (7)   ├── services/       (24)
├── utils/         (8)   ├── viewmodels/     (6)
├── views/         (4)   ├── widgets/        (11)
└── main.dart
```

Consequence for the plan: this is **not** an architecture migration. It is

1. **remove every indoor-only component**, and
2. **apply a small, enumerated set of MVVM corrections** to the shared components (§5 below).

There is no wholesale re-layering, which is what makes byte-level parity achievable.

### 1.1 The four documented MVVM violations in the Reference (all must be corrected)

| # | Violation | Evidence | Correction in New App |
| --- | --- | --- | --- |
| V1 | `SpaceViewModel` is a **second composition root** — instantiates `AnyplaceSpaceRepository`, `MethodChannelNativePositioningService`, `CampusAssetLoader`, `CampusRouteCoordinator` etc. with `?? default` fallbacks inside a view model. Directly contradicts `main.dart:19-20`. | `space_view_model.dart:32-40`, `:84-93`, `:95-153` | All construction moves to `di/`. ViewModel takes required non-null collaborators. |
| V2 | `lib/providers/` is outside the §13 target tree | `lib/providers/*.dart` (5 files, 17 providers) | Absorbed into `viewmodels/` (+ `di/` for the pure-service providers). No `providers/` folder remains. |
| V3 | `SpaceViewModel` uses two injected function fields as a **service locator** | `space_view_model.dart:169`, `:175`, poked from `main.dart:34-36` | Replaced by a real injected dependency (the navigation state port). |
| V4 | `SpaceViewModel` is bound to `LocationViewModel` **imperatively from the widget layer** after construction | `map_screen.dart:156-159` calls `spaceProvider.setLocationViewModel(...)` | Injected at construction in `di/`. No view → viewmodel back-binding. |

### 1.2 Reference behaviours that look like defects but MUST be reproduced verbatim

Per §3/§11 ("If the Reference App contains a special case, preserve it"), these are **carried over unchanged**, not fixed:

| Behaviour | Evidence |
| --- | --- |
| `routing_service.dart:266` comment says entry endpoint should prefer one near the *user*; the code at `:275-286` minimises distance to the *destination* only. Comment/implementation divergence preserved. | `routing_service.dart:266, 275-286` |
| `routeBetweenEdges` emits `[from, ...vertices..., to]`, **skipping the computed snapped projection point**. | `custom_route_graph.dart:505-509` vs `:436/:442` |
| Empty-result contract mismatch: `fetchOutdoorWalkingRoute` returns `[]` on failure, `fetchOutdoorWalkingRouteWithMetadata` returns `null`. Both shapes must be handled. | `anyplace_api_client.dart:889-934` vs `:980-1044` |
| `spliceCustomTail` connection threshold declared twice (`150.0` passed by planner, also the callee default). | `outdoor_route_planner.dart:98`, `custom_route_repository.dart:269` |
| OSRM request omits `steps=true`, so **no turn-by-turn maneuvers exist**; all instructions are synthesised strings. | `anyplace_api_client.dart:877`, `:968` |
| `withRetry` retries **every** exception, including terminal `ApiException`s. No jitter, no cap, `1 << attempt` backoff. | `with_retry.dart:9-18` |
| Zero TTLs on all three disk caches; `lastModified` stored but never compared to the server. | `poi_cache.dart:36-51`, `floorplan_cache.dart:37-52` |
| `ProfileScreen` "Save" is an explicit no-op TODO; server URL is a compile-time constant. | `profile_screen.dart:92` |
| `AppTheme.dark()` returns `light()` unchanged — **there is no real dark theme** in Dart. | `theme.dart:109` |
| `KmzLoader` doc comment claims lat/lon auto-detection; code always assumes KML `lon,lat`. Stale comment preserved. | `kmz_loader.dart:269-275` vs `:306-319` |
| KMZ placemark parsing is **regex-based**, not a real XML parser. | `kmz_loader.dart:107-112` |
| All 6 stock Google Maps affordances disabled; app draws its own controls and user marker. | `map_screen.dart:1472-1476` |
| KMZ asset filenames still say "university" although the data is E-JUST. | `assets/navigation/university roads.kmz` |

---

## 2. PHASE 0 — REFERENCE INVENTORY (SUMMARY)

Full detail is in the discovery pass; this is the decision-relevant summary.

### 2.1 Screens (4 + 1 shell)

| Screen | File | Class |
| --- | --- | --- |
| Composition root + router | `lib/main.dart` | `main()`, `CampusFindApp`, `RootRouter` |
| Map-first shell | `lib/views/main_shell.dart` | `MainShell` |
| Map canvas | `lib/views/map_screen.dart` (1,572 lines) | `MapScreen` |
| Search / directions | `lib/views/search_overlay.dart` | `SearchOverlay` |
| Profile / settings | `lib/views/profile_screen.dart` | `ProfileScreen` |
| Bottom content panel (71 KB, largest UI file) | `lib/widgets/campus_content_panel.dart` | `CampusContentPanel` |

No Drawer, no `PopupMenuButton`, no `showModalBottomSheet` anywhere in the Reference. Dialogs are
3 `AlertDialog`/`showAboutDialog` in `ProfileScreen` only. `SnackBarBehavior.floating` is the app default.

### 2.2 Map (must be reproduced exactly — §5, §12)

`GoogleMap` constructor args, verbatim (`map_screen.dart:1438-1488`):
`initialCameraPosition` (`zoom: isCampusOverview ? 14.5 : MapConfig.defaultZoom`), `mapType: MapConfig.mapType` (hybrid),
`onMapCreated`, `onTap`, `onCameraMove`, `onCameraIdle`, `myLocationEnabled: false`, `myLocationButtonEnabled: false`,
`zoomControlsEnabled: false`, `compassEnabled: false`, `mapToolbarEnabled: false`, `markers`, `polylines`, `groundOverlays`.

Markers: buildings `MarkerId(space.buid)` hueRed/hueYellow; gates `MarkerId('gate_${gate.id}')` hueGreen;
POIs (indoor, removed) hueViolet/hueOrange; user `MarkerId('user_location')` custom `_CustomPainter` dot/cone,
heading from `DeviceHeadingBridge` with movement-derived fallback, `0.5°` deadband, `flat: true`, `anchor: Offset(0.5,0.5)`.
`CameraUpdate.zoomIn/zoomOut`, `animateCamera`, `computeRouteCamera` clamps preview zoom to `[14,19]` with
`topChromeFraction 0.14` / `bottomChromeFraction 0.40`.

### 2.3 Outdoor algorithm inventory (authoritative, reproduced verbatim)

| Area | Location |
| --- | --- |
| 4-strategy outdoor cascade | `outdoor_route_planner.dart:40-114` — S1 pure custom graph → S2 edge-hybrid (`snapThreshold 250.0`) → S3 OSRM→custom → S4 OSRM + `spliceCustomTail` (`connectionThreshold 150.0`) |
| Campus road graph build | `custom_route_graph.dart:118-215` — vertex merge `15.0 m`, dangling-endpoint convergence pass to fixpoint, interior split window `0.05 < t < 0.95`, junction iff `adjacentEdges >= 3` |
| Dijkstra | `custom_route_graph.dart:352-397` — `SplayTreeSet`, deterministic `index` tie-break, undirected, early exit |
| Snapping | `custom_route_graph.dart:284-323` — `maxSnapDistance 100.0`, direction dot product with `1e-10` guards |
| Off-route / progress | `custom_route_repository.dart:169-173` (`30.0 m`), `:191-235` (snap `50.0`, off-route `30.0`) |
| OSRM transport | `anyplace_api_client.dart:868-935`, `:959-1045` — `overview=full&geometries=geojson`, 10 s timeout, `finalBearing` via forward-azimuth normalised `[0,360)` |
| OSRM→custom composition | `routing_service.dart:208-348` — dest vertex `500.0 m`, gate vertex `750.0 m`, **endpoint nearest destination**, degrades to `[...osrmPath, destination]` |
| Gate policy | `assets/config/gate_policy.json` → `preferredGateId: "G2"`, `disabledGateIds: ["G1","G3","G4"]`; gate-as-destination passes `gateEntry: null` (`campus_route_coordinator.dart:876-880`) |
| Navigation state machine | `navigation_state.dart:49-88` 10 states; allowed-edge table `:160-208`; illegal edges **rejected, never thrown** (`navigation_state_machine.dart:67-70`) |
| Arrival / deviation / GPS guard | `navigation_arrival_detector.dart` (`15.0 m`, 2 confirmations), `navigation_deviation_handler.dart` (`15.0 m`, 2 ticks, 15 s cooldown, 3 retries), `navigation_gps_guard.dart` (degraded ≥ 3 poor ticks, hysteresis) |

**Every numeric constant** is enumerated in the discovery pass and will be transcribed 1:1. Reference
`navigation_config.dart` outdoor/gps set: `gpsStaleAfterSeconds 10`, `gpsRejectAccuracyMeters 50`,
`gpsPoorAccuracyMeters 30`, `gpsGoodAccuracyMeters 15`, `gpsMaxImpliedSpeedMps 25`, `gpsOutlierHoldTicks 1`,
`gpsPausePoorTicks 3`, `rerouteDeviationConfirmTicks 2`, `rerouteKmzSnapThreshold 100.0`, `segmentAdvanceThresholdMeters 10.0`,
`showCampusRoutesDuringNavigation false`, `deviationThreshold 15.0`, `rerouteCooldownSeconds 15`, `rerouteMaxRetries 3`,
`customRouteOnThreshold 30.0`, `customRouteSnapThreshold 50.0`, `customRouteConnectionThreshold 100.0`,
`outdoorFollowZoom 17.0`, `routeFramePadding 60.0`, `followLowerThirdFraction 0.67`, `bearingSpeedThreshold 0.2`,
`bearingMinMovementMeters 0.15`, `bearingSmoothingFactor 0.6`, `bearingUpdateIntervalMs 200`, `bearingHoldDurationMs 1000`,
`compassStaleMs 2000`, `cameraMoveThresholdMeters 0.3`, `cameraBearingThresholdDegrees 1.5`.

### 2.4 Data / API

Base `https://map.beout.ai` (`--dart-define=SERVER_URL`), OSRM `https://router.project-osrm.org` (`--dart-define=OSRM_URL`).
**No auth on any request.** 9 POST endpoints; only **2 survive indoor removal**:
`POST /api/mapping/space/public` and `POST /api/mapping/space/get`.
`requestTimeout 30 s`; OSRM 10 s; `ApiConfig.floorplanImageTimeout 15 min` / `floorplanStallTimeout 60 s` are indoor-only.
All 3 bundled assets are **outdoor** — removing indoor requires **zero** pubspec asset edits.

### 2.5 Android

applicationId/namespace `eg.edu.ejust.anyplace_campusfind`; 9 permissions; AGP `9.0.1`, Kotlin `2.3.20`,
Gradle `9.1.0`, JVM target `17`, `minSdk/targetSdk/compileSdk` all delegated to `flutter.*` (unpinned);
release signed with the **debug** keystore; Impeller **disabled**; `usesCleartextTraffic="true"`.
7 Kotlin files: 1 shared (`MainActivity`), 1 shared/outdoor (`DeviceHeadingBridge` — compass), **5 indoor-only**.

---

## 3. THE INDOOR REMOVAL SET (usage-verified, nothing guessed)

Every item below was confirmed by reading its actual callers, not by name.

### 3.1 Dart — delete file (15)

| File | Evidence it is indoor-only |
| --- | --- |
| `lib/datasources/native_positioning_service.dart` | 100% indoor, zero outdoor surface; only callers are `LocationViewModel` and `CampusAssetLoader` |
| `lib/datasources/floorplan_cache.dart` | fed only by `/api/floorplans64` |
| `lib/datasources/radiomap_cache.dart` | stores `indoor-radiomap-mean.txt` |
| `lib/models/position_estimate.dart` | Wi-Fi fingerprint estimate (`matchedAps`/`totalAps`) |
| `lib/models/floor_model.dart` | `buid`+`floorNumber`+`fuid`+per-floor bounds |
| `lib/models/floorplan_model.dart` | base64 floorplan image + per-floor bounds |
| `lib/models/floor_transition_event.dart` | `expected/detected/confirmed/aborted` over floors |
| `lib/models/poi_model.dart` | required `floorNumber`; every consumer is floor-scoped |
| `lib/repositories/floorplan_repository.dart` | `/api/floorplans64` only |
| `lib/repositories/radiomap_repository.dart` | `/api/radiomap/*` only |
| `lib/repositories/poi_repository.dart` | `getPoisByFloor(buid, floor)` only |
| `lib/services/campus_search_index.dart` | entirely floor/POI-scoped |
| `lib/services/navigation_floor_transition_handler.dart` | floor detection/stability/timeout |
| `lib/utils/building_containment.dart` | classifies GPS against **indoor floor bounds** |
| `lib/utils/floorplan_overlay_cache.dart` | `GroundOverlay` prep for floorplan PNGs |

`lib/utils/poi_classification.dart` and `lib/services/service_query.dart` are also indoor-only (every predicate keys on
`poi.poisType` / `floorNumber`) — **19 files total**, see the final tally in §4.2.

### 3.2 Kotlin — delete file (5)

`positioning/PositioningBridge.kt`, `positioning/PositioningEngine.kt`, `positioning/KnnLocalizer.kt`,
`positioning/RadioMap.kt`, `positioning/WifiScanner.kt`.

**Keep:** `MainActivity.kt` (minus the `PositioningBridge` construction + dispose), `orientation/DeviceHeadingBridge.kt` (compass — outdoor).

### 3.3 Platform channels — delete (2)

`eg.edu.ejust.anyplace_campusfind/positioning` (MethodChannel) and
`eg.edu.ejust.anyplace_campusfind/position_stream` (EventChannel).
**Keep** `eg.edu.ejust.anyplace_campusfind/heading_stream`.

### 3.4 Permissions — delete (4)

`ACCESS_COARSE_LOCATION`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES`.
**Keep** `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`.
`ACCESS_FINE_LOCATION` is dual-use (it gates `WifiManager` on API 28+) but cannot be freed — outdoor GPS needs it.

### 3.5 Pubspec — zero package removals

No Flutter-side Wi-Fi package exists; indoor scanning is 100% hand-rolled Kotlin. So removing indoor
**removes no dependency** — it removes 5 Kotlin files, 2 channels, 4 permissions. `archive` stays (KMZ),
`geolocator` stays (GPS), `google_maps_flutter` stays, `connectivity_plus` stays, `shared_preferences` stays.

---

## 4. THE MAPPING TABLE (§7 REQUIRED FORMAT)

`REFERENCE COMPONENT → NEW COMPONENT → MVVM LOCATION → INDOOR/OUTDOOR → ACTION`

### 4.1 Fully reproduced, unchanged (REPRODUCE)

| Reference component | New component | MVVM location | O/I | Action |
| --- | --- | --- | --- | --- |
| `config/api_config.dart` (outdoor subset) | same | `config/` | O | REPRODUCE — drop 2 floorplan timeouts + `defaultRadiomapMeanFilename` + 5 endpoints |
| `config/constants.dart` (outdoor subset) | same | `config/` | O | REPRODUCE — drop `probeFloorNumber`; keep 6 building Quick Access seeds + epoch |
| `config/map_config.dart` | same | `config/` | O | REPRODUCE verbatim incl. `ejustCampusBounds` (camera-fit only, never drawn) |
| `config/navigation_config.dart` (outdoor+gps+shared subset) | same | `config/` | O/S | REPRODUCE — drop 24 indoor thresholds, keep every value above verbatim |
| `config/theme.dart` | same | `config/` | S | REPRODUCE verbatim (incl. `dark() == light()`) |
| `datasources/gps_location_service.dart` | same | `datasources/` | O | REPRODUCE — 500 ms Android interval, `distanceFilter < 1 → 1`, 15 s `timeLimit` |
| `datasources/location_service.dart` | same | `datasources/` | O | REPRODUCE |
| `datasources/device_heading_service.dart` | same | `datasources/` | O | REPRODUCE — channel, `[0,360)` normalisation, `SENSOR_UNAVAILABLE` swallow |
| `datasources/kmz_loader.dart` | same | `datasources/` | O | REPRODUCE verbatim incl. regex parsing and stale doc comment |
| `datasources/gate_policy_config.dart` | same | `datasources/` | O | REPRODUCE |
| `datasources/anyplace_api_client.dart` (outdoor subset) | same | `datasources/` | O | REPRODUCE — 2 Anyplace endpoints + 2 OSRM methods + `OsrmRouteResult` + `ApiException` |
| `repositories/space_repository.dart` | same | `repositories/` | O | REPRODUCE — keep spaces cache; floor cache drops (feeds containment only) |
| `repositories/custom_route_repository.dart` | same | `repositories/` | O | REPRODUCE verbatim incl. all 4 documented defects |
| `repositories/custom_route_graph.dart` | same | `repositories/` | O | REPRODUCE verbatim |
| `repositories/campus_gate_repository.dart` | same | `repositories/` | O | REPRODUCE |
| `repositories/navigation_repository.dart` (OSRM half) | same | `repositories/` | O | REPRODUCE — drop 2 indoor route methods |
| `services/outdoor_route_planner.dart` | same | `services/` | O | REPRODUCE the 4-strategy cascade verbatim |
| `services/navigation_gps_guard.dart` | same | `services/` | O | REPRODUCE |
| `services/navigation_arrival_detector.dart` | same | `services/` | S | REPRODUCE |
| `services/navigation_deviation_handler.dart` | same | `services/` | O | REPRODUCE — drop indoor reroute branch |
| `services/navigation_state_machine.dart` | same | `services/` | S | REPRODUCE — edge table reduced to reachable states only |
| `services/positioning_engine.dart` → `gpsConfidence` only | `utils/` or `services/` | O | REPRODUCE just that method (`≤5 → 0.9`, `≤15 → 0.7`, else `0.25`) |
| `services/cache_service.dart` | same | `services/` | O | REPRODUCE |
| `services/quick_access_service.dart` | same | `services/` | O | REPRODUCE — keep 6 building seeds, drop legacy `saved_pois` POI migration |
| `services/search_service.dart` (spaces/floors subset) | same | `services/` | S | REPRODUCE — spaces + `My Location`, drop POI/floor index paths |
| `services/campus_route_assets.dart` | same | `services/` | O | REPRODUCE |
| `utils/campus_scope.dart` | same | `utils/` | O | REPRODUCE |
| `utils/category_deriver.dart` → `fromSpaceType` + enum | same | `utils/` | O/S | REPRODUCE — keep 13-member enum, drop `fromPoiType` |
| `utils/with_retry.dart` | same | `utils/` | S | REPRODUCE verbatim |
| `utils/navigation_display.dart` (outdoor leg styles) | same | `utils/` | S | REPRODUCE — keep `outdoorWalking` `0xFF1E88E5` w5 `dot,gap(10)`; drop 4 indoor styles |
| `models/space_model.dart` | same | `models/` | O | REPRODUCE |
| `models/campus_gate.dart` | same | `models/` | O | REPRODUCE |
| `models/user_location.dart` | same | `models/` | O | REPRODUCE |
| `models/position_fix.dart` | same | `models/` | S | REPRODUCE — drop `PositionSource.wifi` arm |
| `models/navigation_state.dart` (outdoor states) | same | `models/` | S | REPRODUCE — keep 10-state enum & edge table shape; unreachable indoor edges removed |
| `models/route_segment.dart` → `outdoorWalking` | same | `models/` | S | REPRODUCE — keep enum name, drop 4 indoor variants |
| `models/navigation_route_model.dart` | same | `models/` | S | REPRODUCE — keep `hybrid`, `partialRouteWarning`, `hasRenderablePath` |
| `models/custom_route_model.dart` | same | `models/` | O | REPRODUCE |
| `models/route_progress.dart` | same | `models/` | O | REPRODUCE |
| `models/campus_asset_status.dart` (outdoor arms) | same | `models/` | S | REPRODUCE — drop `RadioMapStatus`/`FloorplanStatus` |
| `models/quick_access_item.dart` (building arm) | same | `models/` | S | REPRODUCE — keep `type: 'building'`, drop `'poi'` |
| `android/.../MainActivity.kt` | same | native | O/S | REORGANIZE — drop `PositioningBridge` (build + dispose) |
| `android/.../orientation/DeviceHeadingBridge.kt` | same | native | O | REPRODUCE verbatim |
| `assets/*` (3 files) | same | assets | O | REPRODUCE byte-identical |
| `views/main_shell.dart`, `views/map_screen.dart`, `views/search_overlay.dart`, `views/profile_screen.dart` | same | `views/` | S | REPRODUCE — surgical indoor deletion only |
| `widgets/map_top_bar.dart`, `map_controls.dart`, `search_result_card.dart`, `gate_detail_card.dart`, `navigation_*.dart`, `arrival_banner.dart` | same | `widgets/` | S | REPRODUCE — drop the Wi-Fi chip, POI card, floor/POI tabs, indoor status strings |

### 4.2 Removed (REMOVE — INDOOR ONLY)

Dart files: `datasources/native_positioning_service.dart`, `datasources/floorplan_cache.dart`, `datasources/radiomap_cache.dart`,
`models/position_estimate.dart`, `models/floor_model.dart`, `models/floorplan_model.dart`, `models/floor_transition_event.dart`,
`models/poi_model.dart`, `repositories/floorplan_repository.dart`, `repositories/radiomap_repository.dart`,
`repositories/poi_repository.dart`, `services/campus_search_index.dart`, `services/navigation_floor_transition_handler.dart`,
`services/service_query.dart`, `utils/building_containment.dart`, `utils/floorplan_overlay_cache.dart`, `utils/poi_classification.dart`
= **17 Dart files**.

Kotlin: 5. Channels: 2. Permissions: 4. `GoogleMap.groundOverlays`: 1. Indoor `RouteSegmentType`s: 4.
Indoor `NavigationState`s: 5 (`activeIndoor`, `enteringBuilding`, `exitingBuilding`, `floorTransition`, + indoor-only edges).
Indoor user-facing strings: 14 (e.g. `Indoor • Floor $floor`, `Moving to Floor`, `No indoor floors mapped for this building.`,
`No points of interest on this floor.`, `Points of Interest`, `Floors`).

### 4.3 Split by responsibility, behaviour preserved (§14)

| Reference component | Split into | Preserve |
| --- | --- | --- |
| `viewmodels/location_view_model.dart` (830 ln, ~55% outdoor) | `viewmodels/location_view_model.dart` (GPS only: `_ingestGps` gate `460-562`, `requestAndCenter` `694-761`, `start/stopTracking`, `gpsDegraded`) + `models/positioning_source.dart` (the ~30-line arbiter collapses: with no Wi-Fi source, the believed fix **is** the GPS fix) | Raw-preservation (INV-11), staleness→`stale` vs rejection→ignore, 25 m/s outlier hold for 1 tick then accept, 3-poor-tick `gpsDegraded`, `setGpsLocation` test seam through the same gate, idempotent `dispose` |
| `services/campus_asset_loader.dart` (689 ln, 5 pipelines) | `services/campus_asset_loader.dart` (**1 pipeline**: spaces only) | `withRetry(maxRetries: 2)`, `CampusScope.filterSpaces`, selection staleness callback, notify-before/after, `finally` fencing |
| `repositories/cross_building_router.dart` (50 KB) | `services/cross_building_router.dart` (outdoor legs only) | OSRM leg selection, `partialRouteWarning` surfacing, fall-through-to-cascade on throw/`null` |
| `services/campus_route_coordinator.dart` (46 KB) | `services/route_coordinator.dart` (**`requestRouteToBuilding` + `requestRouteToGate`**; the POI entry point dies with indoor) | request-id fence re-checked after every await, `gateEntry: null` for gate-as-destination, ground-floor preference `'0'`, proximity-first entrance, building-center sentinel `'__building_center__'`, hard error (no straight-line) for gates, `adoptNavigatedRoute` single-write choke |
| `viewmodels/space_view_model.dart` (787 ln, god object) | `di/` construction + `viewmodels/space_view_model.dart` (selection + route store only) | selection transition guards, `resetNavigationFields` gated on `!_sessionLive`, all 6 error clearers, `defaultCenter` |
| `viewmodels/navigation_view_model.dart` | unchanged shape; `hasGpsFix` only | facade role, `followMode`, `debugNowOverride` test clock |
| `services/navigation_pilot.dart` / `navigation_session_manager.dart` | outdoor handler subset (drop floor handler + `ensureIndoorGuidance`) | handler order, `resetForStartActive()` sequence, `capture-at-launch / verify-at-commit` fencing |
| `widgets/campus_content_panel.dart` (71 KB) | drop Floor/POI context levels + Services tab; keep Campus/Building/Gate | panel list padding `EdgeInsets.fromLTRB(20,10,20,16)`, `BouncingScrollPhysics`, every loading/error/empty string |
| `config/navigation_config.dart` | 60 → ~36 constants | every retained value verbatim |

### 4.4 Reorganize (REORGANIZE — MVVM ONLY)

All of §1.1 V1–V4, plus: all 17 Riverpod providers from `lib/providers/` are absorbed — pure-service ones
(`cacheServiceProvider`, `searchServiceProvider`) into `di/`, UI-ephemeral ones (`campusPanelTabProvider`,
`panelContextProvider`, `activeServiceProvider`, `navPanelOpenProvider`, `searchQueryProvider`,
`searchCategoryFilterProvider`, `searchBuildingFilterProvider`, `directionOriginProvider`,
`directionDestinationProvider`, `isOnlineProvider`, `cacheVersionProvider`, and the 2 camera bridges
`routeBoundsFitterProvider`/`mapFocusRequesterProvider`) into the owning `viewmodels/`.
Result: no `lib/providers/` folder; dependency direction Views→ViewModels→Repositories/Services→Datasources holds.

### 4.5 Shared infrastructure explicitly preserved (§4 mandate)

`KmzLoader` (regex, stale comment), `ApiConfig` base/dart-define mechanism, `withRetry`, `CacheService` +
`datasetEpoch` migration, `FloorplanOverlayCache`-style capacity-LRU (kept for route data), `SearchService`
revision-counter index, `EntityCategory` 13-member enum, `CategoryDeriver.fromSpaceType`, `navigation_display`
segment→polyline style mapping, `isCampusOverview` / `initialCameraTarget` camera derivation, `isOnlineProvider`
fail-open semantics, `DisplayLocation` hold-during-transition logic, `NavigationSession` monotonic
`(sessionId, routeRevision)` fencing, `NavigationStateMachine` reject-don't-throw policy, `MapConfig.ejustCampusBounds`
(camera-fit only, **never rendered**).

---

## 5. MVVM TARGET

```
lib/
├── config/          api_config, constants, map_config, navigation_config, theme
├── di/              composition root; replaces V1 + providers/service-providers
├── models/          space, campus_gate, user_location, position_fix, navigation_state,
│                    route_segment, navigation_route_model, route_progress,
│                    custom_route_model, campus_asset_status, quick_access_item
├── datasources/     anyplace_api_client, gps_location_service, location_service,
│                    device_heading_service, kmz_loader, gate_policy_config
├── repositories/    space, custom_route, custom_route_graph, campus_gate, navigation
├── services/        outdoor_route_planner, route_coordinator, cross_building_router,
│                    campus_route_assets, campus_asset_loader, navigation_engine,
│                    navigation_state_machine, navigation_session_manager,
│                    navigation_pilot, navigation_gps_guard, navigation_deviation_handler,
│                    navigation_arrival_detector, navigation_segment_tracker,
│                    navigation_route_progress_tracker, navigation_route_scope,
│                    navigation_event_log, cache_service, quick_access_service,
│                    search_service, positioning_engine(gpsConfidence)
├── viewmodels/      location, space, navigation, main_shell, map, search_overlay
├── views/           main_shell, map_screen, search_overlay, profile_screen
├── widgets/         map_top_bar, map_controls, campus_content_panel, gate_detail_card,
│                    search_result_card, navigation_bottom_bar,
│                    navigation_instruction_strip, navigation_status_bar,
│                    arrival_banner, quick_access_toggle_button
├── utils/           campus_scope, category_deriver, with_retry, navigation_display,
│                    navigation_log
└── main.dart
```

Guard: a new `test/architecture/import_boundary_test.dart` with planted-violation self-checks
(forbidden View→datasource, View→repository, View→API, ViewModel→datasource, Model→service, circular imports,
presence of `lib/providers/`, leftover `provider` package).

---

## 6. UI REBUILD REQUIREMENT (§10)

Parity is **structural and textual**, not "similar":

- Same screens, same widget tree order, same `Stack`/`Column`/`Positioned` nesting.
- **Every** user-visible string literal reproduced byte-exact (all ~80 catalogued in discovery, incl.
  `Search buildings, rooms, services…`, `Offline — showing cached campus data`, `Reload Buildings from Server`,
  `Route ready to ${gate.name}`, `Scope: $label`, `Indoor navigation app for E-JUST campus.`).
- Same theme colours (`primary 0xFFD32F2F`, `surface 0xFFFFFFFF`, `cardBorder 0xFFE8E8E8`, `textPrimary 0xFF1A1A1A`,
  `textSecondary 0xFF666666`, `textTertiary 0xFF999999`, `markerSelected 0xFFFFA000`), same radii, same
  `preferredSize Size.fromHeight(64)`, same 44×44 control buttons, same spacers `10/6/10`.
- Same loading/error/empty states with their exact copy, including
  `Could not load buildings - retry from the top bar.`, `No buildings available yet.`,
  `No service types discovered yet - data may still be loading.`, `Nothing matches in this scope yet.`
- Only floor/POI/Wi-Fi UI is deleted.
- Removed: the indoor Wi-Fi chip in `MapTopBar` (`map_top_bar.dart:89-122`), the `Floors`/`POI` panel context
  levels, `PoiDetailCard`, and the indoor arms of `NavigationStatusBar`.

---

## 7. MAP PARITY (§12) — **AND AN UNRESOLVED ISSUE (§5)**

Reproduce verbatim: hybrid map type, all six stock affordances disabled, custom user marker with compass
heading, building + gate markers, KMZ custom-route polylines (`showCampusRoutes` gated by
`NavigationConfig.showCampusRoutesDuringNavigation = false` during navigation), active-route polyline
(`outdoorWalking` `0xFF1E88E5` w5 `dot,gap(10)`, base alpha `0.9`), `animateCamera`/`zoomIn`/`zoomOut`,
`computeRouteCamera` `[14,19]` clamp, `ejustCampusBounds` fit-only, marker-signature caching, `GroundOverlay`
removed.

### 7.1 Documented map issue — NOT fixed, needs your decision

**Symptom:** the previous New App build showed a non-rendering map on a physical Android 10 device.

**Verified root cause — it is not a Flutter defect.** Evidence gathered:

| Check | Result |
| --- | --- |
| `google_maps_flutter` resolved version | Reference `2.18.0` / android `2.19.12`; New App `2.18.1` / android `2.20.0` — **effectively identical**, not the cause |
| Maps key embedded in the built APK? | **Yes.** New App merged release manifest contains `com.google.android.geo.API_KEY` = a real `AIza…` key, `len=39` |
| Is the New App's key the *same* key as the Reference's? | **Yes** — identical SHA-256 (`9692deb0b91e…`), `len=39`, `AIza…` |
| `applicationId` / `namespace` | Reference `eg.edu.ejust.anyplace_campusfind`; New App `eg.edu.ejust.campusfind` — **different** |
| Runtime logcat auth errors | none captured (device disconnected before a screenshot was obtainable) |

**Conclusion:** a Google Maps *Android* API key carries application restrictions (package name + SHA-1
signing cert). The identical key is being used from a **different package name**, which is exactly the
condition under which the Maps SDK refuses to render and logs an authorization failure. Both apps are
debug-signed, so the signing cert is very likely fine; the **package name is the mismatch**.

Per §5 I am **not** inventing a fix. Two candidate resolutions, both requiring your instruction:

- **(A)** Set the New App's `applicationId`/`namespace` to `eg.edu.ejust.anyplace_campusfind` (i.e. match the
  Reference exactly, which is arguably what §3 "same Android/platform behavior" demands). Note this collides with
  the Reference app on-device — they cannot be installed side by side.
- **(B)** Keep `eg.edu.ejust.campusfind` and add it to the key's Android application restrictions in Google Cloud
  Console. This is an **`EXTERNAL DEPENDENCY`** you must execute; I cannot.
- **(C)** Ship a dedicated E-JUST key provisioned for `eg.edu.ejust.campusfind`. Also **`EXTERNAL DEPENDENCY`**.

Also note: the release build is signed with the **debug keystore** (inherited from the Reference). If you
intend a real restricted key, the SHA-1 must match the eventual release certificate — another
**`EXTERNAL DEPENDENCY`**.

---

## 8. DISCARDED — CURRENT NEW APP (§8)

The existing `clients/flutter/ejust_campusfind` implementation is **discarded**, not patched. Preserved
only: repository-level infrastructure unrelated to the failed app implementation (the git repo, docs,
and the workspace layout). Its `FINAL-CAMPUSFIND-REPORT.md`, `MASTER-PLAN.md` §8, and
`test/architecture/import_boundary_test.dart` are superseded by this plan and `FINAL-REBUILD-PARITY-REPORT.md`.

**The four user-reported failures map to concrete causes found in discovery:**

| Reported failure | Actual cause (evidence-based) |
| --- | --- |
| "substantial UI differences" | The previous app was an outdoor-only reimplementation, so the Campus→Building→Floor→POI context ladder, Services tab, gate panel, `PoiDetailCard` and indoor nav chrome were never present. Discovery catalogued the full ladder. |
| "non-rendering map" | §7.1 — API key package-name restriction mismatch. Not a UI or plugin issue. |
| "not the requested application" | Correct; it was never derived from the Reference. |
| MVVM state | It was Riverpod-only, dropping the Reference's `ChangeNotifier` domain controllers and its exact state-transition semantics. |

---

## 9. TEST STRATEGY (§15)

Reference has **50 test files** — the executable specification of its behaviour. Strategy:

1. **Port, do not invent.** For each Reference test, classify indoor-only → drop; shared/outdoor → port verbatim.
2. Named outdoor-anchor tests that **must** survive and lock the reproduced behaviour:
   `custom_routes_test` (KMZ graph/Dijkstra/splice), `rerouting_correctness_test`, `termination_test`,
   `gps_quality_test`, `route_rendering_representation_test`, `route_store_test`, `retarget_test`,
   `gate_selection_state_test`, `campus_gate_test`, `shell_gate_test`, `search_filter_test`,
   `search_directions_test`, `quick_access_test` (building arm), `camera_math_test`, `api_config_test`,
   `server_config_test`, `service_query_test` (N/A — indoor), `browsing_neutrality_test`, `race_battery_test`,
   `session_identity_test`, `remediation_crossbuilding_test` (outdoor legs), `ejust_scope_test`,
   `rendering_consistency_test`, `integration_journey_test`, `live_integration_smoke_test`,
   `navigation_ui_test`, `navigation_bottom_bar_test`, `arrival_test`, `handoff_guidance_test` (O/I),
   `campus_panel_test`, `widget_test`, `service_query_test`, `navigation_state_machine_test`.
3. **Indoor-only tests to delete:** `floor_transition_test`, `radiomap_lifecycle_test`,
   `floorplan_download_resilience_test`, `floorplan_overlay_cache_test`, `floorplan_state_pipeline_test`,
   `position_estimate_boundary_test`, `same_building_route_representation_test`, and the indoor halves of
   `navigation_state_machine_test`, `arrival_test`, `handoff_guidance_test`, `browsing_neutrality_test`,
   `quick_access_test`, `remediation_crossbuilding_test`.
4. **New only where the split creates genuinely new surface:** the architecture import-boundary guard, and
   tests proving the collapsed arbiter yields the identical `PositionFix` the Reference produced outdoors.
5. Copy `test/helpers/fake_google_maps_platform.dart` (required for map widget tests).
6. No coverage-driven tests.

---

## 10. VALIDATION GATES (§17, §18, §19)

1. `flutter analyze` → clean
2. `flutter test` → all pass
3. `dart format --set-exit-if-changed .` → clean
4. `flutter build apk --release` → succeeds, key embedded
5. **Reference integrity:** re-hash 238 files, diff against `ref_baseline_phase0.txt` → **0 changed, 0 missing**
6. **Parity matrix** (§18) with statuses `IDENTICAL | REMOVED — INDOOR | DIFFERENT | MISSING | BROKEN | UNKNOWN`;
   every non-`IDENTICAL`/`REMOVED` item explained
7. `FINAL-REBUILD-PARITY-REPORT.md` (§20, 16 required sections), including an honest account of the §7.1 map issue

---

## 11. DECISIONS — RESOLVED, IMPLEMENTATION AUTHORISED

| # | Decision | Resolution |
| --- | --- | --- |
| **D1** | Map key / appId | **Match the Reference `applicationId` exactly** → `eg.edu.ejust.anyplace_campusfind`. The existing Maps key therefore works unmodified. **Accepted consequence:** the New App can no longer be installed alongside the Reference on one device — they share one package identity. On-device comparison must therefore be sequential (install one, test, swap), not side by side. |
| **D2** | State mechanism | **Keep the 3 domain controllers as `ChangeNotifier` exactly as in the Reference** (`LocationViewModel`, `SpaceViewModel`, `NavigationViewModel`) to preserve state-transition semantics verbatim. **Absorb** the 17 Riverpod providers: pure-service ones → `di/`, UI-ephemeral ones → the owning `viewmodels/`. `lib/providers/` is removed. The `provider` package stays; `flutter_riverpod` is dropped. |
| **D3** | Dead permissions | **Preserve verbatim.** `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_LOCATION` stay in the manifest even with zero consumers. Recorded in the parity matrix as `IDENTICAL (unused)`. |
| **D4** | Network security config | **Reproduce verbatim + document.** Ship `res/xml/network_security_config.xml` unreferenced, keep `usesCleartextTraffic="true"`. Recorded in the parity report as a known unintended-permissive config, deliberately preserved. |
| **D5** | Package identity | `pubspec.yaml` → `name: ejust_campusfind` with a real description. The Android `applicationId`/`namespace` is `eg.edu.ejust.anyplace_campusfind` (per D1). The `description` delta is recorded in the parity matrix as `DIFFERENT`. |
| **D6** | Release signing | **Keep the debug keystore**, matching the Reference, so the build stays installable and D1 works immediately. Production signing is a documented `EXTERNAL DEPENDENCY`. |

### 11.1 Consequences to carry into implementation

1. **D1 forces the Android identity to the Reference's.** `namespace`, `applicationId`, the Kotlin source root
   (`android/app/src/main/kotlin/eg/edu/ejust/anyplace_campusfind/`), and the MethodChannel/EventChannel names
   (`eg.edu.ejust.anyplace_campusfind/heading_stream`) are all reproduced exactly. This is also what makes the
   `heading_stream` channel name correct without any remapping.
2. **D1 means the two apps are mutually exclusive on device.** Uninstall/Reference-swap is required to A/B them.
   Never attempt to install both; the second install will silently fail to replace cleanly.
3. **D2 keeps `provider` and drops `flutter_riverpod`.** The architecture guard forbids a `providers/` directory and
   any `flutter_riverpod` import; `ChangeNotifier` in `viewmodels/` is the sanctioned pattern.
4. **D5 means the Dart package name and the Android package name intentionally differ.** `ejust_campusfind` is the
   Dart package; `eg.edu.ejust.anyplace_campusfind` is the installed app. This is deliberate, not an oversight.

---

## 12. EXECUTION ORDER

Per §21 the plan is now approved. Implementation proceeds in this order, verifying after each stage:

1. Re-verify Reference integrity (must be 238/238, 0 modified).
2. Discard the rejected New App implementation; scaffold a clean project.
3. Apply D1–D6 to the Android/platform layer (Gradle, manifest, Kotlin, resources, pubspec).
4. Copy the Reference's shared + outdoor `lib/` files verbatim (copy-then-strip, which is what makes parity achievable).
5. Delete the indoor-only inventory (§3).
6. Strip indoor branches from the 8 split components (§4.3) and apply the 4 MVVM corrections (§1.1, §4.4).
7. Port the tests per §9 and add the architecture guard.
8. Run the §10 validation gates; produce the parity matrix and `FINAL-REBUILD-PARITY-REPORT.md`.

