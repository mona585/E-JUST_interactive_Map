# Phase 11 — Implementation Report

## 1. Objective
Navigation-aware radiomap residency: preload for approach, retain during multi-building trips, targeted eviction, browsing never sabotages navigation sensing (Master Plan §10 PHASE 11).

## 2. Implementation Performed
1. **Policy block documented** in SP beside the radiomap machinery: LOAD / RETAIN / EVICT / GLOBAL-WIPE rules with the native LRU (limit 4) as the natural pressure valve.
2. **Split reset vs wipe**: `_resetRadioMapState()` now resets STATUS FIELDS ONLY — the native `clearRadioMap()` global wipe was removed from it. All selection/exit paths call only the former, so browsing and exits can no longer destroy resident maps.
3. **`resetAllRadiomaps()` added** as the single global-wipe entry point for app-level resets (logout/storage), bumping the request id to cancel in-flight loads.
4. **Targeted eviction on failure preserved**: loader's `removeRadioMap(buid, floor)` paths untouched and now test-proven.

## 3. Files Changed
- `lib/state/space_provider.dart` — policy docs, `_resetRadioMapState` split, `resetAllRadiomaps()`.
- NEW `test/radiomap_lifecycle_test.dart` — recording native fake (`clearAllCalls`, `targetedRemovals`) + failing radiomap repository fixture over the REAL SpaceProvider.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Policy doc in SP | COMPLETED |
| 2. Reset/wipe split + resetAllRadiomaps + caller audit | COMPLETED |
| 3. Browsing-during-navigation semantics asserted | COMPLETED |

## 5. Tests Added/Modified
- NEW 4 tests: browsing churn during a live session produces ZERO native clears/removals; End leaves residency to LRU (no wipe); `resetAllRadiomaps` is the sole global wipe; failed load triggers TARGETED eviction of exactly ('bA','0') with clearAllCalls==0.
- No existing tests modified (arbitration suites unaffected; Matrix O interplay intact).

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/radiomap_lifecycle_test.dart` | 4/4 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **252/252 pass** |

## 7. Acceptance Criteria
- [x] Fake-native assertions prove scoped behavior (clears vs targeted removals recorded). PASS
- [x] Suite green (252). PASS

## 8. Architectural Rules / Invariants
"Radiomap residency serves both browsing and navigation; neither may destroy the other's requirements." Combined with Phase 10's release matrix, exit/browsing paths are now provably non-destructive to sensing.

## 9. Regression Verification
Full suite green including acquisition-lifecycle tests (§4 item 8) which still pass against the split reset — their expectations targeted status fields, which behave identically.

## 10. Problems Encountered
- Fixture assembly churn: duplicate/misplaced POI initialization and a `late` nullable field caused LateInitializationError; matcher `contains` on `List<List<String>>` uses identity, not deep equality — assertion rewritten element-wise.
- PowerShell line-ending mismatch made one scripted edit a silent no-op; repaired via Edit tool.

## 11. Problems Resolved
All above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
NONE

## 14. Final Phase Status
**COMPLETE**
