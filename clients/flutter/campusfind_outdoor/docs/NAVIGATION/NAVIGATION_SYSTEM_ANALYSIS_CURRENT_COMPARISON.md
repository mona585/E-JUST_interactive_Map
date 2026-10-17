# Navigation System Analysis — Current Codebase Comparison

Audit of every problem in `docs/NAVIGATION_SYSTEM_ANALYSIS.md` (§10 issues 1–37,
§11 Final Verdict) against the actual code on this branch. Evidence-first: every
row cites current files/lines that were opened and read during this audit.

- Audit date: 2026-08-23
- Baseline audited against: `docs/NAVIGATION_SYSTEM_ANALYSIS.md` (unmodified)
- Method: direct reads of `lib/state/*`, `lib/config/navigation_config.dart`,
  `lib/data/**`, Kotlin engine sources, UI consumers; plus targeted greps for
  every getter/symbol the baseline claimed was unused or misused.
- Status vocabulary: A = FIXED, B = PARTIALLY FIXED, C = STILL PRESENT,
  D = NO LONGER APPLICABLE, E = CANNOT VERIFY.

---

## 1. Executive summary

The baseline describes a system that mostly no longer exists. Its three most
damning architectural findings — selection-driven positioning scope, a
single-slot native RadioMap, and instant indoor/outdoor flips — are all fixed
in current code. A unified evidence-based arbiter (`LocationProvider`), an
explicit 10-state navigation machine, first-class floor-transition and arrival
pipelines, and a rich UI exposure layer have replaced the fragmented logic the
baseline documented.

What remains broken is concentrated in three families:

1. **Cross-building routing internals** — exit-POI selection, exit-leg floor
   origins, wall-cutting connectors, unflagged straight-line fallbacks
   (baseline items 3, 4, 8, 11, 14, 30, 31).
2. **Session lifecycle leaks** — a tab switch force-ends navigation, a
   confirmed building exit wipes the route and all RadioMap residency
   mid-session, and a manual floor tap during navigation silently desyncs and
   unrenders the route (items 12-partial, 17, 26, 36).
3. **Positioning polish** — no duty cycling, partial smoothing, several rich
   outputs still without consumers (items 7-partial, 20-partial, 22, 34-partial).

**Out of 37 baseline problems: 11 FIXED / 13 PARTIALLY FIXED / 13 STILL PRESENT / 0 NO LONGER APPLICABLE / 0 CANNOT BE VERIFIED.**

The baseline is stale as a description of the current system but remains valid
as a defect ledger for the 13 unresolved rows.

---

## 2. How this audit was conducted

- Full reads: `lib/state/location_provider.dart` (735 lines),
  `lib/state/navigation_controller.dart` (1468 lines),
  `lib/state/navigation_state_model.dart`,
  `lib/data/models/position_fix.dart`,
  `lib/config/navigation_config.dart`,
  key regions of `lib/state/space_provider.dart` and
  `lib/ui/widgets/map_bottom_sheet.dart`.
- Kotlin engine verified: `PositioningEngine.kt`, `PositioningBridge.kt`,
  `KnnLocalizer.kt`, `WifiScanner.kt`.
- Lib-wide greps confirmed absence/presence and consumer counts for:
  `setActiveIndoorFloor`, `_syncLocationProvider` (zero matches),
  `.confidence`, `positioningStability`, `customRouteProgress`,
  `nextSegment`, `floorTransitionEvents`, `isFullyNavigable`,
  `RouteSegment.fallback`, `.hybrid` constructor callers, OSRM endpoints.
- Routing-layer claims were re-verified line-by-line in
  `lib/data/repositories/cross_building_router.dart` and
  `lib/state/space_provider.dart` route-request cascade.

---

## 3. The core architectural question (§4 of baseline)

> Can selecting a destination building/floor still cause positioning to treat
> that building/floor as the user's physical location?

**NO — with one clearly-bounded residue.**

Proof from current code:

- The selection-to-positioning mirror APIs are gone: `setActiveIndoorFloor`
  and `_syncLocationProvider` produce **zero matches** across `lib/`.
- Arbitration is decided exclusively by measurement evidence:
  `location_provider.dart:49-61` ("Decided exclusively by measurement evidence
  … never by UI selection, destination, route, POI, or selected-floor
  context"), enforced by the `_ArbiterMode` machine (`:226-233`) with entry
  requiring `indoorEnterConfirmCount` (3) consecutive qualifying estimates
  (`:261-279`, `navigation_config.dart:85`).
- Building/floor identity on a fix is null until a claim streak of
  `scopeConfirmCount` (3) consistent winning estimates confirms it
  (`location_provider.dart:375-397`; `position_fix.dart:43-52,84-85`).
- The navigation controller's initial activity comes from `fix.source` only
  (`navigation_controller.dart:371-376`), and building-entry corroboration
  requires the fix's *confirmed scope* to match the destination building
  (`:584-589`).

Residue (bounded and disclosed): user selection still determines **which
RadioMaps are resident** and therefore available to be matched against
(`space_provider.dart:1655-1660` loads the selected floor's map into the
engine). Selection shapes the *candidate pool*, never the *belief* or the
*reported identity*. If only the destination floor's map is resident, a false
positive would still need to win the per-scan competition and survive a 3-tick
claim streak before it could be believed.

---

## 4. Missing functionality (baseline items 1–8)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 1 | Arrival detection absent | **A — FIXED** | `_checkArrival` producer: `navigation_controller.dart:1371-1408`; anchor resolution (destination POI → route last point): `:1339-1365`; indoor arrivals additionally require confirmed scope match on buildingId+floor (`:1379-1389`); proximity <15 m × 2 consecutive ticks (`navigation_config.dart:184,188`). `arrived` is a canonical state (`navigation_state_model.dart:44-48`) that freezes the pipeline (`navigation_controller.dart:441-442`) until the user taps Done/End. Deliberate design decision: navigation does **not** auto-terminate on arrival; an `ArrivalBanner` offers End. |
| 2 | Turn-by-turn instructions unexposed | **B — PARTIALLY FIXED** | Current segment's `instruction` is surfaced in the instruction strip (Phase 7 UI); segment index/total shown as a chip. Remaining gaps: `nextSegment` getter (`navigation_controller.dart:258-263`) has **zero consumers** (no "then" preview), and instruction content quality is still whatever the routers emit. |
| 3 | Multi-floor origin handling in exit legs | **C — STILL PRESENT** | `_selectExitPoi` docstring claims "closest to user" but after ground-floor preference it returns `candidates.first` — dataset order, no proximity scoring (`cross_building_router.dart:211-241`, return at `:230-241`). `_generateExitSegment` uses `exitPoi.floorNumber` as the ORIGIN floor (`:268-273`) instead of the user's actual floor, and `composeRoute` takes no user-floor parameter (`:49-54`) — there is no connector leg from the user's real position/floor to the exit floor. |
| 4 | Intermediate buildings unhandled | **C — STILL PRESENT** | No intermediate-building segmentation exists anywhere in the routing layer; routes are composed outdoor leg + single destination building only (verified across `cross_building_router.dart`; no symbol matches intermediate-building handling). |
| 5 | Held position computed but never rendered | **A — FIXED** | `heldPositionDuringTransition` (`navigation_controller.dart:290-291`) is consumed by the display layer (`lib/ui/utils/navigation_display.dart` `displayLocationFor`) which drives the user marker, camera target, and status-bar text during `floorTransition`. |
| 6 | Pause invisible (logic + UI) | **A — FIXED** | `paused` is canonical; while paused only GPS recovery is evaluated (`navigation_controller.dart:446-450`); resume restores the interrupted activity (`:1313-1324`). `pauseReason` is exposed (`:243`) and rendered by status bar + strip (Phase 7). Trigger remains the accuracy>100 m heuristic (`:1418-1424`). |
| 7 | Positioning stability output unused | **B — PARTIALLY FIXED** | Stability is now consumed internally: it weights arbitration confidence (`location_provider.dart:457`). However `PositionFix.confidence` has **zero consumers** lib-wide (grep: only `position_fix.dart` itself references it), and no widget reads `positioningStability`. End-to-end the signal is still dead-ended. |
| 8 | Partial-route guard missing | **C — STILL PRESENT** | `isFullyNavigable` never existed (grep: zero production matches; baseline cited docs at `navigation_route_model.dart:10-12` that describe a guard with no implementation). `startRoutePreview` only demands `hasRenderablePath` (`navigation_controller.dart:331-332`). An `isPartial` getter exists with zero consumers; `building_detail_card.dart` shows a textual warning only. |

## 5. Incorrect behavior (baseline items 9–14)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 9 | Premature indoor declaration | **A — FIXED** | Indoor activity is reached only via (a) the `ENTERING_BUILDING` dwell with identity-aware corroboration — a believed-Wi-Fi fix whose *confirmed scope* matches the destination building (`navigation_controller.dart:526-589`), or (b) the arbiter's own belief flip after 3 consecutive qualifying estimates (`:508-514`; `location_provider.dart:261-279`). Dwell times out after 20 s back to outdoor with a 15 s re-trigger cooldown (`:538-547`; `navigation_config.dart:194,201`). |
| 10 | Ground-floor assumption on building entry | **A — FIXED** | Preload cascade is route-derived first: Tier 1 = floor the route actually enters on (`_routeArrivalFloor`, `navigation_controller.dart:1212-1232`), Tier 2 = literal `'0'`, Tier 3 = numerically lowest floor (`:1178-1197`), all documented ROUTE CONTEXT ONLY. Actual entry into `ACTIVE_INDOOR` still requires corroborated Wi-Fi with matching confirmed scope (`:584-589`). `'0'` survives only as a RadioMap-residency seed, never as a claim about the user's floor. |
| 11 | Wrong-floor reroute origin | **C — STILL PRESENT** | `navigation_controller.dart:756`: `final currentFloor = _currentNavigatingFloor ?? '0';` — API reroutes are requested with the route-bookkeeping floor, which can diverge from the physical floor (mid-transition windows, manual floor taps). `_evidenceFloor()` (`:796-801`) exists and would be correct but is not used here. |
| 12 | Exit-detection paradox + clearSelection wipes route | **B — PARTIALLY FIXED** | Paradox fixed: GPS alone can never flip the source while Wi-Fi is believed (`location_provider.dart:474-480`); exit requires Wi-Fi lost + GPS accuracy ≤15 m + outside floorplan bounds + 3 consecutive ticks (`navigation_controller.dart:1005-1037`) then an `EXITING_BUILDING` dwell where Wi-Fi re-engagement or 20 s silence reverts indoors (`:550-571`). **Remaining half:** `_applyBuildingExitSideEffects` still calls `_spaceScope.clearSelection()` (`:1066`) → `space_provider.dart:452-472` → `_resetNavigationRouteState()` (`:1920-1925`) nulls the scope's route AND `_resetRadioMapState()` (`:1898-1905`) clears ALL RadioMap residency mid-session. The controller's private `_activeRoute` survives, so the session limps on with an unrendered route and no indoor positioning capability. |
| 13 | Transition timeout leaves wrong floor | **A — FIXED** | `_checkTransitionTimeout` aborts to `ACTIVE_INDOOR` keeping `_currentNavigatingFloor` unchanged and clearing expectation/hold state, recording an ABORTED transition event (`navigation_controller.dart:968-996`). |
| 14 | First-candidate exit POI | **C — STILL PRESENT** | Same root as item 3: `candidates.first` after ground-floor preference, no proximity scoring (`cross_building_router.dart:230-241`). |

## 6. Architectural problems (baseline items 15–19)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 15 | Single-slot native RadioMap | **A — FIXED** | Engine holds `residentMaps` as an access-ordered LRU keyed `buid|floor`, capacity `RESIDENT_MAP_LIMIT = 4` (`PositioningEngine.kt:36,43,71`); `loadRadioMapText` upserts and LRU-evicts (`:90,153-161`); targeted `removeRadioMap(buid,floor)` (`:106-113`); `clearRadioMap()` wipes all (`:117-122`). Dart side loads additively (`space_provider.dart:1655-1660`), evicts only the failing pair (`:1677,1701,1710`), and full-clears only on selection resets (`:1904`). Connector-proximity preload genuinely coexists: next-floor map is added while the current floor's map keeps serving. |
| 16 | Positioning scope driven by UI selection | **A — FIXED** | See §3. Zero matches for `setActiveIndoorFloor` / `_syncLocationProvider`; evidence-only arbiter; identity only via claim confirmation; entry corroboration identity-checked. |
| 17 | Two divergent route representations | **C — STILL PRESENT** | The controller holds a private `_activeRoute`; map rendering reads the *scope's* copy (`map_screen.dart:670,835`). Controller-side reroute results are adopted locally only (`navigation_controller.dart:741-743,768-770`) and never pushed back to the scope, so after a reroute the rendered polyline is the OLD route while deviation/tracking use the NEW one. Worse, any mid-session `selectFloor` wipes the scope copy (`space_provider.dart:499`), leaving a live session with nothing rendered. `_onSpaceProviderChanged` (`:487-499`) syncs one way only (scope→controller, non-null). |
| 18 | Controller↔provider coupling | **C — STILL PRESENT** (narrowed by design) | The controller still mutates the scope directly through `NavigationRouteScope` — `selectSpace` (`:1106-1108`), `selectFloor` (`:906-909,941-946,1194-1197`), `clearSelection` (`:1066`). The interface was narrowed and documented (`navigation_state_model.dart:179-196`) and the calls no longer carry physical claims, but the structural coupling the baseline flagged remains. |
| 19 | OSRM demo server over HTTP hard dependency | **C — STILL PRESENT** | `http://router.project-osrm.org/...` hardcoded at `cross_building_router.dart:793` and `:884`; no configuration injection. |

## 7. Positioning pipeline (baseline items 20–23)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 20 | No fusion/smoothing → position jumps | **B — PARTIALLY FIXED** | Added since baseline: entry hysteresis (3 qualifying estimates), exit hysteresis (3 bad cycles) + stale timer, and a 30 m same-scope outlier guard that HOLDS the previous fix instead of jumping (`location_provider.dart:283-343`; `navigation_config.dart:91,100,212`). Still exactly-one-source belief with hard flips between GPS↔Wi-Fi (doc admits "no numerical GPS/Wi-Fi fusion", `location_provider.dart:87-88`), so cross-source discontinuities remain possible. |
| 21 | Fabricated Wi-Fi accuracy (constant 3.0 m) | **A — FIXED** | Accuracy is derived from KNN evidence: clamp(max(`topKSpreadMeters`, `bestDistance`), 2..30 m) (`location_provider.dart:415-432`; `navigation_config.dart:109-112`); GPS confidence maps from reported accuracy (`:463-468`). The constant fabrication is gone. |
| 22 | Both radios always on; no duty cycling | **C — STILL PRESENT** | GPS stream runs continuously once tracking starts (`location_provider.dart:674-701`); Wi-Fi scanning runs whenever any map is resident (event-driven + fallback retrigger). No duty-cycling, motion gating, or screen-off policy anywhere in the pipeline. |
| 23 | Freshness window vs scan cadence mismatch | **B — PARTIALLY FIXED** | Localization is now event-driven — triggered by system scan results, with a 10 s fallback retrigger only when no results arrive (`WifiScanner.kt`, `FALLBACK_RETRIGGER_MS`). The stale timer is unchanged at 10 s (`navigation_config.dart:212`), so the worst-case mismatch is softened by design but the constant was not revisited. |

## 8. Floor detection (baseline items 24–26)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 24 | Floor identity == whichever radiomap occupies the slot | **B — PARTIALLY FIXED** | Every scan is localized against ALL resident maps; exactly one winner is dispatched, chosen by highest matchedAps then lowest bestDistance (`PositioningEngine.kt:179-185`; `KnnLocalizer.kt:44`). Floor labels still originate from load-time arguments (no absolute sensing), and Dart adds a 3-tick claim confirmation before identity is believed (`location_provider.dart:375-397`) — identity is now evidence-contested rather than slot-determined, but it is still only ever as good as the resident pool. |
| 25 | Connector arming depends on route geometry | **B — PARTIALLY FIXED** | An organic-drift path detects floor changes with NO route geometry: consistent divergent evidence (≥ `stabilityMinEstimates` = 3 ticks) in `ACTIVE_INDOOR` drives `_beginOrganicFloorTransition` (`navigation_controller.dart:829-876,915-926`). Connector-proximity preloading still requires `route.floorTransitionIndices` (`:810-826`) — and the router never emits floorTransition segments (they exist only in tests), so the early-preload arm is effectively dormant; the organic path is what carries floor changes in practice. |
| 26 | Manual floor change desyncs the controller | **C — STILL PRESENT** | Mid-session the bottom sheet still renders `BuildingDetailCard` regardless of navigation state (`map_bottom_sheet.dart:237-248`); tapping a floor row calls `selectFloor` (`building_detail_card.dart:569`) which resets the scope's navigation route (`space_provider.dart:499`) and swaps residency. The controller ignores scope floor changes entirely (its listener only adopts routes, `navigation_controller.dart:487-499`), so `_currentNavigatingFloor` and the rendered route silently diverge. |

## 9. Entrance/exit semantics (baseline items 27–29)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 27 | Entrances not boundaries — passing within 25 m claims indoor + reroutes | **B — PARTIALLY FIXED** | Trigger surface unchanged: nearest-entrance <25 m still fires (`navigation_controller.dart:1113-1148`; threshold `navigation_config.dart:16`). But the consequence is transformed: it opens a 20 s `ENTERING_BUILDING` corroboration dwell that reverts to outdoor on silence, with a 15 s re-trigger cooldown (`:1166-1204,538-547`) — no false indoor claim, no forced floor jump, no instant reroute. Residual: deviation checks still run during the dwell against the preloaded indoor polyline and can trigger a spurious reroute churn before the dwell expires. |
| 28 | Centroid fallback fires through walls | **B — PARTIALLY FIXED** | The 30 m center-distance fallback for buildings without entrance POIs is retained (`navigation_controller.dart:1150-1158`; `navigation_config.dart:19`), so pass-by false triggers persist — but as with item 27 they now cost a transient dwell, not a false indoor state. |
| 29 | No hysteresis/confirmation → boundary oscillation | **A — FIXED** | Both boundaries are now hysteretic: entry = proximity dwell + corroborated Wi-Fi + re-trigger cooldown; exit = 3 accumulated qualifying outdoor ticks + `EXITING_BUILDING` dwell where Wi-Fi re-engagement or timeout reverts indoors (`navigation_controller.dart:550-571,1005-1037`); the arbiter mode itself flips only after multi-tick streaks (`location_provider.dart:261-311`). |

## 10. Routing quality (baseline items 30–33)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 30 | Straight-line fallbacks indistinguishable from real routes | **B — PARTIALLY FIXED** | Three fallback sites now stamp `RouteSegment.fallback = true` (verified in `cross_building_router.dart`). Unflagged remain: centroid connector fallbacks, connector-chain last resort, and all legacy `.hybrid` construction paths (5 callers, e.g. `space_provider.dart:993,1544`). Decisively: **zero production consumers read the flag**, so users still cannot tell today. |
| 31 | Connector "hops" cut through walls | **C — STILL PRESENT** | Connectors are still straight segments between POIs with no wall-awareness or waypoint shaping (same generation code as baseline; no corridor graph involvement for these legs). |
| 32 | Deviation metric floor-scoped; vertical drift invisible | **B — PARTIALLY FIXED** | The metric is unchanged — perpendicular distance against `polylinePointsForFloor(_currentNavigatingFloor)` only (`navigation_controller.dart:653-657`). Practical gap largely closed by organic floor-drift resync within ~3 ticks and reroute suppression during `FLOOR_TRANSITION` (`:624`); a short divergence window remains between drift onset and confirmation. |
| 33 | Reroute retry storm | **A — FIXED** | Single-flight via `REROUTING` state (`:692-706`), 15 s cooldown between triggers (`:627-630`; `navigation_config.dart:38`), custom KMZ graph attempted first (`:709-753`), API attempts bounded at 3 with 1 s/2 s/4 s exponential backoff (`:757-779`). Persistent genuine deviation still legitimately re-triggers after cooldown — intended behavior, not a storm. |

## 11. UI / state exposure (baseline items 34–37)

| # | Issue | Status | Current-code evidence |
|---|-------|--------|-----------------------|
| 34 | Rich outputs computed but never exposed | **B — PARTIALLY FIXED** | Exposed (Phase 7): current segment + instruction, segment index/total, pause reason, held position during transitions (marker/camera/status), arrival banner, sub-state icon, dedicated canonical-state labels. Still unexposed with **zero consumers**: `customRouteProgress` percentage (`navigation_controller.dart:247`), `nextSegment` (`:258`), `floorTransitionEvents` history (`:296`), `PositionFix.confidence`, `positioningStability`, and `RouteSegment.fallback` visual differentiation. |
| 35 | Preview mode vestigial | **C — STILL PRESENT** | The only `startRoutePreview` caller immediately chains `startActiveNavigation` back-to-back (`map_bottom_sheet.dart:209-217`), so `routePreview` exists for milliseconds. A preview-only affordance branch exists in `PoiDetailCard` (`hasActiveRoute && !isNavigating` → Start Directions / Clear) but is unreachable as a stable state via that path; building cards populate the scope route without ever starting the controller (`building_detail_card.dart:310-311,955-956`). |
| 36 | Tab switch kills navigation | **C — STILL PRESENT** | `main_shell.dart:35-47` `_stopNavigationOnTabLeave()` calls `endNavigation()` + `clearNavigationRoute()` when the Map tab loses focus (fired at `:79-81`, gated on `isActive || isPreview`). Switching tabs mid-session destroys the session. |
| 37 | Status bar conflates orthogonal concepts | **B — PARTIALLY FIXED** | Concepts are now split across dedicated surfaces (canonical state label + sub-state icon + source/floor/blackout text + instruction strip + arrival banner). Residual conflation: the single `positioningStatus` string still merges source, floor, and transition messaging (`navigation_controller.dart:269-286`), and stability/confidence remain invisible. |

---

## 12. Baseline §11 questions — re-answered against current code

1. **Does selecting a destination building/floor still make positioning treat
   it as the user's physical location?** — **No.** Evidence-only arbiter;
   identity null until a 3-tick confirmed claim; entry corroboration compares
   confirmed scope to the destination (§3 above). Selection only shapes which
   RadioMaps are available to be matched.
2. **Do building exits handle multi-floor origins correctly?** — **No.**
   Exit-leg origin floor is the exit POI's floor, not the user's
   (`cross_building_router.dart:268-273`); exit POI is dataset-order
   `candidates.first` (`:230-241`); reroute requests use route-bookkeeping
   floor (`navigation_controller.dart:756`).
3. **Does arrival detection now exist?** — **Yes** — evidence-gated
   (`_checkArrival`, identity-checked indoors, 2-tick confirmation). It does
   not auto-terminate the session; termination stays a user action by design.
4. **Can a tab switch still destroy an active navigation session?** — **Yes.**
   `main_shell.dart:35-47,79-81`.
5. **Is the native RadioMap still single-slot?** — **No.** LRU-4 multi-map
   residency with per-scan fan-out and single-winner dispatch
   (`PositioningEngine.kt:36-185`).
6. **Are straight-line fallbacks flagged and surfaced?** — **Partially.**
   Three sites stamp `fallback=true`, but other fallback paths are unflagged
   and nothing consumes the flag, so users see no difference.

---

## 13. Priority ranking of remaining work

**P0 — session-destroying leaks (highest user impact)**
- #36: tab switch ends navigation (`main_shell.dart:35-47`).
- #12 (remaining half): confirmed exit wipes route + all RadioMap residency
  mid-session via `clearSelection` (`navigation_controller.dart:1066` →
  `space_provider.dart:452-472,1920-1925,1898-1905`).
- #26: manual floor tap during navigation desyncs controller and unrenders
  the route (`map_bottom_sheet.dart:237-248`; `building_detail_card.dart:569`;
  `space_provider.dart:499`; controller ignores floor changes).
- #17: reroute results never reach the rendering path
  (`navigation_controller.dart:741-743,768-770` vs `map_screen.dart:670,835`).

**P1 — routing correctness**
- #3/#14: exit-POI selection ignores user position/floor
  (`cross_building_router.dart:211-273`).
- #11: reroute origin floor should come from `_evidenceFloor()`
  (`navigation_controller.dart:756` vs `:796-801`).
- #8: partial-route guard absent at `startRoutePreview`
  (`navigation_controller.dart:331-332`).
- #31: connector legs cut walls; #4: intermediate buildings unsupported.

**P2 — positioning polish & honesty**
- #22: no duty cycling (battery).
- #30: consume `RouteSegment.fallback` in UI + flag remaining sites.
- #7/#34 (remainders): give `confidence`, `stability`, `customRouteProgress`,
  `nextSegment`, `floorTransitionEvents` real consumers or remove them.
- #32 (residual window), #2 (`nextSegment` preview).

**P3 — hygiene**
- #18: decouple controller→scope mutations behind an command interface.
- #19: inject OSRM base URL via config; move off demo-over-HTTP.
- #23: retune `indoorStaleTimerSeconds` alongside event-driven cadence.
- #27/#28 residuals: suppress deviation checks inside entry dwell; gate
  centroid fallback behind entrance-POI absence AND route intent.
- #35: decide preview's fate (make it reachable or delete the phase).
- #37 (remainder): split `positioningStatus` into orthogonal fields.

---

## 14. What actually changed since the baseline was written

Systems that did not exist at baseline and now carry most of the fix mass:

- `LocationProvider` unified arbiter (`_ArbiterMode`, claim/confirm streaks,
  outlier hold, derived accuracy, stale timer) replacing per-source fields.
- `PositionFix` as the single canonical position object with evidence-gated
  identity.
- Canonical 10-state `NavigationState` machine + snapshot + allowed-edge
  table (`navigation_state_model.dart`).
- First-class floor transitions: expected/organic paths, blackout +
  held-position + suppression, timeouts, bounded event history.
- Arrival detection with identity gating.
- Native multi-map LRU residency (capacity 4) with per-scan winner dispatch.
- Phase 7 UI exposure layer: status bar, instruction strip, arrival banner,
  display utils consuming held positions and pause reasons.

---

## 15. Final counts

Out of 37 baseline problems: **11 FIXED / 13 PARTIALLY FIXED / 13 STILL
PRESENT / 0 NO LONGER APPLICABLE / 0 CANNOT BE VERIFIED.**

Verdict on the baseline: **stale as a system description, still valid as a
defect ledger.** Its top-three architectural indictments (selection-driven
scope, single-slot RadioMap, boundary flapping) describe solved problems in
current code; its routing-internals and session-lifecycle families describe
problems that are still open today.
