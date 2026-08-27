# Navigation UX + Campus Panel Refinement Report

Post-Phase-9 refinement (camera presentation, panel chrome during navigation, building-card presentation).
No routing/positioning/backend/state-machine logic was touched.

## Changes made

1. **Route Here → fit the ENTIRE route** (`map_screen.dart`, `_fitRouteBounds` rewritten)
   - Bounds computed from the actual route polyline with `NavigationConfig.routeFramePadding` margin.
   - True viewport fit: zoom derived from BOTH the width and height of the padded bounds against the AVAILABLE
     area (screen minus ~14% top chrome for the search bar and ~40% bottom chrome for the destination panel) using a
     meters-per-pixel model; no fixed preview zoom (safety clamp `[indoorFloorplanZoom, 19]` retained).
   - Camera target biased so the geometric center of the route sits at the midpoint of the VISIBLE region
     (south shift by half the bottom-chrome minus half the top-chrome, converted via deg-per-pixel) — the route is
     centered between top UI and bottom panel, neither clipped nor tiny.
2. **Start Directions → navigation camera** (`campus_content_panel.dart`, `_startDirectionsForPoi`)
   - Fresh start: existing `startRoutePreview` → `startActiveNavigation` → **`resumeFollowMode()`**
     (EXISTS in NavigationController) hands the camera to the existing follow pipeline
     (`_followUserPosition`: nav zooms 19 indoor / 17 outdoor, lower-third framing, change-gated coalescing).
     The whole-route refit was REMOVED from this path.
   - Retarget during live session: stays in follow mode (refit removed there too).
3. **Camera follow during active navigation**: unchanged existing pipeline — `_onNavigationChanged` +
   `followMode` + display-location hold logic continue to drive the camera as the user moves. No second tracking
   system.
4. **Compact navigation bottom bar** (`ui/widgets/navigation_bottom_bar.dart`, NEW):
   - Shown in place of the dynamic panel while `NavigationController.isActive` and the panel is collapsed.
   - Contains: active indicator + "Navigation active" (+ optional destination/floor subtitle), expand control
     (↑), close control (✕). Height ≈56dp + safe area — minimal footprint, map gets maximum space.
   - ✕ ends the session through the EXISTING flows only: `terminateNavigation()` + `clearNavigationRoute()`.
   - Tap on bar body or ↑ sets `navPanelOpenProvider = true`: full panel re-opens, navigation CONTINUES.
5. **Panel ↔ bar switching** (`main_shell.dart`): rising-edge detection force-collapses the panel when a NEW
   session starts; ending a session automatically restores the normal dynamic panel/context. When re-expanded
   during navigation, the panel title bar shows a minimize control (picture-in-picture) returning to the compact
   bar.
6. **Buildings as CARDS** (`campus_content_panel.dart`): list rows replaced by a responsive card grid
   (2 columns phone / 3 ≥560dp) — rounded-16 themed cards with icon tile, building name (2 lines), bucode badge
   (or spaceType fallback), selected highlight. Tap behavior unchanged, including same-buid re-entry semantics.
7. **Duplicate count removed**: the "N" trailing count under the Buildings section title is gone; the
   Buildings | Services switch itself is untouched.

## Files modified

| File | Change |
|---|---|
| `lib/ui/screens/map_screen.dart` | viewport-aware `_fitRouteBounds` rewrite (fit + centering bias) |
| `lib/ui/widgets/campus_content_panel.dart` | buildings card grid; duplicate count removed; minimize-during-nav control; directions camera wiring |
| `lib/screens/main_shell.dart` | panel ⇄ compact-bar switching; session edge handling |
| `lib/providers/panel_provider.dart` | `navPanelOpenProvider` |
| `lib/ui/widgets/navigation_bottom_bar.dart` | **NEW** compact bar |
| `test/navigation_bottom_bar_test.dart` | **NEW** bar widget tests |

Not modified: GPS/Wi-Fi positioning, route calculation, repositories/API client, `NavigationController`
state machine (only existing public methods called), floorplan pipeline, theme.

## Camera behavior before / after

| State | Before | After |
|---|---|---|
| Route Here (preview) | span-proportional estimate, screen-center target, fixed-ish clamps | true two-axis viewport fit incl. padding, target centered in visible area above panel/below top bar |
| Start Directions | refit whole route (stayed zoomed-out) | `resumeFollowMode()` → existing follow pipeline zooms to user (19 indoor / 17 outdoor), lower-third framing |
| Active navigation | follow existed | unchanged (reused); no whole-route view |
| Browsing | existing per-context behavior | unchanged |

## Bottom-panel navigation behavior

Session starts → panel auto-collapses to compact bar (56dp). ↑ or bar tap → full panel returns (destination/route
info visible), navigation unaffected; picture-in-picture control returns to bar. ✕ → existing termination +
route cleanup → normal panel/context restored automatically.

## Building cards & count removal

Responsive grid implemented as above; the trailing count under the section title removed. Selection logic,
E-JUST scoping, Quick Access and Recent Waypoints sections untouched.

## Test results

| Gate | Result |
|---|---|
| `flutter analyze` | **56 issues — identical pre-adjustment baseline**, all in pre-existing legacy files or foreign remediation test files. Zero issues in any file touched by this refinement. |
| Full `flutter test` | **312 passed / 7 failed** — same 3 pre-existing floorplan failures (#1) + 4 foreign remediation loading failures (#7); zero new failures. |
| Redesign bundle (incl. new tests) | **79/79 pass** — adds `navigation_bottom_bar_test.dart` (labels/subtitle, expand-without-ending, close callback, body-tap expands) and keeps all ladder/carousel/sync/buildings coverage green on the 360dp surface (card aspect fix verified). |

## Issues / deviations

1. Phone dropped off USB before the final reinstall (`adb: device not found`) — release APK rebuilt successfully
   (`build/app/outputs/flutter-apk/app-release.apk`); run `adb install -r` on it (or ask to retry) once the device
   is reconnected.
2. Manual on-device walkthrough items from §11 (visual centering feel, follow smoothness) remain MANUAL-PENDING —
   all underlying code paths are covered by widget/domain tests where automatable.
3. Deviation: the floating `NavigationStatusBar`/`ArrivalBanner` were intentionally KEPT alongside the compact bar
   (they provide turn guidance/arrival UX and float without consuming layout space); the brief's minimal-space goal
   applies to the docked bottom chrome, which is now the compact bar.
