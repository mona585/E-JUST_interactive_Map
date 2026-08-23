# Phase 2 — Implementation Report

## 1. Objective
One route store; rendered == evaluated by construction; reroutes visible atomically (Master Plan §10 PHASE 2; RC1; BUG-1 divergence half; BUG-2; INV-1/2/6).

## 2. Implementation Performed
1. **NSM**: `NavigationRouteScope` extended with `adoptNavigatedRoute(route)` and `clearNavigationRoute()` (the latter needed so the controller can perform canonical teardown through the interface — see Deviations).
2. **SP**: `adoptNavigatedRoute` implemented — single store write, status→ready, error cleared, ONE `notifyListeners()`; touches no browsing state and no destination bookkeeping. Existing public `clearNavigationRoute` now annotated `@override`.
3. **NC**: private `_activeRoute` FIELD deleted, replaced by delegating getter `_activeRoute => _spaceScope.activeNavigationRoute` (all ~20 internal read sites compile unchanged). Blind adoption listener `_onSpaceProviderChanged` deleted together with its registration/deregistration.
4. **Reroute commits** (KMZ + API branches): fenced identity → `_spaceScope.adoptNavigatedRoute(newRoute)` → `_session.routeRevision++` → `_resolveArrivalAnchor()` inside one observer notification (INV-6).
5. **Preview seeding** records revision **0** and performs NO store write (seeding reads the cascade-produced route already in the store).
6. **`endNavigation`** additionally calls `_spaceScope.clearNavigationRoute()` (INV-10 groundwork).

## 3. Files Changed
- `lib/state/navigation_state_model.dart` — interface additions.
- `lib/state/space_provider.dart` — `adoptNavigatedRoute` implementation + `@override` on clear.
- `lib/state/navigation_controller.dart` — field→getter, listener removal, write-through commits, seed rev 0, teardown store-clear.
- Test fakes implementing the scope updated in: `navigation_state_machine_test.dart`, `arrival_test.dart`, `floor_transition_test.dart`, `navigation_ui_test.dart`, `session_identity_test.dart`, `navigation_baseline_characterization_test.dart`.
- Harness re-seed fixes after End (store now cleared by teardown): `arrival_test.dart` (session-hygiene test), `session_identity_test.dart` (`startOutdoor`).

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Interface + implementation + delegation | COMPLETED |
| 2. Remove adoption listener body; drop registration | COMPLETED |
| 3. Rewire both reroute commits + preview seed | COMPLETED |
| 4. Grep audit zero second-cache writes | COMPLETED (see §7) |
| 5. Delete dead adoption comment block | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/route_store_test.dart` (3): write-through (store==evaluation==replacement; adoptCalls==1; notificationsDuringAdopt==1; reentrancy flag false; revision 0→1 exactly once; cooldown prevents double-write), no-ping-pong under unrelated scope notifies, preview-seed-rev-0-without-store-write + teardown clears store.
- FLIPPED `navigation_baseline_characterization_test.dart`: BUG-2 pin → corrected behavior (store receives reroute; notification cannot revert); BUG-1 six pins → single-store assertion added while keeping the store-nulling half (flips fully in Phase 3).
- UPDATED revision expectations to 0-at-seed: `session_identity_test.dart`, journey-script in `navigation_state_machine_test.dart`.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/route_store_test.dart …` targeted iterations | pass after fixes |
| `flutter test --reporter compact` (full) | **227/227 pass** |
| `flutter analyze --no-pub` | **30 issues = exact baseline parity** |

## 7. Acceptance Criteria
- [x] Exactly one route field exists: grep shows NC has ZERO writes (getter L65 only); SP writes are confined to the idle cascade + `adoptNavigatedRoute` + resets. PASS
- [x] After a committed reroute, provider-read route == evaluation route: asserted with `same()` in route_store tests and the flipped characterization pin. PASS
- [x] Guided floor transition interim check: full fix lands Phase 3 per plan; verified no NEW regressions (full suite green; floor-transition suite green with store-nulling pins still holding). PASS (interim)
- [x] Suite green (227) + analyzer parity. PASS

## 8. Architectural Rules / Invariants
INV-1 (single store), INV-2 (visible==evaluated by construction), INV-6 (atomic replacement: adopt+revision+anchor inside one notify) all established and test-pinned.

## 9. Regression Verification
Full 227-test suite green, including state machine, arrival, floor-transition, UI-projection suites; KMZ suites untouched.

## 10. Problems Encountered
- Full-run failures after targeted passes: two harnesses re-previewed WITHOUT re-seeding the store — canonical teardown now clears it, so the second preview was correctly rejected. Fixed by explicit re-seed in those tests (mirrors production flow).
- `List<dynamic> pois` type mismatch and missing `PoiModel` import in new test file.
- Recording fake's inline `expect()` inside `adoptNavigatedRoute` raised a guarded-function conflict that NC's reroute catch swallowed ("Reroute attempt 0 failed") — replaced with a recorded `reentrantAdoptObserved` flag asserted from the test body.
- New analyzer info for missing `@override` on SP.clearNavigationRoute → fixed (back to 30).

## 11. Problems Resolved
All of the above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- `NavigationRouteScope` gained `clearNavigationRoute()` beyond the plan's listed addition: required for plan item 6 itself (controller must call the teardown through the interface without a concrete-type cast). Impact: additive, implemented by SP anyway.
- Preview seed records revision **0**, superseding Phase 1's "increment on preview seed" (=1): Phase 2 item 5 explicitly specifies 0 and refines revisions to count committed replacements only. Two Phase-1 assertions updated accordingly (expected flip, documented).
- BUG-1 pins not fully removed yet: plan acceptance #3 explicitly defers the store-nulling half to Phase 3; pins now additionally assert the killed divergence half.

## 14. Final Phase Status
**COMPLETE**
