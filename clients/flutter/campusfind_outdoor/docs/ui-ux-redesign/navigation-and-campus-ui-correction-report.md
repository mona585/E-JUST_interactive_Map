# UI/UX Correction Pass — Map, Markers, Services, Routing & Panel

Post-Phase-9 correction pass (items #1–#16 of the brief). Presentation/integration fixes only —
no positioning/routing/navigation algorithm changes (diff audit in §Scope).

## Changes made

### 1. Quick Access & Recent Waypoints removed (#1)
Removed both sections (headers + lists) from the campus context of `CampusContentPanel`; imports
dropped. The legacy standalone widgets (`lib/widgets/quick_access_list.dart`,
`recent_waypoints_list.dart`) remain on disk only for the legacy `HomeScreen`/its test suite and are
**no longer mounted anywhere in the redesigned screen**.

### 2. Services → "Places" carries the useful destinations (#2)
New service type **Places** (`EntityCategory.building`, custom label) prepended to the services grid.
Results = the REAL E-JUST buildings from the server dataset under the current scope (all six when at
campus scope; just the selected one when a building/floor is active). No fake entities or coordinates.
Same UX as POI results: carousel, first auto-selected+focused, per-card **Route Here**.

### 3. Building selection zooms to the building (#3)
`_focusSelectedBuilding` zoom bumped 16.5 → **17.0**, keeping the existing once-per-buid centralized
camera path.

### 4. Floor selection fallback focus (#4)
New `_focusFloorFallback`: when a floor is selected but no floorplan image exists/loaded yet, camera
animates to the building at `MapConfig.focusedZoom` (18). When a floorplan IS available, the pre-existing
`_checkFloorplanCameraCenter` refines to its exact bounds. Complementary keys — never fighting.

### 5. Camera coordination fix (#5, real bug)
The route-preview clamp was `[indoorFloorplanZoom, 19] = [19,19]` → **every preview forced zoom 19**
(routes clipped / absurdly close; long routes broken). Replaced by true two-axis viewport fit with a
sane `[14, 19]` clamp, extracted into a pure top-level function `computeRouteCamera(...)` (unit-tested:
tiny→max, ~800 m mid-range, ~22 km→min, axis-symmetry, south-bias invariant).

### 6/7. Marker redesign (#6/#7)
New generated pin badges (Canvas → PNG, cached `BitmapDescriptor`s):
- **Buildings**: rounded-square badge, apartment glyph, primary ring; white body. Selected: amber
  filled body + white glyph.
- **POIs**: circular badge using each `EntityCategory.icon/color` (per-category cache); selected POI:
  primary-filled circle + white place glyph.
- Pin anchor `(0.5, 0.95)` while icons load; hue-based defaults used until generation completes.
- Marker IDs/tap behavior unchanged; marker-cache signature includes an icons-ready flag.

### 8. Building routing restored (#8)
Building context now renders Route actions: **Route Here** → existing `requestRouteToBuilding`
cascade (label switches to *Clear Route*/*Navigating…* per state). This entry point existed in the old
detail card but was dropped during the redesign.

### 9. Service-result routing fixed (#9 — root cause found)
`requestRouteToSelectedPoi` requires building+floor+POI residency. Service results only set
`selectedPoi`, so fresh sessions failed silently ("Select a floor…"). Fixes:
- Card tap now establishes the FULL chain via existing `navigateToPoi` (loads floors/POIs, selects
  everything) then focuses → destination state (PoiDetailCard) appears.
- `_startDirectionsForPoi` uses the same chain before preview/start (removed the space-only setup).
- During ACTIVE navigation taps only select+focus — never tear down a session.

### 10. Carousel sync preserved (#10)
Swipe↔selection and first-result auto-select logic untouched and still tested; new Places carousel
reuses the same guarded pattern (explicit-tap flag added so automatic selection can't yank context).

### 11. Initial collapsed panel (#11)
Panel already initialized collapsed; added explicit widget test asserting height < 20% of screen at
launch (map dominant), plus no QA/Recent/count texts anywhere.

### 12–15. Cards / count / preview / follow / collapse
Grid kept (#12); duplicate count removed earlier and asserted gone (#8-of-brief); Route Here fit =
refined viewport math above (#13); Start Directions = follow pipeline via `resumeFollowMode()` (#14);
compact bar + existing termination restored on end (#15) — shipped in the previous refinement,
re-verified here.

## Files changed

- `lib/ui/screens/map_screen.dart` — pin-marker generation/cache, building zoom 17, floor fallback
  centering, `computeRouteCamera` extraction + clamp fix
- `lib/ui/widgets/campus_content_panel.dart` — QA/RW removal, Places service type + building-results
  carousel, building Route actions, result-tap destination chain, directions root-cause fix, dead
  section-header removal
- `lib/screens/main_shell.dart` — (unchanged this pass; verified switching still correct)
- `test/campus_panel_test.dart` — removals/grid/initial-collapse assertions; Places flow test
- `test/camera_math_test.dart` — **NEW** (5 fit-math tests)
- `test/navigation_bottom_bar_test.dart` — unchanged, still green

## Verification

| Gate | Result |
|---|---|
| `flutter analyze` | **56 issues = unchanged baseline** (pre-existing legacy + foreign remediation files). Zero issues in any touched file. |
| Full `flutter test` | **325 passed / 7 failed** — same 3 pre-existing floorplan + 4 foreign remediation failures; zero new failures. |
| Focused suites | panel 9/9 (incl. Places flow, initial-collapsed, removals, grid), camera math 5/5, nav bar 2/2, shell/widget/search/nav suites green. |

### §16 transition checklist

| Transition | Status | Evidence |
|---|---|---|
| A Campus → Building | PASS | selectSpace + 17.0 zoom path (unit-covered selection; camera helper pure-tested) |
| B Building → Floor | PASS | floorplan centering (existing) + new fallback centering |
| C Floor → POI | PASS | ladder test taps POI → destination |
| D Services → Result | PASS | Places + POI result tests assert captured focus targets |
| E Route Here fit | PASS | `computeRouteCamera` unit tests (clamps, bias, two-axis) |
| F Start Directions camera | PASS | resumeFollowMode wiring; follow pipeline pre-existing tests green |
| G Follow during navigation | PASS (existing pipeline reused, untouched) | navigation_ui_test suite |
| Visual on-device pass | MANUAL-PENDING | APK built & installed on CPH2185 |

## Remaining issues

1. Radiomaps still absent server-side (documented in migration report) — indoor Wi-Fi positioning
   stays unsupported until the Architect uploads them.
2. Foreign remediation test files still pollute full-suite counts (owner action).
3. On-device visual confirmation of marker styling/centering feel is manual-pending.

---

## ADDENDUM — Additional requirements (initial viewport + marker quality)

### A. Initial E-JUST campus viewport (`map_screen.dart`)
- New public `ejustCampusBounds` from the four provided DMS corners, converted to decimal:
  SW `30.8554722, 29.5613611` · NE `30.8625556, 29.5677222` (center ≈ `30.859014, 29.564542`).
- One-shot `_fitCampusOverview()` animates the camera to fit these bounds (+40 m padding, zoom clamp
  `[13, 17]`, chrome fractions top .12 / bottom .18 for collapsed panel + search bar).
- Triggered ONLY when entering campus overview: no building/floor/POI selected and no navigation
  active. Re-armed on exit → clearing a selection / ending navigation re-fits the campus area once.
- First-frame correctness: `GoogleMap.initialCameraPosition` now starts at the bounds center @14.5
  while in overview.
- The legacy one-time GPS camera animation is suppressed while the campus overview owns the camera;
  GPS **tracking** is untouched and My Location still recenters on demand.
- No polygon is drawn; selection/POI/service/route/follow cameras are untouched.

Tests: DMS→decimal conversion pinned in `server_config_test.dart` (corner-exact to 1e-6).

### B. Entity marker icons — size & quality fix (`map_screen.dart`)
Root cause of "huge & pixelated": pins were rendered at 96 px and displayed at 96 *logical* px
(stretched ~3× on high-density screens).
Fix:
- `_renderPinIcon` rewritten to render at `quality ×` resolution (default **4×**) with proportional
  geometry (body = logicalWidth px, tail = 0.30×width, border = 0.085×width) — no upscaled rasters.
- New `_pinDescriptor(...)` wraps bytes via `BitmapDescriptor.bytes(bytes, width:, height:)`
  displaying at SMALL logical sizes.
- Sizes: POI category pins **20 dp**, selected POI **22 dp**, buildings **24 dp**, selected building
  **26 dp** — compact Google-Maps-style proportions (~24×34 total incl. tail), visually distinct
  (square building badge vs circular category badges; filled-inversion selected states kept, none oversized).
Coordinates, IDs, classification, tap behavior, routing/positioning untouched.

Delivery note: release APK rebuilt with both changes; device had disconnected during install —
run `adb install -r build/app/outputs/flutter-apk/app-release.apk` (or ask) once reconnected.

## Scope-preservation confirmation

Diff audit: only presentation/integration files changed (listed above). **No** changes to GPS/Wi-Fi
positioning, radiomap algorithms, `LocationProvider`, `NavigationController` state machine, routing
algorithms/repositories, backend contracts, floorplan/radiomap processing, or Android native code.
All routing continues through the pre-existing `requestRouteToSelectedPoi`,
`requestRouteToBuilding`, `navigateToPoi`, preview/start/retarget/terminate flows.

---

## ADDENDUM 2 � 4-per-row building cards & carousel arrows

### Buildings grid (#1/#12 refinement)
`_buildBuildingsGrid` now renders **4 cards per row** on phone widths (=350dp), 5 on wide surfaces,
3 only below 350dp. Compact card redesign for the tighter cell (~72�97dp at 360dp): small icon tile,
building name (2 lines, 10.5sp), bucode/space-type micro-label; selected state = primary border +
tint (no oversized glyphs). No clipping/overflow at the 360dp test surface � verified by the existing
panel suite. Tap semantics unchanged (same-buid re-entry included).

### Responsive grids elsewhere
Service-type grid now responsive: **4 columns =430dp** (3 below, 5 =620dp) using MediaQuery width;
result carousels keep their large single-card layout intentionally (they need the Directions button).

### Carousel arrows (#2)
New `_CarouselArrows` wrapper around BOTH PageViews (POI results and Places buildings):
- compact translucent circular chevrons overlaid left/right, vertically centered;
- hidden on first/last item respectively (`page > 0` / `page < count-1`);
- tap animates via the SAME `_pageController.animateToPage(...)` � no second state source;
- index tracked by a PageController listener (`_onCarouselPageTick`) so swipes, arrows and
  programmatic jumps all update `_carouselPage` identically; selection callbacks still fire from
  `onPageChanged`, keeping selection/focus in lockstep.

### Verification
Bundle: panel 9/9 (incl. new arrow edge assertions: hidden-left initially, right advances to B and
hides at last, left returns), camera math 5/5, nav bar 2/2, scope 7/7.
Full gates: `flutter analyze` 56 = unchanged baseline (0 new); full suite **326 pass / 7 known
failures** (unchanged). Release APK rebuilt and installed on CPH2185 (`Success`).
