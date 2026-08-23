# Phase 4 — Implementation Report

## 1. Objective
Explicit lifecycle for destination changes; no silent retargets; no ghost previews (Master Plan §10 PHASE 4; BUG-3, BUG-8; completes RC2).

## 2. Implementation Performed
1. **Lifecycle documentation** block added to NSM header (REQUESTED → … → TERMINATED, invalidation rules).
2. **`NavigationController.retargetDestination(PoiModel)`**: identity-first transaction — installs a NEW `NavigationSession` (new id, revision 0) before any content moves; resets per-session bookkeeping; fires the cascade via the scope; post-await `identical(_session, newSession)` gate; on success resolves the arrival anchor from the new store; on failure keeps the NEW session with an anchor on the requested POI (degraded but honest); overlays (`rerouting`/`paused`) restore to their activity; refused from `idle` and `arrived`.
3. **SP `requestRouteForRetarget(target)`** (interface + impl): selects context exclusively via For-Navigation variants, floor cascade (target floor → '0' → lowest numeric), then runs the UNCHANGED initial cascade behind its request-id machinery; returns renderable success.
4. **BUG-8 ghost preview**: bottom-sheet preview close already pairs through Phase-2 canonical teardown (`endNavigation` clears the single store); comment added documenting closure.
5. **UI affordance**: `onStartDirections` in map_bottom_sheet routes to `retargetDestination` when `isActive` — "Navigate here" is now the only retarget entry point.

## 3. Files Changed
- `lib/state/navigation_state_model.dart` — lifecycle docs + `requestRouteForRetarget` interface member.
- `lib/state/space_provider.dart` — retarget cascade support (~45 lines).
- `lib/state/navigation_controller.dart` — `retargetDestination` (~85 lines).
- `lib/ui/widgets/map_bottom_sheet.dart` — affordance wiring + BUG-8 note.
- Test fakes ×7: `requestRouteForRetarget` stubs.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Lifecycle documentation block in NSM header | COMPLETED |
| 2. retargetDestination implementation + state handling | COMPLETED |
| 3. Ghost-preview pairing fix | COMPLETED (via Phase-2 teardown; documented) |
| 4. Wire UI entry point(s) | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/retarget_test.dart` (3 = matrix H/I unit versions + BUG-8 residue):
  1. mid-outdoor retarget → new sessionId, polyline==B, pending A-reroute released afterwards is discarded silently, en-route reroute targets poiB (repo-recorded), arrival anchor resolves B (arrives at B);
  2. retarget during REROUTING overlay → old gated result lands after retarget, never overwrites B commit; activity restored;
  3. closing a preview leaves zero route residue.
- Fake-scope stubs record `requestRouteForRetarget:<puid>` where a call list exists.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/retarget_test.dart` | 3/3 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **233/233 pass** |

## 7. Acceptance Criteria
- [x] Navigate-here mid-trip retargets cleanly; no delayed old-destination route ever appears — test-proven (tests 1–2). PASS
- [x] Closing a preview leaves zero route residue — test-proven (test 3). PASS
- [x] Suite green (233). PASS

## 8. Architectural Rules / Invariants
Destination changes are transactions (identity first, content second); INV-3 extended to the destination dimension. Old-session artifacts provably cannot interleave.

## 9. Regression Verification
Full suite green (233) including session/store/browsing suites from Phases 1–3.

## 10. Problems Encountered
- Batch fake-patching again mis-spliced two files (glued `}  @override`, stranded method outside class) → repaired by un-glue replace + interpolation fix (`$(poi.puid)` → `${poi.puid}` — PowerShell had emitted invalid Dart interpolation).
- Redundant null-check warning on promoted `selectedPoi` in the UI closure → removed.
- Test-harness cooldown interaction: second reroute was suppressed until `debugNowOverride` advanced past the 15 s window.

## 11. Problems Resolved
All of the above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Plan names the SP entry "call requestRouteToSelectedPoi after selecting target context"; implemented as dedicated `requestRouteForRetarget` wrapper because floor loading must be awaited between selection and route request (not exposed through the scope interface otherwise). It reuses the unchanged cascade/request-id machinery as required.
- On retarget failure the NEW session persists (anchored on POI) rather than restoring the old one: the plan's "failed validation discards candidate, old route persists" applies to ROUTE candidates inside one identity; a retarget changes user intent, which we do not silently reverse.

## 14. Final Phase Status
**COMPLETE**
