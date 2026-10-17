# Navigation Master Plan — RACE AUDIT (R1–R12)

Phase 14 deliverable. Every race from the Master Plan §3 matrix is mapped to
its guarding mechanism, the exact code location, and the automated test that
proves it. "Battery" refers to `test/race_battery_test.dart`.

| Race | Scenario | Guard mechanism | Guard location | Proving test | Result |
|---|---|---|---|---|---|
| R1 | Route request A finishes after request B | SpaceProvider per-resource `_navigationRouteRequestId` discards stale cascade responses; NC reroute loop fenced by `(sessionId, revision)` | SP `requestRouteToSelectedPoi`/`requestRouteToBuilding` requestId checks; NC `_triggerReroute` post-await `_isCurrent` | Battery R1/R6; `route_store_test` cooldown+single-write; `session_identity_test` superseded-revision case | CLOSED |
| R2 | Reroute finishes after End | Same NC fence — dead session cannot commit or restore | NC `_triggerReroute` all three discard points + backoff recheck | `session_identity_test`: late ended-session result mutates nothing; Battery R2 (End mid-backoff) | CLOSED |
| R3 | Destination changes during routing | Retarget protocol installs a NEW session id BEFORE content moves; in-flight old results fail identity fence | NC `retargetDestination` step 1/4; `_isCurrent` | `retarget_test` mid-outdoor & mid-rerouting cases | CLOSED |
| R4 | Floor changes during routing | Floor is browsing context, not route identity: commits are destination-fenced; navigating-floor bookkeeping recomputed on commit (`_resolveArrivalAnchor`, Phase 9 exhaustion resets) | NC `_triggerReroute` fence; `_completeFloorTransition`; Phase 6 nullable-floor wire format removes floor from outdoor requests entirely | Battery R4; `rerouting_correctness_test` wire-format (floors==[null]) | CLOSED |
| R5 | Building changes during routing | Same as R4: outdoor reroutes are building-agnostic (coordinate→destination); indoor legs only run under confirmed scope identity from the arbiter (LP) which has its own 3-run atomic switch | LP arbiter (protected); NC fence as above | arbitration suite (untouched) + Battery R1/R6 | CLOSED |
| R6 | Reroute finishes after destination change | Identical to R3 fence: captured `destinationPuid` belongs to dead session → discarded silently with activity restore | NC `_triggerReroute` discard branches | `retarget_test` test 2 (old gated result after retarget never overwrites B) | CLOSED |
| R7 | Positioning belief flips during routing | Accepted by design: routing targets destination, not mode; mode transitions continue via evidence pipeline; overlay restore uses previous-activity edge | NSM dynamic edges; `_triggerReroute` origin capture | `navigation_state_machine_test` rerouting-overlay keeps fixes untouched | CLOSED (by design) |
| R8 | End while initial cascade running | SP request-id invalidation on clear/reset + preview guard requiring renderable store route | SP `clearNavigationRoute` id bump; `startRoutePreview` guards | `route_store_test` preview-seed test; characterization idle-parity pins | CLOSED |
| R9 | External replacement of active route mid-session | Structurally eliminated: ONE store exists; external writers are browsing APIs which are INV-4-guarded no-ops on navigation fields during sessions | Phase 2 delegation getter + adopt-only writes; Phase 3 guards | grep audit (zero second-cache writes); `browsing_neutrality_test` | CLOSED (structural) |
| R10 | Radiomap load completes after leaving floor/building | SP radiomap request-id + selection-recheck before native load; targeted eviction only on failure (Phase 11) | SP loader requestId checks (~L1810–1905) | existing acquisition suite (§4 item 8) + `radiomap_lifecycle_test` failure-eviction case | CLOSED |
| R11 | Old async callback after NEW session starts | Phase 1 session fencing applied to EVERY continuation class in NC (reroute ×3 points, guidance fetch, preload completion, retarget seeding) | `_isCurrent` call sites (grep: 5 sites) | `session_identity_test`; `handoff_guidance_test` latch/fence cases; Battery R11 | CLOSED |
| R12 | Tab/lifecycle changes during async work | Tab-leave policy kills the session deliberately via canonical teardown (`main_shell` hook); dispose-safety proven over the real pipeline; lifecycle resume re-centers without state mutation | MS `_onTabChanged`; LP boundary tests; M lifecycle observer | `position_estimate_boundary_test` late-events-inert; Battery stress loop | CLOSED |

## Leftover implementations completed this phase

1. **Cancellable backoff** — delay-then-recheck already present since Phase 1
   (`await Future.delayed(...)` followed by `_isCurrent` before continuing);
   verified and referenced by Battery R2.
2. **Preload completion validation** — `_preLoadBuildingData` performs its
   effect synchronously behind a captured-identity check (Phase 1). There is
   no pending future across awaits to gate further; satisfied by construction.
3. **Reentrancy assertion** — every controller write now funnels through
   `_adoptNavigatedRoute()` whose debug assert fails fast on any reentrant
   adoption loop (NC L163–171).

## Stress verification

`race_battery_test.dart` drives 50 rapid preview→active→End cycles plus a
post-cycle live fix, asserting clean state transitions, monotonic session ids,
no leaked timers at end-of-test, and continued responsiveness afterwards.
