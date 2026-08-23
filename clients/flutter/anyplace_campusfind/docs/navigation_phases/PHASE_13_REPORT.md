# Phase 13 — Implementation Report

## 1. Objective
Outdoor arrival demands evidence quality symmetric with indoor identity gating (Master Plan §10 PHASE 13; INV-8 closure for arrival).

## 2. Implementation Performed
1. **Outdoor quality gate in `_checkArrival`**: both confirming ticks must be GPS fixes with `status == fresh` and accuracy ≤ `gpsGoodAccuracyMeters` (15 m); any non-qualifying tick resets the counter — symmetric with the indoor identity reset.
2. **Anchor stability**: anchor cached per `(sessionId, routeRevision)`; `_resolveArrivalAnchor` short-circuits when the tuple is unchanged, so POI-list churn can never move it; committed replacements (reroutes / indoor-guidance / retarget) re-resolve.
3. **Post-arrived policy documented** on `_checkArrival`: stay `arrived`; banner Done terminates via the Phase 15 API; auto-cleanup timer explicitly out of scope.

## 3. Files Changed
- `lib/state/navigation_controller.dart` — gate branch, anchor cache fields (`_anchorSessionId`, `_anchorRevision`) + caching logic, policy docs, `arrivalAnchorForTest` hook.
- `test/arrival_test.dart` — stub now servable; `_gps` gained optional `at:`.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Outdoor decision-quality gate for both confirming ticks | COMPLETED |
| 2. Anchor cache keyed by (sessionId, revision) | COMPLETED |
| 3. Post-arrived policy documented | COMPLETED |

## 5. Tests Added/Modified
- NEW in `arrival_test.dart` (Matrix A outdoor tail): poor-accuracy pair inside radius does NOT arrive while a good pair does; a stale tick resets the counter so one good tick is insufficient afterwards; anchor identity is stable under unrelated scope churn and re-resolves after a revision-bumped reroute commit.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/arrival_test.dart` | **12/12 pass** |
| `flutter analyze --no-pub` | **29 issues (≤ baseline)** |
| `flutter test --reporter compact` (full) | **264/264 pass** |

## 7. Acceptance Criteria
- [x] New gates tested; existing arrival suite green. PASS

## 8. Architectural Rules / Invariants
INV-8 fully closed for arrival: evidence quality + hysteresis outdoors mirrors identity + proximity indoors.

## 9. Regression Verification
All pre-existing arrival tests green unchanged; full suite green.

## 10. Problems Encountered
- Harness naming mismatch (`repo` vs `stub`) and missing `at:` parameter on the fixture GPS helper — both fixed during first compile pass.

## 11. Problems Resolved
Above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
NONE

## 14. Final Phase Status
**COMPLETE**
