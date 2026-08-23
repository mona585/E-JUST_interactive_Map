# Phase 6 — Implementation Report

## 1. Objective
Reroutes fire on persistent evidence with validated context and commit atomically to the visible store (Master Plan §10 PHASE 6; BUG-5, BUG-12; INV-6/INV-8 for rerouting).

## 2. Implementation Performed
1. **Tick order fixed (BUG-5b)**: `_checkGpsLoss` now runs BEFORE `_checkDeviationAndReroute`; a pause short-circuits the remainder of the tick, so garbage can never reroute before the quality gate sees it.
2. **Hysteresis**: `rerouteDeviationConfirmTicks=2` — both polyline-deviation and KMZ off-route evidence require two consecutive qualifying ticks; streaks reset when back on-route or on non-qualifying fixes.
3. **Decision-quality gate**: deviation evaluation skips (and resets streaks) unless the current fix is `fresh` with accuracy ≤ poor band (Phase 5 flags).
4. **BUG-12 closure**: `NavigationRepository.getRouteFromCoordinates(floorNumber:)` and the API client are now nullable; outdoor reroutes send NULL (omitted from payload); indoor legs send the confirmed navigating floor; the `'0'` fabrication is gone.
5. **Failure visibility**: transient `rerouteFailed` flag set when no attempt commits; old route persists; status bar shows "Recalculation failed — retrying soon"; cleared on next success / End / preview / retarget.
6. **Magic numbers → config**: `rerouteKmzSnapThreshold`, `segmentAdvanceThresholdMeters`.
7. Snapshot timestamps moved to `_now()` (remaining BUG-13 leak).

## 3. Files Changed
- `lib/config/navigation_config.dart` — 3 new constants.
- `lib/state/navigation_controller.dart` — tick reorder, hysteresis fields/logic, quality gate, nullable-floor origin logic, commit tracking + failure flag + resets, snapshot clock, config literals.
- `lib/data/repositories/navigation_repository.dart`, `lib/data/datasources/anyplace_api_client.dart` — nullable floor plumbing (payload omits empty floor).
- `lib/ui/utils/navigation_display.dart` — failed-recalculation label.
- Test repo stubs ×10 — nullable signature.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Tick order | COMPLETED |
| 2. Hysteresis (both evidence paths) | COMPLETED |
| 3. Context validation pre-fetch (nullable floor + Phase-1 fencing) | COMPLETED |
| 4. Atomic commit + failure flag | COMPLETED |
| 5. Clock conversion | COMPLETED |
| 6. Magic numbers to config | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/rerouting_correctness_test.dart` (3): Matrix F trigger hysteresis; wire-format audit (floors==[null], destinations recorded, cooldown respected on injected clock); failure keeps old route + visible label + clears on success/End.
- FLIPPED single-tick fixtures to two-tick triggers: characterization BUG-2 flip, route_store ×2 tests, session_identity ×3 tests, state_machine rerouting-overlay test and end-mid-reroute test, retarget_test trigger sites (×4).

## 6. Tests Executed
| Command | Result |
|---|---|
| Targeted rerouting suite | 3/3 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **240/240 pass** |

## 7. Acceptance Criteria
- [x] Hysteresis + ordering tests green. PASS
- [x] Wire-format audit: backend never receives `'0'` during activeOutdoor reroutes — grep shows zero `_currentNavigatingFloor ?? '0'` remnants; test asserts floors==[null]. PASS
- [x] Suite green (240). PASS

## 8. Architectural Rules / Invariants
INV-8 decision semantics complete for rerouting (quality-gated input + N≥2 hysteresis); INV-6 failure branch (persist old route) is now observable to users.

## 9. Regression Verification
Full 240-test suite green; arrival/floor suites unaffected (their ticks are on-route/good-band).

## 10. Problems Encountered
- PowerShell batch line-duplication for tick pairs mis-fired on overlapping text (commented variant matched plain substring) leaving duplicated/stray fixture lines in three files — repaired by hand via Edit with exact context.
- Missing ternary semicolon after config-literal replacement (compile error caught immediately).
- New test initially lacked PoiModel/display imports and served no stub route (backoff left overlay open).
- state_machine mid-reroute fixture needed second tick (expected flip).

## 11. Problems Resolved
All above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Poor-band threshold used as the decision-quality ceiling (`accuracy > gpsPoorAccuracyMeters` skips deviation) — plan says "below decision quality" without naming the constant; poor band is the natural boundary already defined by Phase 5.

## 14. Final Phase Status
**COMPLETE**
