# Navigation Implementation History

> Reconstructed from git history, working-tree diffs against `HEAD` (18e2ba79),
> the current codebase, test suites, and session reports. Every claim is traced
> to evidence. Where chronology cannot be proven, it is marked explicitly.

## 1. Purpose

Document what was **actually implemented** during the Navigation System
Unification work, and compare it against the ORIGINAL implementation plan
(7 original phases). This distinguishes architectural completion from passing
tests, and establishes exactly where the work currently stands.

Terminology note: internal implementation steps were numbered "Phase 2 —
Step N" during execution. Those steps were **all still part of ORIGINAL
PHASE 1 — Unified Positioning** (hardening/verification of the positioning
boundary). They are classified below as Original Phase 1 work. The name
collision is recorded as a deviation (§6, D7).

## 2. Original Implementation Plan (summary)

Goals: (1) unified GPS + Wi-Fi positioning that determines where the user
actually is; destination/floor selection must never determine physical
location; continuous indoor/outdoor and floor-to-floor navigation; explicit
navigation transition states; one canonical route representation; proper
building entrance/exit semantics with confirmation (not mere proximity);
automatic arrival detection; no hardcoded campus data.

Original phases:
1. **Unified Positioning** — LocationProvider, GpsLocationService,
   MethodChannelNativePositioningService, PositioningBridge, PositioningEngine,
   WifiScanner, KnnLocalizer, RadioMap. Remove/redesign the
   `_activeIndoorBuid` / `_activeIndoorFloor` selection-driven validity
   coupling. Evidence/confidence/stability/hysteresis/stale based arbitration;
   no fake numerical fusion; investigate hardcoded Wi-Fi accuracy; resolve the
   single-active-RadioMap limitation (strategy A–D).
2. **Navigation State Machine** — evolve `NavigationPhase{idle,preview,active}`
   + `NavigationSubState{outdoor,indoor,transitioning}` into IDLE /
   ROUTE_PREVIEW / ACTIVE_OUTDOOR / ENTERING_BUILDING / ACTIVE_INDOOR /
   FLOOR_TRANSITION / EXITING_BUILDING / ARRIVED / PAUSED / REROUTING.
3. **Canonical Route Model** — make CrossBuildingRouter segment representation
   canonical over the legacy flat hybrid route.
4. **Building Transitions** — first-class approaching/entering/exiting states
   with confirmation/hysteresis; no proximity-as-proof; no assumed floor "0".
5. **Floor Transitions** — first-class events; expected/detected/in-progress/
   confirmed floor distinction; loaded RadioMap ≠ physical-floor proof.
6. **Arrival** — POI-proximity confirmation → ARRIVED, auto-stop, UI notify.
7. **UI** — expose state/segment/instruction/progress/source/transition/
   rerouting/arrival without redesigning UI; preserve all existing Anyplace
   functionality; no invented backend APIs.

Migration rules: read before modify, smallest coherent change, analyzer checks
per logical change, no duplicate responsibilities, no special-case conditionals
replacing architecture.

## 3. Actual Implementation Timeline

Evidence base: `git log` shows the last commit touching this client is
`18e2ba79` ("Merge remote-tracking branch 'origin' into campusfind-migration").
**The entire unification implementation exists as uncommitted working-tree
changes on top of that commit.** Older commits (`c745f50a` "indoor & outdoor
navigation feature", `dd37d698`, `bd545b47` "Update navigation and positioning")
represent earlier evolution of these same components and are context, not part
of this effort.

### Internal Step P1-A — Core Unified Positioning build-out (pre-session)

- **Chronology uncertain** (order of sub-changes within this block cannot be
  proven from git because nothing was committed; content is fully evidenced by
  the working-tree diff vs HEAD).
- **Requested (original plan):** remove selection-driven indoor validity;
  evidence-based arbitration; unified output; multi-RadioMap strategy; accuracy
  investigation.
- **Implemented:**
  - `LocationProvider` rewritten 356 → 643 lines. Removed
    `_activeIndoorBuid`/`_activeIndoorFloor`, `setActiveIndoorFloor()`, and the
    gate `estimate.buid == _activeIndoorBuid && estimate.floor ==
    _activeIndoorFloor` (verified present at HEAD, absent in tree; zero
    references to `setActiveIndoorFloor` remain under `lib/`). Introduced
    `_ArbiterMode {outdoor, indoor}` exclusive-belief arbitration, qualifying-
    estimate filter (status success, non-empty scope, matchedAps ≥
    `stabilityMinMatchedAps`=2, ratio ≥ 0.25), entry hysteresis
    (`indoorEnterConfirmCount`=3), exit hysteresis
    (`indoorExitStaleCycles`=3 bad cycles + 10 s stale timer, generation-guarded;
    timer concept existed at HEAD), claim/scope confirmation
    (`scopeConfirmCount`=3), same-scope outlier guard (>30 m hold), stability
    window (5 s / 3 estimates / 15 m delta; window existed at HEAD), confidence
    formula 0.45 ratio + 0.25 spread + 0.30 stability.
  - New `lib/data/models/position_fix.dart`: canonical `PositionFix`
    (lat/lng/source/buildingId/floor/accuracy/confidence/timestamp/status/
    PositionSource{gps,wifi}/PositionFixStatus{fresh,held,stale}).
  - `PositionEstimate` extended with evidence fields `bestDistance`,
    `topKSpreadMeters`; tolerant `fromMap` (string numerics, missing/null
    fields); `isValid` semantics (success + finite non-zero coords +
    matchedAps > 0); `toMap` omits absent evidence (backward compatible).
  - Native engine rebuilt 94 → 233 lines: single `activeRadioMap` replaced by
    LRU `LinkedHashMap` residency (`RESIDENT_MAP_LIMIT = 4`, sole definition,
    PositioningEngine.kt:36); per-scan localization against every resident map;
    single winner by highest `matchedAps`, tie-break lowest `bestDistance`;
    zero-match maps skipped; `no_match` estimates carry empty identity;
    `removeRadioMap(buid,floor)` added; `getActiveInfo()` additive metadata.
  - `KnnLocalizer` (+50): `LocalizationResult` carries `bestDistance`
    (default ∞), `topKSpreadMeters`.
  - `PositioningBridge` (+69): payload gains `bestDistance`/`topKSpreadMeters`
    (all keys always present); `removeRadioMap` method; scanning stops only when
    residency empties.
  - `MethodChannelNativePositioningService` (+294): `removeRadioMap` API,
    `onFailureDetail` diagnostics, stream `.where(is Map)` filter.
  - `navigation_config.dart`: new constants `residentMapLimit` (doc-only mirror),
    `indoorEnterConfirmCount`, `indoorExitStaleCycles`, `minMatchedRatio`,
    `scopeConfirmCount`, `wifiAccuracyMinMeters=2.0`, `wifiAccuracyMaxMeters=30.0`.
    Accuracy is now derived: clamp(max(spread, bestDistance)) instead of a
    hardcoded value.
  - `space_provider.dart`: floor selection loads/removes RadioMaps as
    **residency management** (loadRadioMap :1643, removeRadioMap :1665/:1689/
    :1698, clearRadioMap :1892); selection no longer feeds positioning validity.
    (Diffstat ~4172 lines is dominated by CRLF churn; functional changes are
    the residency calls.)
  - `quick_access_test.dart`: mechanical updates to provider API changes.
- **Tests:** existing suite updated (107 passing at end of this block).
- **Verification:** analyzer/tests run per migration rules (session reports).
- **Original phase:** Original Phase 1.
- **Status:** functionally complete; field/hardware validation deferred.

### Internal Step P1-B — Phase 2 Step 0: Read-only baseline audit (session)

- **Requested:** freeze regression bar before any hardening.
- **Implemented:** audit only — 10 tracked modified files, untracked
  `position_fix.dart` + analysis doc; analyze 32 issues/0 errors; 107/107 tests;
  Kotlin compile OK. No code changed.
- **Files changed:** none. **Tests:** none. **Original phase:** Phase 1.
- **Status:** complete.

### Internal Step P1-C — Phase 2 Step 1: Lifecycle/dispose hardening (session)

- **Requested:** fix dispose/listener races without touching arbitration.
- **Implemented:**
  - `PositioningEngine.clearListener(listener)` ownership-safe compare-and-clear
    (fixes activity-recreation clobber: replacement bridge registers its
    listener before outgoing bridge disposes).
  - `PositioningBridge`: anonymous listener → owned field `engineListener`;
    `dispose()` uses `clearListener(engineListener)`.
  - `LocationProvider`: `_isDisposed` flag guards in `_evaluateArbitration`,
    `_updateStability`, `_onNativeEstimate`, stale-timer callback, GPS
    listener/onError; idempotent `dispose()`.
- **Files changed:** PositioningEngine.kt, PositioningBridge.kt,
  location_provider.dart, NEW test/location_provider_lifecycle_test.dart.
- **Tests:** +4 lifecycle (fake-async): resubscribe-once, dispose cancels
  streams + late emissions inert, stale-timer expiry, generation guard.
  107 → 111.
- **Verification:** analyze 32/0-errors; 111/111; compileDebugKotlin +
  assembleDebug OK; temporary JVM harness 5/5 (deleted); channels frozen;
  all 8 invariants green.
- **Original phase:** Phase 1. **Status:** complete (approved).

### Internal Step P1-D — Phase 2 Step 2: Arbitration edge-case tests (session)

- **Requested:** permanent focused tests proving winner selection, hysteresis,
  scope confirmation, outlier guard, exit rules, determinism, selection
  independence; native comparator proof.
- **Implemented:** NEW test/location_provider_arbitration_test.dart (19
  testWidgets). **No production changes** — initial failures were all
  test-expectation errors; one behavior documented (identity publishes on the
  estimate *after* the Nth consistent claim — "one-fix publication lag"),
  judged compliant with invariant 3.
- **Native verification:** temporary JVM scaffold, overlapping-MAC fixtures —
  higher matchedAps wins; equal matchedAps → lower bestDistance wins both
  directions; zero-match maps never win; no residents → null. 11/11 PASS,
  scaffold deleted.
- **Files changed:** only the new test file. **Tests:** 111 → 130.
- **Original phase:** Phase 1. **Status:** complete (approved).

### Internal Step P1-E — Phase 2 Step 3: Transport-boundary hardening (session)

- **Requested:** harden native↔Dart payload/parsing boundary without changing
  arbitration; test rather than change where already satisfied.
- **Implemented:**
  - Audit verdict: bridge payload (fixed 11 keys, nulls for absence,
    StandardMethodCodec carrying NaN/∞ losslessly), stream filtering
    (`.where`), `handleError` containment, and disposal guards already
    satisfied the boundary contract → pinned by tests.
  - ONE production fix (Step 3 mandate B): `PositionEstimate.fromMap` threw
    `RangeError` on corrupt numeric timestamps (e.g. 9007199254740992);
    now falls back to wall-clock like non-numeric timestamps. Zero arbitration
    impact.
- **Files changed:** lib/data/models/position_estimate.dart,
  NEW test/position_estimate_boundary_test.dart (12 tests: parsing matrix,
  hostile-map battery, real EventChannel pipeline under garbage traffic,
  post-dispose inertness through the true transport).
- **Tests:** 130 → 142. **Verification:** analyze 32/0-errors; 142/142;
  native build not required (no Kotlin edits); git scope clean except an
  unrelated external deletion (§6 D8).
- **Original phase:** Phase 1. **Status:** complete (awaiting approval when
  this document was requested).

## 4. Requirement-by-Requirement Comparison

### Original Phase 1 — Unified Positioning

| Requirement | Actual implementation | Status | Evidence | Remaining |
|---|---|---|---|---|
| Remove `_activeIndoorBuid/Floor` selection-driven validity | Fully removed; selection only manages residency | **[COMPLETE]** | symbols present at HEAD (`git show HEAD:…location_provider.dart`), absent in tree; no `setActiveIndoorFloor` refs | none |
| Positioning decides applicable indoor estimate | Qualifying filter + arbiter modes | **[COMPLETE]** | `_qualifies`, `_ArbiterMode` in location_provider.dart | none |
| Confidence | Weighted formula (ratio/spread/stability) | **[COMPLETE]** | `_computeWifiConfidence`; asserted finite∈[0,1] in tests | none |
| Temporal stability | 5 s window, ≥3 estimates, 15 m max-delta | **[COMPLETE]** | config :60–69; stability tests | none |
| Hysteresis | Enter 3 consecutive; exit 3 bad cycles | **[COMPLETE]** | config :85/:91; arbitration tests | none |
| Stale detection | 10 s timer, generation-guarded, disposal-safe | **[COMPLETE]** | config :178; lifecycle tests | none |
| Building identity when confident | `scopeConfirmCount`=3 consistent winning claims | **[COMPLETE]** | config :105; scope-exactness tests | none |
| Floor identity when confident | Same pair mechanism (buid+floor atomic) | **[COMPLETE]** | claim-switch test | none |
| Unified output (lat/lng/source/buid/floor/accuracy/confidence/ts/status) | `PositionFix` canonical | **[COMPLETE]** | position_fix.dart; currentFix getter | none |
| GPS outdoor preserved | Untouched GpsLocationService; believed outdoors | **[COMPLETE]** | gps_location_service.dart unmodified | none |
| Wi-Fi indoor preserved | Native stack operational | **[COMPLETE]** | engine/bridge/scanner | none |
| No fake numerical fusion | Exclusive single-source belief | **[COMPLETE]** | arbiter design; invariant tests | none |
| Robust arbitration suite | All five mechanisms present | **[COMPLETE]** | §P1-A list | none |
| Hardcoded Wi-Fi accuracy investigated | Derived clamp(2–30 m), no-basis→30 m | **[COMPLETE]** | wifiAccuracyMin/MaxMeters; derivation tests | none |
| Single-RadioMap limitation resolved | Strategy A: multiple residents, LRU ≤ 4, controlled switching via load/remove/clear | **[COMPLETE]** | RESIDENT_MAP_LIMIT :36; space_provider residency calls | none |
| Consistency checks incl. route context "where appropriate" | Scope-consistency + outlier guard implemented; route context deliberately NOT consulted (measurement-only identity) | **[PARTIAL]** | arbiter has no route input by design | Explicit product sign-off that route context stays excluded, or add it in Phase 2 |
| Field/hardware validation inside E-JUST | Deferred to user | **[INTENTIONALLY DEFERRED]** | session reports items B–F, partial G | physical testing |

### Original Phase 2 — Navigation State Machine

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| Explicit 10-state model | Not touched | **[NOT STARTED YET]** | navigation_controller.dart:19 `enum NavigationPhase { idle, preview, active }`; :22 `NavigationSubState { outdoor, indoor, transitioning }`; no ARRIVED/PAUSED/REROUTING/FLOOR_TRANSITION/ENTERING/EXITING anywhere |
| Retire scattered booleans | Unchanged | **[NOT STARTED YET]** | controller unmodified in working tree |

### Original Phase 3 — Canonical Route Model

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| Segment representation canonical | Both representations still coexist; controller consumes flat route | **[NOT STARTED YET]** | cross_building_router.dart & route models unmodified; SpaceProvider cascade unchanged |

### Original Phase 4 — Building Transitions

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| First-class transition states w/ confirmation | Only pre-existing proximity heuristics in controller (`checkEntranceProximity`, `checkBuildingApproach`) | **[NOT STARTED YET]** (positioning-layer confirmation exists and is reusable, but no navigation states) | controller unmodified |

### Original Phase 5 — Floor Transitions

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| Floor transitions as first-class events; expected/detected/in-progress/confirmed | Positioning-level detected/confirmed floor done in Phase 1; navigation event model untouched | **[NOT STARTED YET]** (navigation half) | `_checkFloorTransition` pre-existing; controller unmodified |

### Original Phase 6 — Arrival

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| Auto arrival detection, stop, notify UI | Absent; manual End / tab-leave only | **[NOT STARTED YET]** | NAVIGATION_SYSTEM_ANALYSIS.md §1.2 step 6; controller has no arrival logic |

### Original Phase 7 — UI

| Requirement | Actual | Status | Evidence |
|---|---|---|---|
| Expose new state/segment/transition/arrival info | Only pre-existing exposure remains (indoor badge, positioning status bar, rerouting indicator) | **[NOT STARTED YET]** for new items | map_screen.dart:1130 `isIndoorWifiActive` (pre-existing); UI files unmodified |
| Preserve Anyplace APIs/routing/KMZ/OSRM/rendering/loading/search/Quick Access | Preserved | **[COMPLETE]** (as preservation constraint) | untouched files list §11 |
| No hardcoded campus data | None introduced by this work | **[COMPLETE]** (as constraint) | tests use synthetic buids; production code data-driven |

## 5. Architectural Invariants

- **Destination ≠ physical position:** SATISFIED. Selection path ends in
  residency management; arbiter consumes measurements only; selection-
  independence test (different loaded maps → identical results).
- **Positioning from positioning evidence only:** SATISFIED. Qualification,
  winner, claims, confirmation all derive from estimate fields.
- **RadioMap loading ≠ physical-floor proof:** SATISFIED. Loading affects
  candidacy; identity requires 3 consistent winning claims.
- **No fake fusion:** SATISFIED. Exactly one believed source; switches via
  hysteresis/stale only.
- **No hardcoded campus data:** SATISFIED. Constants are behavioral thresholds,
  not campus facts.
- **Existing Anyplace functionality preserved:** SATISFIED. API client, repos,
  router, graph, OSRM, rendering, search, Quick Access untouched.
- **No duplicate responsibility:** LARGELY SATISFIED. One known deliberate
  documentation-mirror: Dart `residentMapLimit` is doc-only; the enforced
  constant lives once natively (PositioningEngine.kt:36).
- **No special-case conditionals replacing state architecture:** SATISFIED so
  far (none added); Original Phases 2–6 will be the real test and have not
  started.

## 6. Deviations From Original Plan

| # | Deviation | Why | Safe? | Keep? | Correction needed? |
|---|---|---|---|---|---|
| D1 | Identity publishes on the estimate AFTER the 3rd consistent claim ("one-fix publication lag") | Fix object built before confirmation flips | Yes (invariant "null until N" holds strictly) | Yes | Document only; change would alter timing semantics |
| D2 | Malformed-but-Map payloads deliver as degraded invalid evidence instead of being dropped | Preserves stream liveness; conservative | Yes | Yes | No |
| D3 | Corrupt numeric timestamp → wall-clock fallback | Boundary robustness (Step 3 mandate) | Yes | Yes | No |
| D4 | `clearListener` ownership pattern (addition beyond plan) | Real recreation-order bug found in Step 1 | Yes | Yes | No |
| D5 | Strategy A (multi-residency LRU≤4) selected among plan options A–D | Plan allowed choice | Yes | Yes | No |
| D6 | Dart-side doc-only `residentMapLimit` mirror | Avoids frozen-channel/format churn | Yes | Acceptable | Optionally remove the mirror or annotate harder |
| D7 | Internal step naming collision ("Phase 2 — Step N" ≠ Original Phase 2) | Process labeling | Yes | Rename future comms to avoid ambiguity | Communication hygiene only |
| D8 | `docs/MAP_MIGRATION_PLAN.md` deleted in working tree (tracked at f807849f) | External/unattributed — not produced by any recorded implementation step | Unknown | Pending user decision | User must confirm intent (restore or commit deletion) |
| D9 | Entire unification effort uncommitted | Process choice | Risk of loss | Commit after approval | Recommended |

Pre-session sub-step ordering within P1-A: **Chronology uncertain** (no commits;
diff is monolithic).

## 7. Work Completed (actual)

1. Selection-driven indoor-validity coupling removed (core Phase 1 goal).
2. Full evidence-based arbiter: qualification, confidence, temporal stability,
   bidirectional hysteresis, stale detection, outlier guard, scope
   confirmation, exclusive single-source output via `PositionFix`.
3. Multi-RadioMap residency engine (LRU ≤ 4) with measurement-only winner
   selection and evidence metadata end-to-end (Kotlin → bridge → Dart model).
4. Evidence-derived accuracy replacing any fixed accuracy value.
5. Backward-compatible tolerant parsing boundary (legacy payloads, string
   numerics, malformed/non-finite/corrupt-timestamp inputs).
6. Lifecycle/dispose safety across Dart provider, bridge, and engine listener.
7. Permanent test infrastructure: 35 new tests across 3 files
   (4 lifecycle + 19 arbitration + 12 boundary); suite 107 → 142, all green.
8. Analyzer baseline held at exactly 32 issues / 0 errors throughout.

## 8. Work Remaining (required by original plan)

- Original Phase 1 closure: user field validation (deferred); explicit
  decision on route-context exclusion; commit the working tree.
- Original Phase 2: entire navigation state machine (not started).
- Original Phase 3: canonical segment route adoption (not started).
- Original Phase 4: first-class building transitions (not started).
- Original Phase 5: navigation-level floor-transition events (positioning half
  done) (not started).
- Original Phase 6: automatic arrival (not started).
- Original Phase 7: UI exposure of the above (not started).

## 9. Current Position In The Original Plan

- **Current original phase:** Original Phase 1 — Unified Positioning
  (hardening/verification tail).
- **Completed original phases:** none formally closed end-to-end (Phase 1 is
  architecturally complete except deferred field validation and the
  route-context sign-off; Phases 2–7 not started).
- **Partially completed:** Original Phase 1 (~95%; remaining items are
  validation/process, not architecture). Original Phase 5 positioning-half
  prerequisites exist but the phase itself is not started.
- **Not started:** Original Phases 2, 3, 4, 5(navigation half), 6, 7(new UI).
- **Latest internal implementation step:** Phase 2 — Step 3 (transport-boundary
  hardening) = Original Phase 1 work.
- **Remaining work in current phase:** field testing (deferred), route-context
  decision, commit.
- **Correct next step:** close Original Phase 1 (commit + deferred-validation
  tracking), then begin Original Phase 2 state-machine design — NOT another
  positioning hardening step.

## 10. Files Changed So Far (by internal step)

**P1-A (pre-session, chronology uncertain):**
`lib/state/location_provider.dart` (356→643), `lib/config/navigation_config.dart`,
`lib/data/models/position_estimate.dart`, `lib/data/datasources/native_positioning_service.dart`,
`lib/state/space_provider.dart`, `test/quick_access_test.dart`,
NEW `lib/data/models/position_fix.dart`,
Kotlin: `PositioningEngine.kt` (94→233), `PositioningBridge.kt`, `KnnLocalizer.kt`,
`WifiScanner.kt`.

**P1-B:** none (read-only).

**P1-C:** `PositioningEngine.kt`, `PositioningBridge.kt`,
`lib/state/location_provider.dart`, NEW `test/location_provider_lifecycle_test.dart`.

**P1-D:** NEW `test/location_provider_arbitration_test.dart`.

**P1-E:** `lib/data/models/position_estimate.dart` (timestamp fallback),
NEW `test/position_estimate_boundary_test.dart`.

**Unattributed/external:** deletion of `docs/MAP_MIGRATION_PLAN.md` (D8).

## 11. Files That Have NOT Been Changed (important untouched architecture)

- `lib/state/navigation_controller.dart` — the entire Original Phase 2/4/5/6
  surface (still idle/preview/active + sub-states; no arrival).
- `lib/data/repositories/cross_building_router.dart`,
  `custom_route_repository.dart`, `custom_route_graph.dart`, route models —
  Original Phase 3 surface.
- `lib/ui/**` incl. `map_screen.dart`, `map_bottom_sheet.dart`, detail cards —
  Original Phase 7 surface.
- `lib/main.dart`, `main_shell.dart` — wiring/shell.
- `gps_location_service.dart`, `anyplace_api_client.dart`,
  `radiomap_cache.dart`, `user_location.dart` — preserved services.
- `device_heading_service.dart` — separate sensor channel.
- Kotlin `MainActivity`/glue, manifest, gradle — frozen.
- Server code — out of scope throughout.

## 12. Risks / Technical Debt

1. Everything uncommitted (D9) — single point of loss; also makes bisection
   impossible.
2. One-fix publication lag is now load-bearing documented behavior — future
   consumers must not assume identity appears AT the confirming estimate.
3. Doc-only `residentMapLimit` mirror can drift from native truth.
4. Malformed-evidence delivery semantics (degraded, not dropped) must stay
   consistent if the payload contract ever evolves.
5. `MAP_MIGRATION_PLAN.md` deletion unresolved (D8).
6. Pre-session changes lack granular history — future archaeology depends on
   this document and test names.
7. Deferred hardware validation could reveal tuning issues (thresholds are
   config constants, adjustable without structural change).

## 13. Recommended Next Implementation Step (identify only — do NOT implement)

Close out Original Phase 1: obtain user decision on D8 (restore vs accept the
MAP_MIGRATION_PLAN.md deletion), commit the approved working tree (making the
unification history durable), record the deferred field-validation checklist as
the explicit Phase 1 exit criterion, and capture the route-context exclusion
decision. Only after that closure should Original Phase 2 (navigation state
machine) begin.
