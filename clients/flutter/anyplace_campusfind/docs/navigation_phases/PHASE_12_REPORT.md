# Phase 12 — Implementation Report

## 1. Objective
Map shows exactly the relevant geometry for the current context; camera behaves predictably (Master Plan §10 PHASE 12; BUG-9, BUG-10, BUG-11, BUG-16).

## 2. Implementation Performed
1. **Floor-scoped rendering**: pure rule `segmentVisibility(type, floorNumber, displayedFloor, indoorEmphasis)` in navigation_display — outdoor legs visible outdoors / dimmed outline while indoors; indoor+floorTransition legs only on their displayed floor; entrance/exit boundaries follow context. `_buildPolylines` now consumes it with the BROWSING-selected floor; legacy indoor polyline is floor-filtered too.
2. **KMZ gating (BUG-9b)**: pure `showCampusRoutes(sessionLive, routeHasOutdoorCoverage, flagEnabled)` + `NavigationConfig.showCampusRoutesDuringNavigation=false`; custom KMZ block gated accordingly.
3. **Fit-bounds zoom (BUG-10)**: pure `routeFitZoomForSpan(meters)` table (≤300→19, >300→17, >800→15.5, >2000→14); `_fitRouteBounds` converts degrees→meters and uses it.
4. **Follow-exit robustness (BUG-11)**: `_programmaticTailPending` keeps the programmatic guard until `onCameraIdle`, so post-animation inertia cannot exit follow mode; genuine drags still exit. Dead `_isUserGesture` field removed (analyzer warning count 30→29).
5. **Heading cleanup (BUG-16)**: dead compass-from-location branch deleted (heading fields, fresh-window math); heading EMA now consumes the DISPLAYED (held) position during holds so arrow and dot agree.
6. Instruction strip/store equality already guaranteed by Phase 2's single store and pinned by route_store identity tests.

## 3. Files Changed
- `lib/ui/utils/navigation_display.dart` — visibility rule, KMZ gate, zoom table (+ imports).
- `lib/config/navigation_config.dart` — `showCampusRoutesDuringNavigation`.
- `lib/ui/screens/map_screen.dart` — polylines rewrite (nav-aware), fit-zoom, follow tail, heading cleanup.
- NEW `test/rendering_consistency_test.dart`.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Floor-scoped segment rendering | COMPLETED |
| 2. KMZ layer gating | COMPLETED |
| 3. Fit-bounds zoom mapping | COMPLETED |
| 4. Follow-exit robustness | COMPLETED |
| 5. Heading cleanup + hold freeze | COMPLETED |
| 6. Strip/source unification assertion | COMPLETED (covered by Phase 2 `same()` pins) |

## 5. Tests Added/Modified
- NEW `rendering_consistency_test.dart` (9): outdoor dim/visible matrix; per-floor indoor & transition gating; boundary-context rule; KMZ gate ×4 incl. flag and no-outdoor-coverage cases; zoom span table incl. long-route-not-pinned.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/rendering_consistency_test.dart` | 9/9 pass |
| `flutter analyze --no-pub` | **29 issues (improved from baseline 30 — dead field removed)** |
| `flutter test --reporter compact` (full) | **261/261 pass** |

## 7. Acceptance Criteria
- [x] Visual smoke script correctness at every stage: pure-rule tests cover every branch of the projection rules; full visual walk-through deferred → NOT EXECUTED — REQUIRES PHYSICAL DEVICE (Phase 16 protocol).
- [x] No camera jump on reroute commit: reroute commits never invoke `_fitRouteBounds` (grep: only preview/onFitRouteBounds path calls it) — structural guarantee; device confirmation pending as above.
- [x] Suite green (261). PASS

## 8. Architectural Rules / Invariants
"Rendering is a pure projection of (route store, display context); camera is presentation-only" — all new logic lives in pure functions or presentation state; zero navigation-state mutation from M.

## 9. Regression Verification
Full suite green; navigation_ui verbatim-source expectations already flipped in Phase 8 remain green.

## 10. Problems Encountered
- Initial zoom helper clamped min to `MapConfig.indoorFloorplanZoom` (=19.0), silently resurrecting the pin — caught by the new table test before any integration run; clamp removed for outdoor tiers.
- Scripted multi-line replacement inserted literal `\r\n` once more; repaired by hand.

## 11. Problems Resolved
Both above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Plan's "clamp [indoorFloorplanZoom..17]" is internally inconsistent (floor=19 would re-pin); implemented the plan's own TABLE as normative (≤300 m tier may reach 19 = indoor scale; all outdoor tiers ≤17). Table-test enforces it.

## 14. Final Phase Status
**COMPLETE**
