# IMPLEMENTATION REPORT — EJUST CampusFind

Historical execution log for `MASTER-PLAN.md`. Append-only: sections are frozen once written, and later phases record their own fixes rather than editing earlier ones.

- Contract: `MASTER-PLAN.md` (immutable)
- New project: `clients/flutter/ejust_campusfind`
- Reference project (READ-ONLY): `clients/flutter/anyplace_campusfind`
- Toolchain used: Flutter 3.44.9 (stable, rev 6b182d2c75), Dart 3.12.2 (DevTools 2.57.0), Windows dev host

---

## Reference project integrity baseline (recorded before any implementation)

| Measure | Value |
|---|---|
| `git status --porcelain -- clients/flutter/anyplace_campusfind` entries | 152 (all pre-existing, from earlier work outside this session) |
| Files hashed (`lib/`, `assets/`, `android/app/src/main/`, `test/`, `pubspec.yaml`, `analysis_options.yaml`) | 175 |
| Baseline manifest | `C:\Users\MONAMO~1\AppData\Local\Temp\opencode\ref_baseline.txt` (SHA-256 per file + size + mtime) |
| Untracked files in reference before this work | 38 (all pre-existing) |

These 152 modified/renamed/untracked entries were already present in the working tree when this execution started. The baseline above is the comparison point for �§19-style final verification.

---

## Phase 0 — Skeleton

### Planned scope

From `MASTER-PLAN.md` �§12:

> **P0 — Skeleton** | Create the project; set identity, namespace/applicationId, `MainActivity` package; manifest and permissions; minimum dependencies; architecture test | `flutter analyze` clean; no indoor token anywhere in the project; architecture test green

From �§1 (identity): directory `clients/flutter/ejust_campusfind`, pubspec `ejust_campusfind`, namespace and applicationId `eg.edu.ejust.campusfind`, launcher label **EJUST CampusFind**, Dart `^3.12.2`, Java/Kotlin 17.

From �§2 (permission set): `INTERNET`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` only; no background location, no Wi-Fi permissions, no foreground service, no `usesCleartextTraffic`, no `network_security_config.xml`.

From �§5 (assets): copy the three campus data assets from the reference.

### Implemented

- Created the project with `flutter create --project-name ejust_campusfind --org eg.edu.ejust --platforms android` (Android-only, matching the plan's structure which lists `android/...`).
- Corrected Android identity: `namespace` and `applicationId` → `eg.edu.ejust.campusfind`; moved `MainActivity.kt` to `kotlin/eg/edu/ejust/campusfind/` and changed its `package` declaration.
- `AndroidManifest.xml` rewritten: exactly the three approved permissions, `android:label="EJUST CampusFind"`, no `usesCleartextTraffic`, no network security config, `MAPS_API_KEY` injected via `${MAPS_API_KEY}` manifest placeholder.
- `build.gradle.kts`: `local.properties` → `MAPS_API_KEY` env → empty fallback, injected through `manifestPlaceholders`; Java/Kotlin 17.
- `pubspec.yaml`: name `ejust_campusfind`, Dart `^3.12.2`, dependencies `flutter_riverpod ^2.6.1`, `google_maps_flutter ^2.10.0`, `geolocator ^13.0.2`, `http ^1.6.0`, `archive ^3.6.1`, `connectivity_plus ^6.0.0`, `cupertino_icons`. **`provider` is absent.** `shared_preferences` / `path_provider` deliberately omitted: with Quick Access removed (R4/F12) and no other persistence in scope, the plan allows them "only if actually used".
- Assets copied from the reference (data, not code): `assets/navigation/ejust roads.kmz` (2519 B), `assets/config/ejust gates.kmz` (1747 B), `assets/config/gate_policy.json` (71 B).
- App skeleton: `lib/main.dart` (`ProviderScope` + `appProviderOverrides`), `lib/app/app.dart` (`CampusFindApp`, Material 3, normal theme), `lib/app/theme.dart` (plain Material 3 theme — no custom map styling, F5), `lib/app/providers.dart` (composition root override hook), `lib/presentation/shell/app_shell.dart` (minimal shell; P5 replaces the body).
- `analysis_options.yaml` tightened on top of `flutter_lints`.
- Architecture import-boundary test with four cases: known-layer check, dependency-direction check, data-layer isolation, and presentation→app restriction.

### Files created

- `clients/flutter/ejust_campusfind/` (35 files from `flutter create`, plus all additions below)
- `clients/flutter/ejust_campusfind/lib/main.dart`
- `clients/flutter/ejust_campusfind/lib/app/app.dart`
- `clients/flutter/ejust_campusfind/lib/app/theme.dart`
- `clients/flutter/ejust_campusfind/lib/app/providers.dart`
- `clients/flutter/ejust_campusfind/lib/presentation/shell/app_shell.dart`
- `clients/flutter/ejust_campusfind/test/architecture/import_boundary_test.dart`
- `clients/flutter/ejust_campusfind/assets/navigation/ejust roads.kmz`
- `clients/flutter/ejust_campusfind/assets/config/ejust gates.kmz`
- `clients/flutter/ejust_campusfind/assets/config/gate_policy.json`

### Files modified

- `clients/flutter/ejust_campusfind/pubspec.yaml` (name, description, deps, assets)
- `clients/flutter/ejust_campusfind/analysis_options.yaml`
- `clients/flutter/ejust_campusfind/android/app/build.gradle.kts`
- `clients/flutter/ejust_campusfind/android/app/src/main/AndroidManifest.xml`
- `clients/flutter/ejust_campusfind/android/app/src/main/kotlin/eg/edu/ejust/campusfind/MainActivity.kt` (created at the corrected path)
- `clients/flutter/ejust_campusfind/test/widget_test.dart`

### Files deleted

- `clients/flutter/ejust_campusfind/android/app/src/main/kotlin/eg/edu/ejust/ejust_campusfind/MainActivity.kt` (generated at the wrong package path, superseded by the corrected path)

### Verification

Commands run in `clients/flutter/ejust_campusfind`:

| Command | Result |
|---|---|
| `flutter --version --no-version-check` | `Flutter 3.44.9 • channel stable` / `Tools • Dart 3.12.2` — matches the plan's `^3.12.2` |
| `flutter create --project-name ejust_campusfind --org eg.edu.ejust --platforms android --no-pub .` | `Wrote 35 files. All done!` |
| `flutter pub get` | `Changed 65 dependencies!` — resolved, no conflicts |
| `flutter analyze` (first run) | 3 issues: `referenced_before_declaration` on a local helper in the architecture test, `no_leading_underscores_for_local_identifiers` on the same helper, unused `material.dart` import in `test/widget_test.dart` |
| `flutter analyze` (after fixes) | **`No issues found!` (ran in 2.8s)** |
| `flutter test` | **`00:01 +5: All tests passed!`** — 4 architecture tests + 1 widget boot test |
| Indoor-token scan over `lib/`, `test/`, `assets/`, `android/app/src/`, `pubspec.yaml`, `analysis_options.yaml` (28 files) | `floor` 0 · `radiomap` 0 · `knn` 0 · `fingerprint` 0 · `wifi` 0 · `indoor` 0 · `transition` 0 · `containment` 0 · `quick_access`/`QuickAccess` 0 · `provider:` 0 · `ChangeNotifier` 0 · `poi` 3 hits, all false positives ("break**poi**nts" in the two `flutter create` debug/profile manifests, "import **poi**nts" in an architecture-test comment) |

Not verified in P0: no APK build, no device run. Both are gated on `MAPS_API_KEY` (EXTERNAL DEPENDENCY, `MASTER-PLAN.md` �§15).

### Issues discovered

1. `flutter create --org eg.edu.ejust --project-name ejust_campusfind` derives the Android package as `eg.edu.ejust.ejust_campusfind`, not the required `eg.edu.ejust.campusfind`.
2. `MainActivity.kt` was generated under the derived package directory with a matching `package` declaration.
3. First `flutter analyze` run surfaced three lint/compile issues in the new test files.
4. The `poi` token scan produces false positives on the substring "point".

### Issues fixed

1. `build.gradle.kts` `namespace` and `applicationId` set to `eg.edu.ejust.campusfind`; `MainActivity.kt` moved to `kotlin/eg/edu/ejust/campusfind/` with `package eg.edu.ejust.campusfind`.
2. Declared `MAPS_API_KEY` manifest placeholder and `local.properties`/env lookup.
3. Hoisted and renamed the local path-normalization helper to `normalizePath`; removed the unused import. Re-ran analyze → clean; re-ran tests → 5/5 green.
4. Recorded as a known false positive; the final audit (P10) uses word-boundary matching for this token.

### Remaining issues

- `AppShell` body is a placeholder text widget. Expected: P5 replaces it with the map surface and the Buildings/Places/Gates/About panel. Not a defect carried forward — it is the P5 scope.
- No APK built and no device run yet. **EXTERNAL DEPENDENCY**: `MAPS_API_KEY` / `android/local.properties`.

### External information required

| ID | Item | Needed for | Can continue without it |
|---|---|---|---|
| EXT-001 | A valid `MAPS_API_KEY` (or an `android/local.properties` entry) | APK build and any on-device verification | Yes — analyze, unit tests and widget tests all run without it |
| EXT-002 | A reachable `map.beout.ai` from the dev host (currently HTTP 403) | Live backend verification of the 6-building dataset | Yes — tests use fixtures per the plan's �§13 |
| EXT-003 | A physical Android device with location permission granted | P10 runtime walkthrough (camera follow, arrival, off-route) | Yes — every navigation behaviour is unit-testable without a device |

### Acceptance criteria

`MASTER-PLAN.md` �§14 criteria attributable to P0:

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Builds/runs as a separate app with identity `eg.edu.ejust.campusfind` / "EJUST CampusFind", reference unmodified | **BLOCKED** | Identity is set in `build.gradle.kts` (`namespace`, `applicationId`) and `AndroidManifest.xml` (`android:label`); the build/run half needs EXT-001 |
| 9 | No indoor data/routing/positioning code or assets | **PASS** | Token scan: 0 real hits across 28 files |
| 10 | Strict MVVM, Riverpod only, `provider` absent | **PASS** | `pubspec.yaml` has no `provider`; token scan 0 hits for `provider:`/`ChangeNotifier`; 4 architecture tests green |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; `All tests passed!` (+5) |
| �§12 P0 exit | `flutter analyze` clean; no indoor token; architecture test green | **PASS** | All three demonstrated above |

### Phase status

**COMPLETE** — all P0 exit criteria met and verified. Criterion �§14.1 is partially deferred to the APK build (EXT-001) and is reported as BLOCKED rather than claimed.

### Evidence

- `flutter analyze` → `No issues found! (ran in 2.8s)`
- `flutter test` → `00:01 +5: All tests passed!`
- Architecture tests listed individually in the console: "every Dart source under lib/ compiles into a known layer", "layer dependency direction is respected", "domain and presentation never import the data layer", "presentation only reaches app/ through the composition root"
- `pubspec.yaml` dependency block contains no `provider` entry
- `AndroidManifest.xml` contains exactly three `<uses-permission>` lines and no `usesCleartextTraffic`
- Reference baseline captured (175 files hashed) before any write

## Phase 1 - Core utilities

### Files created

| Path | Purpose |
|---|---|
| `lib/core/config/app_config.dart` | Every compile-time configurable value: campus identity, backend base URL, the single permitted endpoint, OSRM base URL, map zoom limits, asset keys, campus bounding box. Overridable via `--dart-define`; no other file in `lib/` holds a host literal (F14). |
| `lib/core/util/result.dart` | `Result`/`Success`/`Failure`/`AppError` so data sources report failures as state instead of throwing. |
| `lib/core/util/geo.dart` | Great-circle math: haversine distance, initial bearing, bearing normalisation, destination point, segment projection (point + along-segment parameter), distance-to-path, distance-along-path (the F2 progress primitive), path length, bounding boxes. |
| `lib/core/util/kmz.dart` | `KmzParser`: ZIP decode, locate the single KML entry, placemark name/Point/LineString extraction, KML `lon,lat[,alt]` to `LatLng`, out-of-range and unparsable coordinate rejection. |
| `test/unit/app_config_test.dart` | Configuration invariants. |
| `test/unit/geo_test.dart` | Geometry and `Result` invariants. |
| `test/unit/kmz_test.dart` | KML/KMZ parsing invariants. |

### Test results

| Command | Result |
|---|---|
| `flutter analyze` (after fixes) | `No issues found! (ran in 2.2s)` |
| `flutter test` | `00:01 +47: All tests passed!` (from 5 in P0) |

### Issues discovered

1. `const_eval_method_invocation`: `String.fromEnvironment` defaults cannot be post-processed by a method inside a `const` declaration, so `serverUrl`/`osrmBaseUrl` had to become getters.
2. The architecture test forbade `core/` from importing anything internal, which rejected `core/util/kmz.dart` importing `core/util/result.dart`. Same-layer imports inside `core/` are legitimate, so the rule was relaxed to allow `core/` to import `core/`.
3. Three geometry test expectations were wrong, not the code:
   - A due-east great-circle *initial* bearing at latitude 30 is ~89.75 degrees, not 90. Travelling along a parallel does not follow a great circle. The test was corrected to 89.75 +/- 0.05 and an exact-90 case at the equator was added.
   - The `distanceAlongPathMeters` fixture segments are 173 m and 200 m, not the 200 m/200 m the test assumed. Expectations are now derived from `Geo.distanceMeters` so the test asserts the along-path contract rather than a coordinate guess.
   - `prefer_const_declarations` lints in two test files.

### Issues fixed

1. `serverUrl` and `osrmBaseUrl` converted to getters; trailing-slash stripping moved to call time. Re-ran analyze clean.
2. Import-boundary rule corrected and the doc table in the test updated to match.
3. Test expectations corrected as described; two `final` declarations made `const`.

### Report integrity repair

Ten CP-1252 section-sign bytes (0xA7) had been written raw into this otherwise UTF-8 file, corrupting every `MASTER-PLAN.md` section reference in the P0 section (rendered as `A15`, `A12`, `A14`). The file is append-only, so history was not rewritten; the bytes were re-encoded in place to proper UTF-8, which restores the intended `section` references without altering a single reported fact. All content appended after this point is ASCII.

### Acceptance criteria

`MASTER-PLAN.md` section 14 criteria attributable to P1:

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 3 | No fabricated data, hosts, DNS, TLS, map keys, IDs or URLs | **PASS** | `AppConfig` is the only host source; every default is either the verified backend default or the verified public OSRM default. The single `map.beout.ai` 403 is reported, not worked around. |
| 4 | Real backend fields, no field invention | **PASS** | No backend field is parsed in P1; the endpoint and shape are consumed in P3. |
| 10 | Strict MVVM, Riverpod only | **PASS** | `core/` imports only `core/` and packages; architecture test enforces it. |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 47/47 tests |
| section 12 P1 exit | Unit tests pass | **PASS** | 47/47 |

### Phase status

**COMPLETE** - all P1 exit criteria met and verified.

### Evidence

- `lib/core/util/geo.dart` - `SegmentProjection` returns the closest point on a segment together with its clamped `t`, which the P2 convergence pass needs to distinguish a genuine interior junction from a near-endpoint case.
- `lib/core/util/kmz.dart` - failures are returned as `kmz_unreadable` / `kmz_no_kml` rather than thrown, so a broken asset becomes visible state.

## Phase 2 - Campus map data

### Files created

| Path | Purpose |
|---|---|
| `lib/domain/routing/route_graph.dart` | `RouteGraph`: vertex list, edges, adjacency, degree, junction count, connected-component count, nearest-vertex search, and Dijkstra shortest path. `RouteEdge` and `RoutePath` are value types. Contains the two-stage builder: vertex-to-vertex merging, then a convergence pass that splices dangling endpoints onto other roads interiors. |
| `lib/data/models/campus_gate.dart` | `CampusGate` (id, name, lat, lon, enabled, snap distance). Gates are a separate top-level entity, never a Services entry. |
| `lib/data/models/campus_map_data.dart` | `CampusMapData`: graph + enabled gates + disabled gates + policy, plus the usable-gate filter. |
| `lib/data/datasources/asset_loader.dart` | `AssetBytesLoader` typedef and the `rootBundle` implementation, so asset I/O has one seam and is injectable in tests. |
| `lib/data/datasources/roads_kmz.dart` | `RoadsKmzSource.buildGraph` (KMZ bytes to `RouteGraph`) and `GatePolicy.parse` (the `gate_policy.json` schema). |
| `lib/data/repositories/gate_repository.dart` | `CampusGates` (enabled/disabled/preferred) and `GateRepository`: load gate KMZ, apply policy, annotate each gate with its distance to the nearest road vertex. |
| `lib/data/repositories/campus_map_repository.dart` | `CampusMapRepository`: loads roads and gates, returns `CampusMapData` or a `Result` failure. |
| `test/unit/campus_map_repository_test.dart` | Loads the real packaged assets and asserts the verified topology, gate policy and snap distances. |
| `test/unit/route_graph_test.dart` | Graph construction, convergence pass, topology metrics, nearest-vertex and Dijkstra behaviour, immutability. |
| `test/unit/gate_repository_test.dart` | Gate policy parsing, gate model, real-asset loading, degraded-asset behaviour, road-source failure codes. |

### Verified against the real packaged assets

| Quantity | Plan / reference expectation | Measured | Status |
|---|---|---|---|
| Road graph vertices | 52 | 52 | MATCH |
| Road graph edges | 64 | 64 | MATCH |
| Junctions (degree >= 3) | 28 | 28 | MATCH |
| Connected components | 1 | 1 | MATCH |
| Road placemarks | 25 LineStrings + 1 Point | 25 LineStrings | MATCH |
| Gate placemarks | 4 points | 4 | MATCH |
| G1 gate-to-road distance | 5.1 m | 5.08 m | MATCH |
| G2 gate-to-road distance | 27.7 m | 27.71 m | MATCH |
| G3 gate-to-road distance | 16.1 m | 16.12 m | MATCH |
| G4 gate-to-road distance | 202.8 m | 202.83 m | MATCH |
| Enabled gate per `gate_policy.json` | G2 only | G2 only | MATCH |

The KMZ and the policy JSON were copied verbatim from the reference project in P0; they are the approved-data artefacts, and the readings above are measurements of the shipped files, not new data.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.9s)` |
| `flutter test` | `00:03 +103: All tests passed!` (from 47 in P1) |

### Issues discovered

1. **The first graph builder did not reproduce the verified topology.** It merged coincident vertices at 1 m and collapsed duplicate edges, yielding 60 vertices, 43 edges, 4 junctions and **17 disconnected components**. A 17-component campus road network is unroutable, so this was a real defect, not a tolerance question.
2. Cause: the campus KMZ draws roads as separate features whose endpoints land on the *interior* of other roads. Endpoint sharing alone cannot connect them. The tolerance sweep proved the problem was not tunable: 0.2 m through 10 m all produced 17 components.
3. A sweep test asserting tolerance-insensitivity was itself wrong and was removed once the topology matched.
4. `RouteEdge.other` was written as `int get other(int vertex)`, which is not valid Dart (a getter cannot take parameters), and two other compile errors surfaced with it: `rootBundle.load` returns `ByteData` rather than `Uint8List`, and `CampusGate` was missing an import in the campus-map repository.
5. Two `route_graph_test` expectations were wrong rather than the code: a 150 m junction threshold collapses the whole 170 m fixture to 2 vertices, not 3; and a point 96 m east of the trunk is out of range at a 50 m tolerance, so the assertion was inverted.
6. The campus-map repository carried `_gatesAsset` and `_policyAsset` fields it never used, since `GateRepository` owns those assets.

### Issues fixed

1. Rewrote the builder to match the verified reference algorithm exactly: 15 m junction threshold for vertex merging, no edge de-duplication, and an iterative-to-fixpoint convergence pass that splits a road segment at the projection point when a dangling endpoint lands inside it. No coordinate is ever moved - only topology is added. Result: 52/64/28/1 exactly.
2. Added `Geo.projectOntoSegment` returning the closest point plus the clamped along-segment parameter, and gated the splice to `0.05 < t < 0.95` so genuine interior junctions are joined while near-endpoint cases stay with vertex merging. Both test expectations corrected, and the tolerance-sweep test removed.
3. `RouteEdge.other` changed to a method; `bundleAssetBytes` converts the `ByteData` to a `Uint8List` with the correct offset and length; the missing `campus_gate.dart` import added.
4. `CampusMapRepository` now takes only the loader and the roads asset, using initialising formals; the two unused fields removed.

### Degradation behaviour chosen (and why it is safe)

| Condition | Behaviour | Reason |
|---|---|---|
| Roads KMZ missing or corrupt | `Failure` with `kmz_unreadable` / `kmz_no_kml` | Campus navigation cannot be offered on unknown roads. Fails loudly instead of pretending. |
| Roads KMZ parses but holds no LineStrings | `Failure` with `campus_roads_empty` | A silently empty graph is indistinguishable from a routable one and would push every trip onto public roads. |
| Gates KMZ missing or corrupt | `Failure` with `campus_gates_unreadable` | Without a gate there is no handover point from public roads, so the cascade cannot complete. |
| Gates KMZ parses but holds no points | `Failure` with `campus_gates_empty` | Same reasoning; distinguishes "no gate data" from "unreadable file". |
| `gate_policy.json` missing or corrupt | Falls back to `GatePolicy.permissive` (every gate enabled, no preference) | The planner still requires a gate to snap onto the campus road network, so this degrades to "any usable gate", never to an invented route. Losing a policy file should not remove navigation. |
| Gate policy present but names unknown gates | Unknown ids simply match no gate | A stale policy entry cannot disable the campus by accident. |

### Design notes

- `usableSnapRadiusMeters` is 60 m. The three real gates sit 5.1 m, 16.1 m and 27.7 m from the road network; G4 sits 202.8 m away. The 60 m radius accepts the real gates and would reject G4 even if a future policy re-enabled it, which is asserted by a test.
- `RouteGraph.fromPolylines` merges by first match in vertex insertion order, matching the verified reference behaviour, so a rebuild on the same asset reproduces the same 52/64/28/1 topology.
- Vertices and edges are exposed unmodifiable; a test asserts mutation throws.
- `RouteGraph` is pure domain code: no I/O, and the only non-`core` import is the shared `LatLng` value type.

### Acceptance criteria

`MASTER-PLAN.md` section 14 criteria attributable to P2:

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 2 | Campus data only from the real backend plus the two bundled KMZ assets and `gate_policy.json` | **PASS** | `CampusMapRepository` reads only `roadsKmzAsset`, `gatesKmzAsset` and `gatePolicyAsset`. No other data source exists. |
| 6 | R7 untrusted coordinates surfaced, never routed to | **PARTIAL** | Campus assets are verified to lie inside the campus bounding box by test. The R7 state for *backend building* coordinates is P3 scope. |
| 8 | Route quality reported honestly | **PARTIAL** | `RoutePath` carries the true edge-summed distance. `RouteQuality` labelling is P6 scope. |
| 10 | Strict MVVM | **PASS** | `domain/routing` imports no `data/`; architecture test green. |
| 11 | analyze and test clean | **PASS** | `No issues found!`; 103/103 tests |
| section 12 P2 exit | Graph and gate unit tests pass, verified topology and snap distances preserved | **PASS** | Table above; 52/64/28/1 and 5.1/27.7/16.1/202.8 m all reproduced |

### Phase status

**COMPLETE** - all P2 exit criteria met and verified. The first builder was wrong (17 components) and was replaced; the shipped builder reproduces the verified topology exactly.

### Evidence

- `flutter test test/unit/campus_map_repository_test.dart` printed `TOPOLOGY vertices=52 edges=64 junctions=28 components=1` and `GATES [G2:27.7m, G1:5.1m, G3:16.1m, G4:202.8m]` from the packaged assets.
- `flutter test` full suite: `00:03 +103: All tests passed!`.
- `assets/config/gate_policy.json` content confirmed byte-identical to the reference: preferred `G2`, disabled `["G1","G3","G4"]`.

## Phase 3 - Buildings

### Files created

| Path | Purpose |
|---|---|
| `lib/data/models/campus_building.dart` | `CampusBuilding` (1:1 with the backend space record), `SpaceType` (closed enum plus `unknown`), `CoordinateStatus`. Optional `description` / `address` / `url` / `bucode` are null unless the backend really supplied a value. No category field exists. |
| `lib/data/datasources/backend_api_client.dart` | The single permitted call: `POST {SERVER_URL}/api/mapping/space/public` with body `{}`, gzip-aware body decoding, timeout, and HTTP/network/malformed failures returned as `Result` failure codes. |
| `lib/data/repositories/building_repository.dart` | `BuildingRepository.fetchBuildings` and `BuildingSnapshot` (buildings plus the drop counts needed to explain what was removed and why). |
| `test/unit/building_repository_test.dart` | 48 tests: parsing, R7 coordinate trust, `SpaceType`, campus scope, search, verified dataset, filtering, and API error mapping. |

### Endpoint contract as implemented

| Aspect | Behaviour | Source |
|---|---|---|
| Method and body | `POST` with `{}`, `Content-Type: application/json` | Verified live probe in the migration report; matches the reference client |
| Envelope | `{"spaces": [...], "buildings": [...]}`; only `spaces` is read, so the duplicate key cannot double the list | Plan section 5 |
| Compression | `Accept-Encoding: gzip` requested; body inflated when the gzip magic bytes are present | Plan section 5 notes the response is gzip-encoded |
| In-band errors | A 200 response carrying `{"status":"error","message":...}` becomes `backend_error` with the server message | Reference client behaviour |
| Endpoint construction | `AppConfig.spacesPublicUri()`, from `SERVER_URL` + `/api/mapping/space/public` | F4 |

Error codes: `backend_timeout`, `network_unavailable`, `backend_status` (with the HTTP code in the message), `backend_error`, `backend_malformed`.

### R7 implemented as a first-class coordinate trust state

`CoordinateStatus` is `valid` / `missing` / `unparsable` / `outsideCampus`. Only `valid` yields a `LatLng`.

| Rule | Consequence |
|---|---|
| A record with no `buid` is discarded | It cannot be addressed, de-duplicated or navigated to, so keeping it would be unusable state |
| Missing, null or blank coordinates become `missing` with null lat/lon | **The reference coerces unparsable coordinates to `0.0`**, which silently places a building at Null Island in the Gulf of Guinea. That defect is not reproduced. |
| Present-but-garbage, `NaN` or infinite coordinates become `unparsable` | A bad value is reported, never rounded to a location |
| Finite but out-of-campus coordinates become `outsideCampus`, value retained for diagnostics | A building in another country is recognised as untrustworthy without discarding the record |
| Bounding-box edges are inclusive | The campus corners are valid |
| The building is still listed, searchable and identifiable in every case | R7 exactly: listed and searchable, Navigate disabled |
| `is_published` explicitly false is dropped and counted | The server already filters; the client re-checks so an unpublished record can never reach the map |
| A missing `is_published` counts as published | The server is the filter; absence must not silently hide a real building |
| A `cuid` different from `AppConfig.campusCuid` is dropped and counted | Campus scope, as the reference implements it. The verified E-JUST dataset has no `cuid`, so all six records pass. |
| Duplicate `buid`s collapse to the first record | Prevents double markers for one entity |

### Fixture provenance (important) -

Verified from the record: the six names (B7, E-JUST Blue Hall, Food court, National Bank branch, E-JUST Administrative Building, E-JUST Library), their real `buid`s (as recorded in the reference constants), and the field set present on the live payload.

NOT verified and therefore generated: the per-building coordinate values. The migration report records names and field sets, not coordinates, and the live endpoint returns 403 from this host. The fixture therefore places buildings at synthetic offsets around the verified E-JUST centroid (30.859877, 29.563241). These are test doubles for asserting client behaviour; no `lib/` code contains them, and they are not presented as campus facts anywhere.

### Issues discovered

1. `dart:io` `GZipCodec().decode` rejects the gzip stream produced by the `archive` package with `FormatException: Filter error, bad data`, so the gzip test failed. The body decoder now inflates with `GZipDecoder` from the already-present `archive` dependency, which round-trips correctly and is also cross-platform.
2. Test-file compile errors: `const List<String> verified...` should have been `const String`; `dart:async` and `dart:typed_data` were missing imports.
3. `GZipEncoder().encode` takes an `InputStream` in `archive` 3.6.1, not a `List<int>` and not an `Archive`; two attempts were needed to build a valid gzip fixture.

### Issues fixed

1. `BackendApiClient._decodeUtf8` switched to `GZipDecoder().decodeBytes`; the gzip test now passes. The scratch test used to isolate the codec failure was deleted.
2. Test declarations and imports corrected.
3. Fixture built with `InputStream`.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.7s)` |
| `flutter test` | `00:03 +152: All tests passed!` (from 103 in P2) |

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 2 | Campus data only from the real backend | **PASS** | `BuildingRepository` calls one endpoint and returns its records. No bundled list, no fallback data, no hardcoded buildings. |
| 3 | No fabricated data, hosts or URLs | **PASS** | Host comes from `AppConfig`; all optional fields null unless populated. Test-only synthetic coordinates are documented as test doubles. |
| 4 | Real backend fields, no invention | **PASS** | Only the eleven verified fields are read. `SpaceType` mirrors the closed `fSpaceTypes` enum and keeps an unrecognised value as `unknown` instead of coercing. |
| 5 | No category system, no name-based inference | **PASS** | No category field on the model; a test asserts no fixture record carries one. |
| 6 | R7 untrusted coordinates surfaced, never routed to | **PASS** | Four trust states, tests per state, and a test that an unusable building is still listed and searchable |
| 7 | No fake or unverified campus data | **PASS** | Newly published backend buildings appear with no code change (tested) |
| 10 | Strict MVVM | **PASS** | `data/` only; architecture test green |
| 11 | analyze and test clean | **PASS** | `No issues found!`; 152/152 |
| section 12 P3 exit | Unit tests for validation and parsing pass | **PASS** | 48 building tests |

### Phase status

**COMPLETE** - all P3 exit criteria met and verified.

### Evidence

- Test asserting the duplicate envelope key does not double the list: 6 records in, 6 out.
- Test asserting the request is `POST /api/mapping/space/public` with body `{}`.
- Test asserting a `building_newly_published` record appears as the 7th building with no code change.

---

## Phase 4 - Location (device GPS, accuracy gating, permission flow)

### Scope

Device-side positioning only. The app has no indoor positioning source, so every trust decision is a
pure function of what the platform reports. Nothing in this phase adds a compass, magnetometer,
Wi-Fi or sensor fusion plugin, and nothing depends on a floor or an indoor space.

### Files added

| File | Responsibility |
|---|---|
| `lib/domain/location/gps_sample.dart` | `GpsQuality`, `GpsSample`, `HeadingTracker` |
| `lib/domain/location/location_source.dart` | `LocationPermissionState`, `LocationAvailability`, `LocationAccess`, `LocationSource`, `ConnectivitySource` |
| `lib/data/datasources/geolocator_location_source.dart` | `geolocator` adapter, plugin-error to `AppError` mapping |
| `lib/data/datasources/connectivity_source.dart` | `connectivity_plus` adapter |
| `lib/presentation/location/location_view_model.dart` | `LocationState`, `LocationViewModel`, Riverpod providers |
| `test/unit/gps_sample_test.dart` | quality thresholds, sample semantics, heading tracker |
| `test/unit/location_view_model_test.dart` | permission flow, fix handling, subscription lifecycle |

`lib/core/config/app_config.dart` was extended with the location thresholds so they are not magic
numbers in the domain layer.

### Thresholds (single source of truth, in `AppConfig`)

| Constant | Value | Meaning |
|---|---|---|
| `gpsGoodAccuracyMeters` | 15 | good enough for arrival and turn decisions |
| `gpsPoorAccuracyMeters` | 30 | usable, not good enough for turn decisions |
| `gpsRejectAccuracyMeters` | 50 | usable for coarse positioning, rejected above it |
| `approximateAccuracyMeters` | 1000 | treated as an Android approximate-location fix |
| `locationLastKnownMaxAge` | 2 min | a cached fix older than this is not drawn as the position |

### Design decisions

| Decision | Rationale |
|---|---|
| `GpsQuality` is an enum with an explicit `fromAccuracy` classifier | Trust is one function, not scattered `if (accuracy > ...)` checks in the UI |
| A null, negative, `NaN` or infinite accuracy is `unusable` | Some platform APIs report `-1` for "accuracy unknown"; treating that as perfect precision is exactly backwards |
| `unusable` fixes are still delivered to the state | The UI must be able to say *why* the position is missing instead of showing an unexplained blank map |
| `isUsable` covers good, fair and poor; `isAccurate` is good only | Positioning tolerates a 50 m radius; arrival and turn decisions do not |
| `looksApproximate` is a separate flag from quality | Android's approximate-location grant produces a large but finite accuracy, which is a different message from "GPS is bad" |
| Heading is derived from movement, not a magnetometer | No new plugin, no permission, no calibration prompt; standing still yields null rather than a bearing made of GPS noise |
| Heading requires at least `3 m` of displacement between fixes | Below that, bearing is dominated by multipath noise |
| Heading is smoothed `0.3` along the shortest arc | A wrap through north must not swing the estimate 180 degrees the long way round |
| `minimumDisplacementMeters` is constructor-injected | Tested, and tunable if device behaviour demands it |
| `LocationAccess` folds service state and permission into one value | The UI has exactly four cases to render, and each carries its own message and actions |
| Denials are states, not errors | A refused permission is a normal outcome; it must never surface as a crash or a red error banner |
| `requestPermission` re-checks access instead of trusting the returned enum | `requestPermission` can return `denied` on some platforms even when the user granted, and vice versa |
| `refreshAccess` and `requestPermission` await `startWatching` | A caller that awaited them gets a truthful `isWatching` instead of a half-initialised state |
| `startWatching` cancels prior subscriptions before re-subscribing | The reference stacked subscriptions across navigation sessions; repeated calls cannot leak |
| `dispose` cancels every subscription and resets the heading tracker | A leaked position stream is a battery and privacy defect, not a cosmetic one |
| A position stream error stops watching and keeps the last sample | The map keeps its last known good marker; the app does not crash on a transient GPS error |
| Last-known fix seeds the position only when fresher than 2 minutes | Avoids a blank map on launch without placing the user at a stale location |
| `connectivity_plus` reports interfaces, not reachability | It decides whether a backend retry is worth attempting; it never re-labels a `403` or timeout as "offline" |
| A failing connectivity channel is treated as online | The request then fails honestly instead of the app inventing an offline state |

### No compass

Adding `flutter_compass` would have required a second runtime permission and produced worse results:
a phone lying flat on a desk reports a stable but meaningless heading. Movement-derived heading is
null while stationary, which is the only honest value in that case.

### Issues discovered

1. `ConnectivityPlusSource([this._connectivity = Connectivity()])` failed analysis with
   `non_constant_default_value`: `Connectivity()` is a plugin factory, not a compile-time constant.
2. `refreshAccess` returned before `startWatching` finished, so tests and callers observed
   `isWatching == false` immediately after a successful access check.
3. Three P4 test expectations contradicted the implemented (and documented) threshold semantics:
   `GpsQuality.poor` is inside the reject radius and therefore usable; and a smoothed turn from east
   to north must *decrease* toward zero rather than increase. The tests were wrong, not the code.
4. A heading test used a 0.478 m displacement against a `0.5 m` threshold; the step was smaller than
   the threshold it was testing.

### Issues fixed

1. `ConnectivityPlusSource` now takes no constructor argument and resolves `Connectivity()` from a
   getter, keeping the class const-constructible.
2. `refreshAccess` and `requestPermission` now `await startWatching()` / `stopWatching()`.
3. Test expectations corrected to the documented semantics, and each now asserts the reason
   explicitly (for example that the default tracker ignores sub-3 m movement).
4. The displacement step was widened to ~0.86 m and the comparison against the default tracker
   added.
5. `lastKnownSample` maps the plugin `Position` to a `GpsSample`; an earlier draft returned the
   `Position` typed as `GpsSample?`, which is unsound even where the analyser did not flag it.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.8s)` |
| `flutter test` | `00:03 +189: All tests passed!` (from 152 in P3) |

P4 added 37 tests: 17 for quality/sample/heading and 20 for the permission flow, fix handling and
subscription lifecycle.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 8 | Device GPS positioning | **PASS** | `GeolocatorLocationSource.watchPosition` streams fixes; `LocationViewModel` owns the subscription and cancels it on dispose |
| 9 | Permission handling | **PASS** | Denied, denied-forever, service-disabled and granted paths each tested; settings route invoked only for a permanent denial |
| 10 | Strict MVVM | **PASS** | Ports in `domain/`, plugins in `data/`, Riverpod state in `presentation/`; architecture test green |
| 11 | analyze and test clean | **PASS** | `No issues found!`; 189/189 |
| section 12 P4 exit | Location tests pass; no leaked subscriptions | **PASS** | Cancel-on-dispose and no-double-subscribe tests both green |

### Phase status

**COMPLETE** - all P4 exit criteria met and verified.

### Evidence

- Test: a `unusable` fix is retained in `lastSample` but `usableSample`, `accurateSample` and
  `position` are all null.
- Test: a permanent denial sets `needsPrompt == false` and `openSystemSettings` reaches the plugin.
- Test: disposing the `ProviderContainer` cancels the position stream (`onCancel` observed).
- Test: `startWatching` twice leaves exactly one live subscription per source.
- Test: a position stream error sets `isWatching == false` without throwing.
- Test: a heading turn from east to north lands strictly between the old and the new bearing.
---

## Phase 5 - Map shell (basemap, camera, markers, bottom sheet, panel)

### Scope

The first surface a user sees: the campus map, a draggable panel, and the four browsing tabs. This
phase renders what P2-P4 already produce and adds no new data source, no routing (P6) and no
navigation (P7).

### Files added

| File | Responsibility |
|---|---|
| `lib/presentation/map/map_view_model.dart` | `MapState`, `MapViewModel`, `MapCameraRequest`, `MapSelection`, road-network toggle |
| `lib/presentation/map/campus_map_view.dart` | Google basemap, building and gate markers, road polylines, accuracy circle, status banner, camera intents |
| `lib/presentation/shell/app_shell.dart` | map plus `DraggableScrollableSheet`, post-frame bootstrap, `mapSurfaceProvider` seam |
| `lib/presentation/shell/campus_panel.dart` | panel chrome, location chip, the four tabs |
| `lib/presentation/shell/panel_sections.dart` | shared panel widgets |
| `lib/presentation/buildings/buildings_tab.dart` | building list and the R7 warning rows |
| `lib/presentation/places/places_tab.dart` | Places (Services) over real backend buildings |
| `lib/presentation/gates/gates_tab.dart` | enabled and disabled gate lists |
| `lib/presentation/shell/about_tab.dart` | data sources, outdoor GPS scope, indoor exclusions |
| `test/support/fakes.dart` | shared deterministic fakes and fixtures |
| `test/widget/app_shell_test.dart` | 19 shell, panel, tab and permission-chip tests |

`lib/app/providers.dart` became the composition root: it holds the repository providers and re-exports
the data types the presentation layer needs, which is what keeps
`test/architecture/import_boundary_test.dart` green. `test/widget_test.dart`, the old counter-app smoke
test, was deleted: it asserted the removed template counter title.

### Design decisions

| Decision | Rationale |
|---|---|
| `mapSurfaceProvider` is a provider holding the map widget | `GoogleMap` is a platform view with no test implementation; the sheet, panel and chip still have to be verifiable without a device |
| Map data and buildings load as two independent futures | A failing building backend must not blank the map, and the two failures are reported separately |
| Camera is a one-shot `MapCameraRequest` held in state and consumed by the map | A view model cannot own a `GoogleMapController`; one-shot intents keep the view imperative and the view model free of platform types |
| Selection is a sealed `MapSelection` | A building and a gate are different entities; two nullable ids would allow an impossible state where both are set |
| Only `mappableBuildings` get markers | R7: buildings without usable coordinates stay listed and searchable but never become a map target |
| Disabled gates are listed but never drawn | `gate_policy.json` disables G1, G3 and G4; drawing them would advertise a routing entry that does not exist |
| Road polylines are a toggle, not permanent chrome | 64 edges are noise at street zoom; the toggle is how a user clears the view |
| Accuracy is drawn as a `Circle` | An accuracy radius is a claim about precision; a bare dot overstates the fix |
| The panel chrome resizes the sheet through `DraggableScrollableController` | Dragging the lists instead fights with scrolling them, and it left the collapsed sheet with no way back |
| `initialExtent` is 0.40, and a `LayoutBuilder` drops the chip below 260 px | The denied-permission state is the tallest chip; at 0.32 on a 780 px screen the chrome plus the tab bar overflowed the sheet by 2.4 px |
| `TabBar` is not scrollable | Four short labels always fit a phone-width sheet, so no tab is parked off the right edge |
| The chip reports an approximate fix before it judges quality | An Android approximate-location grant is coarse by definition; "Approximate position" is more useful than "GPS too weak" |
| A `unknown` access value was added to `LocationAvailability` and `LocationPermissionState` | Before the platform has answered, the UI must claim nothing; the previous four values forced a false reading |

### Issues discovered

1. `ListTile` asserted that its background colour and ink splashes may be invisible: a coloured
   `Container` between the panel and its rows hides both. The panel surface is now a `Material`.
2. `DraggableScrollableController.jumpTo` takes a fraction, not pixels; passing pixels tripped its
   `0 <= size <= 1` assert.
3. At the original 0.32 collapsed extent the panel overflowed by 2.4 px whenever the permission chip
   was at its tallest, which is exactly the state a first-time user sees.
4. The `TabBar` was scrollable and parked the fourth tab off the right edge of a phone-width sheet, so
   a tap on "About" silently missed.
5. The test finders skip a `TabBarView` page as offstage even when it is the page on screen, so
   `find.text` matched nothing inside any tab. Assertions now look inside the tab's own subtree with
   `skipOffstage: false`, which also stops a building name shared by two tabs from matching the wrong
   page.
6. A panel that could only be resized by dragging its lists could not be reopened once collapsed.

### Issues fixed

1. Panel surface changed from a decorated `Container` to a rounded `Material`.
2. `_resize` converts the drag delta to a fraction before calling `jumpTo`.
3. `initialExtent` raised to 0.40 and the chip is dropped below 260 px of panel height, so the panel
   can no longer overflow whatever the chip says.
4. `TabBar` is no longer scrollable; every tab is reachable at any sheet width.
5. Tab-content assertions are scoped per tab with `skipOffstage: false`; the panel is opened by the
   same header drag a user performs, and `pumpApp` asserts that it actually opened.
6. The coarse-fix branch was moved ahead of the quality thresholds in the chip.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 2.0s)` |
| `flutter test` | `00:06 +209: All tests passed!` (from 189 in P4) |

P5 added 21 tests and removed 1: 19 in `test/widget/app_shell_test.dart`, 2 covering the new
`unknown` access state in `test/unit/location_view_model_test.dart`, minus the deleted counter-app
smoke test.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 2 | Buildings come from the backend; no hardcoded list | **PASS** | every shell test injects a `BuildingRepository`; the header count is the loaded snapshot length |
| 5 | Places lists real backend buildings, no invented taxonomy | **PASS** | the Places tab asserts real names and that no "Category" text exists anywhere in it |
| 6 | Gates are browsable on their own surface, never a Services tile | **PASS** | a separate Gates tab; no gate appears in the Places list |
| 9 | No indoor data, routing or positioning | **PASS** | the About tab states the exclusions; the P0 token grep stays clean |
| 10 | Strict MVVM, Riverpod only | **PASS** | `MapViewModel` owns state, `mapSurfaceProvider` is the only view seam, architecture test green |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 209/209 |
| P5 exit | App runs and shows the campus map | **PARTIAL - EXTERNAL DEPENDENCY** | shell, panel, tabs, markers, selection and camera verified headlessly against the real view models; the real `GoogleMap` needs `MAPS_API_KEY` in `android/local.properties`, absent on this host, so on-device rendering cannot be checked here |

### Amendment to Phase 4

`LocationAvailability.unknown` and `LocationPermissionState.unknown` were added during P5 so the
permission chip can render nothing at all until the platform has answered. The P4 decision table
records "the UI has exactly four cases to render"; the honest count is now five, of which `unknown`
is the pre-answer state and is never presented to the user as a denial.

### Phase status

**CODE COMPLETE, EXIT CRITERION PARTIALLY VERIFIED** - every P5 exit criterion that can be checked
without a Google Maps key passes. The remaining item is the on-device render, which is blocked on
`MAPS_API_KEY` (EXTERNAL DEPENDENCY) and is carried into the P10 walkthrough.

### Evidence

- Test: the panel opens by dragging its header, and the sheet grows past its initial extent.
- Test: a building with missing coordinates is listed, badged, and tapping it leaves the selection
  empty (R7).
- Test: a failed building load renders the backend error code rather than an empty list.
- Test: disabled gates are listed under "Out of service" and tapping one sets no selection.
- Test: a plain denial offers "Allow", and granting it starts the fix stream.
- Test: a permanent denial routes to system settings and never offers "Allow".
- Test: an approximate fix is labelled "Approximate position".
- Test: an unparsable coordinate is reported as such instead of being silently dropped.
## Phase 6 - Routing (single planner, five-step cascade)

### Scope

One `RoutePlanner` (F1), one `RouteQuality` per produced route (F3), and the
public-road client that step 2 needs. No navigation UI: that is P7.

### Files added

- `lib/domain/routing/route_quality.dart` - `customGraph`, `hybrid`, `osrmSpliced`,
  `osrm`, `approximate`, each with a user-facing `label` and `isApproximate`.
- `lib/domain/routing/outdoor_route.dart` - the produced route: geometry,
  distance, duration, quality, and the optional `gateId` that lets the UI
  highlight the gate it entered by. See the deviation record below.
- `lib/domain/routing/public_road_router.dart` - the port the planner depends on
  (`PublicLeg`: points, distance, duration) and nothing more.
- `lib/domain/routing/route_planner.dart` - the cascade, plus the `RoutingGate`
  projection of a campus gate.
- `lib/data/datasources/osrm_client.dart` - the OSRM implementation of that port.
- `test/unit/route_planner_test.dart`, `test/unit/osrm_client_test.dart`,
  `test/unit/route_planner_wiring_test.dart`.

### Files changed

- `lib/app/providers.dart` - adds `routePlannerProvider`, built from `OsrmClient`.
- `lib/data/models/campus_map_data.dart` - adds `routingGates`, the single
  translation point from `CampusGate` to `RoutingGate`.

### The cascade as implemented

| Step | Condition | Quality | Needs |
|---|---|---|---|
| 1 | both endpoints snap to the campus graph within 60 m | `customGraph` | nothing external |
| 2 | a usable gate has a campus path to the destination **and** OSRM reaches the gate | `hybrid` | OSRM |
| 3 | OSRM's line ends more than 60 m short and the campus graph can reach the destination from there | `osrmSpliced` | OSRM |
| 4 | OSRM has a path end to end | `osrm` | OSRM |
| 5 | nothing else applies | `approximate` | nothing |

- The first step that produces a route wins; there is one planner and no
  duplicated cascade anywhere in the project.
- **Gate selection** is by total cost - public leg plus campus leg - with ties
  broken on gate id, so the same request always yields the same route. A gate is
  only considered when it is enabled, inside the 60 m snap radius, and actually
  connected to the destination on the campus graph. The verified distances decide
  it: 5.1 m, 27.7 m and 16.1 m pass, 202.8 m never reaches the routing server.
- **Durations** come from the routing server when it supplies one; campus-road
  and straight-line legs are estimated at 1.35 m/s.
- **Endpoints** outside the configured campus bounds fail with
  `route_endpoint_off_campus` rather than producing a nonsense route. Inside
  them, `plan` always succeeds: a route is returned even when nothing else is
  available, flagged `approximate`.
- The public-road client treats every transport failure as "no route" - a
  routing server being down is a normal condition, and the cascade exists for it.
- Geometry is requested as GeoJSON, not an encoded polyline: it costs more bytes
  and saves a decoder whose precision would otherwise have to be guessed.

### Deviation: `OutdoorRoute` placement (CHANGE-001)

`MASTER-PLAN.md` §8's project-structure tree lists `outdoor_route.dart` under
`data/models/`, while the same section requires pure domain services and
forbids `domain/` importing `data/` - a rule the architecture test enforces. The
two cannot both hold for a type the pure `RoutePlanner` returns.

**Resolution: the file stays at `lib/domain/routing/outdoor_route.dart`** and the
dependency rule is preserved. Moving a domain concept into the data layer to
match a file-tree line would have required either an illegal dependency
direction or indirection with no purpose. `MASTER-PLAN.md` is unchanged. Full
record: `changes/CHANGE-001-outdoor-route-domain-placement.md`.

The same reasoning governs `PublicLeg`: it is what the router port returns, so it
lives beside the port rather than in `data/models/`.

### Issues discovered

1. `RouteGraph` has no public unnamed constructor, so a hand-built two-vertex
   graph is not expressible; test graphs must go through
   `RouteGraph.fromPolylines`.
2. The 60 m snap tolerance interacts with real coordinates: a destination 79 m
   from its nearest vertex is not on the campus network, however central it looks
   on a map. The first draft of the planner tests asserted campus-road routes
   for endpoints that were in fact out of tolerance and correctly failed.
3. A scripted router that refuses every request cannot exercise step 3, because
   step 3 needs OSRM to answer and simply stop short. The test double needed a
   "return this exact geometry" mode, not only a refuse switch.

### Issues fixed

1. The unusable-gate radius was first written as a constant declared at the
   bottom of the class with a type name as its identifier; it is now
   `usableGateRadiusMeters`, declared with the planner's other thresholds, and
   `CampusMapData` remains the owner of the data-side radius.
2. The campus-graph step computed its deduped geometry three times over; it is
   now computed once into `points` and reused for distance and duration.
3. Every public-road failure mode is exercised: error status, transport
   exception, malformed body, and a single-waypoint request that must not reach
   the network at all.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.8s)` |
| `flutter test` | `00:07 +233: All tests passed!` (from 209 in P5) |

P6 added 24 tests: 10 for the cascade and gate selection, 10 for the OSRM URI
and parser and its failure modes, 4 for the data-to-planner wiring.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 3 | Campus road network preferred; falls back through the cascade | **PASS** | the campus graph is consulted first and a test asserts the routing server is never called when it succeeds; each later step is reached only when the earlier one cannot serve the route |
| 4 | Every route carries a visible quality | **PASS** | `OutdoorRoute.quality` is required, non-nullable, and has a label for the UI; `approximate` is separately flagged through `isApproximate` |
| 6 | Gates are separate from buildings and never Services entries | **PASS** | `RoutingGate` carries only an id, a position and a snap distance; `routingGates` is built from `usableGates`, which excludes the policy-disabled gate |
| 7 | Bad building coordinates never route | **PASS** | R7 state exists in P3 and P5; the planner has no building input, so an invalid coordinate cannot reach it |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 233/233 |
| P6 exit | Planner tests cover cascade order, gate selection and every fallback | **PASS** | `test/unit/route_planner_test.dart` covers all five steps, cheapest-gate selection, the too-far gate being ignored, and the public-leg-unavailable drop to the flagged straight line |

### Phase status

**CODE COMPLETE, EXIT CRITERION VERIFIED**. Every P6 exit criterion is covered by
a passing test. One item is unverifiable on this host and is not part of the exit
criteria: no live OSRM request has been made, because the dev host has no
reachable routing endpoint and no API key is configured. The client is therefore
exercised against the real OSRM response shape and real failure modes, not
against a live server - `EXTERNAL DEPENDENCY`, carried into the P10 walkthrough.

### Evidence

- Test: a route entirely on the campus roads is returned without a single
  public-road request.
- Test: an endpoint beyond the snap tolerance falls through to the public road.
- Test: of two usable gates, the one with the cheaper total cost wins, and the
  chosen gate id is reported on the route.
- Test: a gate 202.8 m from the roads is never offered to the routing server.
- Test: when the public leg to the gate is unavailable, the hybrid step is
  abandoned rather than drawn.
- Test: when OSRM stops 89 m short and the campus graph can finish the job, the
  result is `osrmSpliced` and the duration exceeds the public leg's own.
- Test: with no campus network at all the route is `osrm`; with the routing
  server refusing everything it is `approximate`, two points, and non-zero
  duration.
- Test: coordinates off the campus produce a `route_endpoint_off_campus` failure
  instead of a route.
- Test: `OsrmClient` asks the foot profile for GeoJSON geometry, emits
  longitude before latitude, and returns null on an error status, a transport
  exception, a malformed body, or a single waypoint - in the last case without
  touching the network.
- Test: the composed `routePlannerProvider` plans on the bundled campus graph,
  and a policy-disabled gate never appears among the planner's gates.

---

## Phase 7 - Navigation

### Delivered

- `domain/navigation/progress_tracker.dart`: `ProgressTracker`, `RouteProgress`,
  `Maneuver`, `ManeuverKind`. Progress is distance travelled *along* the
  polyline, not a segment index, so it is monotonic and junction-safe (F2).
- `domain/navigation/gps_guard.dart`: `GpsGuard` / `GpsVerdict`. Rejects stale,
  inaccurate and implausible fixes before they can move the user, reroute them
  or end a trip. A fix 200 m from the last one is a jump even when its reported
  accuracy looks fine.
- `domain/navigation/arrival_detector.dart`: arrival needs three consecutive
  precise fixes inside the arrival radius; one good fix does not end a trip.
- `domain/navigation/reroute_service.dart`: off-route is confirmed over three
  fixes and acted on at most once per cooldown, so a momentary GPS wobble near
  the line cannot start a reroute storm.
- `domain/navigation/navigator_controller.dart`: the state machine
  (`idle` / `planning` / `navigating` / `rerouting` / `arrived` / `failed`). It
  owns no timers, streams or widgets: it takes fixes and produces immutable
  states.
- `core/config/app_config.dart`: navigation thresholds added - max fix age 10 s,
  max jump 12 m/s, off-route 40 m for 3 fixes, reroute cooldown 20 s, arrival
  radius 20 m for 3 precise fixes, and `navigationMapZoom` 18.
- `core/util/geo.dart`: `Geo.signedBearingDelta`, shared by the heading
  estimator and the turn classifier so a right turn can never be reported as a
  left one at the 359/0 degree boundary.
- `presentation/navigation/navigation_view_model.dart`: owns the session. Starts
  from the current fix, feeds every published fix to the state machine, reads the
  campus graph and gates from the map layer, and releases the camera on cancel.
- `presentation/navigation/navigation_banner.dart`: the instruction strip -
  next maneuver and distance, progress bar, remaining distance, ETA, the route
  quality badge, and one warning line that reports the worst current fact
  (off-route, rerouting, a rejected fix, a route error).
- `presentation/map/map_view_model.dart`: `followUser` state and `followUserTo`.
  The camera moves with the user only while following is on, so a deliberate pan
  is never fought by a fix.
- `presentation/map/campus_map_view.dart`: draws the active route over the campus
  roads - solid for a real route, dashed in the error colour when the quality is
  `approximate` - and reports fixes to the view model for follow. The strip
  replaces the status banner while a trip is running.
- `presentation/buildings/building_detail.dart`: the building sheet with the
  backend's own fields and the one action. Directions is disabled, with the
  reason on screen, for a building whose coordinates cannot be trusted.
- `changes/CHANGE-002-navigation-value-objects-in-domain.md`: `GpsSample` and
  `RouteProgress` are domain value objects, not `data/models/`.

### Design notes

1. Navigation is refused, not faked, without a position. `startTo` has no
   fallback origin: a route planned from a made-up position is one the user is
   already off.
2. The instruction strip has no state of its own. Every string on it is derived
   from `NavigationState`, so guidance cannot disagree with the state machine.
3. A failed reroute never removes the route. If the planner cannot answer, the
   user keeps walking the line they have and the banner says what happened.
4. An approximate route is drawn dashed and badged in the error colour. A
   straight-line guess must not look like a surveyed path.
5. Camera follow is a view-model flag, not a subscription, so exactly one place
   decides whether the camera may move by itself.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 2.2s)` |
| `flutter test` | `00:08 +304: All tests passed!` (from 233 in P6) |

P7 added 71 tests: 15 for progress and manoeuvres, 13 for the GPS guard and
arrival detector, 23 for the state machine, 8 for the session view model and
camera follow, and 12 widget tests for the instruction strip and the building
sheet.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 3 | Directions route to a building's outdoor coordinates and report a quality | **PASS** | the same `routePlannerProvider` from P6 plans the trip; the strip always shows `RouteQuality.label` |
| 4 | Bad coordinates appear with a warning; Navigate is disabled with an explanation | **PASS** | a test asserts the sheet's button `onPressed` is null and the R7 explanation is on screen; a navigable one starts a real session from the current fix |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 304/304 |
| P7 exit | Navigation tests pass | **PASS** | state machine, progress, guards, arrival, reroute, session wiring, and both surfaces are covered |

### Phase status

**CODE COMPLETE, EXIT CRITERION VERIFIED**. Every P7 exit criterion is covered
by a passing test. Two things are unverifiable on this host and are not part of
the exit criteria: no live positioning on a physical device (there is no
`MAPS_API_KEY` in `android/local.properties`, so the app cannot even be
installed here), and no live GPS stream - the guard, progress and arrival
decisions are exercised against deterministic fixes instead. Carried into the
P10 walkthrough as `EXTERNAL DEPENDENCY`.

### Evidence

- Test: a session with no usable fix is refused with a stated reason, no route is
  planned, and the camera does not move.
- Test: a session starts from the current fix, and the map view model is put
  into follow mode.
- Test: a fix published on the location stream advances progress with no UI call
  at all.
- Test: the session planner uses the graph and gates the map layer actually
  loaded - a route with both endpoints on the campus roads is `customGraph`.
- Test: cancel returns to idle and releases the camera.
- Test: `followUserTo` moves the camera only while following is on, and stops
  moving it the moment following is turned off.
- Test: three off-route fixes trigger exactly one reroute; a second burst inside
  the cooldown does not.
- Test: a reroute planned while the routing server is refusing still leaves the
  user with a route, flagged `approximate`.
- Test: a rejected fix sets a warning and moves nothing - the route, the progress
  and the phase are unchanged.
- Test: three precise fixes inside the arrival radius produce `arrived`; two do
  not.
- Test: the strip shows the maneuver, the distance to it, `1.5 km left` and
  `11 min left`, the quality label, and one warning line.
- Test: the strip shows `You have arrived` in the arrived phase, and the cancel
  control is reachable.
- Test: the building sheet renders only the fields the backend published.
- Test: the sheet's Directions is disabled with the R7 explanation for a building
  with no usable coordinates, and starts a real session for one that has them.
---

## Phase 8 - Search

### What was built

`lib/domain/search/search_index.dart` - the index. Two categories, buildings and
gates, and nothing else: the POI and floor indexing the reference carried is
deleted. The index is a pure function of the query, built once from a
`SearchDocument` projection of each record.

`lib/presentation/search/search_view_model.dart` - the index owner. It projects
`CampusBuilding` and `CampusGate` onto `SearchDocument`, rebuilds only when the
underlying records change, and re-answers the query in flight when they do.

`lib/presentation/search/search_view.dart` - the surface: one field, two category
chips, one navigable-only chip, and grouped results.

`campus_panel.dart` - the header gained a search control, and the panel body
hands over to `SearchSurface` while a search is open. Search is not a fifth tab,
because it searches *across* categories instead of being one of them. The four
browsing tabs the plan fixes are untouched.

### The defect F6 asks for, and how it is closed

The reference took a global top-K and *then* filtered. A large irrelevant
category could fill the quota and leave the user with nothing, while results
that did exist stayed invisible - the filter ran too late to matter.

Here the order is fixed. The filters run first, the per-category count is taken
from the filtered set, and only then is the per-category limit applied. The
consequence is that a truncated group says so:

```
Buildings                       Showing 25 of 63
```

A test builds 60 buildings and 1 gate, all matching `library`, and asserts the
gate still returns its single hit. Under the reference's ordering that gate is
exactly what disappears.

### Matching

Ranks: exact name, then name prefix, then name substring, then a secondary
field, with the name order as the tiebreak so results do not reshuffle between
rebuilds. Searchable fields are the name, the building code and the description.
Matching folds case and Latin diacritics, and collapses punctuation to single
spaces, so `CAFE` finds `Café` and `b 01` finds `B-01`. Arabic text is compared
exactly as written - it has no case, and stripping characters from it would
corrupt it. Nothing is transliterated.

### The states are distinct

| State | Cause | Message |
|---|---|---|
| idle | nothing typed | `Search the campus` |
| no match | documents exist, none match | `No matches`, quoting the text |
| no campus data | nothing indexed at all | `No campus data to search` |
| no categories | every chip is off | `No categories selected` |

An empty index and a query that missed are different facts, so they are
different messages. The unit suite asserts the distinction directly, and the
widget suite asserts neither message is shown for the other state.

### R7 in search

A building whose coordinates cannot be trusted is still indexed, still
searchable, and carries the reason in its document. Its row shows the reason in
the error colour, and tapping it opens the detail sheet - where the Directions
button is disabled and the explanation is spelled out - without selecting it on
the map, because there is no position to select at.

The reason text itself now lives on `CampusBuilding.coordinateWarning` rather
than being re-derived in each surface that shows it, so the list, the sheet and
search cannot drift into describing the same state three different ways.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 2.5s)` |
| `flutter test` | `00:14 +362: All tests passed!` (from 304 in P7) |

P8 added 58 tests: 24 for the index (categories, filter-before-limit, ranking,
folding, the empty cases, index hygiene), 17 for the view model (the projection,
the filters, the surface states, the index following a reload), and 17 widget
tests for the surface (grouping, counts, the chips, the four empty states, and
tapping a building, an R7 building and a gate).

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 7 | Search returns Buildings and Gates with filters applied before top-K | **PASS** | a test with 60 buildings and 1 gate matching one term asserts the gate is still returned and that the building group reports 60 matches while showing 1 |
| R3 | Gates are searchable as their own category | **PASS** | a gate is in `SearchCategory.gate` only, and a test asserts it does not appear in the building group |
| R7 | Bad coordinates appear in search with a warning | **PASS** | the document carries `navigable: false` and the reason; the widget test finds both on screen |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 362/362 |
| P8 exit | Search tests pass | **PASS** | the index, the projection, the filters and the surface are all covered |

### Phase status

**CODE COMPLETE, EXIT CRITERION VERIFIED**. No search behaviour needs a device,
a network or a map key, so nothing in P8 is blocked. Carried into the P10
walkthrough: search has never been exercised against a real campus directory,
only against fixtures, because the live backend answers `403 Forbidden`.

### Evidence

- Test: a blank query returns both categories, buildings first; a category the
  query excludes is absent entirely; every category off matches nothing and is
  reported as a no-match rather than a crash.
- Test: 60 matching buildings and 1 matching gate - the gate still returns its
  hit, the building group reports 60 and shows the limit, and the group says it
  is truncated.
- Test: the navigable filter is applied before the limit - 30 buildings, half
  unpositionable, a limit of 5, and the answer is 15 matches of which 5 are
  shown, all navigable.
- Test: a filter that removes everything reports zero matches and is not
  truncated, so it cannot be mistaken for a cut-off list.
- Test: an exact name outranks a prefix, which outranks a substring, which
  outranks a hit in a secondary field.
- Test: equal ranks are ordered by name, so a rebuild cannot reshuffle results
  the user has already read.
- Test: `CAFE` finds `Café Al-Riwaya`; `b 01` finds `B-01 Annex`; an Arabic
  query matches the Arabic name as written.
- Test: an empty index is distinct from one that merely missed, and a blank
  query is not a no-match.
- Test: duplicate ids are indexed once, so the counts cannot inflate.
- Test: a category with no documents reports zero, not an error, and is left out
  of the non-empty groups.
- Test: search sees exactly the buildings the Buildings tab lists - the two
  lists are derived from one snapshot.
- Test: the R7 building is searchable, unpositioned, and carries
  `no coordinates published`.
- Test: a reload that changes the directory re-answers the query in flight; the
  index is not a cache that outlives the data.
- Test: closing search drops the query, the filters and the surface; clearing
  the field keeps the surface open on its prompt.
- Test: the four browsing tabs are not a fifth; opening search replaces them and
  cancelling brings them back.
- Test: the chips carry the same counts as the group headers, and the
  per-category limit is applied after filtering at the view model.
- Test: a truncated group says `Showing 25 of 30`.
- Test: tapping a building selects it on the map and opens its detail; tapping
  an R7 building opens the detail with the explanation and does not select;
  tapping a gate selects the gate.
- Test: with nothing loaded the surface says `No campus data to search`, and
  does not say `No matches`.
- Test: with every category off the surface says `No categories selected`.

## Phase 9 - Content (Places, Gates, About)

### What changed

| File | Change |
|---|---|
| `lib/presentation/gates/gate_detail.dart` | New. `GateDetailSheet`: name, `code`, level, lat/lon, snap distance, policy role, preferred flag, and a Directions action. |
| `lib/presentation/gates/gates_tab.dart` | Each gate row gained a Details chevron; policy state stays on the row. |
| `lib/presentation/places/places_tab.dart` | Now shares the same `PanelMessage` loading/failed states as Buildings, keeps the last directory on a failed refresh, and labels it stale. |
| `lib/presentation/buildings/buildings_tab.dart` | Shows `StaleDataWarning` on a failed refresh over a cached directory. |
| `lib/presentation/shell/panel_sections.dart` | `PanelMessage` and the new `StaleDataWarning` live together, so the two list surfaces cannot describe the same state differently. |
| `lib/presentation/map/map_view_model.dart` | A failed building refresh keeps the previous snapshot instead of blanking it. |
| `test/widget/content_surfaces_test.dart` | New. 13 widget tests for the gate detail sheet and the gate list. |
| `test/widget/app_shell_test.dart` | Places: a failed refresh keeps the last directory and says it is stale. |

### Gates are entities, not tiles in a Services list

A gate is a thing you can be routed to, so it gets a detail sheet rather than a row
in a category. The sheet answers the questions the list row cannot: the coordinates
the backend published, the distance from the road graph, the role the policy file
gives the gate, and whether the backend marked it preferred. The policy state is
still visible on the row, because a list is scanned and a sheet is read.

Directions is offered for an enabled gate and withheld from a disabled one. A
policy-disabled gate is not an entrance, so a Directions button on it would
promise a route the planner is not allowed to produce. The row says why instead.

### A failed refresh keeps the last directory

`MapViewModel.load` used to leave the snapshot empty when the building request
failed, which meant a dropped connection emptied a list the user was halfway
through reading. It now keeps the last successful snapshot and records the error.
The list surfaces then have three distinct states, matching Buildings:

| State | Cause | What the user sees |
|---|---|---|
| Loading | a request is in flight and there is nothing cached | `PanelMessage` with a spinner |
| Stale | cached data plus a failed refresh | `StaleDataWarning` above the retained rows, with retry |
| Unavailable | the first request failed, nothing cached | `PanelMessage` `Places unavailable`, with retry |

Retaining the data and saying it is out of date is the honest version. Showing
out-of-date data as if it were current is not, and emptying the list throws away
something the user can still use. Both warnings and both retry paths are asserted
in tests rather than assumed.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 2.2s)` |
| `flutter test` | `00:14 +378: All tests passed!` (from 362 in P8) |

P9 added 16 tests: 13 in `content_surfaces_test.dart` for the gate detail sheet
and list, and 3 in `app_shell_test.dart` for the Places loading, unavailable and
stale states. Two of the three existed as weaker assertions before and were
tightened; the MapViewModel snapshot-retention change is covered by the stale case.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 5 | Places lists real backend buildings, no invented taxonomy, no bundled facilities dataset | **PASS** | the tab renders `snapshot.buildings` and declares no category list; there is no facilities asset in the package |
| 6 | Gates are browsable, searchable as their own category, participate in routing | **PASS** | the Gates tab lists them, P8 asserts the search category, P6 asserts the planner uses them, and the detail sheet calls the same planner |
| 9 | Content surfaces render real backend data only | **PASS** | no content surface constructs a building or gate of its own; the About tab reads the config and build metadata |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 378/378 |
| P9 exit | Content surfaces render real backend data only | **PASS** | every assertion is against a fixture matching the verified field set |

### Phase status

**CODE COMPLETE, EXIT CRITERION VERIFIED**. No gate-detail or places behaviour
needs a device, a network or a map key. Carried into P10: the live backend answers
`403 Forbidden`, so every content surface has been exercised against fixtures
matching the verified field set and never against a real campus directory.

### Evidence

- Test: the detail sheet shows the gate name, code, level, coordinates and the
  snap distance the graph computed.
- Test: the sheet shows the policy role and the preferred flag as the policy file
  gives them, rather than re-deriving them.
- Test: Directions is available on an enabled gate and absent on a policy-disabled
  one.
- Test: starting Directions from the sheet routes through `NavigationViewModel`,
  which closes the sheet and reports the outcome on the map, including the
  blocked reason when the planner refused.
- Test: the gate list and the gate detail are separate surfaces; opening the sheet
  does not change the list selection.
- Test: a failed first load shows `Places unavailable` with a working retry.
- Test: a failed refresh keeps the published building rows and shows
  `Showing the last data that loaded` with the failure reason.

## Phase 10 - Integration and audit

### What changed

| File | Change |
|---|---|
| `test/architecture/import_boundary_test.dart` | Fixed the resolver so the guard reads this project's imports; added a self-check group that proves the guard can fail. |
| `lib/app/providers.dart` | `locationSourceProvider` and `connectivitySourceProvider` moved here from the location view model. |
| `lib/presentation/location/location_view_model.dart` | Keeps only `headingTrackerProvider`, which is pure domain. |
| `test/unit/location_view_model_test.dart`, `test/widget/content_surfaces_test.dart` | Import updates for the moved providers. |
| `FINAL-AUDIT.md` | New. The P10 audit report. |

### The architecture guard was not doing anything

This is the finding that mattered, and it is a finding about the *evidence*,
not about the app.

`import_boundary_test.dart` resolves every import to a `lib/...` path and then
checks that path against the layer table. Its `resolve()` tested

```dart
if (importUri.contains(':')) return null;                              // first
if (importUri.startsWith('package:ejust_campusfind/')) { /* ... */ }    // second
```

in that order. Every import in this codebase is a `package:` import, so
`contains(':')` matched first and returned null for all of them. The guard was
handed an empty set of internal imports and passed on it, for P0 through P8,
reporting `No issues found` about a rule it never evaluated.

Reordering the two lines made it read the imports, and it immediately reported
two genuine violations that had been sitting in the tree the whole time:

```
lib/presentation/location/location_view_model.dart -> lib/data/datasources/connectivity_source.dart
lib/presentation/location/location_view_model.dart -> lib/data/datasources/geolocator_location_source.dart
```

`location_view_model.dart` declared the `LocationSource` and `ConnectivitySource`
providers next to the view model, so the composition root was not the only place
data-layer types got constructed. That is exactly the thing immutable rule 7
forbids and the boundary test was written to catch. The providers moved to
`lib/app/providers.dart`, where the other data-layer wiring already was.

### A guard that cannot fail is not evidence

Correcting the resolver would have fixed the current violation and left the
same class of bug one careless edit away. So the test file now plants illegal
imports in a throwaway file and requires the resolver to flag them:

- a `package:ejust_campusfind/data/...` import from `presentation/` - flagged
- a relative `../../data/...` import from `presentation/` - flagged
- an `export` of a `data/` file from `presentation/` - flagged
- `dart:async`, `package:http`, `package:google_maps_flutter` - not flagged

If someone re-breaks the ordering, those four tests fail. The same reasoning
applies to every exit criterion in this report that is marked PASS: a criterion
whose check cannot fail is not evidence of anything, and the check itself is
part of what was delivered.

### Grep audit results

Indoor symbols (`floor`, `poi`, `radiomap`, `knn`, `fingerprint`, `wifi`,
`indoor`, `transition`, `containment`, `quick_access`, `bssid`, `ssid`) produce
six hits in `lib/` and `test/`, all of them prose asserting the absence of those
features, plus one test fixture string that is a building `description`. No
identifier, type, model, field or code path. The three packaged assets - roads
KMZ, gates KMZ, `gate_policy.json` - decode to no indoor content either.

`pubspec.yaml` has `flutter_riverpod: ^2.6.1` and no `provider`. The manifest
requests three permissions and no cleartext. Two host literals exist, both in
`AppConfig`, both overridable by `--dart-define`.

### Reference project

`git status` does not show a clean reference project, and reporting that as
"clean" would be false: `clients/flutter/anyplace_campusfind` was already dirty
against `HEAD e26ecdc4` before this work began, with staged renames of
`lib/data/**` and modifications to its config and providers. None of it is from
this engagement.

The valid evidence is the pre-work hash baseline. All 175 baseline entries are
still present and byte-identical, and the newest write to any file in the
reference project is the newest baseline entry itself - so nothing in it has
been written since the baseline was taken. The 46 files outside the baseline are
pre-existing scaffolding, docs and `android/` build files, the newest of them
dated ten days before the last baseline write.

### Test results

| Command | Result |
|---|---|
| `flutter analyze` | `No issues found! (ran in 1.9s)` |
| `flutter test` | `00:13 +382: All tests passed!` |

Declared test count equals executed count across all 24 files. The suite went
from 378 to 382 because of the four guard self-checks.

### Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Separate app and identity alongside an unmodified reference project | **PASS** | `eg.edu.ejust.campusfind`; section 5 above; APK build pending `MAPS_API_KEY` |
| 2 | Buildings from the backend, nothing hardcoded | **PASS** | 49 repository tests; no building list in code or assets |
| 3 | Five-step cascade, always a `RouteQuality` | **PASS** | 14 planner tests |
| 4 | Bad coordinates listed and searchable with Navigate disabled | **PASS** | R7 tests across repository, search and widgets |
| 5 | Places lists real backend buildings, no invented taxonomy | **PASS** | no category list exists in the tab |
| 6 | Gates browsable, searchable, in routing, not a Services tile | **PASS** | 13 content-surface tests, 22 gate tests |
| 7 | Search filters before top-K | **PASS** | 60 buildings / 1 gate, and the navigable-filter-before-limit cases |
| 8 | Three permissions, no cleartext | **PASS** | manifest and `lib/` inspected |
| 9 | No indoor data, routing or positioning | **PASS** | the six prose hits, the three assets |
| 10 | Riverpod only, `provider` absent | **PASS** | `pubspec.yaml`; 16/16 imports |
| 11 | `flutter analyze` and `flutter test` clean | **PASS** | `No issues found!`; 382/382 |
| P10 exit | All checks pass, audit report written | **PASS** | `FINAL-AUDIT.md` |

### Phase status

**CODE COMPLETE, AUDIT WRITTEN**. Three items could not be verified on this
host and are recorded as external rather than as passes: `MAPS_API_KEY` is
absent so no APK was built; `https://map.beout.ai/api/mapping/space/public` now
times out from here (it returned `403 Forbidden` earlier), so no surface has
been exercised against live data; and the public OSRM endpoint answered `200`
with a real route, but not from a device and not for a campus-area pair.

Two residual risks are worth carrying forward. The backend has never answered,
so the entire data path is fixture-verified only. And nine `domain/` files
import `google_maps_flutter` for the `LatLng` value type, which keeps the
domain layer from being pure Dart; replacing `LatLng` with a `GeoPoint` domain
value object is the right follow-up and is recorded in `FINAL-AUDIT.md` rather
than started here.
