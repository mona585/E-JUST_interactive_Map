# Phase 7 — Implementation Report

## 1. Objective
Route models truthfully describe the journey; composition cannot silently truncate; partiality is explicit (Master Plan §10 PHASE 7; BUG-4, BUG-14; INV-7).

## 2. Implementation Performed
1. **`NavigationRoutePoint.outdoor`** factory no longer accepts buid/floorNumber — outdoor points are identity-free (`''`/`''`, poisType `outdoor`, isOutdoor true).
2. **`fromJson` derives `isOutdoor`** from `poisType=='outdoor' || puid=='__outdoor__'`; server POI waypoints stay indoor-flagged.
3. **`floorTransitionIndices` counts only non-empty↔non-empty changes** — the ''↔'0' phantom boundary class is dead; added convenience **`entranceExitIndices`** (poisType-based markers).
4. **`fromSegments` projection truth**: outdoorWalking segments project identity-free points; segment-level buildingId remains journey context for instructions only.
5. **Mechanical sweep of all 66 `.outdoor(` call sites** (lib+test) removing stamped metadata — analyzer clean afterwards.
6. **CBR six-cap defused**: >8 segments now keeps FIRST+LAST, marks route `partial` with explicit "journey truncated" warning instead of silent removeRange.
7. **Centroid fallbacks mark partiality**: both CBR fallback constructions pass `isIncomplete: true`; `RouteSegment.fallback` documented accordingly.
8. **NC deviation source selection**: outdoors, deviation computes over `outdoorPolylinePoints` with full-polyline fallback — the empty-floor-filter → infinity path is structurally gone; indoors unchanged.

## 3. Files Changed
- `lib/data/models/navigation_route_model.dart` — truth rules + entranceExitIndices + projection.
- `lib/data/models/route_segment.dart` — fallback doc.
- `lib/data/repositories/cross_building_router.dart` — cap guard, 2× fallback isIncomplete, swept outdoor points.
- `lib/state/space_provider.dart` — swept hybrid builders.
- `lib/state/navigation_controller.dart` — deviation source selection.
- Tests swept: arrival, characterization, state_machine, ui, rerouting_correctness, retarget, route_model, route_store, session_identity.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Model truth rules | COMPLETED |
| 2. Router/composer updates (cap guard, fallback flags, metadata drop) | COMPLETED |
| 3. Downstream consumers audited & fixed (deviation source) | COMPLETED |
| Characterization flips for stamped-metadata expectations | COMPLETED |

## 5. Tests Added/Modified
- FLIPPED characterization BUG-4 group → "PHASE 7 FLIP": identity-free outdoor point; fromJson derivation matrix; no phantom ''↔'0' transitions.
- UPDATED `route_model_test.dart`: projection poisType/buid expectations ('outdoor', '') and transition-indices [1,3]→[3] under the new rule.
- All fixture routes across suites now build truthful geometry via the sweep.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **240/240 pass** |
| Production grep audit | AUDIT CLEAN |

## 7. Acceptance Criteria
- [x] No production code path constructs an outdoor point carrying non-null building/floor (grep + identity-free pin test). PASS
- [x] Outdoor deviation never returns infinity due to empty floor filter — structural fix plus existing two-tick hysteresis tests exercise exactly this path. PASS
- [x] Suite green (240). PASS

## 8. Architectural Rules / Invariants
INV-7 enforced at construction time: `isOutdoor ⇒ buildingId=='' && floorNumber==''` (empty-string absence in a non-nullable field model); indoor points carry real ids; server derivation replaces the default-false lie. Enables Phases 12's per-floor rendering predicates.

## 9. Regression Verification
Full suite green; floor-transition suites unaffected (their connectors use real floors); KMZ suites untouched and green.

## 10. Problems Encountered
- First flipped fromJson fixture used empty `buid`/`floor_number` strings which `parseRequiredString` rejects by design — both points were skipped (RangeError). Fixture corrected to realistic payloads (server synthetic waypoints carry context fields).

## 11. Problems Resolved
Above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Plan says outdoor points store "null/null"; the model's fields are non-nullable Strings whose established absence marker is `''` (used identically by `fromSegments` before this phase). Truth semantics identical; representation consistent with the codebase. Documented here rather than widening nullability across every consumer.

## 14. Final Phase Status
**COMPLETE**
