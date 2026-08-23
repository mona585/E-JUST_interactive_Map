# NAVIGATION MASTER PLAN — PHASE 0 BASELINE (FROZEN)

| | |
|---|---|
| Frozen at | Phase 0 execution, working tree snapshot commit `nav-phase-0` |
| HEAD before freeze | `2856a4b7` (`campusfind-migration`) |
| Toolchain | Flutter 3.44.9 stable / Dart 3.12.2 |
| Analyze baseline | **30 issues: 0 errors, 3 warnings, 27 infos** (23× `avoid_print` in CBR; 2 warnings in space_repository; 1 warning unused `_isUserGesture` in map_screen; infos: prefer_final_fields/initializing_formals ×2 SP, unnecessary_import + initializing_formals M) |
| Test suite baseline | **209 tests / 16 files — ALL PASSING** (pre-characterization) |
| Characterization suite | `test/navigation_baseline_characterization_test.dart` — **10 pins, all passing** (they pin the BROKEN behavior and flip later) |

## Per-file test inventory (all green at freeze)

| File | Protects | Notes |
|---|---|---|
| `navigation_state_machine_test.dart` | state machine edges, dwells, preload cascade, scripted journey | largest suite; includes reroute gating cases |
| `arrival_test.dart` | 2-tick confirmation, indoor identity gating, anchor tiers | |
| `floor_transition_test.dart` | EXPECTED/DETECTED/CONFIRMED/ABORTED lifecycle, hold, suppression, timeout | |
| `location_provider_arbitration_test.dart` | belief/hysteresis/scope-confirm/outlier-hold/confidence | |
| `location_provider_lifecycle_test.dart` | subscribe/dispose/stale-timer basics | |
| `position_estimate_boundary_test.dart` | transport robustness incl. late events after dispose | |
| `custom_routes_test.dart` | KMZ graph unit behavior | |
| `custom_routes_integration_test.dart` | real asset `assets/navigation/university roads.kmz` | re-verified standalone at freeze: **16/16 pass** |
| `route_model_test.dart` | fromSegments projection semantics | expectations flip in Phase 7 |
| `navigation_ui_test.dart` | display projections, status bar, instruction strip, banner | |
| `quick_access_test.dart` / `home_quick_access_test.dart` | browsing flows incl. cross-building nav | |
| `search_filter_test.dart`, `shell_gate_test.dart`, `widget_test.dart`, `floorplan_overlay_cache_test.dart` | app chrome / caches | |

## Characterization pins (current broken behavior — LOCKED)

All annotated `CHARACTERIZATION ... (flips in Phase N)` in source.

| Pin | Asserts today's BUG | Flip owner |
|---|---|---|
| selectFloor nulls scope route while live | BUG-1 | Phase 2/3 |
| clearFloorSelection nulls scope route while live | BUG-1 | Phase 2/3 |
| selectSpace nulls scope route while live | BUG-1 | Phase 2/3 |
| clearSelection nulls scope route while live | BUG-1 | Phase 2/3 |
| selectPoi(other) nulls scope route while live | BUG-1 | Phase 2/3 |
| clearSelectedPoi nulls scope route while live | BUG-1 | Phase 2/3 |
| reroute commits to controller only; store keeps stale object | BUG-2a | Phase 2 |
| later scope notification reverts controller to stale route | BUG-2b | Phase 2 |
| outdoor factory retains destination buid+floorNumber | BUG-4a | Phase 7 |
| fromJson never derives isOutdoor | BUG-4b | Phase 7 |
| phantom floorTransitionIndices ''↔'0' | BUG-4c | Phase 7 |

## Freeze mechanics

The pre-existing dirty worktree (+1764/−1007 vs `2856a4b7`, 14 modified files,
23 untracked files incl. new lib/test/doc files) was committed verbatim as
`chore(nav): working-tree snapshot pre master-plan` and tagged `nav-phase-0`.
Every subsequent phase lands as its own changeset on top of this point.
