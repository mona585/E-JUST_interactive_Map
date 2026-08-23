# Phase 8 — Implementation Report

## 1. Objective
When entry corroboration confirms ACTIVE_INDOOR, guidance geometry becomes genuinely indoor (Master Plan §10 PHASE 8; BUG-7 closure).

## 2. Implementation Performed
1. **`_ensureIndoorGuidance()`** on NC, invoked at every INTO-`activeIndoor` transition: dwell confirmation, wifi-believed `startActiveNavigation`, and `_completeFloorTransition` (the retry point). Contract: session-fenced, once-per-session latch (`_indoorGuidanceEnsured`, reset on preview/End/retarget), usable-guidance short-circuit (hasIndoorSegment + last point == destinationPuid + floor match), fenced write-through commit with revision bump + anchor re-resolution.
2. **Failure policy**: keeps the old route, sets visible hint flag `indoorGuidanceUnavailable` ("Indoor route unavailable — following general path"), leaves the latch OPEN so the next floor confirmation retries (proven in test 2).
3. **SP wrapper** `requestIndoorRouteForSession(...)` (interface + impl): gates on RadioMap readiness for the confirmed scope (20 s cap, early-exit on unsupported), anchors POI-to-POI on the nearest loaded POI of the scope, returns an UNCOMMITTED candidate via existing guarded repository machinery.
4. **Misleading comment replaced** with a pointer to the real implementation.
5. Status-bar hint wired through `navigationStatusLabel`.

## 3. Files Changed
- `lib/state/navigation_controller.dart` — ensure method (~70 lines), latch/flag fields + resets, 3 call sites, comment fix.
- `lib/state/space_provider.dart` — readiness-gated indoor fetch wrapper (~55 lines).
- `lib/state/navigation_state_model.dart` — interface member.
- `lib/ui/utils/navigation_display.dart` — hint precedence after rerouteFailed.
- Test fakes ×9 gained the stub (recording variant where a call list exists).

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. _ensureIndoorGuidance with latch/fence/write-through | COMPLETED |
| 2. Radiomap readiness gate (20 s cap, defer/proceed semantics) | COMPLETED |
| 3. Remove misleading comment | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/handoff_guidance_test.dart` (3): scripted handoff → exactly one request for confirmed scope, write-through commit, revision bump, latch holds; failure → old route persists + hint label + floor-confirmation retry succeeds and clears; retarget resets latch so the new target re-ensures (dest2 recorded).
- FLIPPED `navigation_ui_test.dart` verbatim-source test: with a null-serving stub the plan-mandated hint now takes the label; verbatim source line asserted on the controller getter.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/handoff_guidance_test.dart` | 3/3 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **243/243 pass** |

## 7. Acceptance Criteria
- [x] After scripted O→I handoff, rendered+evaluated route contains destination-floor indoor segment (or documented degradation hint) — both branches test-proven. PASS
- [x] Entry dwell/corroboration tests unchanged-green (state machine suite untouched by flips here). PASS
- [x] Suite green (243). PASS

## 8. Architectural Rules / Invariants
Handoff completeness without invented geometry: content follows mode transitions through the SAME fenced write-through as reroutes (INV-1/2/3/6 preserved); verified dwell machinery reused untouched.

## 9. Regression Verification
Full 243-test suite green; arbitration/dwell suites unchanged.

## 10. Problems Encountered
- Fixture subtleties surfaced real contract details: (a) destination POI co-located with the fixture GPS fired arrival during setup — moved POIs away; (b) arbiter scope re-confirmation consumes 3 estimates before `fix.floor` reflects a new floor, so organic-drift retries need >3 emits; (c) retarget anchor fell back to the old route endpoint when the new POI was absent from the fixture list (real SP resolves from its own loaded set).
- Pending LP stale timers failed the end-of-test invariant once assertions passed — burned explicitly per suite convention.
- Two fakes missed during batch stub insertion (formatting mismatch) → added individually; wrong-enum comparison in the readiness gate caught by analyzer and removed.

## 11. Problems Resolved
All above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Interface gained `requestIndoorRouteForSession` (plan listed only "narrow SP wrapper"): required because the controller is coupled to the scope abstraction, not concrete SP.
- Hint precedence placed AFTER rerouteFailed and BEFORE the plain source line: plan specifies surfacing but not precedence; chosen order matches severity (both are degradations of the same line).

## 14. Final Phase Status
**COMPLETE**
