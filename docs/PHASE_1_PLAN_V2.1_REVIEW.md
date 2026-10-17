# PHASE 1 PLAN V2.1 — Outdoor-Only CampusFind Sibling Application

> **IMMUTABLE REVIEW BASELINE: This approved plan is a read-only reference during implementation. Never edit or regenerate this file while implementing. Any future plan changes require a separately named, explicitly approved revision.**

**Scope:** Planning + review artifact only. **Source:** `clients/flutter/anyplace_campusfind` · **Target:** `clients/flutter/campusfind_outdoor`
**Supersedes:** the in-conversation "PHASE 1 PLAN v2" (which was never written to disk).
**Change markers:** `[V2.1 CHANGE]` = corrected relative to V2 · `[V2.1 ADDITION]` = new in V2.1. Unmarked material is carried forward from V2.
**Evidence labels used throughout:** **CONFIRMED** (read-only inspected) · **REPORTED** (prior finding, CP-0 must verify) · **ASSUMPTION** · **UNRESOLVED**.

### How to read this document
* I do not have V2's exact file text in context (it was never persisted). No statement here claims an exact textual diff against V2. Where V2's exact wording matters, it must be compared against the plan text during CP-0.
* No command output in this document is invented. Commands are **proposed** unless explicitly labelled as already executed.
* Read-only observations captured while writing this plan (baseline hash, test counts, git state) are labelled **CONFIRMED (planning pass)**.

---

## 0. V2.1 Change Summary (what this revision corrected)

`[V2.1 CHANGE]` **A — Gate B redesigned.** Whole-repo `git status` equality remains withdrawn; Gate B now compares **branch + HEAD + path-set + per-file content hash**, handles paths with spaces via NUL-delimited porcelain, and requires recorded hashes for pre-existing modified files (e.g. `AGENTS.md`). (See §4 and §9.5.)

`[V2.1 CHANGE]` **B — CP-7 split.** Former single high-risk CP-7 is split into **CP-7A (read-only routing impact analysis)** and **CP-7B (routing implementation after explicit authorization)**. CP-8/CP-9/CP-10 and dependencies/stop conditions updated. (See §8.)

`[V2.1 CHANGE]` **C — Scope-specific integrity allowlists.** CP-2's allowlist now contains **only** identity/label/channel paths. Indoor removal, MVVM extraction, routing change, and test-change paths are **not** pre-authorized in CP-2; each later checkpoint has its own allowlist with exact path, reason, authorizing checkpoint, and behavior-vs-structure flag. (See §9.4.)

`[V2.1 CHANGE]` **D — Manifest lifecycle made explicit.** The three manifest concepts now have defined root, normalization, sort, algorithm, output location (outside the repo), guarantee scope (path+content only; **not** empty dirs or filesystem metadata), and failure behavior. `$LASTEXITCODE` must be captured immediately after `robocopy`. (See §3.4, §9.1.)

`[V2.1 CHANGE]` **E — Indoor-absence proof strengthened.** Text search alone is now explicitly insufficient; a layered dependency-map + registration/call-site/native/plugin/permission inspection + hit-classification + regression evidence is required. (See §6.4, §8 CP-3/CP-5/CP-10.)

`[V2.1 ADDITION]` 46-vs-47 test-count discrepancy **resolved with evidence** during this planning pass. (See §7.1.)

---

## 1. Objective, Scope, Definition of Done

### 1.1 Objective
Create `clients/flutter/campusfind_outdoor` as an **Outdoor-only, strict-MVVM** sibling of `clients/flutter/anyplace_campusfind`, preserving the source's Outdoor behavior, campus data, routing/rerouting semantics, and the user's pre-existing working-tree state — **without modifying the source app**. This document authorizes **nothing**; implementation requires a separate explicit message.

### 1.2 In scope (Phase 1)
Sibling creation · Android/package/brand identity · heading-channel rename · Indoor runtime removal · MVVM responsibility extraction · test classification/migration · integrity + acceptance verification.

### 1.3 Out of scope
Toolchain upgrades · algorithm redesign · server/backend/web/android-new changes · restoring pre-existing deletions · Phase 2+ work · any behavior change not separately approved.

### 1.4 Definition of Done

| # | Criterion | Evidence source | Status now |
|---|---|---|---|
| D1 | Target exists and is a runnable Flutter app | `flutter analyze` + `flutter test` from target dir | Not executed |
| D2 | Source tree byte-identical to CP-0 full manifest | Gate A″ | Not executed |
| D3 | Pre-existing working tree preserved; only allowlisted new paths | Gate B | Not executed |
| D4 | No reachable Indoor runtime dependency in target runtime graph | §6.4 dependency map + regressions | Partial (F1–F6) |
| D5 | Outdoor routing/rerouting/gate/KMZ behavior preserved | targeted regressions + asset-graph tests | Not executed |
| D6 | Strict MVVM responsibility checks pass | §6.3 assertions | Not executed |
| D7 | Identity confirmed: `eg.edu.ejust.campusfind_outdoor`, label `CampusFind Outdoor`, channel renamed atomically | manifest/gradle/source inspection | Not executed |
| D8 | No source secret copied; key never printed | presence/absence check + hash-only audit | Not executed |
| D9 | Test inventory reconciled and classified | §7 | **CONFIRMED (planning pass)** inventory; classification pending |
| D10 | Every outdoor behavior change approved in writing | approval record | Not obtained |

---

## 2. Source/Target Isolation

* **Source** `clients/flutter/anyplace_campusfind` is the reference and is **read-only** for the entire implementation.
* **Target** `clients/flutter/campusfind_outdoor` is the only implementation surface.
* **CONFIRMED (planning pass):** target does not currently exist (`Test-Path` = `False`).
* No Phase 1 action may touch `server/`, `clients/web/`, `clients/android-new/`, `clients/android/`, `clients/deprecated/`, or the stale root Flutter app (`lib/{core,data,state,ui}/`).
* `AGENTS.md` (repo root) is a **pre-existing user change** and must not be modified further.

---

## 3. Copy Contract, Identity, Secrets, Manifests

### 3.1 `[V2.1 CHANGE]` Copy method — proposal, not executed
A Git-only copy is disqualified: the source contains untracked build-critical files (wrapper JAR + scripts). Use a filesystem copy.

**PROPOSAL:**
```powershell
$src = "clients\flutter\anyplace_campusfind"
$dst = "clients\flutter\campusfind_outdoor"

robocopy $src $dst /E `
  /XD .dart_tool build .gradle .kotlin .idea .vscode `
  /XF local.properties .flutter-plugins-dependencies `
      GeneratedPluginRegistrant.java `
  /NFL /NDL /NJH /NP
$rc = $LASTEXITCODE                 # [V2.1 CHANGE] capture IMMEDIATELY
if ($rc -ge 8) { throw "robocopy failed: $rc" }
```

`[V2.1 ADDITION]` **CP-0 must validate via a non-writing dry run before authorization:**
```powershell
robocopy $src $dst /E /L `
  /XD .dart_tool build .gradle .kotlin .idea .vscode `
  /XF local.properties .flutter-plugins-dependencies GeneratedPluginRegistrant.java `
  /NFL /NDL /NJH /NP /FP /NS
```
Validation obligations:
1. Listing **includes** `android/gradlew`, `android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`.
2. Listing **excludes** `android/local.properties`, `.flutter-plugins-dependencies`, `GeneratedPluginRegistrant.java`.
3. Hidden files not explicitly excluded are included (robocopy default includes hidden files; if any hidden file is skipped, the method must change).
4. `/XD build` matches only generated output, not a legitimate source dir named `build`.
5. `.dart_tool` exclusion does not drop anything required by `flutter pub get`.
6. The implementation agent must **validate the copy rule against actual repo state** — no assumption that `/XD` semantics match expectation.

**Fail → STOP; do not copy.**

### 3.2 Exclusion policy (identical on both sides of every excluded comparison)

| Excluded item | Kind | Purpose | In full-source manifest? |
|---|---|---|---|
| `.dart_tool/` | generated | regenerated by `pub get` | **Yes** |
| `build/` | generated | build output | **Yes** |
| `android/.gradle/` | generated | Gradle cache | **Yes** |
| `android/.kotlin/` | generated | Kotlin cache | **Yes** |
| `.idea/`, `.vscode/` | editor local | not app content | **Yes** |
| `android/local.properties` | **secret + machine-local** | `MAPS_API_KEY`, `sdk.dir`, `flutter.sdk` | **Yes (hashed only)** |
| `.flutter-plugins-dependencies` | generated | regenerated | **Yes** |
| `GeneratedPluginRegistrant.java` | generated | regenerated; never hand-edit | **Yes** |

Rule: an exclusion from a **copy** never implies exclusion from the **source-integrity** manifest.

### 3.3 Identity changes (Phase 1, minimal)

| Item | Source | Target | Note |
|---|---|---|---|
| Dart package (`pubspec.yaml` `name:`) | `anyplace_campusfind` | **unchanged** | avoids Dart import rewrites |
| Android `namespace` | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | verify current value at CP-0 |
| `applicationId` | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | |
| Kotlin package decls | `eg.edu.ejust.anyplace_campusfind` | `eg.edu.ejust.campusfind_outdoor` | atomic with the above |
| App label | (current) | `CampusFind Outdoor` | verify current label at CP-0 |
| Heading channel | `eg.edu.ejust.anyplace_campusfind/heading_stream` | `eg.edu.ejust.campusfind_outdoor/heading_stream` | **atomic**: Dart + Kotlin, one checkpoint |

`[V2.1 ADDITION]` **No toolchain upgrade** in Phase 1 without separate approval.

### 3.4 `[V2.1 CHANGE]` Manifest lifecycle — three distinct manifests

**Output root (outside the repo):** `$audit = Join-Path $env:TEMP "campusfind_v2_1_audit"`.
**Relative-path normalization:** paths relative to the manifest root, separators normalized to `/`, trailing slashes stripped.
**Sorting:** ascending ordinal by normalized path, before writing and before comparison.
**Hash algorithm:** SHA-256.
**Guarantee scope (explicit):** the manifest guarantees **file path + file content identity only**. It does **not** cover empty directories, file modification times, ACLs, alternate data streams, or git-ignore semantics. Do not claim broader guarantees.
**Secret safety:** only hashes are emitted; file contents are never printed.

| # | Manifest | Root | Exclusions | Captured at | Compared at | Failure behavior |
|---|---|---|---|---|---|---|
| M1 | Full source integrity baseline | `clients/flutter/anyplace_campusfind` | **none** | CP-0 | CP-10 (Gate A″) | any diff → **STOP**, do not auto-repair |
| M2 | Copy-equivalence (source side + target side) | source & target app roots | §3.2 list, **identical both sides** | CP-1 | CP-1 (Gate A) | any unmatched diff → **STOP** |
| M3 | Post-identity / per-checkpoint target manifests | target app root | per-checkpoint allowlist (§9.4) | each authorized checkpoint | corresponding checkpoint (Gate A′) | any diff not matching exactly one allowlist entry → **STOP** |

M2 proves only that *included* files match; it is **not** proof of source integrity (that is M1/Gate A″).

---

## 4. `[V2.1 CHANGE]` Pre-existing Git-Worktree Protection (Correction A)

### 4.1 Why status letters are insufficient
An already-modified file (` M`) keeps the same status letter even if its content changes again. A deletion entry disappears only if the file is restored. So Gate B must compare **paths + statuses + content hashes**, not status letters alone.

### 4.2 Baseline — CONFIRMED (planning pass, read-only)
```
branch : navigation-app
HEAD   : 534ff9086d5e3296dfc7daa2e314726c1e973b25
```
Porcelain (`--porcelain=v1 -uall`), 13 entries:
```
 M AGENTS.md
 D CONTEXT.md
 D CONTRIBUTING.md
 D FINAL-AUDIT.md
 D FINAL-CAMPUSFIND-REPORT.md
 D IMPLEMENTATION-REPORT.md
 D IMPLEMENTATION_PLAN.md
 D MASTER-PLAN.md
 D REBUILD-PLAN.md
 D RECOVERY_REPORT.md
 D changes/CHANGE-001-outdoor-route-domain-placement.md
 D changes/CHANGE-002-navigation-value-objects-in-domain.md
 D plans/smart-marinating-fog.md
```
Pre-existing modified-file content hash (**CONFIRMED (planning pass)**):
```
AGENTS.md  SHA-256 = B0EAC4E1B58D33A1A00BCC43E510C2CFAC535445AE7C651690B3614F563786E7
```
`[V2.1 ADDITION]` These 13 entries and this hash must be **re-captured by the implementation agent at CP-0**; the values above are a planning-pass observation, not a substitute for CP-0 capture.

### 4.3 Gate B requirements

1. Capture at CP-0: branch, HEAD, full porcelain (`--porcelain=v1 -uall -z`), and per-file SHA-256 for every pre-existing modified/untracked entry.
2. Record the exact 12 deleted paths and verify they remain deleted (absence on disk).
3. Allow new/modified paths **only** under:
   - `clients/flutter/campusfind_outdoor/`, and
   - the one approved documentation artifact `docs/PHASE_1_PLAN_V2.1_REVIEW.md`.
4. Compare **path sets, statuses, and hashes** (not letters alone).
5. `[V2.1 CHANGE]` **Path-with-spaces / special-character handling:** use `git status --porcelain=v1 -uall -z` and split on `NUL`, never on newlines, and never rely on Git's C-style quoting. Repo path `Downloads\anyplace for android part\...` contains spaces, so a naive whitespace parser is forbidden.
6. Do **not** restore, stage, stash, clean, or otherwise modify pre-existing work to satisfy any check.

**Robust approach (specification, not a fragile parser):** decompose Gate B into three independent comparisons, and require the implementation agent to validate each against the real repository:
- **(a) Name/status set:** `-z` porcelain baseline vs final; every baseline record must still appear byte-identically; every new record must match the §4.3(3) allowlist.
- **(b) Content hash of pre-existing modifications:** re-hash `AGENTS.md` and any other pre-existing `M`/`??` entry; must equal CP-0 baseline.
- **(c) Deletion persistence:** each of the 12 deleted paths must still be absent from the working tree.

### 4.4 `[V2.1 ADDITION]` Proposed Gate B comparison (to be validated)

```powershell
# CP-0 capture
$audit = Join-Path $env:TEMP "campusfind_v2_1_audit"; New-Item -ItemType Directory -Force -Path $audit | Out-Null
git -C $repo status --porcelain=v1 -uall -z | Set-Content -Encoding utf8 "$audit\status_baseline.z"
git -C $repo rev-parse HEAD            | Set-Content "$audit\head_baseline.txt"
git -C $repo branch --show-current     | Set-Content "$audit\branch_baseline.txt"
(Get-FileHash AGENTS.md -Algorithm SHA256).Hash | Set-Content "$audit\agents_baseline.sha256"

# CP-10 compare (illustrative)
$b = (Get-Content -Raw "$audit\status_baseline.z") -split "`0" | Where-Object { $_ -ne '' }
$n = (git -C $repo status --porcelain=v1 -uall -z) -split "`0" | Where-Object { $_ -ne '' }
$missing = $b | Where-Object { $n -notcontains $_ }
$added   = $n | Where-Object { $b -notcontains $_ }
$allowed = '^(\?\?|A |AM| M|M ) (clients/flutter/campusfind_outdoor/|docs/PHASE_1_PLAN_V2\.1_REVIEW\.md)'
$illegal = $added | Where-Object { $_.Substring(3) -notmatch '^(clients/flutter/campusfind_outdoor/|docs/PHASE_1_PLAN_V2\.1_REVIEW\.md$)' }
if ($missing) { "MISSING BASELINE: $missing" }
if ($illegal) { "ILLEGAL NEW PATH: $illegal" }
if ($missing -or $illegal) { throw 'GATE B FAILED' }
```
Requirements on this script: **must be validated by the implementation agent against the actual repo**; must handle rename records (`R`/`C` emit a second NUL-separated path); must not be trusted without a positive+negative self-test.

---

## 5. Secrets and Local Configuration

* Source `android/local.properties` contains `MAPS_API_KEY`, `sdk.dir`, `flutter.sdk`. **Never copy. Never print. Never embed in this plan, logs, manifests, reports, screenshots.**
* Hash for integrity only (`Get-FileHash`).
* Target must be checked for the **absence** of a copied source `local.properties`.
* Target-local config is generated only **during implementation**, as authorized: the developer's own SDK paths plus the existing mechanism — REPORTED as local.properties → environment variable → `""` fallback (`android/app/build.gradle.kts:37-40`); **CP-0 must verify**.
* No secret value may appear in any manifest diff output.

---

## 6. Outdoor/Indoor Classification, Strict MVVM, Indoor Absence

`[V2.1 CHANGE]` Classification is by **method + call site + dependency**, never by file or directory name. A file may appear in more than one row.

### 6.1 Routing classification (F1, F2, F3, F5)

| Item | Refs | Class | Required action |
|---|---|---|---|
| `NavigationRepository.getRouteFromCoordinates` | `navigation_repository.dart:21` (decl), `:62` (impl) | **SHARED** | **Preserve.** Outdoor reroute passes `floorNumber: null` (`navigation_deviation_handler.dart:259-275`) and adopts raw geometry at `:297-298`. Trim Indoor call sites only. |
| `NavigationRepository.getRouteBetweenPois` | `:16` (decl), `:54` (impl) | **INDOOR** (provisional) | Inspect all callers before removal. Known callers: `cross_building_router.dart:990,1210`; `routing_service.dart:125`; `campus_route_coordinator.dart:398,513,745,1011,1046`; `space_view_model.dart:722` (doc ref). |
| `NavigationRepository.getOutdoorWalkingRouteWithMetadata` | used `cross_building_router.dart:450,467,626,797` | **OUTDOOR** | Preserve. |
| `routing_service.dart` connector builder | `:80-169`, call `:125` | **INDOOR** | Preserve independent Outdoor cascade; inspect callers before removal. |
| `cross_building_router._generateOutdoorSegment` | `:450,467,626,797` | **OUTDOOR** | Preserve. |
| `cross_building_router._generateExitSegment` | `:343`; indoor call `:366`; fallback `:355,359,393` | **MIXED** | See 6.2. |
| `cross_building_router._generateEntranceSegment` | `:964`; indoor `:990,1015`; connectors `:1044`; fallbacks `:977,981,1072` | **MIXED** | See 6.2. |
| `cross_building_router._routeViaConnectors` | `:1134`; indoor `:1210`; caller `:1044`; test hook `:1260` | **INDOOR** | Removal breaks `remediation_crossbuilding_test` NAV-003 (§7). |
| `cross_building_router.composeRoute` | decl `:71`; callers `campus_route_coordinator.dart:259,604` | **MIXED / LIVE** | **Not dead code** (F2). |
| `_detectBuildingFromPolygon` / `detectUserBuilding` | `cross_building_router.dart:273`; coordinator `:246` | **OUTDOOR (geometry)** | Floor-bounds containment; no Wi-Fi required. Preserve. |
| `navigation_deviation_handler` Step-2 reroute | `:256-310` | **MIXED** | Outdoor branch `:259-261`,`:297-298`; indoor branch `:299-302` (`toSegmentedIndoor`). Trim Indoor branch only. |
| `NavigationState.{enteringBuilding,activeIndoor,exitingBuilding}` | `navigation_state.dart` | **UNRESOLVED (U2)** | Enumerate all states/transitions/handlers/consumers/tests first. |

### 6.2 F2 — `composeRoute` behavior must be reviewed, not assumed
`composeRoute` is reached whenever the user is outside the destination building (`campus_route_coordinator.dart:246-276`), via polygon geometry. Its Indoor exit/entrance legs are reachable on ordinary cross-building routes while the user stands inside any building polygon. Removing them yields straight-line `exitTransition`/`entranceTransition` with `isIncomplete: true` → `hasIncomplete` (`cross_building_router.dart:202`) → `partialRouteWarning` (`:223`) → UI (`campus_route_coordinator.dart:268`, `navigation_status_bar.dart:90`).

Obligations: not dead code · straight-line/incomplete/`partialRouteWarning` **not** pre-accepted · body-level review of `:71-342`, `:343-449`, `:964-1133` before decisions · determine whether Outdoor behavior is preservable without Indoor runtime deps · **CP-7B approval gate** for any necessary behavior change · no silent redesign.

### 6.3 `[V2.1 ADDITION]` Strict MVVM — responsibility-based acceptance

| Layer | Must hold | Assertion (≥1 per moved responsibility) |
|---|---|---|
| View | Renders state; forwards intent; **no multi-step orchestration**; **no business-provider writes** | `_startDirectionsForPoi`-equivalent contains no sequential VM command chain and no `ref.read(...notifier).state =` for business workflows |
| ViewModel | No Flutter widgets, no `GoogleMapController`, no camera/rendering calls | static scan of `lib/viewmodels/` for `Widget|GoogleMapController|animateCamera|moveCamera` |
| Service/use case | Owns data access + platform integration | unit tests run without a widget tree |
| Repository | Method-level Indoor/Outdoor/shared separation | §6.5 dependency map |
| Model/domain/shared state | No presentation-widget dependency | no `import 'package:flutter/material.dart'` in `lib/models/`, nav services |
| Navigation transitions / routing decisions | Testable without Flutter UI | state-machine + router tests pass headlessly |
| UI callbacks / controller ops | Explicit boundary | callback-interface test |
| Runtime graph | No Indoor positioning/radiomap dependency | §6.5 zero-reachable-hit proof |

Compilation is **not** evidence of MVVM compliance.

### 6.4 `[V2.1 CHANGE]` Indoor-absence proof (Correction E) — text search is insufficient

Required combination (all at CP-3 / CP-5 / CP-10):
1. **Dependency map** from Outdoor runtime entry points (`main.dart` → provider tree → views → viewmodels → services/repositories → platform channels → native → assets) down to each Indoor candidate.
2. **Registration/call-site inspection:** imports, constructor/`Provider`/Riverpod registrations, DI wiring, direct call sites, `MethodChannel`/`EventChannel` registrations, plugin/permission requirements.
3. **Hit classification:** classify every search result as production dependency / test / dead code / comment / harmless reference.
4. **Reachability proof:** no reachable Outdoor runtime path depends on Indoor positioning, radiomap, floorplan rendering, or Indoor POI routing.
5. **Regression confirmation:** retained Outdoor features still work.

**Removal-safety verifier (proposed, read-only):**
```powershell
rg -n "getRouteBetweenPois|_routeViaConnectors|NativePositioningService|latestIndoorEstimate|isIndoorWifiActive|loadRadioMap|resetAllRadiomaps" lib test android
```
Every hit must be classified per item 3 before any deletion. Any unclassified production hit → **STOP**.

Do not delete shared files or native components until consumers are traced. Preserve heading, required location capabilities, and Outdoor floor-selection behavior where the design requires them.

### 6.5 Location / native / assets (REPORTED — CP-0 verifies)

| Item | Refs | Class | Action |
|---|---|---|---|
| `MethodChannelNativePositioningService()` | `main.dart:21-24` | INDOOR | remove after dependency map |
| `positionStream` subscription | `location_view_model.dart:227` | MIXED | split GPS vs Wi-Fi |
| Radiomap fallback → `CampusAssetLoader` | `space_view_model.dart:92-100` | INDOOR | verify callers |
| Radiomap load/reset | `campus_asset_loader.dart:285-389`, `:602` | INDOOR | |
| Indoor exposure to pilot | `navigation_view_model.dart:82-89` | INDOOR | consumers: `NavigationPilot` |
| Floors + POIs | `poisForBuildingFloor`, `floorNumbersForBuilding`, `BuildingContainment` | **SHARED** | **Keep** |
| `orientation/DeviceHeadingBridge.kt` | channel `…/heading_stream:44` | OUTDOOR | **Keep** |
| `positioning/{PositioningBridge,KnnLocalizer,PositioningEngine,RadioMap,WifiScanner}.kt` | — | INDOOR | remove only after CP-3 dependency map |
| `MainActivity.kt` constructs both | `:10,17,19-21,25-27` | MIXED | split |
| Permissions `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `NEARBY_WIFI_DEVICES` | manifest | INDOOR-candidate | remove only after inspecting all remaining plugin/native requirements |
| `INTERNET`, `ACCESS_FINE/COARSE/BACKGROUND_LOCATION`, `FOREGROUND_SERVICE(+_LOCATION)` | manifest | OUTDOOR | keep |
| `assets/config/gate_policy.json`, `assets/config/university gates.kmz`, `assets/navigation/university roads.kmz` | 3 files | **OUTDOOR** | preserve (gate policy `G2` preferred; `G1`,`G3`,`G4` disabled — verify at CP-0) |
| `network_security_config.xml:11` empty `<domain>` | — | observation | log only; do not "fix" |

### 6.6 MapScreen / CampusContentPanel responsibilities (REPORTED — CP-0 verifies)

* `map_screen.dart`: heading service construction `:98-99`; heading subscription `:148`; bitmap synthesis `:184-419`; camera math `:607-992`; floorplan overlay cache/async prepare/`setState` `:1298-1370`; marker/route projection `:1057-1289`. Extracted: `computeRouteCamera` `:1538-1572` (**contract must be preserved or an approved test/API migration documented**), `routePolylineSpecs`, `showCampusRoutes`, `BuildingContainment`.
* `campus_content_panel.dart` (F6): `_startDirectionsForPoi` `:1329-1360` (View-owned ~6-step orchestration incl. provider write `:1359`); `_fitRouteBoundsIfAvailable` `:1314-1317` (View→Map camera callback); `_buildBuildingRouteActions` `:1077-1133` (action state derived from 3 ViewModels); Indoor copy `:974`; floor chips `:984-992` (**keep** — floor-bounds containment + floor-scoped POI selection).

MVVM actions: move orchestration to a ViewModel/use-case; keep camera behind an explicit UI callback (**do not** move camera into a ViewModel); relocate derived action state; rewrite Indoor copy only; keep floor chips.

---

## 7. Test Inventory and Regression Matrix

### 7.1 `[V2.1 ADDITION]` 46-vs-47 discrepancy — RESOLVED (planning pass, read-only)
**CONFIRMED (planning pass):**
```
test/*_test.dart (recursive, runnable)      = 46
test/*.dart.disabled (recursive)            = 4
test/*.dart (recursive, all)                = 47
test/helpers/fake_google_maps_platform.dart = 1  (the 47th .dart, not runnable)
```
Interpretation: **both prior counts were partially right** — 46 runnable tests and 47 total `.dart` files (the helper is the extra). No file was renamed. CP-0 must re-run this inventory and record the exact file list; all later counts compare to that baseline. **No final counts are invented.**

### 7.2 Per-test / per-assertion classification
Classes: **Preserve** · **Adapt** · **Exclude** (written justification) · **Add**.

`test/remediation_crossbuilding_test.dart` (mixed — split per test):

| Case | Refs | Hook | Class | Reason |
|---|---|---|---|---|
| NAV-002 nearest ground entrance | `:127-142` | `selectExitPoiForTest` | **Preserve** | Outdoor entrance selection |
| NAV-003 connector chain returns null | `:144-164` | `routeViaConnectorsForTest` | **Adapt or Exclude — CP-0 decision** | Depends on `_routeViaConnectors` (Indoor) |
| B7 outside-bounds | `:166-184` | `detectUserBuilding` | **Preserve** | building containment |
| B7 inside-bounds | `:186+` | `detectUserBuilding` | **Preserve** | building containment |
| Remaining cases | not yet read | — | **UNRESOLVED — CP-0** | |

Indoor-leaning candidates (per-case classification, **not** permission to delete whole files): `location_provider_arbitration_test`, `radiomap_lifecycle_test`, `floor_transition_test`, `handoff_guidance_test`, `position_estimate_boundary_test`; Indoor cases inside `navigation_ui_test`, `navigation_state_machine_test`.

Must preserve: `custom_routes_test`, `custom_route_connectivity_test`, Outdoor cases in `remediation_crossbuilding_test`, outdoor reroute + null-floor behavior (F1), B7 detection, NAV-002, graph-connectivity + gate-policy assertions, `camera_math_test`.

### 7.3 Environment facts (REPORTED — verify)
* `custom_route_connectivity_test.dart` reads `assets/navigation/university roads.kmz` by relative path → run tests **from the target app directory**; verify path assumptions.
* Widget tests require `test/helpers/fake_google_maps_platform.dart` / `installFakeGoogleMapsPlatform()` → verify and preserve.
* `test/live_integration_smoke_test.dart` opt-in via `--dart-define=LIVE_SMOKE=true` → keep separate; never assume external services.
* 4 `*.dart.disabled` files are excluded by the Dart runner — **do not rename to restore coverage**.

### 7.4 `[V2.1 ADDITION]` New tests required
Outdoor reroute with `floorNumber: null`; Indoor runtime-absence (§6.4); each §6.3 responsibility boundary; target identity + heading-channel; Gate A / A′ / A″ / B proofs.

---

## 8. Checkpoints CP-0 … CP-10

Per checkpoint: **Preconditions · Actions · Evidence · Pass · Fail · Must remain unchanged · Next allowed**. In every checkpoint: `[V2.1 ADDITION]` no claim of success without recorded evidence; no invented outputs.

### CP-0 — Read-only preflight and baseline
* **Preconditions:** none. **No copy or edit until CP-0 is complete and separately approved.**
* **Actions:** capture baseline (git branch/HEAD/`-z` porcelain, pre-existing hashes, deleted-path list) · full-source manifest (M1) · record target/source dir state · verify Android/Kotlin/Gradle/Java/Flutter/Dart config + `.metadata` revision + manifest + gradle + settings + channels · inventory `lib/`, `test/` (re-run §7.1), `assets/` (expect 3) · **body-level read of every unresolved item (register P1–P8 below)** · complete per-test classification · review route composition and incomplete-transition behavior · review `map_screen.dart`, `campus_content_panel.dart`, location/nav/repository/native bodies · resolve U2–U10; recover A1–A7 · validate copy method via `/L` dry run.
* **Evidence:** `$audit` files, M1 manifest, `cp0_inventory.txt`, `cp0_unresolved_register.txt`, dry-run listing.
* **Pass:** every register row has a recorded finding; no contradiction open.
* **Fail:** any required path unresolved/truncated/assumption-based; key assumption contradicted; route-behavior impact not understood; counts unreconciled.
* **Unchanged:** entire repository (read-only).
* **Next:** only after your separate approval. If Outdoor behavior cannot be preserved without user-visible regression → return findings, ask for decision, **STOP**.

**`[V2.1 CHANGE]` Preflight register (each: what to read / how recorded / decision gated / stop trigger)**

| # | Read/verify | Record as | Gates decision | Stop trigger |
|---|---|---|---|---|
| P1 | full `cross_building_router.dart` bodies (composition, exit/entrance transitions, incomplete handling, outdoor generation) | finding note + refs | F2; CP-7A | truncated read, or outcome contradicts an assumption → **stop & report** |
| P2 | full `campus_content_panel.dart` bodies | finding note + refs | CP-8 | same |
| P3 | U2–U10 status | per-item | §6 boundaries | unresolved at end of CP-0 |
| P4 | all call sites for each proposed Indoor removal | dependency map | CP-3/CP-5/CP-7B | any Outdoor consumer |
| P5 | every test/assertion affected by API/behavior change | classification table | CP-9 | an assertion would be weakened |
| P6 | exact test/file inventory; re-resolve 46 vs 47 | `cp0_inventory.txt` | D9; CP-9 | counts irreconcilable |
| P7 | Android identity, Flutter import structure, build config, assets, native channels | config record | §3.3; CP-2 | undocumented deviation |
| P8 | recover A1–A7 verbatim from prior plan | assumption log | §11.2 | not recoverable → mark unverified |

### CP-1 — Initial sibling copy
* **Preconditions:** CP-0 complete **and separately approved**; dry-run validated.
* **Actions:** create target; run §3.1 copy; preserve required untracked wrappers; exclude source `local.properties` + §3.2 items; do not alter source; verify required-file presence + Gate A.
* **Evidence:** copy exit code (`$rc` captured immediately), presence list, M2 diff.
* **Pass:** `$rc < 8`; zero unexplained differences.
* **Fail:** any copy error, unexpected diff, missing required file, source change.
* **Unchanged:** source; pre-existing entries.
* **Next:** only on pass.

### CP-2 — `[V2.1 CHANGE]` Target-local config and build identity (AL-2 allowlist only)
* **Preconditions:** CP-1 passed.
* **Actions:** confirm target has no copied source `local.properties`; create target-local config only as authorized; apply §3.3 identity edits; keep toolchain versions; run Gate A′ against **AL-2 only**.
* **AL-2 allowlist (exhaustive; identity only):** `android/app/build.gradle.kts` (namespace/applicationId) · `android/app/src/main/kotlin/eg/edu/ejust/anyplace_campusfind/**/MainActivity.kt` + `orientation/DeviceHeadingBridge.kt` (package decls + channel string) · label resource value · Dart heading-channel constant file. **No Indoor-removal, MVVM, routing, or test paths are allowed in AL-2.**
* **Evidence:** absence check, identity grep, Gate A′ diff (each diff = exactly one AL-2 entry).
* **Pass:** no secret present/exposed; identity consistent; every diff matches one AL-2 entry.
* **Fail:** secret exposure, identity inconsistency, any diff outside AL-2.
* **Next:** only on pass.

### CP-3 — Native Indoor runtime removal
* **Preconditions:** CP-2 passed; P4 native dependency map complete.
* **Actions:** keep `DeviceHeadingBridge.kt`; remove positioning bridge wiring + verified Indoor native files; revise `MainActivity.kt`; review permissions against actual remaining plugin/native requirements; confirm atomic channel rename; run §6.4 verifier; Gate A′ against **AL-3**.
* **AL-3:** removed native files + `MainActivity.kt` + manifest.
* **Pass:** heading intact and renamed atomically; §6.4 reachability proof shows zero Indoor runtime dependency.
* **Fail:** any required Outdoor capability depends on a proposed removal; any unclassified hit.
* **Next:** only on pass.

### CP-4 — MapScreen MVVM boundaries *(before CP-6 overlay removal)*
* **Preconditions:** CP-3 passed; full `map_screen.dart` body read.
* **Actions:** body inspection; responsibility inventory; extract pure logic to testable helpers; keep controller/rendering UI-side; preserve `computeRouteCamera` contract or document approved migration; add responsibility tests; Gate A′ against **AL-4**.
* **Pass:** responsibility tests pass; no controller/rendering in ViewModels; Outdoor rendering/routing unchanged.
* **Fail:** behavior change or boundary violation.
* **Next:** only on pass.

### CP-5 — Location and positioning split
* **Preconditions:** CP-4 passed; location dependency map complete.
* **Actions:** split Outdoor GPS from Indoor Wi-Fi/radiomap lifecycle; remove Indoor service deps from Outdoor runtime graph; preserve GPS streams/fallback/rerouting; verify all consumers; add lifecycle + outdoor-routing-integration tests; Gate A′ against **AL-5**.
* **Pass:** Outdoor location + rerouting semantics unchanged; §6.4 proof.
* **Fail:** split breaks Outdoor location or rerouting.
* **Next:** only on pass.

### CP-6 — Indoor map/floorplan/radiomap removal *(after CP-4)*
* **Preconditions:** CP-5 passed; overlay/cache seam read (`map_screen.dart:1298-1370`).
* **Actions:** remove verified Indoor-only pipeline; preserve hybrid basemap, markers, road/gate overlays, Outdoor route display; preserve floor selection for containment/POI selection; rewrite Indoor copy (`campus_content_panel.dart:974`); Gate A′ against **AL-6**.
* **Pass:** no residual Indoor runtime dependency; building/POI/routing intact.
* **Fail:** loss of required Outdoor building/POI/routing functionality.
* **Next:** only on pass.

### `[V2.1 CHANGE]` CP-7A — Read-only routing impact analysis *(no implementation)*
* **Preconditions:** CP-6 passed; P1/P3/P4 complete.
* **Actions (read-only):**
  1. Inspect complete implementations + call sites of `composeRoute`, `_generateExitSegment`, `_generateEntranceSegment`, and all related transitions.
  2. Trace the **normal outdoor cross-building route** and the **outdoor rerouting** flows end-to-end.
  3. Establish how Indoor-related legs affect current Outdoor behavior.
  4. Identify potential incomplete routes, straight-line transitions, missing entrance/exit legs, and `partialRouteWarning` changes.
  5. Record concrete test cases + expected behavior for each identified scenario.
* **Evidence:** routing-impact analysis document (call graphs, scenario table, before/after route-shape expectations).
* **Pass:** every route scenario has a documented current behavior and a documented expected post-change behavior, each with a test.
* **Fail:** any scenario unresolved; any read truncated.
* **Unchanged:** all code (read-only).
* **Next:** proceed to **your review** of CP-7A findings. **No routing implementation change in CP-7A.**

### `[V2.1 CHANGE]` CP-7B — Routing implementation after explicit authorization
* **Preconditions:** CP-7A findings **reviewed by you** and **explicit authorization granted** for any required observable Outdoor behavior change.
* **Actions:**
  * If existing Outdoor behavior is preservable → document how, and prove it with regression tests.
  * If safe Indoor removal necessarily changes Outdoor behavior → **STOP.** Present the exact proposed behavior change, evidence, and alternatives. **Do not choose an alternative or implement without explicit approval.**
  * Preserve shared coordinate routing + `getRouteFromCoordinates`; preserve Outdoor rerouting, graph routing, entrance selection, route metadata; verify method-level `NavigationRepository` separation; Gate A′ against **AL-7**.
* **Evidence:** scenario results vs CP-7A expectations; regression tests; approval record.
* **Pass:** behavior matches CP-7A-approved expectations, **or** an approved behavior change is implemented exactly as approved.
* **Fail:** any unapproved observable change; compilation/tests alone are **not** proof of behavior preservation.
* **Next:** only on pass + approval.

### CP-8 — CampusContentPanel MVVM refactor
* **Preconditions:** CP-7B passed/approved; P2 complete.
* **Actions:** move orchestration to ViewModel/use-case; keep camera behind explicit UI callback; relocate derived action state; preserve floor chips; rewrite Indoor copy; add §6.3 tests; Gate A′ against **AL-8**.
* **Pass:** View has no business orchestration/business-provider writes; ViewModel has no widget/controller ops.
* **Fail:** either condition true.
* **Next:** only on pass.

### CP-9 — Test migration and verification
* **Preconditions:** CP-8 passed; §7 classification approved.
* **Actions:** apply per-test classification; preserve Outdoor assertions; adapt only changed contracts; exclude only proven Indoor-only tests with written per-case justification; add §7.4 tests; run offline tests **from the target dir**; keep live tests opt-in; record commands + exit codes + counts; Gate A′ against **AL-9**.
* **Pass:** no weakened assertions; Outdoor assertions green; results explainable vs CP-0 baseline.
* **Fail:** tests weakened; Outdoor assertion fails; unexplained delta.
* **Next:** only on pass.

### CP-10 — Final acceptance and integrity
* **Actions:** Gate A″ (M1) · Gate B (§4) · Gate A′ re-run · Outdoor routing/rerouting regressions · gate policy + graph topology · §6.4 Indoor-absence proof · §6.3 MVVM checks · identity/channel consistency · API-key confidentiality · final inventory + exact test results.
* **Pass:** every mandatory gate verified with evidence. **Do not claim success if any gate is unverified.**

---

## 9. Integrity Gates

`[V2.1 CHANGE]` All commands are **proposed, not executed**. Common rules: `Get-ChildItem -Force` (hidden files) · relative normalized paths · sorted entries · SHA-256 · identical exclusions on both sides of every excluded comparison · **never print file contents** · output to `$env:TEMP\campusfind_v2_1_audit` (outside the repo).

### 9.1 `[V2.1 CHANGE]` Core helpers (root-safe, hidden-inclusive)
```powershell
function Get-TreeManifest {
  param([string]$Root,
        [string[]]$ExclDirs  = @('.dart_tool','build','.gradle','.kotlin','.idea','.vscode'),
        [string[]]$ExclFiles = @('local.properties','.flutter-plugins-dependencies','GeneratedPluginRegistrant.java'),
        [string[]]$ExclPaths = @())
  $rf = (Resolve-Path -LiteralPath $Root).Path
  Get-ChildItem -LiteralPath $rf -Recurse -Force -File | ForEach-Object {
    $rel = $_.FullName.Substring($rf.Length).TrimStart('\','/').Replace('\','/')
    $parts = $rel -split '/'
    $name  = $parts[-1]                                  # root-safe (no invalid slicing)
    $dirs  = if ($parts.Count -gt 1) { $parts[0..($parts.Count-2)] } else { @() }
    $okDir  = -not ($dirs  | Where-Object { $ExclDirs  -contains $_ })
    $okFile = -not ($ExclFiles -contains $name)
    $okPath = -not ($ExclPaths -contains $rel)
    if ($okDir -and $okFile -and $okPath) {
      [pscustomobject]@{ Path = $rel
                         Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
    }
  } | Sort-Object Path
}
function Compare-TreeManifest {
  param($A, $B)
  $ha = @{}; $A | ForEach-Object { $ha[$_.Path] = $_.Hash }
  $hb = @{}; $B | ForEach-Object { $hb[$_.Path] = $_.Hash }
  foreach ($p in (@($ha.Keys + $hb.Keys) | Sort-Object -Unique)) {
    if ($ha[$p] -ne $hb[$p]) {
      [pscustomobject]@{ Path = $p
        SourceHash = $(if ($null -eq $ha[$p]) { '<MISSING>' } else { $ha[$p] })
        TargetHash = $(if ($null -eq $hb[$p]) { '<MISSING>' } else { $hb[$p] }) }
    }
  }
}
```
Guarantee scope: path + content only (see §3.4). Hashes only — secrets can appear solely as hashes.

### 9.2 Gate A — Initial copy equivalence (CP-1)
Identical §3.2 exclusions on both sides: source vs target via `Get-TreeManifest` + `Compare-TreeManifest`. **Pass:** empty diff. **Fail:** any diff → **STOP; never normalize silently.** This proves only that *included* files match.

### 9.3 Gate A″ — Original source integrity (CP-10)
No exclusions at all (hidden + local config + generated + untracked), compared against M1. **Pass:** exact equality. **Fail:** any difference → **STOP immediately; do not auto-repair.** Secrets only as hashes.

### 9.4 `[V2.1 CHANGE]` Gate A′ — per-checkpoint allowlists (Correction C)
For every checkpoint that edits the target, compare against that checkpoint's **exact** allowlist. Each entry states: **exact path · reason expected to change · authorizing checkpoint · behavior-vs-structure flag**. Broad directory-level allowlisting is forbidden.

| Allowlist | Checkpoint | Scope |
|---|---|---|
| AL-2 | CP-2 | Android identity (namespace/applicationId) · Kotlin package decls (`MainActivity.kt`, `DeviceHeadingBridge.kt`) · app label · heading channel (Dart + Kotlin) · justified+approved config paths |
| AL-3 | CP-3 | removed native files · `MainActivity.kt` · manifest |
| AL-4 | CP-4 | `map_screen.dart` + extracted helper/service files + their tests |
| AL-5 | CP-5 | location/positioning viewmodel+service+repository files + their tests |
| AL-6 | CP-6 | Indoor overlay/floorplan/radiomap pipeline files + panel copy line + their tests |
| AL-7 | CP-7B | routing composition + repository-split files + their tests (only after approval) |
| AL-8 | CP-8 | `campus_content_panel.dart` + new VM/use-case + their tests |
| AL-9 | CP-9 | test files per §7 classification |

**Pass:** every diff matches exactly one enumerated entry. **Fail:** any unmatched diff → **STOP.** Original-source integrity (§9.3) remains independent of copy equivalence (§9.2) and target-local changes (§9.4).

### 9.5 Gate B — baseline-aware worktree preservation
See §4.3–§4.4. **Pass:** no missing baseline entry; no new path outside `clients/flutter/campusfind_outdoor/` + `docs/PHASE_1_PLAN_V2.1_REVIEW.md`; pre-existing hashes unchanged; 12 deletions still absent. **Fail → STOP.** Never restore/clean pre-existing work.

`[V2.1 ADDITION]` Status equality is necessary but **not sufficient**; Gate A″ (§9.3) + recorded content hashes (§4.4b) are the independent proof.

---

## 10. Risks R1–R12

Each: mitigation · verification evidence · STOP.

| ID | Risk | Mitigation | Evidence | STOP |
|---|---|---|---|---|
| R1 | Accidental source modification | source read-only throughout | Gate A″ | any source hash drift |
| R2 | API-key leakage | never copy/print `local.properties`; hash only; ban key in logs | absence check + secret scan | any key value outside source |
| R3 | Incorrect manifest exclusions | §3.2 table; identical both sides; separate full-source manifest | Gates A/A′/A″ | unexplained diff |
| R4 | Hidden/untracked build-critical files omitted | `-Force`; robocopy `/L`; wrapper checklist | presence list | required file missing |
| R5 | Broken Android package/channel identity | atomic identity edit set (§3.3) | identity grep + AL-2 entries | Dart/Kotlin channel mismatch |
| R6 | Residual Indoor runtime dependencies | §6.4 layered proof | dependency map | any reachable Indoor hit |
| R7 | Outdoor rerouting regression from deleting shared routing APIs | **F1: keep `getRouteFromCoordinates`**; null-floor reroute test | reroute test | reroute differs from baseline |
| R8 | Incomplete-route / `partialRouteWarning` regression | **F2 + CP-7A/7B gate** | route-shape comparison | unapproved behavior change |
| R9 | Loss of Outdoor function via over-removal of floor/POI data | floors+POIs SHARED; floor chips kept; per-call-site inspection | building/POI/routing regressions | any such test fails |
| R10 | MVVM refactor changes behavior or moves controller ops into VMs | §6.3 boundaries + tests | responsibility assertions | VM owns widgets/controller, or behavior changes |
| R11 | Test suite weakened by broad deletion/exclusion | per-test classification + written justification | disposition table | any assertion weakened |
| R12 | Destruction/restoration of pre-existing worktree changes | Gate B; never restore/stage/clean | Gate B output | missing/altered pre-existing entry |

`[V2.1 ADDITION]` R13 (advisory): approval-gate bypass (implementing a behavior change before written approval) — mitigation: CP-7B preconditions + approval record; STOP: any change without an approval record.

---

## 11. Uncertainties U1–U10 and Assumptions A1–A7

### 11.1 U1–U10
Each unresolved item states: **what is unknown · files/refs needed · checkpoint to resolve · blocking condition.**

| ID | Unknown | Needed | Resolve at | Blocks |
|---|---|---|---|---|
| U1 | Full indoor-leg line ranges in `cross_building_router.dart` (`_generateExitSegment`, connector legs, `_selectExitPoi` scope) | complete body read | CP-0 (P1) | CP-7A |
| U2 | `RouteSegmentType.{indoorRouting,floorTransition}` consumers + `toSegmentedIndoor` | grep + reads | CP-0 (P3) | CP-7A/7B |
| U3 | `NavigationPilot` call sites into building-context/floor-transition handlers | reads | CP-0 (P3) | CP-5/CP-7B |
| U4 | `NavigationSessionManager` dwell/activity-restore bookkeeping | reads | CP-0 (P3) | CP-7B |
| U5 | `NavigationConfig` orphan constants | reads | CP-0 (P3) | CP-6 |
| U6 | `NavigationRouteScope.activeFloorplan` / `releaseIndoorContextForNavigation` / `selectFloorForNavigation` consumers | reads | CP-0 (P3) | CP-6/CP-7B |
| U7 | `campus_content_panel.dart` floor/floorplan presentation ranges | reads | CP-0 (P2) | CP-6/CP-8 |
| U8 | Assertion-level indoor content of mixed tests | per-test reads | CP-0 (P5) | CP-9 |
| U9 | dead-code candidates (`AnyplaceRadioMapRepository.clearRadioMap`, `AnyplaceFloorplanRepository.isFloorplanCached`/`clearFloorplan`, `PositionEstimate.latLng`) | reads | CP-0 (P3) | CP-6 |
| U10 | `main_shell.dart` / `profile_screen.dart` / `search_overlay.dart` MVVM status | reads | CP-0 (P2) | CP-8 |

`[V2.1 ADDITION]` No U item may be marked resolved without a recorded body-level finding. **Partially resolved so far:** U1, U7, U8 (see §6.1, §6.6, §7.2); remainder still UNRESOLVED.

### 11.2 A1–A7
`[V2.1 CHANGE]` **The exact text of A1–A7 is not available in the current planning context** and must be **recovered verbatim from the prior plan at CP-0 (register P8)**. They are intentionally **not** restated here, to avoid invention. Each must then be labelled exactly one of: *Verified by read-only evidence* · *Still unverified and blocking* · *Rejected by new findings* · *Requires explicit approval*.

**Known rejected/qualified premise (from F1–F6):** V2's premise that `getRouteFromCoordinates` and `composeRoute`'s indoor legs were Indoor-only removal candidates is **rejected/qualified** — see §6.1/§6.2.

---

## 12. Stop Conditions, Evidence, Acceptance, Approval Boundaries

### 12.1 Global stop conditions
Any of the following halts the workflow and requires your input: a source-hash drift (Gate A″) · an unexplained diff (Gates A/A′) · an illegal new path or missing/altered pre-existing entry (Gate B) · a truncated/contradictory CP-0 read that changes an assumption · a reachable Outdoor dependency on a proposed Indoor removal · any proposed Outdoor behavior change (CP-7B) without written approval · any weakened test assertion · any secret exposure.

### 12.2 Final acceptance checklist
- [ ] Gate A″ source integrity · [ ] Gate B worktree preservation · [ ] Gate A copy equivalence · [ ] Gate A′ per-checkpoint allowlists
- [ ] Outdoor routing cascade + rerouting + `floorNumber: null` preserved · [ ] gate policy (`G2` preferred; `G1`,`G3`,`G4` disabled) · [ ] KMZ graph topology + connected-component assertions (not relaxed)
- [ ] 3 assets present/unchanged · [ ] no reachable Indoor runtime dependency (§6.4) · [ ] §6.3 MVVM checks · [ ] `computeRouteCamera` contract preserved or approved migration
- [ ] identity + label + atomic channel rename · [ ] API-key confidentiality · [ ] required untracked wrappers present
- [ ] test inventory reconciled + every test/assertion dispositioned · [ ] exact commands, exit codes, counts recorded (no invented results)
- [ ] every outdoor behavior change documented + approved

### 12.3 Approval boundaries
CP-1 requires CP-0 approval. **CP-7B requires written approval of CP-7A findings.** Any necessary observable Outdoor behavior change requires its own written approval. This document grants no implementation authorization; authorization must arrive as a **separate explicit message**.

---

## Appendix Z — Seven-Blocker → V2.1 Resolution Map

| Blocker | V2.1 correction | Verification | STOP |
|---|---|---|---|
| 1 Working-tree preservation | §4: branch+HEAD+`-z` path-set+content hashes; space-safe; deleted-path persistence; allow only sibling + `docs/PHASE_1_PLAN_V2.1_REVIEW.md` | §4.4 Gate B | missing/altered entry; illegal path |
| 2 SHA-256 manifests & gates | §3.4/§9.1: three distinct manifests; `-Force`; root-safe; sorted; hash-only; filtered ≠ source-integrity | Gates A/A′/A″ | any unexplained diff |
| 3 Outdoor/Indoor boundary | §6: responsibility/dependency/call-site; mixed files split per method; explicit inspection list | §6.1–6.5 | any Outdoor consumer of a removal |
| 4 Read-only preflight | §8 CP-0 + register P1–P8; F1–F6 do not complete inspection | CP-0 artifacts | contradictory/truncated read → **stop & report** |
| 5 MVVM = responsibilities | §6.3 layer table; bans on View orchestration / VM widgets+cameras / domain→Flutter | assertions + §6.4 | boundary violation |
| 6 Preserve Outdoor + existing work | §3.3/§5/§6.2/§11 protected set; F1 shared API; CP-7B gate; Gate B | checklist + Gates | any Outdoor regression / weakened assertion / unapproved change |
| 7 Evidence + stop per checkpoint | §8 Preconditions/Actions/Evidence/Pass/Fail/Unchanged/Next; CP-7A/7B split | checkpoint artifacts | fail → no advance; no invented results |
