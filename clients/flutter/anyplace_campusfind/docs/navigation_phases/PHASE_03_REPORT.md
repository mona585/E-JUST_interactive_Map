# Phase 3 — Implementation Report

## 1. Objective
Browsing can never destroy an active session; navigation-driven selection cannot corrupt browsing state (Master Plan §10 PHASE 3; RC3; BUG-1 root cause; INV-4/INV-5).

## 2. Implementation Performed
1. **SP**: injected `bool Function()? isNavigationSessionLive` (+ `_sessionLive` helper) and temporary `terminateActiveSessionForRetarget` bridge.
2. **Six browsing APIs guarded** (`selectSpace`, `clearSelection`, `selectFloor`, `clearFloorSelection`, `selectPoi`, `clearSelectedPoi`): navigation-field resets suppressed while a session is live; selection semantics unchanged. `selectSpace`/`selectFloor` refactored through `_selectSpaceInternal`/`_selectFloorInternal(resetNavigationFields:)`.
3. **Navigation-safe variants added**: `selectFloorForNavigation`, `selectSpaceForNavigation` (never reset nav fields) + **`releaseIndoorContextForNavigation()`** — clears floor/POI/floorplan/radiomap residency while preserving route/session/destination AND keeping the selected building for map context (route-safety half of INV-9; full policy Phases 10–11).
4. **NC call sites switched** (5): connector transition → `selectFloorForNavigation`; organic completion → `selectFloorForNavigation`; exit side-effects → `releaseIndoorContextForNavigation`; approach preload → `selectSpaceForNavigation`; entrance preload → `selectFloorForNavigation`.
5. **navigateToPoi bridge**: with a live session it invokes the injected terminate callback (wired to `endNavigation`) then runs the legacy idle path — no silent destruction.
6. **Composition root** (`main.dart`): wired `isNavigationSessionLive = () => navigationController.isActive` and the retarget bridge.

## 3. Files Changed
- `lib/state/space_provider.dart` — guards, variants, release method, bridge fields (~90 lines).
- `lib/state/navigation_state_model.dart` — interface: 2 For-Navigation variants + release method.
- `lib/state/navigation_controller.dart` — 5 call-site switches.
- `lib/main.dart` — wiring.
- Test fakes ×7 gained the three new methods: state_machine, arrival, floor_transition, navigation_ui, session_identity, characterization (_FakeScope), route_store (_RecordingScope).

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Inject liveness callback; guard six APIs | COMPLETED |
| 2. Two For-Navigation variants + release; switch controller sites | COMPLETED |
| 3. Bridge navigateToPoi for live sessions | COMPLETED |
| 4. Characterization flips (live→opposite; idle→unchanged) | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/browsing_neutrality_test.dart` (3): all-six-APIs neutral during live session (route object identical, session id/revision/destination unchanged, browsing still effective); INV-5 variant methods preserve route + distinct call recording; navigateToPoi clean-restart bridge ends exactly once.
- FLIPPED characterization BUG-1 group → idle-parity pins (6 tests, permanent legacy behavior when idle); live-neutrality delegated to the new suite.
- UPDATED call-name expectations in state_machine suite (`selectFloor:` → `selectFloorForNavigation:` etc., 4 assertions) and exit-flow expectation → `releaseIndoorContextForNavigation`.

## 6. Tests Executed
| Command | Result |
|---|---|
| Targeted neutrality/characterization runs | pass after fixes |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **230/230 pass** |

## 7. Acceptance Criteria
- [x] INV-4/INV-5 tests green. PASS
- [x] Guided multi-floor journey keeps polyline visible: store-nulling during live sessions eliminated by guards; floor_transition suite green end-to-end (emulator smoke deferred to Phase 16 device protocol). PASS
- [x] Suite green (230). PASS

## 8. Architectural Rules / Invariants
INV-4 established (browsing neutrality) and INV-5 (navigation-driven selection safety). INV-9 route-safety half landed ahead of Phase 10.

## 9. Regression Verification
Full suite green including quick_access/search/shell suites (idle parity preserved); arrival/floor-transition/UI suites green after expected call-name flips.

## 10. Problems Encountered
- PowerShell fake-patching script mis-spliced four test files (insertion at wrong index; split imports / stranded methods) → 222 analyzer errors and 4 load failures. Repaired by `git checkout --` of the four files + careful Edit-tool re-application.
- Fakes with getter-only `activeFloorplan` could not assign it in `releaseIndoorContextForNavigation` → release body drops that line in fakes (SP's real implementation owns residency clearing).
- Four state-machine expectations asserting legacy call names failed as EXPECTED behavior flips → updated to For-Navigation names.
- Neutrality harness initially double-disposed controllers (manual + tearDown) and leaked LocationProviders → fixture now owns both disposables.

## 11. Problems Resolved
All of the above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- `releaseIndoorContextForNavigation` keeps `_selectedSpace` (old path nulled it via clearSelection): required so exit-detection fallbacks and map context survive; matches plan §10 Phase 10 release matrix ("keep last building context"). Documented; full policy still lands in Phases 10–11.
- Interface/fakes carry the three new methods (necessary for controller calls through the scope abstraction).
- Characterization live-neutrality moved into dedicated `browsing_neutrality_test.dart` rather than duplicating six API flows twice in one file.

## 14. Final Phase Status
**COMPLETE**
