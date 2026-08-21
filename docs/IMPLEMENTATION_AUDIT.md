# CampusFind (anyplace_campusfind) — Post-Implementation Audit

**Date:** 2026-08-12
**Audited against:** `docs/CAMPUSFIND_PLAN.md` (original approved scope: MVP table, API strategy, phases 0–7, bugs in scope).
**Method:** Read every file under `clients/flutter/anyplace_campusfind/lib/`, cross-checked backend contracts against `server/conf/api.routes` and `server/app/controllers/*` + `server/app/datasources/SCHEMA.scala`, re-ran `flutter analyze`, `flutter test` (62 passing), and `flutter build apk --debug` (success). Trusted git/source/tests over the completion claims in the plan; conclusions below are independently derived.

---

## Summary Verdict

**NEEDS FIXES** — overall completion **≈ 86%**.

The app implements the overwhelming majority of the approved MVP correctly and all 62 tests pass. However, two functional bugs remain against explicit plan requirements: (1) **Recent Waypoints is dead** — the feature is fully implemented in `CacheService` but never wired to any UI action, so the Home list is always empty; (2) **entrance selection ignores distance** — plan 5.3 requires the *nearest* `is_building_entrance` POI, but the code always picks `entrances.first`. Both are small, isolated, low-risk fixes (Section 10). One documented external dependency (self-hosted outdoor tile server) is also outstanding.

---

## 1. Requirement-by-Requirement Classification

Legend: ✅ implemented · ⚠️ partially implemented / deviation · ❌ missing · 🔴 implemented but functionally broken.
For every non-✅ item: **Required / Implemented / Missing / Fix**.

### 1.1 MVP features (plan lines 20–34)

| # | Requirement | Status |
|---|---|---|
| F1 | Campus selection — multi-campus, pick on first launch, stored locally | ✅ |
| F2 | Home screen — greeting, search bar, quick access cards, recent waypoints | ⚠️ |
| F3 | Campus map — `flutter_map` + self-hosted outdoor tiles + tiled indoor floorplans | ⚠️ |
| F4 | Dynamic POI filters — chips derived from backend data (not hardcoded) | ✅ |
| F5 | Cross-entity search — client-side across all cached Spaces + POIs | ✅ |
| F6 | Building detail — hero placeholder, floors directory, accessibility, navigate button | ✅ |
| F7 | Professor profile — parsed name, title, department, office hours | ✅ |
| F8 | Indoor routing — Dijkstra via `/api/navigation/route`, polylines per floor | ✅ |
| F9 | Outdoor routing — OSRM public demo, GPS → entrance polyline | ✅ |
| F10 | Combined navigation — outdoor leg (blue) + indoor leg (red) in single view | ✅ |
| F11 | Wi-Fi positioning — server-side via `/api/position/estimate` (requires fingerprint data) | ✅ |
| F12 | Floorplan tiles — download zip → extract → `FileTileProvider` | ✅ |
| F13 | Recent waypoints — local persistence (no API) | 🔴 |

**F2 (Home screen) — ⚠️**
- **Required:** Home shows greeting, search bar, dynamic quick-access cards, and a recent-waypoints list (local persistence).
- **Implemented:** Greeting, search entry, dynamic quick-access cards (from `CategoryDeriver`), and a Recent Waypoints UI list populated via `CacheService.loadRecentWaypoints()`.
- **Missing:** Nothing writes to the list — `addRecentWaypoint()` (`lib/services/cache_service.dart:160`) is never called from app code (only from `test/cache_service_test.dart`). Every waypoint navigation leaves the list empty.
- **Fix:** Call `addRecentWaypoint(puid)` on every waypoint navigation (e.g. in `openPoi`/`openSearchResult` in `lib/screens/detail_navigation.dart`).

**F3 (Campus map) — ⚠️**
- **Required:** `flutter_map` base layer uses a **self-hosted** tile server serving E-JUST campus outdoor tiles.
- **Implemented:** `flutter_map` base layer + tiled indoor floorplan overlay both work (Carto Positron fallback template in `lib/config/constants.dart`).
- **Missing:** The self-hosted tile server was never stood up (plan's own external-dependency table). This is an **external dependency**, not an app-code defect; the plan explicitly lists Carto Positron as the temporary fallback (risk table).
- **Fix:** Stand up the tile server (infrastructure) and swap the template in `lib/config/constants.dart`. No app-code change needed.

**F13 (Recent waypoints) — 🔴** (same root cause as F2 element)
- **Required:** Navigating to a POI/building persists it; Home lists recent waypoints across sessions.
- **Implemented:** Full storage layer exists — `addRecentWaypoint`/`loadRecentWaypoints`/`clearRecentWaypoints` backed by SharedPreferences, plus the Home list UI.
- **Missing:** The write path is never invoked → the persisted list is always empty and Home renders nothing. The feature is dead in practice.
- **Fix:** Wire `addRecentWaypoint` into navigation entry points (see F2 fix).

### 1.2 API endpoints (plan lines 177–189)

| # | Endpoint | Status |
|---|---|---|
| A1 | `POST /api/mapping/space/public` — list all spaces | ✅ |
| A2 | `POST /api/mapping/campus/get` — campus buildings | ✅ |
| A3 | `POST /api/mapping/floor/all` — floors | ✅ |
| A4 | `POST /api/mapping/pois/space/all` — POIs | ✅ |
| A5 | `POST /api/mapping/pois/search` — search POIs | ⚠️ |
| A6 | `POST /api/floortiles/zip/:buid/:floor` — floorplan zip | ✅ |
| A7 | `POST /api/navigation/route` — indoor route | ✅ |
| A8 | `POST /api/navigation/route/coordinates` — route from coords | ✅ |
| A9 | `POST /api/position/estimate` — Wi-Fi positioning | ✅ |
| A10 | `POST /api/position/predictFloorAlgo1` — floor prediction | ⚠️ |
| A11 | `GET router.project-osrm.org/route/v1/driving/...` — outdoor | ✅ |

**A5 (`pois/search`) — ⚠️**
- **Required:** Plan lists server POI search in the data flow.
- **Implemented:** `ApiService.searchPois()` exists (`lib/services/api_service.dart:83`) and is covered by a unit test.
- **Missing:** Never called from app code. Search is fully client-side over the cached cross-entity index (MVP F5), so the endpoint is redundant for the shipped UX.
- **Fix:** Either remove the dead method, or keep as documented future API surface. No functional impact.

**A10 (`predictFloorAlgo1`) — ⚠️**
- **Required:** Plan lists floor prediction as part of positioning API surface.
- **Implemented:** Endpoint constant `ApiConfig.positionPredictFloor` (`lib/config/api_config.dart:31`).
- **Missing:** No call site, no model, no tests. Positioning relies on `position/estimate` only (F11).
- **Fix:** Remove the dead constant or implement a floor-prediction flow when fingerprint data becomes available. No functional impact.

### 1.3 Phase tasks

| Phase | Status | Notes |
|---|---|---|
| 0 — Bug fixes & infrastructure | ❌ | Not started (plan itself marks ⏸). Tasks 0.1–0.5 are Logger/backend fixes in `clients/android/` + `server/` (outside the Flutter app; `clients/android/` is excluded legacy code per AGENTS.md). 0.6 tile server and 0.7 data-collection guide are external/infra. |
| 1 — Foundation | ✅ | All 8 tasks; deps, structure, `ApiConfig`, Dio client with gzip, manifest permissions, Riverpod skeleton, map proof. |
| 2 — Data layer | ✅ | All 8 tasks; models mirror backend fields (verified vs `SCHEMA.scala`), bulk fetch, `DescriptionParser`, `CategoryDeriver`, `TileService`, `DistanceCalculator`. (Dead method `searchPois` — see A5.) |
| 3 — Core screens | ✅ | All 7 tasks; campus selection, Home, Map (markers, filter chips, floorplan overlay, floor switcher), Search, bottom nav, clustering (grid-bucket < zoom 16), indoor/outdoor zoom switching (≥19). |
| 4 — Detail screens | ✅ | All 4 tasks; Building Detail (hero placeholder, floors directory, room search, accessibility, navigate), Professor Profile (parsed name/title/dept/office hours), tap-through routing. |
| 5 — Navigation | ⚠️ | Tasks 5.1, 5.2, 5.4, 5.5, 5.6, 5.7 ✅. **Task 5.3 deviation** (see below). |
| 6 — Positioning | ✅ | All 6 tasks; GPS blue dot, Wi-Fi scanning, server positioning, combined position stream, nearest-location sheet, graceful fallbacks. |
| 7 — Polish | ✅ | All 6 tasks; error/empty/loading gates + Retry, offline snapshot + banner, `TileService.ensureTiles()` offline floorplans, Material 3 theming, 62 tests, README + plan record. |

**Phase 5 task 5.3 (find nearest `is_building_entrance` POI) — ⚠️/🔴**
- **Required:** "find nearest `is_building_entrance` POI" and route outdoor leg GPS → that entrance, indoor leg entrance → dest.
- **Implemented:** Entrance POIs are found by filtering `pois_type == is_building_entrance` and the no-entrance fallback (route from building center) works.
- **Missing:** Distance is never considered — `entrances.first` is used (`lib/providers/route_provider.dart:91,117,158`). Cache order is not geographical; the outdoor leg can end at the wrong entrance of a multi-entrance building.
- **Fix:** Select the entrance with minimum Haversine distance from the user's GPS position (reuse `DistanceCalculator`).

### 1.4 NOT-in-MVP items (plan lines 36–48) — ✅ correctly excluded

Auth/login, bookmarks/Profile tab, push notifications, building photos (hero placeholder used instead), iOS, voice/step-by-step guidance, real-time crowd data, cafeteria menus, time-based heatmaps, self-hosted OSRM (public demo used). All absent from the app as specified.

---

## 2. Bugs Found

### Critical (🔴)
1. **Recent Waypoints dead** — `addRecentWaypoint` (`cache_service.dart:160`) has no call site in `lib/`. Home's recent-waypoints list is always empty (F2/F13). Only test references it.
2. **Wrong entrance selected for routing** — `route_provider.dart:91,117,158` use `entrances.first` instead of the nearest entrance (plan 5.3). Multi-entrance buildings produce suboptimal/incorrect outdoor+indoor legs.

### Non-critical (⚠️)
3. **Unused API surface** — `ApiService.searchPois` (`api_service.dart:83`), `ApiConfig.positionPredictFloor` (`api_config.dart:31`), `ApiConfig.floorTilesBase` (`api_config.dart:39`) are defined but have no call sites in `lib/`. Dead code / documented-only surface.
4. **Self-hosted outdoor tiles not set up** — external dependency; Carto Positron fallback in use (documented and mitigated in the plan).

### Original in-scope bugs (plan "Bugs to Fix" table)
All five (Logger auth mismatch, hardcoded server URL, MAP/MMSE sigma bug, 10K measurement cap, `getByFloorsAll()` URL bug) are in `clients/android/` and `server/` — Phase 0, outside this Flutter app's scope. **Not fixed, not regressed.** The app depends on none of them.

---

## 3. APIs / Features Implemented (backend contract verification)

App-side calls were checked against server source, not just route files:

- **Bulk load:** `space/public` returns `{spaces: [...], buildings: [...]}` (same list twice) — app parses `spaces` first then falls back to `buildings`. ✅ `MapSpaceController.scala:245`.
- **Route:** `navigation/route` returns `{num_of_pois, pois:[{lat, lon, puid, buid, floor_number, pois_type}]}` — matches `NavigationRoute`/`RoutePoint` exactly. ✅ `NavigationController.scala:150`, `NavResultPoint.toJson`.
- **Positioning:** `position/estimate` expects `APs` serialised as a **JSON string** (not object) + `algorithm_choice` string, returns `{lat, long}` — matches `PositioningService`/`PositionEstimate`. ✅ `PositioningController.scala:120,143`.
- **Floorplan tiles:** `POST /api/floortiles/zip/:buid/:floor_number` returns a zip; extracted `static_tiles/` layout served by `LocalFloorplanTileProvider`. ✅ `server/conf/api.routes`.
- **Campus:** fetched per-cuid via `campus/get`; campuses enumerated via `--dart-define=CAMPUS_IDS` because **no public list-campuses endpoint exists** (confirmed). Documented deviation, not a defect.

---

## 4. Architectural Decisions (audit focus items)

| Focus item | Finding |
|---|---|
| Map + POI filters | ✅ Dynamic `CategoryDeriver`-driven chips on Map and Search; POI visibility gated by building selection + zoom ≥ 19. |
| Indoor floorplan tiles | ✅ Zip download → extract → cached local tiles; `ensureTiles()` serves from disk offline. |
| Indoor routing | ✅ Server Dijkstra via `/navigation/route`; red polyline per floor; entrance bug above. |
| Wi-Fi positioning | ✅ Scans → `position/estimate`; graceful "Positioning unavailable" when no radiomap data. External prerequisite (fingerprint data) never collected. |
| GPS outdoor navigation | ✅ `geolocator` stream → blue dot + nearest-location sheet; OSRM outdoor leg with straight-line fallback. |
| Search + client caching | ✅ Full cross-entity client-side index with caching + offline snapshot; server `pois/search` intentionally unused. |
| Campus selection | ✅ First-launch picker persisted to SharedPreferences; restored in `main.dart`. |
| Description parsing | ✅ `\|`-delimited parsing of POI/space/floor descriptions into professor, building, floor metadata with fallbacks. |
| Backend API reuse | ✅ No new endpoints, no schema changes; contracts verified above. |
| Android-only MVP | ✅ Single-platform Flutter app; `wifi_scan`/`geolocator` used as expected. |

---

## 5. Tests

**62/62 passing.** Coverage by file:

| File | Focus |
|---|---|
| `test/models_test.dart` | model field mapping |
| `test/utils_test.dart` | `DescriptionParser`, `CategoryDeriver`, `DistanceCalculator` |
| `test/api_service_test.dart` (8) | endpoint parsing, APs-as-JSON, byte response, 5xx/connection error mapping |
| `test/tile_service_test.dart` (4) | extract, cache-hit no re-download, missing cache, broken archive |
| `test/cache_service_test.dart` | cache + recent-waypoints storage |
| `test/search_provider_test.dart` | cross-entity search index |
| `test/route_test.dart` (9) | OSRM parsing + combined/fallback/error/clear logic |
| `test/campus_selection_test.dart` (2) | error → Retry → recovery, empty state |
| `test/detail_screens_test.dart` | building detail, professor profile, room-search no-match widget test |
| `test/shell_gate_test.dart` (4) | bulk-load/empty/offline gates + nav-bar gating |
| `test/widget_test.dart` | smoke |

Gaps: no test asserts that a waypoint is actually added on navigation (would catch bug #1), and none asserts nearest-entrance selection (would catch bug #2).

---

## 6. Limitations & External Dependencies

- **Fingerprint data** for Wi-Fi positioning — not collected; feature falls back gracefully. `EXTERNAL DEPENDENCY`.
- **Self-hosted outdoor tile server** — not set up; Carto Positron fallback used. `EXTERNAL DEPENDENCY`.
- **Official hostname** (`anyplace.ejust.edu.eg`) is illustrative (decision D-07); server URL injected via `--dart-define=SERVER_URL`. No global domain replacement done.
- **OSRM public demo** — rate-limited; no client-side route caching.
- **Phase 0 backend/Logger bugs** — outstanding, outside Flutter app scope.

---

## 7. Recommended Fixes (before declaring the MVP done)

1. **Wire recent waypoints (critical).** Call `addRecentWaypoint(puid)` in `lib/screens/detail_navigation.dart` (`openPoi`/`openSearchResult`) so Home's list populates and persists. Add a widget/unit test.
2. **Nearest entrance (critical).** In `route_provider.dart`, sort candidate entrances by `DistanceCalculator` distance to the user GPS position and pick the minimum instead of `entrances.first`. Add a test with two entrances.
3. **Prune dead API surface (non-critical).** Delete `searchPois`, `positionPredictFloor`, `floorTilesBase` or document them as reserved.
4. **Tile server (external).** Stand up the tile server and update the base-layer template.

---

## 8. Final Verdict

**NEEDS FIXES.** ~86% of the approved scope is complete, verified (62 tests, clean `flutter analyze`, debug APK builds), and the architecture is sound. The two 🔴 functional bugs (dead recent-waypoints, non-nearest entrance selection) directly violate explicit plan requirements (F13 / 5.3) and are trivial, isolated fixes with test coverage to add. No re-architecture or backend changes are required. After items 1–2 of Section 7 are addressed, this audit should be re-run to confirm **READY**.
