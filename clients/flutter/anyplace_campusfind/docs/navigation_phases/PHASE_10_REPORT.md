# Phase 10 — Implementation Report

## 1. Objective
Exit releases ONLY indoor context; outdoor continuation keeps everything (Master Plan §10 PHASE 10; INV-9 full closure).

## 2. Implementation Performed
1. **Release matrix finalized** in SP `releaseIndoorContextForNavigation`:
   - RELEASED: floorplan overlay browsing state, POI selection.
   - PRESERVED for map context: selected building AND last floor selection (reverses the Phase-3 interim which nulled the floor).
   - RADIOMAP: untouched here — Phase 11 owns scoped residency policy.
   - NEVER TOUCHED: route store / destination / session id / revision; navigating-floor bookkeeping goes stale-but-harmless; custom-route progress switches source via the existing state gate.
2. **Matrix documented in NSM header** beside the lifecycle block.
3. **Fake scopes aligned** across 8 test files (release stubs no longer clear floor selection).
4. **Re-entry support proven by test** — preload + corroboration re-run under the SAME session id.

## 3. Files Changed
- `lib/state/space_provider.dart` — release method finalization.
- `lib/state/navigation_state_model.dart` — release-matrix documentation block.
- Test fakes ×8 aligned.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Release matrix implemented in release method | COMPLETED |
| 2. Re-entry support test (preload+corroboration again, same session) | COMPLETED |
| 3. Matrix documented in NSM header | COMPLETED |

## 5. Tests Added/Modified
- NEW in `handoff_guidance_test.dart`: **Matrix E double-handoff** — I→O exit (stale Wi-Fi + 3 outside confirmations + confirming tick) then O→I return (preload latch re-arms, corroboration re-confirms): session id constant, route object identical across both boundaries.
- Fake release stubs aligned to keep floor context.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/handoff_guidance_test.dart` | 4/4 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **248/248 pass** |

## 7. Acceptance Criteria
- [x] Double-handoff test green; no route loss at either boundary. PASS
- [x] Suite green (248). PASS

## 8. Architectural Rules / Invariants
INV-9 closed: exit clears positioning/browsing context for the building left; navigation content survives. Radiomap residency intentionally deferred to Phase 11 per plan dependency note.

## 9. Regression Verification
Full suite green; exit-flow tests (state machine) unaffected — their assertions target call names and states, which are unchanged.

## 10. Problems Encountered
- Exit dwell needs one tick BEYOND the confirmation count to resolve (`_maintainDwell` completes it) — initial fixture asserted too early.
- Batch fake-alignment script initially a no-op (replace result discarded); redone with write-back.

## 11. Problems Resolved
Both above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
NONE beyond the plan's own deferral of radiomap eviction scope to Phase 11.

## 14. Final Phase Status
**COMPLETE**
