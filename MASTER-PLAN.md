# MASTER PLAN — EJUST CampusFind (outdoor-only Flutter app)

**Status:** Planning complete. Not implemented. No project created.
**Reference project (READ-ONLY):** `clients/flutter/anyplace_campusfind`
**This document is a record of the plan agreed during the planning session. It is not a new plan.**

---

## 1. Project identity

| Item | Value |
|---|---|
| Directory | `clients/flutter/ejust_campusfind` (sibling of the reference) |
| Dart package (pubspec `name`) | `ejust_campusfind` |
| Android `namespace` | `eg.edu.ejust.campusfind` |
| Android `applicationId` | `eg.edu.ejust.campusfind` |
| Launcher label | **EJUST CampusFind** |
| Creation command | `flutter create --project-name ejust_campusfind --org eg.edu.ejust .` then correct namespace/applicationId and the Kotlin `MainActivity` package to `eg.edu.ejust.campusfind` |
| Dart SDK | `^3.12.2` |
| Java / Kotlin target | 17 |

`anyplace` is deliberately dropped from the identity so the new APK cannot collide with the reference build on a device.

---

## 2. Scope and exclusions

### In scope
- Outdoor GPS positioning on the E-JUST campus.
- Building-level navigation using each building's outdoor coordinates.
- Campus road graph routing, campus gates, OSRM public-road legs.
- Buildings browsing, Places (Services) browsing, Gates browsing, search, turn-by-turn style outdoor navigation.

### Explicitly excluded
- Floors, floorplans, rooms, indoor POIs, indoor entrance data.
- Indoor positioning: Wi-Fi/KNN, radiomaps, fingerprints, native/Kotlin positioning code.
- Indoor routing, floor transitions, building containment / inside-outside detection.
- Indoor disk caches (floorplan/POI/radiomap caches).
- Indoor Android permissions and APIs.
- Quick Access (pinned buildings) — removed entirely, including its six seeded BUIDs and persistence.
- The legacy `clients/android`, `clients/deprecated`, `docker/`, and the tiler pipeline.

### Android permission set (final)
`INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` only.
Removed: `ACCESS_BACKGROUND_LOCATION`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `usesCleartextTraffic`, and `network_security_config.xml`.

---

## 3. Locked decisions (R1–R7)

| # | Decision |
|---|---|
| R1 | Folder/pubspec `ejust_campusfind`, namespace + applicationId `eg.edu.ejust.campusfind`, label **EJUST CampusFind** |
| R2 | Approve F1–F14 (F13 rewritten, see §4) |
| R3 | Gates are a top-level entity: own tab, own search category, own detail, routing target |
| R4 | Quick Access removed entirely |
| R5 | **Services = "Places"** — a service-browsing entry point over backend buildings. No category tiles, because the backend supplies no category field. **Gates are not a Services tile.** No invented facilities dataset. Client-only; a future server `space_category` would be adopted in one place. |
| R6 | Public OSRM default, `--dart-define=OSRM_URL=…` override, campus graph first |
| R7 | Buildings with bad coordinates: listed and searchable, warning badge shown, **Navigate disabled** with an explanation |

---

## 4. Approved deviations F1–F14 (from the reference)

| # | Deviation |
|---|---|
| F1 | Single routing planner replacing both divergent cascades in the reference coordinator |
| F2 | Corrected route-progress math (distance-along-path vs. segment index) |
| F3 | Explicit route-quality enum surfaced in the UI: `customGraph` / `hybrid` / `osrmSpliced` / `osrm` / `approximate` |
| F4 | `SERVER_URL` honored everywhere; zero hardcoded hosts |
| F5 | Normal Google basemap, no custom styles, max zoom 20 as a configuration constant |
| F6 | Search = Buildings + Gates, filter applied **before** top-K, per-type limits (fixes the reference's post-filter defect) |
| F7 | Bad-coordinate policy per R7 |
| F8 | Manifest restricted to the three permissions above; no cleartext; no network security config |
| F9 | All indoor subsystems deleted (floors, POIs, floorplans, radiomaps, Wi-Fi/KNN, containment, transitions, caches, Kotlin positioning) |
| F10 | Riverpod only; `provider` removed |
| F11 | God classes split into feature-scoped ViewModels (reference: `SpaceViewModel`, `CrossBuildingRouter`) |
| F12 | Quick Access removed |
| F13 | Services = Places; building detail surfaces `description` / `address` / `url` / `bucode`; indoor-derived service types deleted; no facilities asset |
| F14 | Dependency and configuration hygiene, single source of truth, import-boundary test |

---

## 5. Backend data-source decisions

### The only backend endpoint used
`{SERVER_URL}/api/mapping/space/public`

- Envelope: `{"spaces": [...], "buildings": [...]}` (duplicate key; read `spaces`).
- Response is gzip-encoded.
- Server filters `is_published == "true"` and strips `geometry`, `owner_id`, `co_owners`, `_id`.
- Evidence: `server/app/controllers/MapSpaceController.scala:244-245`, `server/app/datasources/MongodbDatasource.scala:1467-1482`.

### Verified space field set
`server/app/models/Space.scala:56-68` — `buid, is_published, name, description, url, address, coordinates_lat, coordinates_lon, bucode, space_type`. `cleanupJson` (`:205-212`) drops `bucode` / `address` / `description` / `url` when empty or `"-"`.

### Verified live E-JUST dataset
`docs/ui-ux-redesign/ejust-server-migration-report.md:24-25,35` — `POST /api/mapping/space/public {}` → 200, **6 buildings**: B7, E-JUST Blue Hall, Food court, National Bank branch, E-JUST Administrative Building, E-JUST Library. Fields present: `buid, name, coordinates_lat/lon, is_published, space_type`. No `cuid`; `description` / `address` / `url` / `bucode` are not populated.

### There is no building category or service field
- `server/app/datasources/SCHEMA.scala:76-77` — `space_type` is the only type field, a closed enum `Array("building", "vessel")`.
- `server/public/anyplace_architect/controllers/BuildingController.js:219-222` — the Architect type dropdown is exactly `["building", "vessel"]`. An architect cannot publish "library", "bank", or "cafeteria" as a type.
- `lib/utils/category_deriver.dart:164-173` `fromSpaceType()` is therefore dead code against this backend; the reference's real categories come from `pois_type` matching, i.e. indoor data.
- Conclusion: `Bank`, `Library`, `Food court` are all `space_type: "building"` and are distinguishable only by the `name` free-text.

### Data rules
- Backend buildings are the single source of truth. No hardcoded building list.
- Newly published valid backend buildings must appear automatically.
- No fabricated coordinates, categories, or facilities.

### Local assets (copied/adapted from the reference, data not code)
| Asset | Verified facts |
|---|---|
| `assets/navigation/ejust roads.kmz` (from `university roads.kmz`) | 26 placemarks = 1 Point + 25 LineStrings, 68 coordinates |
| `assets/config/ejust gates.kmz` (from `university gates.kmz`) | 4 gates |
| `assets/config/gate_policy.json` | G2 enabled; G1/G3/G4 disabled |

Gate snap distances to the road graph, preserved: G1 5.1 m, G2 27.7 m, G3 16.1 m, G4 202.8 m.
Road graph topology, preserved: 52 vertices, 64 edges, 28 junctions, 1 connected component.

### Map asset workflow
Google My Maps → export KMZ → place the file in `assets/`. **No in-app map/asset editors.**

---

## 6. Data model

```dart
class CampusBuilding {           // 1:1 with the backend space record
  String buid; String name;
  double lat; double lon;        // coordinates_lat / coordinates_lon
  String? description, address, url, bucode;   // present-if-populated, never fabricated
  bool isPublished;
  SpaceType spaceType;           // enum { building, vessel } — mirrors fSpaceTypes
  String? lastModified, cuid;
}
```

**No `category` field exists in this model.** No new bundled facilities dataset (toilets, water points, parking, shade, benches, ATM, noticeboards) is created — no such dataset exists in the backend or the reference, and fabricating one is forbidden.

Other models: `campus_gate`, `outdoor_route`, `route_progress`, `gps_sample`.

---

## 7. Services, Places, and Gates

### Services = "Places"
- A service-browsing entry point whose entries **are** the real backend buildings.
- Each entry opens the building detail; Directions routes to that building's outdoor coordinate — identical to the Buildings flow.
- **No category tiles.** The backend supplies no category data, so any category taxonomy would be invented.
- The reference already reached this conclusion — `lib/widgets/campus_content_panel.dart:589-592` ("CORRECTION PASS (#2) … are real E-JUST BUILDINGS from the server … No fake entities").
- One static scope line explains that the dataset is outdoor/building-level; no per-category fake empty states.

### Gates — a separate entity
- Own top-level tab, own search category, own detail card, and routing participation (OSRM leg target when enabled).
- **Not** a Services tile and **not** a replacement for the Services section.
- Enabled/disabled state comes from `gate_policy.json`.

### Panel tabs
**Buildings · Places · Gates · About**

Buildings and Places may share the same cached `CampusBuilding` list but remain distinct browsing surfaces.

---

## 8. Architecture

- **Strict clean MVVM.** Views contain no business logic; ViewModels expose immutable state and intents; domain services are pure; data layer owns I/O.
- **Riverpod only** (`flutter_riverpod`, no code generation). `provider` is removed entirely.
- God classes split into feature-scoped ViewModels.
- Single routing planner; no duplicated cascades.
- Single configuration source of truth.
- An architecture import-boundary test enforces layer direction.

### Project structure

Folders are named for the single responsibility they hold, not for a technical
layer abstraction. `models/` is "data shapes", `services/` is "business logic",
`datasources/` is "where bytes come from", and the arrow between any two folders
is checked by `test/architecture/import_boundary_test.dart`.

```
clients/flutter/ejust_campusfind/
  pubspec.yaml
  analysis_options.yaml
  android/...
  assets/
    navigation/ejust roads.kmz
    config/ejust gates.kmz
    config/gate_policy.json
  lib/
    main.dart
    config/        app_config.dart, theme.dart
    utils/         result.dart, geo.dart, text_fold.dart
    models/        building_snapshot, campus_building, campus_gate, campus_map_data,
                   gate_policy, gps_sample, kmz_placemark, location_access,
                   location_source, map_state, navigation_state, outdoor_route,
                   public_road_leg, route_graph, route_progress, route_quality,
                   routing_gate, search_query
    datasources/   anyplace_api_client, asset_loader, campus_roads_loader,
                   connectivity_source, gate_policy_parser, geolocator_location_source,
                   kmz_parser, osrm_client, public_road_router
    services/      arrival_detector, heading_tracker, navigation_gps_guard,
                   navigator_controller, progress_tracker, reroute_service,
                   route_planner, search_index
    repositories/  building_repository, campus_map_repository, gate_repository
    viewmodels/    location, map, navigation, search view models
    views/         map/ buildings/ places/ gates/ search/ navigation/ shell/ about/
    widgets/       panel_sections.dart
    di/            providers.dart            (composition root)
  test/
    unit/
    widget/
    architecture/import_boundary_test.dart
```

Three invariants the guard enforces, each with its own test:

1. `models/` never imports `datasources/` or `services/` - a value object cannot
   reach back out to fetch or compute.
2. `viewmodels/`, `views/` and `widgets/` never import `datasources/` -
   presentation reads repositories, never the API client, the GPS plugin or the
   KMZ parser.
3. `views/` and `viewmodels/` reach `di/` only through `di/providers.dart` -
   they may read a provider, never wire a datasource themselves.

`models/location_source.dart` holds the `LocationSource` / `ConnectivitySource`
contracts rather than an implementation, which is what lets a ViewModel depend
on "a location source" without importing a datasource. The geolocator and
connectivity implementations stay in `datasources/`.

---

## 9. Routing and navigation requirements

### Routing cascade (single planner, in order)
1. Custom campus road graph (Dijkstra).
2. Hybrid: OSRM to the campus gate / graph endpoint, then campus graph to the destination.
3. OSRM with a custom tail splice.
4. OSRM only.
5. Straight-line fallback, explicitly flagged `approximate`.

Every produced route carries a `RouteQuality` value, surfaced in the UI so the user is never misled.

### Navigation behavior (preserved from the reference's outdoor path)
- Outdoor GPS only; no indoor sub-state.
- GPS quality thresholds.
- Instruction strip, progress, distance remaining, ETA.
- Camera follow.
- Off-route detection and rerouting.
- Arrival detection.
- R7: Navigate is disabled for buildings with missing/invalid outdoor coordinates, with a visible explanation.

---

## 10. Map, location, and search requirements

- **Normal Google basemap.** No custom map styles.
- Max zoom 20, defined as a configuration constant.
- Markers for buildings and gates; route polylines.
- Location: `geolocator` GPS stream, quality thresholds, device heading, permission flow, connectivity awareness.
- Campus centroid `30.859877, 29.563241` used only as a fallback center.
- **Search:** Buildings + Gates as two result categories; filters applied **before** top-K; per-type result limits; per-category counts; distinct empty and no-match states. POI/floor indexing is deleted.

---

## 11. Dependencies and configuration

### Dependencies
`flutter_riverpod` (^2.6.1, no code generation), `google_maps_flutter` (^2.10.0), `geolocator` (^13.0.2), `http`, `archive` (KMZ), plus `shared_preferences` / `path_provider` only if actually used. `provider` (^6.1.2) is removed. Unused dependencies are dropped.

### Build-time configuration (all via `--dart-define`, defaults in `app_config.dart`)
| Define | Default |
|---|---|
| `SERVER_URL` | `https://map.beout.ai` |
| `OSRM_URL` | `https://router.project-osrm.org` (HTTPS only; public OSRM) |
| `CAMPUS_CUID` | `ejust` |
| `CAMPUS_NAME` | `E-JUST` |
| `MAPS_API_KEY` | from `android/local.properties` or environment, injected via manifest placeholder |

No hardcoded hosts anywhere in `lib/`.

---

## 12. Implementation phases and responsibilities

| Phase | Responsibilities | Exit criteria |
|---|---|---|
| **P0 — Skeleton** | Create the project; set identity, namespace/applicationId, `MainActivity` package; manifest and permissions; minimum dependencies; architecture test | `flutter analyze` clean; no indoor token anywhere in the project; architecture test green |
| **P1 — Core utilities** | `AppConfig`, geo math (haversine, bearing, snapping), KMZ/KML parsing, `Result` | Unit tests pass |
| **P2 — Campus map data** | Roads KMZ → `RouteGraph` with Dijkstra; gates KMZ; `gate_policy.json`; preserve the verified topology and snap distances | Graph and gate unit tests pass |
| **P3 — Buildings** | `BuildingRepository`; coordinate validation and the R7 bad-coordinate state; Buildings list; building detail exposing `description` / `address` / `url` / `bucode` | Unit tests for validation and parsing pass |
| **P4 — Location** | `geolocator` stream, quality thresholds, heading, permission flow, connectivity | Unit tests pass; permission denial handled |
| **P5 — Map shell** | Normal basemap, camera, building and gate markers, bottom sheet, panel with Buildings / Places / Gates / About | App runs and shows the campus map |
| **P6 — Routing** | Single `RoutePlanner` implementing the five-step cascade; `RouteQuality` | Planner tests cover cascade order, gate selection, and every fallback |
| **P7 — Navigation** | Navigation state machine, instruction strip, progress/ETA, camera follow, off-route detection, rerouting, arrival | Navigation tests pass |
| **P8 — Search** | Search index over buildings + gates, filter before top-K, per-type groups and counts, empty/no-match states | Search tests pass |
| **P9 — Content** | Places (Services) surface, Gates list and detail, About | Content surfaces render real backend data only |
| **P10 — Integration and audit** | Full walkthrough, `flutter analyze`, `flutter test`, independence grep audit, confirm the reference project is untouched | All checks pass; audit report written |

---

## 13. Tests and verification criteria

- `flutter analyze` — zero issues.
- `flutter test` — full unit suite green, including the architecture import-boundary test.
- Unit coverage for: geo math, KMZ parsing, road graph and Dijkstra, gate policy, building parsing, coordinate validation (R7), routing cascade and `RouteQuality`, navigation state machine and progress math (F2), search filtering and per-type limits (F6).
- Fixture-based tests: the live backend returns 403 from the dev host, so tests use fixtures matching the verified field set and the verified 6-building dataset.
- Independence grep audit: no indoor symbols (`floor`, `poi`, `radiomap`, `knn`, `fingerprint`, `wifi`, `indoor`, `transition`, `containment`, `quick_access`, …) in the new project.
- `git status` confirms the reference project has no changes from this work.

---

## 14. Acceptance criteria

The app is accepted when all of the following hold:

1. It builds and runs as a separate app with identity `eg.edu.ejust.campusfind` / "EJUST CampusFind", alongside an unmodified reference project.
2. Buildings come from `{SERVER_URL}/api/mapping/space/public`; no building list is hardcoded; newly published backend buildings appear automatically.
3. Directions to any valid building routes to its outdoor coordinates through the documented five-step cascade and always reports a `RouteQuality`.
4. Buildings with invalid or missing coordinates appear in lists and search with a warning, and Navigate is disabled with an explanation.
5. Services ("Places") lists real backend buildings; no category taxonomy is invented; no facilities dataset is bundled.
6. Gates are browsable, searchable as their own category, and participate in routing; they are not a Services tile.
7. Search returns Buildings and Gates with filters applied before top-K.
8. The app requests only `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`; no cleartext traffic.
9. No indoor data, indoor routing, or indoor positioning code or assets exist in the project.
10. Architecture is strict MVVM with Riverpod as the only state-management framework; `provider` is absent.
11. `flutter analyze` and `flutter test` are clean.

---

## 15. Known blockers and unknowns

| Item | Status |
|---|---|
| `MAPS_API_KEY` / `android/local.properties` | **EXTERNAL DEPENDENCY** — required for any APK build; `flutter analyze` and `flutter test` do not need it |
| `map.beout.ai` returns 403 from this host | Live 6-building dataset and E-JUST OSRM reachability unverified today; the dataset record comes from the reference's own verified probe |
| E-JUST OSRM reachability from a real device | Unverified — verify during P10 walkthrough |
| Road polyline legibility on the normal basemap at max zoom 20 | Unverified — verify during P10 walkthrough |
| Building `description` / `address` / `url` / `bucode` not populated in current live data | Detail UI must degrade cleanly when absent |
| A future server-side `space_category` field | Out of scope; if added later, adopt it in one place in the data layer |

---

## 16. Immutable Master Plan rules

These rules are fixed for the life of this project:

1. **Outdoor-only.** No floors, floorplans, rooms, indoor POIs, indoor entrances, floor transitions, radiomaps, Wi-Fi/KNN positioning, or indoor routing — in code, assets, permissions, or dependencies.
2. **Buildings are the primary entity**, sourced from the backend. Never hardcode a building list; never fabricate a building.
3. **No fabricated data.** No invented categories, no invented facilities, no invented coordinates. If the backend does not supply it, the app does not show it.
4. **No hardcoded hosts.** Every endpoint and asset path is configuration.
5. **Gates are their own entity**, separate from Services.
6. **Riverpod only.** `provider` must not appear in the dependency list.
7. **Strict MVVM** with enforced layer boundaries.
8. **One routing planner.** No duplicated routing cascades.
9. **Every route declares its quality.** Approximate routes are labeled as such.
10. **The reference project is read-only.** It is evidence, not a template to mutate.
11. **The app is independent** — a separate project, a separate package, a separate Android application id.

## 17. Change and deviation rules

1. This Master Plan is the authority. Implementation must not deviate from it.
2. Any proposed deviation — including adding scope, removing scope, or reinterpreting a locked decision — must be raised explicitly and approved **before** code is written.
3. Ambiguity is reported, not resolved by invention. If the plan is unclear, stop and ask.
4. New scope requires a decision, an update to this document, and explicit approval.
5. Verified-external-data changes (a new backend field, a new server-side category field) are adopted in exactly one place — the data layer — and must not leak into domain or presentation logic.
6. No commits are made unless explicitly requested.
7. Verification evidence is required per phase; a phase is not complete until its exit criteria pass.
