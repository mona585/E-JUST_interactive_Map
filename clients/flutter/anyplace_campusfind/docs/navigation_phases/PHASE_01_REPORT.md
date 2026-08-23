# Phase 1 — Implementation Report

## 1. Objective
Every navigation run gets an explicit identity; every async result proves membership before committing (Master Plan §10 PHASE 1; RC2; INV-3 core).

## 2. Implementation Performed
1. **NSM**: added `NavigationSession` value class — `sessionId` (monotonic counter), `destinationPuid`, `destinationSpace`, `destinationFloorNumber`, mutable `routeRevision`.
2. **NC `startRoutePreview`**: creates the session; revision bumped to 1 on seed; **deleted the unused `destinationFloorNumber` parameter (BUG-15c)** — session floor now derived from the destination POI when resolvable in the scope.
3. **NC destination fields → delegates**: `_destinationPuid`/`_destinationSpace` fields removed; public getters delegate to the session; all internal reads migrated (`snapshot`, `_entryCorroborated`, `checkBuildingApproach`, `_checkFallbackEntranceProximity`, `_resolveArrivalAnchor`, `_triggerReroute`).
4. **Fencing helper** `_isCurrent({sessionId, revision})`; applied to: KMZ reroute commit, API-reroute post-await commit, reroute catch-branch, backoff continuation, building-preload completion, entrance-preload floor selection.
5. **Stale-discard restore**: a superseded-revision discard while the session is still live restores the interrupted activity instead of stranding `rerouting`.
6. **BUG-13 clock fix**: cooldown check and stamp use `_now()`; `_lastRerouteTime = _now()` moved AFTER the successful `_transition(rerouting)` — rejected/guarded entries can no longer burn the cooldown.
7. **Logs**: `[NAV] SESSION_START sid=… dst=… rev=…` / `[NAV] SESSION_END sid=…`.
8. **Test hooks** (`@visibleForTesting`): `sessionForTest`, `lastRerouteTimeForTest`, `debugTriggerReroute()`, `debugBumpRouteRevision()`.

## 3. Files Changed
- `lib/state/navigation_state_model.dart` — NavigationSession class (+ctor lint fix).
- `lib/state/navigation_controller.dart` — session wiring, fencing, clock, logs, hooks (~120 lines touched).
- `lib/ui/widgets/map_bottom_sheet.dart` — call-site: removed deleted parameter.
- Tests updated for new signature: `arrival_test.dart`, `floor_transition_test.dart`(×2), `navigation_state_machine_test.dart`(×3 + journey-script session assertions), `navigation_ui_test.dart`, `navigation_baseline_characterization_test.dart`(×2).

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Implement class + wiring | COMPLETED |
| 2. Replace `_destinationPuid!` reuse after awaits with validated reads | COMPLETED |
| 3. Injectable clock + move cooldown stamp after transition (BUG-13) | COMPLETED |
| 4. Emit SESSION_START/SESSION_END tagged logs | COMPLETED |
| Journey-script test session assertions | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/session_identity_test.dart` (5 tests): preview-creates/end-destroys + POI-derived floor; stable id across states & fresh id per run; late ended-session result inert; revision-bumped result discarded with activity restore; guarded reroute consumes no cooldown / real one does + cooldown suppression.
- `navigation_state_machine_test.dart` scripted journey: sessionId null-before, constant-through, revision==1 at seed, destroyed-at-end assertions.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/session_identity_test.dart …characterization… …state_machine…` | All 39 pass |
| `flutter analyze --no-pub` | 30 issues (= baseline parity) |
| `flutter test --reporter compact` (full) | **224/224 pass** |

## 7. Acceptance Criteria
- [x] Grep audit: NC contains exactly two `await` sites (`getRouteFromCoordinates`, backoff delay) — both fenced by `_isCurrent` before any mutation. PASS
- [x] R1/R2-style races provably inert beyond previous `isSessionLive`: tests 4–5 prove dead-session results commit nothing even when the repo delivers valid geometry. PASS
- [x] Full suite green (224). PASS

## 8. Architectural Rules / Invariants
INV-3 core established ("no async continuation may mutate navigation state unless captured identity equals current"). Destination identity now has exactly one home (the session) — groundwork for INV-1/2 in Phase 2.

## 9. Regression Verification
Full suite green including state-machine/arrival/floor-transition suites; characterization pins unaffected.

## 10. Problems Encountered
- Compile errors from missed internal `_destinationSpace`/`_destinationPuid` references (6 sites) after field removal.
- One wrong-site fix attempt (`_isOutsideBuilding`) immediately caught and reverted — original semantics preserved.
- Test-side: ctor name mismatch (`Scope` vs `_Scope`); `same(_replacement())` compared distinct instances.
- Plan's guard sketch used `identical(sessionId, sessionId)` — unsafe for non-interned strings; replaced with `==`.

## 11. Problems Resolved
All of the above; suite green, analyzer at baseline.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Guard uses `==` not `identical` for sessionId comparison (correctness; identical would false-negative on equal strings).
- Stale-discard paths also perform an activity-restore transition when the session is still live (plan silent on superseded-but-live case; prevents stranding `rerouting`). Impact: strictly safer; no approval concern.
- Added four `@visibleForTesting` hooks (plan's tests are unimplementable without them).

## 14. Final Phase Status
**COMPLETE**
