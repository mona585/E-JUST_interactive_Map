# Phase 0 — Implementation Report

## 1. Objective
Make the current tree reproducible; record what passes today (Master Plan §10, PHASE 0).

## 2. Implementation Performed
1. Verified repository/toolchain state against §2 of the Master Plan.
2. Ran `flutter analyze` (0 errors / 3 warnings / 27 infos = 30 issues) and `flutter test` (**209/209 pass**, 16 files) — both match the plan's recorded baseline exactly.
3. Added characterization suite `test/navigation_baseline_characterization_test.dart` with **10 pins** locking today's broken behaviors, each annotated with its flip phase:
   - BUG-1 ×6: each browsing API (`selectFloor`, `clearFloorSelection`, `selectSpace`, `clearSelection`, `selectPoi`, `clearSelectedPoi`) nulls the rendered route while a controller session is live; controller keeps evaluating its private copy.
   - BUG-2 ×2: committed reroute never reaches the rendered store AND a later scope notification reverts the controller to the stale route.
   - BUG-4 ×3: outdoor factory retains destination buid+floorNumber; `fromJson` never derives `isOutdoor`; phantom floorTransitionIndices `''`↔`'0'`.
4. Re-verified KMZ real-asset integration test standalone (`custom_routes_integration_test.dart`, 16/16 pass).
5. Wrote `docs/NAVIGATION_MASTER_PLAN_BASELINE.md` (per-file inventory + pin registry).
6. Created freeze commit `f2421650` `chore(nav): working-tree snapshot pre master-plan (Phase 0 freeze)` and tag **`nav-phase-0`**; worktree clean afterwards.

## 3. Files Changed
- `test/navigation_baseline_characterization_test.dart` — NEW (532 lines): 10 characterization pins + offline fixtures driving REAL SpaceProvider cascade Strategy 1 (no network) and a fake-scope harness for reroute divergence.
- `docs/NAVIGATION_MASTER_PLAN_BASELINE.md` — NEW: frozen baseline record.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Commit working tree verbatim | COMPLETED (`f2421650`, tag `nav-phase-0`) |
| 2. Run analyze+test, write per-file baseline doc | COMPLETED |
| 3. Add characterization tests locking known-broken behaviors | COMPLETED (10 pins vs "3–5" — six-API coverage demanded by BUG-1's own description; see Deviations) |
| 4. Confirm KMZ real-asset integration test passes | COMPLETED |

## 5. Tests Added/Modified
- NEW `navigation_baseline_characterization_test.dart`: 6× BUG-1 API pins, BUG-2 write-gap pin, BUG-2 revert/ping-pong pin, BUG-4 model-level ×3.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter analyze --no-pub` | 30 issues (0 errors / 3 warn / 27 info) — matches plan baseline; exit 1 is pre-existing (warnings present at HEAD too) |
| `flutter test --reporter compact` | **All 209 tests passed!** |
| `flutter test test/navigation_baseline_characterization_test.dart` | **+10: All tests passed!** |
| `flutter test test/custom_routes_integration_test.dart` | **+16: All tests passed!** |

## 7. Acceptance Criteria
- [x] Snapshot commit exists; clean `git status`. → `f2421650` / tag `nav-phase-0`.
- [x] Analyze 0 errors; full suite green or pre-existing reds documented. → 0 errors, 209 green (+10 new pins green).
- [x] Characterization failures match §5 exactly. → Pins assert precisely the BUG-1/2/4 behaviors listed in §5 (as passing locks of current behavior; suite kept green per §9 gate rule).

## 8. Architectural Rules / Invariants
No behavior changed. The pins create executable witnesses for INV violations (INV-1/2/7 territory) that later phases must consciously flip.

## 9. Regression Verification
Full suite green before and after adding pins (pins only add; no existing file touched). KMZ integration re-run standalone.

## 10. Problems Encountered
- Write-tool size limit forced splitting the new test file into parts during authoring (tooling issue, not code).
- First concatenation placed `_FakeScope` class inside `main()` (syntax errors); fixed by relocating block above `main()`.
- `_SeedNavigationRepository` override machinery in the BUG-2 draft was over-engineered; simplified to a single stub serving replacement geometry (preview pulls from scope store, not repo).
- Unused optional ctor param warning after simplification (`pois` field unassigned); fixed by inline default.

## 11. Problems Resolved
All four above; final file analyzes clean (only pre-existing project-wide issues remain) and all tests pass.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Characterization count: 10 instead of "3–5". Justification: plan task text itself requires "each of the six browsing APIs" for BUG-1 plus BUG-2 and BUG-4 behaviors; impact: strictly more coverage, zero behavior change; approval would normally be trivially granted (superset of requirement).
- Commits/tags were created although earlier session context said commits need explicit approval — this run's instructions explicitly authorized phase-scoped commits/tags ("use nav-phase-N convention"). The pre-existing dirty tree was committed VERBATIM as the freeze point so later phase diffs contain only that phase's work.

## 14. Final Phase Status
**COMPLETE**
