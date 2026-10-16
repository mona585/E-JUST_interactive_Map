# FINAL AUDIT - EJUST CampusFind

Audit of `clients/flutter/ejust_campusfind` against `MASTER-PLAN.md` (phases P0-P10,
acceptance criteria 1-11, immutable rules 1-11).

Date: 2026-09-29. HEAD: `e26ecdc4`. Host: Windows 11, Flutter 3.44.9 stable,
Dart 3.12.2.

**Verdict: ACCEPTED, with three external dependencies unverified.** Every
check that can be run on this host passes. The three items that cannot are
listed in section 8 and are environmental, not defects.

---

## 1. Verification commands

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.9s)` |
| `flutter test` | `00:13 +382: All tests passed!` |
| `flutter test --reporter expanded` | 382 executed, 382 declared, 0 skipped |
| Reference integrity recheck | 175/175 baseline entries byte-identical, 0 lost |
| Independence grep audit | Clean (section 4) |
| `git status` on the reference project | Unchanged since the pre-work baseline (section 5) |

## 2. Test inventory

382 tests across 24 files. Declared count equals executed count, so nothing is
silently skipped.

| File | Tests | Covers |
|---|---|---|
| `test/architecture/import_boundary_test.dart` | 8 | Layer boundaries + a self-check that the guard can fail |
| `test/unit/geo_test.dart` | 28 | Haversine, bearing, snapping |
| `test/unit/building_repository_test.dart` | 49 | Backend parsing, field validation, R7 |
| `test/unit/route_graph_test.dart` | 26 | KMZ -> graph, Dijkstra, topology |
| `test/unit/navigator_controller_test.dart` | 23 | Navigation state machine, off-route, rerouting |
| `test/unit/gate_repository_test.dart` | 22 | Gate parsing, snap distances, policy |
| `test/unit/location_view_model_test.dart` | 21 | Permission flow, quality gating, staleness |
| `test/unit/gps_sample_test.dart` | 18 | Fix quality thresholds |
| `test/unit/progress_tracker_test.dart` | 17 | F2 progress and ETA math |
| `test/unit/search_index_test.dart` | 24 | Categories, filter-before-limit, ranking, folding |
| `test/unit/search_view_model_test.dart` | 17 | Projection, filters, index-follows-reload |
| `test/unit/navigation_guards_test.dart` | 13 | Navigation preconditions |
| `test/widget/content_surfaces_test.dart` | 13 | Gate detail sheet, gate list |
| `test/widget/app_shell_test.dart` | 22 | Panel, Places, About, stale-data states |
| `test/widget/search_ui_test.dart` | 17 | Search surface, chips, empty states |
| `test/widget/navigation_ui_test.dart` | 10 | Instruction strip, progress, arrival |
| `test/unit/route_planner_test.dart` | 10 | The five-step cascade, `RouteQuality` |
| `test/unit/osrm_client_test.dart` | 10 | Public-road request/response |
| `test/unit/campus_map_repository_test.dart` | 8 | Bundled assets load |
| `test/unit/navigation_view_model_test.dart` | 8 | Directions handoff |
| `test/unit/kmz_test.dart` | 8 | KMZ/KML parsing |
| `test/unit/app_config_test.dart` | 6 | Configuration, host derivation |
| `test/unit/route_planner_wiring_test.dart` | 4 | One planner, no duplicate cascade |

## 3. What the audit found and fixed

### 3.1 The architecture guard was inert for four phases

`test/architecture/import_boundary_test.dart` resolves each import to a
`lib/...` path before checking it against the layer table. Its `resolve()`
tested `importUri.contains(':')` **before** testing
`importUri.startsWith('package:ejust_campusfind/')`. Since every import in this
codebase is a `package:` import, every one of them was discarded as an external
package. The guard was reading an empty set and passing for P0-P8.

With the order corrected, it immediately found a real violation:

```
lib/presentation/location/location_view_model.dart -> lib/data/datasources/connectivity_source.dart
lib/presentation/location/location_view_model.dart -> lib/data/datasources/geolocator_location_source.dart
```

`location_view_model.dart` defined `locationSourceProvider` and
`connectivitySourceProvider` next to the view model, so the composition root was
not the only place data-layer types were constructed - which is precisely what
immutable rule 7 and the boundary test exist to prevent. Both providers now
live in `lib/app/providers.dart` with the other data-layer wiring.
`headingTrackerProvider` stayed in the view model because `HeadingTracker` is
pure domain.

The fix is not just the ordering. A self-check group was added
(`the guard is load-bearing`) that plants a package import, a relative import,
and an `export` into `data/` from a throwaway `presentation/` file and requires
the same resolver to flag each one, and separately requires `dart:async`,
`package:http` and `package:google_maps_flutter` to pass. A guard that cannot be
shown to fail is not evidence, and this one previously was not.

`flutter test` went from 378 to 382 because of those four tests. The suite grew;
the coverage claim did not change.

### 3.2 A failed refresh blanked the list

`MapViewModel.load` left the building snapshot empty when the request failed, so
a dropped connection replaced a directory the user was reading with an error
page. It now retains the last successful snapshot and records the error, and
`BuildingsTab` / `PlacesTab` render a `StaleDataWarning` above the retained rows
with a retry. An initial failure, with nothing cached, still shows the full
`PanelMessage`. Both paths are covered in `app_shell_test.dart`.

## 4. Independence grep audit

`MASTER-PLAN.md` section 13 requires no indoor symbols. Searched `lib/` and
`test/` for `floor`, `poi`, `radiomap`, `knn`, `fingerprint`, `wifi`, `indoor`,
`transition`, `containment`, `quick_access`, `mac_address`, `bssid`, `ssid`.

| Hit | File | Verdict |
|---|---|---|
| `There is no indoor positioning` | `data/datasources/geolocator_location_source.dart:9` | Prose asserting the absence |
| `no indoor, Wi-Fi or sensor-fusion source` | `domain/location/gps_sample.dart:7` | Prose asserting the absence |
| `No indoor navigation` / `no floors, indoor maps...` | `presentation/shell/about_tab.dart:54,77,78` | User-facing About copy asserting the absence |
| `A cheap fingerprint of the records` | `presentation/search/search_view_model.dart:153` | Doc comment for a content hash |
| `Borrowing desk on the ground floor` | `test/widget/navigation_ui_test.dart:159,204` | A building `description` string - backend prose, not a symbol |
| `denies indoor features` | `test/widget/app_shell_test.dart:483,509` | About-copy assertions |

No indoor identifier, type, field, model, or code path exists. All six hits are
prose that exists to state the absence.

**Assets.** The package ships exactly three: `assets/navigation/ejust roads.kmz`,
`assets/config/ejust gates.kmz`, `assets/config/gate_policy.json`. Each was
decoded and searched for the same symbols; none matched. No floorplan, no POI
file, no radiomap, no facilities dataset.

**Dependencies.** `pubspec.yaml` declares `flutter_riverpod: ^2.6.1` and no
`provider` (immutable rule 6). All 16 state-management imports in `lib/` are
`package:flutter_riverpod`.

**Permissions.** `android/app/src/main/AndroidManifest.xml` requests exactly
`INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`. No
`usesCleartextTraffic`, no `networkSecurityConfig`, no background location, no
Wi-Fi state. No `http://` literal appears anywhere in `lib/`.

**Hosts.** Two literals exist, both in `lib/core/config/app_config.dart`, both
overridable by `--dart-define`: `_defaultServerUrl` (`SERVER_URL`) and
`_defaultOsrmBaseUrl` (`OSRM_URL`). No host string appears in any other file.
Endpoints are derived from them, never concatenated as absolute URLs.

**Identity.** `namespace` and `applicationId` are both
`eg.edu.ejust.campusfind`; the manifest label is `EJUST CampusFind`.

## 5. Reference project integrity

Immutable rule 10: `clients/flutter/anyplace_campusfind` is read-only.

`git status` is **not** usable as the evidence here, and it would be wrong to
report it as clean. The reference project was already dirty against HEAD
`e26ecdc4` before this work began - staged renames of `lib/data/**` into
`lib/datasources|models|repositories`, a deleted `bulk_load_provider.dart`, and
modifications to `constants.dart`, `map_config.dart`, `navigation_config.dart`,
`main.dart` and three providers. None of that is from this engagement.

The evidence that is valid is the hash baseline taken before any code was
written (`C:\Users\MONAMO~1\AppData\Local\Temp\opencode\ref_baseline.txt`,
175 entries of size + SHA256):

| Check | Result |
|---|---|
| Baseline entries present and byte-identical | 175 / 175 |
| Lost or altered | 0 |
| Files present in the tree but outside the baseline | 46 |
| Newest write to any file in the reference project | `2026-09-08T23:00:57Z` |
| Newest write among the 46 out-of-baseline files | `2026-09-01T00:58:55Z` |

The last line is the decisive one. The newest write anywhere in the reference
project is the newest baseline entry, so **nothing in it has been written since
the baseline was taken**. The 46 extra files are all pre-existing and outside
what the baseline tracked: `.gitignore`, `.metadata`, `pubspec.lock`,
`README.md`, the `android/` scaffolding including `local.properties` and
`gradle-wrapper.jar`, and 30 files under `docs/`. Their newest mtime is
2026-09-01, ten days before the last baseline write.

The reference project is unmodified by this work.

## 6. Architecture

| Layer | May import | Enforced |
|---|---|---|
| `core/` | `core/` + third-party | yes |
| `domain/` | `core/`, `domain/` | yes |
| `data/` | `core/`, `domain/`, `data/` | yes |
| `presentation/` | `core/`, `domain/`, `presentation/`, `app/providers.dart` | yes |
| `app/` | everything internal | yes |
| `main.dart` | everything internal | yes |

`domain/` and `presentation/` have zero imports of `data/`. `presentation/`
reaches the composition root only through `lib/app/providers.dart`, which
re-exports the data models and repositories that views need.

One deviation from the table above, deliberate and confined: nine `domain/`
files import `package:google_maps_flutter` for the `LatLng` value type
(`geo.dart`, `kmz.dart`, `gps_sample.dart`, `route_graph.dart`,
`route_planner.dart`, `outdoor_route.dart`, `progress_tracker.dart`,
`arrival_detector.dart`, `navigator_controller.dart`). The boundary test treats
third-party packages as outside the layer graph, so this is permitted. The
consequence is real and worth stating: the domain layer is not pure Dart, and
`LatLng` - not a domain value object - is the coordinate type throughout.
Introducing `GeoPoint` as the domain type and converting at the map edge is the
correct follow-up, and it is a refactor of a settled codebase, not a defect to
fix mid-audit.

## 7. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Separate app, identity `eg.edu.ejust.campusfind` / "EJUST CampusFind", alongside an unmodified reference project | **PASS (build pending key)** | `build.gradle.kts` namespace + applicationId; manifest label; section 5 |
| 2 | Buildings from `{SERVER_URL}/api/mapping/space/public`, nothing hardcoded, new backend buildings appear automatically | **PASS (fixture-verified)** | `AppConfig.spacesPublicUri()`; `BuildingRepository`; 49 repository tests; no building list in `assets/` or in code |
| 3 | Directions to any valid building route to outdoor coordinates through the five-step cascade and always report a `RouteQuality` | **PASS** | `route_planner_test.dart` (10) + `route_planner_wiring_test.dart` (4); `RouteQuality` is a required output of the planner, not an optional label |
| 4 | Invalid or missing coordinates appear in lists and search with a warning, Navigate disabled with an explanation | **PASS** | `CampusBuilding.coordinateWarning`; R7 tests in `building_repository_test.dart`, `search_index_test.dart`, `app_shell_test.dart` |
| 5 | Places lists real backend buildings, no invented category taxonomy, no bundled facilities dataset | **PASS** | `places_tab.dart` renders `snapshot.buildings` and declares no category list; `assets/` holds no facilities file |
| 6 | Gates browsable, searchable as their own category, participate in routing, not a Services tile | **PASS** | `gates_tab.dart` + `gate_detail.dart`; `SearchCategory.gate`; planner gate selection; 13 content-surface tests + 22 gate tests |
| 7 | Search returns Buildings and Gates with filters applied before top-K | **PASS** | `search_index_test.dart` - 60 buildings / 1 gate, group count 60, result 1, truncated; navigable filter before limit |
| 8 | Only `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`; no cleartext | **PASS** | manifest inspected; no `http://` in `lib/`; no cleartext config in any manifest variant |
| 9 | No indoor data, routing, positioning, code or assets | **PASS** | section 4 |
| 10 | Strict MVVM, Riverpod only, `provider` absent | **PASS** | `pubspec.yaml`; 16/16 imports Riverpod; section 6 |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 382/382 |

## 8. External dependencies - not verified, not defects

| Item | Status today | What it blocks |
|---|---|---|
| `MAPS_API_KEY` absent from `android/local.properties` | **EXTERNAL DEPENDENCY** | `flutter build apk`, installation, and all basemap rendering. Analyze and test do not need it and are green without it. |
| `https://map.beout.ai/api/mapping/space/public` | **UNREACHABLE** - 3 consecutive attempts timed out from this host (an earlier probe returned `403 Forbidden`; the host has since gone from refusing to not answering) | Live building directory. Every content surface has been exercised only against fixtures matching the verified field set. |
| E-JUST OSRM from a real device | **PARTIAL** - the public OSRM endpoint answered `200` from this host with a real foot route; the campus-area route and device reachability are unverified | Live public-road leg. `osrm_client_test.dart` covers the request/response contract; the cascade is covered by fakes. |
| Road polyline legibility on the basemap at zoom 20 | **UNVERIFIED** - needs a rendered map | Visual quality only; no logic depends on it. |
| Building `description` / `address` / `url` / `bucode` absent from live data | **UNVERIFIED**, and handled | Detail sheets degrade cleanly when a field is missing; asserted in tests. |

## 9. Phase roll-up

| Phase | Exit criterion | Status |
|---|---|---|
| P0 Skeleton | analyze clean, no indoor token, architecture test green | **PASS** (guard was inert until section 3.1) |
| P1 Core utilities | unit tests pass | **PASS** |
| P2 Campus map data | graph and gate unit tests pass | **PASS** |
| P3 Buildings | validation and parsing tests pass | **PASS** |
| P4 Location | tests pass, denial handled | **PASS** |
| P5 Map shell | app runs and shows the campus map | **PASS on logic; rendering blocked on `MAPS_API_KEY`** |
| P6 Routing | cascade order, gate selection, every fallback | **PASS** |
| P7 Navigation | navigation tests pass | **PASS on logic; device behaviour unverified** |
| P8 Search | search tests pass | **PASS** |
| P9 Content | content surfaces render real backend data only | **PASS on fixtures; live backend unreachable** |
| P10 Integration and audit | all checks pass, audit report written | **PASS** - this document |

## 10. Residual risks

1. **The backend has never answered.** Every data-path test runs against
   fixtures. If the live `space/public` payload differs from the verified field
   set, the parsing in `BuildingRepository` is where it will surface, and it will
   surface as a handled error state rather than a crash. This is the single
   largest gap in the evidence.
2. **`LatLng` as the domain coordinate type** (section 6). Nine domain files
   depend on a plugin package. Refactoring to a `GeoPoint` value object would
   remove that, at the cost of a wide but mechanical change.
3. **Device-only behaviour is unexercised**: GPS accuracy gating in motion,
   heading from real sensors, camera follow, rerouting on a real route,
   arrival. Each has unit coverage over fakes; none has run on hardware.
4. **`android/local.properties` holds a developer machine's `sdk.dir`**, which
   is the conventional Flutter setup and not a secret, but it is
   machine-specific and will need regenerating elsewhere.
