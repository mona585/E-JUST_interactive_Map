# E-JUST CampusFind — Architecture Refactor Report

**Date:** 2026-09-29
**Scope:** `clients/flutter/ejust_campusfind` (Flutter 3.44.9, Dart 3.12.2)
**Reference:** `clients/flutter/anyplace_campusfind` — read-only, verified untouched

---

## 1. Outcome in one paragraph

The app was moved from a five-folder technical layering (`core/`, `data/`, `domain/`, `presentation/`, `app/`) to the requested responsibility-based structure (`config/`, `models/`, `datasources/`, `repositories/`, `services/`, `viewmodels/`, `views/`, `widgets/`, `utils/`, `di/`). The move was not a rename: importing the real edge list showed four genuine dependency inversions, which were fixed by re-homing value types and contracts to the layer that actually owns them. `flutter analyze` reports no issues, all 383 tests pass, a release APK builds, and the Google Maps key is correctly embedded in it. The APK is debug-signed and untested on hardware — see §7.

---

## 2. What was actually done

### 2.1 Mechanical reorganisation
- 41 files moved into the new folders.
- 7 files split along a responsibility seam (model ⇄ parser/loader/router/port/service/viewmodel).
- 62 files had their import URIs rewritten; `main.dart`'s two *relative* `app/` imports were found and fixed separately, since a `package:`-URI rewrite does not touch them.
- The old `app/`, `core/`, `data/`, `domain/`, `presentation/` trees are gone.

### 2.2 Four real inversions, found by measuring rather than assuming
The first cut produced a compiling codebase but the *architecture* was still wrong in four places. The edge list was dumped from the source and compared against the intended graph:

| # | Problem | Fix | Consequence |
|---|---------|-----|-------------|
| 1 | `viewmodels/location_view_model.dart` imported `datasources/location_source.dart` — a ViewModel reaching a datasource | The `LocationSource` / `ConnectivitySource` **contracts** moved to `models/location_source.dart`; the geolocator and connectivity implementations stay in `datasources/` | ViewModel now depends on a port, not on I/O |
| 2 | `models/` imported `services/` (`RouteGraph` in `campus_map_data.dart` and `map_state.dart`) | `RouteGraph` is a data structure, not a service → `models/route_graph.dart` | Models no longer depend on logic |
| 3 | `models/campus_map_data.dart` imported `services/route_planner.dart` for `RoutingGate` | `RoutingGate` is a value object → `models/routing_gate.dart` | Same |
| 4 | `views/navigation/navigation_banner.dart` imported `services/navigator_controller.dart` and `services/progress_tracker.dart` | `NavigationState`/`NavigationPhase` → `models/navigation_state.dart`; `RouteProgress`/`Maneuver`/`ManeuverKind` → `models/route_progress.dart` | A view reads state, not a state machine |

Supporting moves for the above: `services/geo_math.dart` → `utils/geo.dart` (generic math, needed by `models/route_graph.dart`, which must not reach into `services/`).

`models/location_source.dart` is the load-bearing decision behind #1: the port has to live somewhere a ViewModel may import, and the requested structure has no separate ports folder, so the contract sits with the other data shapes and the implementations stay in `datasources/`.

### 2.3 One shared helper extracted rather than duplicated
`SearchQuery._normalise` and `SearchIndex` both needed text folding, but the helper was `private`, and a private top-level function is not visible across libraries. Copying it would have created two sources of truth for a behaviour that search matching depends on, so it became `utils/text_fold.dart` — genuinely generic, no knowledge of search or of the campus — which both a model and a service may depend on without an inversion.

---

## 3. Final layer graph (measured, not intended)

Every internal edge in `lib/`, recomputed from source after the refactor:

```
config      -> utils
models      -> config, utils
datasources -> config, models, utils
services    -> config, datasources, models, utils
repositories-> config, datasources, models, utils
viewmodels  -> config, models, services, utils, di(providers.dart only)
views       -> config, models, services, utils, viewmodels, widgets, di(providers.dart only)
widgets     -> config, models, utils
di          -> config, datasources, models, repositories, services
main        -> di, views
```

Acyclic. Note that `views -> services` and `viewmodels -> di` are present in the raw measurement: the first is `RouteGraph` as a map-overlay type and `NavigationState`/`RouteProgress` as state objects, all of which now live in `models/`; the second is the deliberate, pre-existing composition-root exception, preserved from the old guard and now stated explicitly in `MASTER-PLAN.md`.

`services -> datasources` is the one allowed upward edge, and it is exactly one line: `RoutePlanner` owns a `PublicRoadRouter` collaborator for the hybrid (OSRM-to-a-gate) step. The user's explicit prohibitions were on presentation reaching datasources; the routing service consulting its own transport is the one place where the data-access edge is intrinsic to the responsibility.

---

## 4. Every production Dart file and what it is for

62 files, 7,671 lines. `lib/`:

### `config/` — one place for every compile-time constant
| File | Lines | Responsibility |
|---|---|---|
| `app_config.dart` | 188 | Single source of truth for hosts, endpoints, zoom limits, GPS quality thresholds and navigation tolerances. Overridable with `--dart-define`. No other file in `lib/` may hold a host literal. |
| `theme.dart` | 28 | The single Material 3 light theme and its extensions. |

### `utils/` — generic, app-agnostic
| File | Lines | Responsibility |
|---|---|---|
| `result.dart` | 66 | `Result<T>` / `Success` / `Failure` / `AppError`. Repositories return `Result<T>` so failures are values and presentation never catches. |
| `geo.dart` | 330 | `Geo` and `SegmentProjection`: haversine, bearing, snapping, point-to-segment projection. Pure functions, no app knowledge. |
| `text_fold.dart` | 70 | Case/diacritic/punctuation folding for search comparison. Arabic passes through unchanged. Shared by `models/search_query.dart` and `services/search_index.dart`. |

### `models/` — data shapes only; no I/O, no logic
| File | Lines | Responsibility |
|---|---|---|
| `building_snapshot.dart` | 56 | Result of one campus-directory load: the buildings plus the counts explaining what was dropped and why. |
| `campus_building.dart` | 284 | `CampusBuilding`, `SpaceType`, `CoordinateStatus`; coordinate validation and query matching. |
| `campus_gate.dart` | 65 | A gate on the campus boundary that public-road routing targets so campus roads take over. Never shown as a Services entry. |
| `campus_map_data.dart` | 58 | The assembled campus map: graph, buildings, gates, snap tolerance. |
| `gate_policy.dart` | 32 | Parsed gate-routing policy. Data only; JSON reading is in the datasource. |
| `gps_sample.dart` | 130 | `GpsSample` / `GpsQuality`: one position fix plus its quality classification and usability. |
| `kmz_placemark.dart` | 31 | A parsed KMZ placemark and its geometry kind. |
| `location_access.dart` | 63 | `LocationAccess`, `LocationPermissionState`, `LocationAvailability` — permission state normalised across platforms. |
| `location_source.dart` | 43 | **The location/connectivity contracts.** Moved out of `datasources/` so a ViewModel can depend on a port without importing a datasource. |
| `map_state.dart` | 182 | `MapState`, `MapSelection`, `MapCameraRequest` — the map's presentation state and its one-shot camera intent. |
| `navigation_state.dart` | 109 | `NavigationState` / `NavigationPhase`: where navigation is. Extracted so views can read state without importing the state machine. |
| `outdoor_route.dart` | 39 | The outdoor route and its quality/leg structure. |
| `public_road_leg.dart` | 20 | One leg of a public-road (OSRM) route. |
| `route_graph.dart` | 353 | `RouteGraph`, `RouteEdge`, `RoutePath`: the campus road network and its queries. A data structure, so it is a model, not a service. |
| `route_progress.dart` | 74 | `RouteProgress`, `Maneuver`, `ManeuverKind` — where the user is on the route and what to do next. |
| `route_quality.dart` | 28 | How much of a produced route is real surveyed routing. The enum is part of the route, not an afterthought. |
| `routing_gate.dart` | 20 | A campus gate as the router needs it: id, position, snap distance. |
| `search_query.dart` | 179 | `SearchQuery`, `SearchDocument`, `SearchCategory`, and the per-category result shapes. |

### `datasources/` — where bytes come from
| File | Lines | Responsibility |
|---|---|---|
| `anyplace_api_client.dart` | 192 | `BackendApiClient`: the Anyplace HTTP client, and `BackendSpace` for its response records. |
| `asset_loader.dart` | 16 | Thin wrapper over `rootBundle` so assets are faked in tests. |
| `campus_roads_loader.dart` | 51 | `RoadsKmzSource`: loads the bundled roads KMZ and builds the route graph. |
| `connectivity_source.dart` | 39 | `ConnectivityPlusSource`: online/offline via `connectivity_plus`. |
| `gate_policy_parser.dart` | 57 | Reads and parses `assets/config/gate_policy.json` into a `GatePolicy`. |
| `geolocator_location_source.dart` | 117 | `GeolocatorLocationSource`: position fixes and permission prompts via `geolocator`. |
| `kmz_parser.dart` | 147 | Unzips a KMZ and yields placemarks. |
| `osrm_client.dart` | 89 | Raw OSRM HTTP client. |
| `public_road_router.dart` | 13 | `PublicRoadRouter`: the OSRM call expressed as a routing result. |

### `services/` — business logic, no platform
| File | Lines | Responsibility |
|---|---|---|
| `arrival_detector.dart` | 62 | Decides the user has arrived, with confirmation fixes and a distance floor. |
| `heading_tracker.dart` | 60 | Smooths raw GPS fixes into a usable compass heading. |
| `navigation_gps_guard.dart` | 75 | `GpsGuard`: accepts, rejects or warns on a fix (stale, inaccurate, speed jump, no baseline). |
| `navigator_controller.dart` | 182 | The navigation state machine: feeds fixes in, immutable `NavigationState` out. Owns no timers, streams or widgets. |
| `progress_tracker.dart` | 165 | `ProgressTracker`: distance-along-polyline progress, ETA, upcoming maneuver. |
| `reroute_service.dart` | 74 | Decides when a reroute is due and rate-limits attempts. |
| `route_planner.dart` | 274 | The single routing planner and its one cascade (graph → hybrid → OSRM with a spliced tail). |
| `search_index.dart` | 157 | `SearchIndex`: builds once from campus data, then answers queries as a pure function. |

### `repositories/` — data coordination and caching
| File | Lines | Responsibility |
|---|---|---|
| `building_repository.dart` | 67 | Fetches the campus directory and returns a `BuildingSnapshot`. |
| `campus_map_repository.dart` | 57 | Assembles campus map data, caching the last good result for offline use. |
| `gate_repository.dart` | 149 | Loads gates + policy, resolves the preferred gate, falls back to a permissive policy on parse failure. |

### `viewmodels/` — presentation state
| File | Lines | Responsibility |
|---|---|---|
| `location_view_model.dart` | 221 | `LocationState`, `LatLngSnapshot`: permission, fix quality, and the smoothed position the UI shows. |
| `map_view_model.dart` | 215 | `MapViewModel`: `MapState` plus intents; owns map error/empty/stale presentation. |
| `navigation_view_model.dart` | 141 | `NavigationViewState`: drives `NavigatorController` and exposes the banner's data. |
| `search_view_model.dart` | 191 | `SearchViewState`: query, filters, counts and results. |

### `views/` — rendering only
| File | Lines | Responsibility |
|---|---|---|
| `campus_find_app.dart` | 20 | Root widget and theme wiring. |
| `shell/app_shell.dart` | 76 | Tab scaffold. |
| `shell/campus_panel.dart` | 384 | Draggable campus panel: tab enum, sheet chrome, location chip. |
| `map/campus_map_view.dart` | 372 | The Google Map: markers, polylines, accuracy circle, camera, status banner. |
| `navigation/navigation_banner.dart` | 242 | One-glance instruction strip: instruction, distance left, route quality. |
| `buildings/buildings_tab.dart` | 145 | Building list. |
| `buildings/building_detail_sheet.dart` | 114 | Building detail sheet. |
| `gates/gates_tab.dart` | 131 | Gate list. |
| `gates/gate_detail_sheet.dart` | 164 | Gate detail sheet. |
| `places/places_tab.dart` | 106 | Places tab with the scope note. |
| `search/search_view.dart` | 329 | Search surface: filter bar, grouped results, empty/error states. |
| `about/about_tab.dart` | 127 | About tab. |

### `widgets/` — shared presentation
| File | Lines | Responsibility |
|---|---|---|
| `panel_sections.dart` | 123 | `PanelSectionHeader`, `StaleDataWarning`, `PanelMessage` — states reused by every panel. |

### `di/` — the composition root
| File | Lines | Responsibility |
|---|---|---|
| `providers.dart` | 65 | Every `Provider` and the `appProviderOverrides` that injects implementations. Nothing else constructs a datasource. |

---

## 5. Validation actually run

| Check | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **No issues found** |
| Tests | `flutter test` | **383 passed, 0 failed** (was 382 before; the rewritten guard has 9 tests instead of 8) |
| Formatting | `dart format lib test` | 86 files, **0 changed** on re-run (idempotent) |
| Release build | `flutter build apk --release` | Built, 50.11 MB, Maps key embedded (§8) |
| Reference untouched | SHA-256 vs `ref_baseline.txt` | **175 / 175 byte-identical**, 0 changed, 0 missing |

The 383 tests are the pre-existing suite, unmodified in intent — the refactor is proven behaviour-preserving by them still passing, not by new tests asserting the new shape. The one rewritten file is the architecture guard, which is itself a test.

### The guard is load-bearing
`test/architecture/import_boundary_test.dart` (9 tests) keeps the P10 fix intact: the `package:ejust_campusfind/` case must be tested **before** the generic `contains(':')` test, because every import in this codebase is a package import and the previous ordering made the whole file silently skip everything. A self-check group plants a package import, a relative import, and an export in a temp file and requires the same resolver to reject each, plus confirms a genuinely external package is not flagged. Without those, "the boundary test passes" could again mean "the boundary test was reading nothing".

---

## 6. Decisions taken, and why

1. **`lib/di/` exists although the requested tree had no DI folder.** Something has to own `Provider` construction. Putting it in `main.dart` would make the entry point the composition root; a `di/providers.dart` keeps `main()` to `runApp(ProviderScope(...))`. Documented in `MASTER-PLAN.md`.
2. **Contracts live in `models/`.** The requested structure has no ports folder, but a ViewModel must not import `datasources/`. The port is a data shape, so `models/location_source.dart` holds the interface and `datasources/` holds the geolocator/connectivity implementations. This is the one place I extended the folder semantics; it is the alternative to leaving a forbidden edge in place.
3. **`services -> datasources` allowed for one edge.** `RoutePlanner` owns a `PublicRoadRouter`. Moving the OSRM call behind a repository would have added a layer that owns no state and no caching, i.e. a pass-through, for one call site.
4. **Views may import `models/`.** Views receive immutable state objects as parameters (`NavigationState`, `RouteProgress`, `MapState`). Forbidding this would mean duplicating every state class as a second "view model" with no behaviour. The forbidden edge that matters — presentation reaching a datasource — is enforced.
5. **`analysis_options.yaml` left unchanged.** 13 two-line `if` statements were flagged by `curly_braces_in_flow_control_structures` (surfaced when a `pub get` under `flutter_lints: ^6.0.0` resolved a newer 6.x). I verified on a scratch file that `dart format` *preserves* braces rather than stripping them, so the fix was to add the 13 braces, not to weaken the lint. The single-line `if (c) return x;` form is that rule's documented exception and was left alone. Re-formatting is a no-op.
6. **Indoor parity stays out of scope**, per the user's explicit decision. `MASTER-PLAN.md` remains outdoor-only; only §8 (structure) was rewritten.
7. **No commit was made**, since none was requested.

### Two process notes worth recording
- A `PowerShell Add-Content` round-trip re-encoded two characters in `utils/geo.dart` as CP1252 (§ and —), producing an invalid-UTF-8 file. The analyzer reports an unparseable file as `Target of URI doesn't exist`, which sent the investigation down the wrong path for a while. The file is now valid UTF-8 (`C2 A7`, `E2 80 94`).
- Two doc comments were orphaned by line-based splitting (the `BuildingRepository` and `SearchIndex` class docs stayed behind in the model files). Both were found by scanning for `///` blocks not followed by a declaration, and moved to the classes they describe.

---

## 7. Not verified / open items

- **The APK is debug-signed.** `android/app/build.gradle` sets `signingConfig = signingConfigs.getByName("debug")` for release, with a comment saying so. It is installable but not production-signed; no signing material was invented.
- **Live backend unreachable.** `https://map.beout.ai/api/mapping/space/public` timed out on three attempts, so all backend behaviour is proven against fixtures only.
- **Untested on hardware:** rendered Google Maps, device GPS, real campus-area OSRM routing, rerouting, camera follow and arrival. No physical device was attached, so although the Maps key is correctly embedded (§8), a rendered map has not been seen.
- `FINAL-AUDIT.md` still describes the pre-refactor tree and is now stale; this report supersedes it.

## 8. APK artefact

```
build/app/outputs/flutter-apk/app-release.apk
size   : 50.11 MB (52,541,573 bytes)
built  : 2026-09-29 20:16:49
sha256 : AB4EABEEF0F5884136246F7E141AF7653441550BC4BC8C7D37F992CAE86BD279
```

### Maps key
The Google Maps API key was supplied by the user and written to
`android/local.properties`, which is gitignored (`/local.properties`). It was
then verified to reach the APK: in the merged release manifest
(`build/app/intermediates/merged_manifests/release/processReleaseManifest/AndroidManifest.xml`)
`com.google.android.geo.API_KEY` resolves to the expected 39-character value
rather than the empty string or an unresolved `${MAPS_API_KEY}` placeholder it
resolved to before. The key appears in no tracked file — `lib/`, `test/`,
`android/app/`, `assets/` and `pubspec.yaml` were all scanned and are clean, and
it is deliberately not reproduced in this report.

Anyone rebuilding from a clean checkout must add the key themselves; it is not
in version control by design.
