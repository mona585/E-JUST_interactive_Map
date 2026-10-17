# UI/UX Redesign Implementation Plan

Project: `anyplace_campusfind` (Flutter) — Campus → Buildings/Floors/POIs + Services map-first redesign.
Scope guard: this project is ONLY the UI/UX redesign described here. Positioning, GPS, Wi-Fi fingerprinting,
routing algorithms, backend APIs, and navigation logic are explicitly OUT OF SCOPE. The new UI may only CALL
existing features.

---

## 1. Objective

Replace the current two-tab (Home / Map) experience with a single map-first screen:

```
Search / Directions   (top)
        ↓
      Map             (full-screen canvas)
        ↓
One Dynamic Content Area  (bottom panel whose content follows context)
```

The dynamic content area changes with context:

- Campus overview → `Buildings | Services` switch
- Building selected → floors of that building
- Floor selected → POIs of that floor
- Service chosen → service types → service results (carousel when multiple)

Search (with From/To) lives at the top and stays independent from the bottom dynamic content.

## 2. Current UI Assessment

### What exists today

| Area | Current implementation | Files |
|---|---|---|
| App entry | `MaterialApp` → `RootRouter` (restores campus id) → `MainShell` | `lib/main.dart` |
| Shell | Bottom `NavigationBar` with 2 tabs: Home (0), Map (1), lazy indexed stack. Leaving Map tab terminates any active navigation by design | `lib/screens/main_shell.dart` |
| Home tab | Search field (pushes full-page SearchScreen), Quick Access horizontal strip, Recent Waypoints list, profile avatar in app bar | `lib/screens/home_screen.dart`, `lib/screens/profile_screen.dart` |
| Map tab | Full-screen GoogleMap; top "Anyplace" header chip; right-side `MapControls` (search sheet, recenter, zoom ±, reload); conditional draggable `MapBottomSheet` (12% / 45% / 85%) only when a building or POI is selected; NavigationStatusBar + ArrivalBanner during navigation; error banner | `lib/ui/screens/map_screen.dart` |
| Building detail | Metadata card with buid copy, horizontal floor chips, floorplan/POI/route status badges, navigable-POI list (auto-routes on tap), Route Here / Clear Route buttons | `lib/ui/widgets/building_detail_card.dart` inside `lib/ui/widgets/map_bottom_sheet.dart` |
| POI detail | Detail card with bookmark, Navigate/Clear route/Start directions actions (preview + active navigation via `NavigationController`) | `lib/ui/widgets/poi_detail_card.dart` |
| Map search | Modal `BuildingSearchSheet` — building-name search only | `lib/ui/widgets/building_search_sheet.dart` |
| Directory search | Full-page `SearchScreen`: text query + filter modal (category, building). Results are POIs only (`SearchService.query` filters `entityType == 'poi'`) | `lib/screens/search_screen.dart` |
| Search engine | `SearchService` (ChangeNotifier): progressive index of spaces/floors/POIs (bulk-loaded at startup via `bulkLoadProvider` + `SpaceProvider.loadAllFloorsAndPois`), ranked multi-field scoring, `discoverBuids()`, `discoverCategoriesFromIndex()` | `lib/services/search_service.dart`, `lib/providers/search_provider.dart`, `lib/providers/bulk_load_provider.dart` |
| Domain state | `SpaceProvider` (ChangeNotifier): spaces, selectedSpace, floors, selectedFloor, floorplan overlay pipeline, per-floor POIs, radioMap state, route store, `selectSpace/selectFloor/selectPoi/clearSelection/navigateToPoi/requestRouteToSelectedPoi/requestRouteToBuilding/clearNavigationRoute` with INV-4 browsing-neutrality guarantees | `lib/state/space_provider.dart` |
| Navigation session | `NavigationController`: preview/start/retarget/terminate, follow mode, sub-states | `lib/state/navigation_controller.dart` |
| Location | `LocationProvider` (GPS fix, tracking) — untouched by this redesign | `lib/state/location_provider.dart` |
| Classification | `EntityCategory` enum (professor, cafeteria, library, lab, room, office, toilets, …) + `CategoryDeriver`; `PoiClassification` (connector/entrance/door/elevator/stairs) | `lib/utils/category_deriver.dart`, `lib/utils/poi_classification.dart` |
| Theme | Red primary `#D32F2F`, white surfaces, thin borders, Material 3 | `lib/config/theme.dart` |
| Cross-tab glue | `openSearchResult` / `openQuickAccessItem` set `shellTabProvider = 1` then drive SpaceProvider | `lib/screens/detail_navigation.dart` |

### From/To UI

Does not exist. Today routing is triggered only from building/POI cards and always uses the current device
location as origin. A From/To bar is new UI. Functional custom-origin support can be delivered WITHOUT touching
route calculation because an existing API already exists: `NavigationRepository.getRouteBetweenPois(fromPuid, toPuid)`
(used as Strategy 2 inside `requestRouteToSelectedPoi`). Custom "From" will be supported only when the chosen origin
resolves to a POI; otherwise it falls back to My Location.

### Services UI

Does not exist as a browsing surface. The data foundation does exist: every POI carries `poisType`
(`CategoryDeriver.fromPoiType` → `EntityCategory`), and startup bulk-load progressively indexes ALL campus POIs into
`SearchService`. Campus-scope service results can therefore be served from the existing index; building-scope results
filter that index by `buid`; floor-scope filters by `buid + floorNumber`. No repository or API change is required.
A small pure helper (`ServiceQuery`) will encapsulate scope filtering over already-loaded data.

### State management

Mixed: `provider` (ChangeNotifier) for domain state, Riverpod for shell tab / search providers / cache version.
The redesign keeps this split as-is. New UI state is added as small Riverpod `StateProvider`s plus one new
ChangeNotifier-style controller for the dynamic-content context if needed — no migration.

## 3. Target UX

Main structure:

```
┌──────────────────────────────┐
│  [From ▾] [To 🔍]  [avatar]  │  ← Search / Directions bar (top)
├──────────────────────────────┤
│                              │
│            MAP               │  ← full-bleed GoogleMap (existing)
│                              │
├──────────────────────────────┤
│ ═══ drag handle ═══          │  ← ONE dynamic content area (bottom)
│ context content …            │     collapsed = handle + context title
│                              │     expanded = full context UI
└──────────────────────────────┘
```

Contexts of the dynamic area:

1. **Campus** — `Buildings | Services` segmented switch (Buildings default). Buildings tab also hosts Quick Access + Recent Waypoints sections so no existing functionality is removed.
2. **Building** — building name + Floors chips (+ building actions).
3. **Floor** — POIs of the selected floor.
4. **POI / Destination** — destination card with Directions (existing flows).
5. **Service** — service-type grid; picking a type shows Service Results (single card or horizontal carousel).

Map states: campus overview → building zoom → floor zoom (floorplan overlay) → POI focus → service-location focus.

## 4. UX Hierarchy

```
Campus
├── Buildings
│     └── Building
│           └── Floors
│                 └── POIs
│                       └── Destination
│
└── Services
      └── Service Type
            └── Service Results
                  └── Selected Location
                        └── Destination
```

Both branches converge on **Destination**, where the EXISTING route/navigation functionality is invoked
(`requestRouteToSelectedPoi`, `startRoutePreview`, `startActiveNavigation`, `retargetDestination`).

## 5. Search

- Free-form search across buildings/floors/POIs using the existing `SearchService` index.
  NOTE: `SearchService.query()` currently returns POIs only; the search phase adds an opt-in flag to include
  buildings/floors WITHOUT changing default behavior of the existing directory page.
- Optional recommendations when the query is empty (Recent Waypoints, Quick Access, top matches). Recommendations
  are NOT mandatory — plain typing always works.
- From defaults to **My Location**; user can change From by picking a result (POI/building).
- To is the destination; selecting To runs the destination chain (`navigateToPoi` / building selection) and puts
  the dynamic area into the matching context.
- Search is independent of the bottom dynamic content: opening/typing in search never collapses or mutates the
  dynamic area; dismissing search restores it unchanged.

## 6. Dynamic Content

| Context | Content |
|---|---|
| Campus | `Buildings \| Services` switch. Buildings = scrollable building list (+ Quick Access, Recent Waypoints). Services = service-type grid |
| Building | Building title + Floors chip row (existing floor loading/status reused) |
| Floor | POI list for the selected floor (navigable POIs only, reusing `PoiClassification` filtering) |
| Service | Service types grid → after choosing a type: Service Results (card or carousel) |

Back behavior: each context offers an explicit back affordance (Floor→Building→Campus, Results→Service Types),
mirroring the hierarchy. Map tap-to-clear keeps its current semantics where safe (clears POI first, then floor,
then building).

## 7. Services

Definition: a **service** is a POI category (`EntityCategory`) such as Toilets, Cafeteria, Library, Lab.

Scope behavior:

- **No building selected (campus scope)** — results come from the bulk-loaded campus index (all buildings).
- **Building selected** — results restricted to POIs with `buid == selectedSpace.buid`.
- **Floor selected** — results restricted to `buid + floorNumber == selectedFloor.floorNumber`.

Result-count behavior:

- **Single result** — map focuses that location; one result card with Directions button.
- **Multiple results** — horizontal carousel; first result selected automatically; map focuses the first result.
- **Zero results** — empty state with hint to widen scope.

Connectors (`pois_type == 'None'`) and doors are excluded from services; entrances/elevators/stairs remain valid
service-like categories only if they surface through `discoverCategoriesFromIndex` (they do today).

## 8. Service Carousel

- Horizontal swipeable carousel (PageView) of result cards.
- On open: **first result is selected automatically** and the camera focuses it.
- Carousel → map: swiping to card B selects B (`selectPoi(B)`) and animates the camera to B; C likewise.
- Map → carousel: tapping a marker selects the POI; the carousel auto-scrolls to that card (controller animation,
  no user-visible jank).
- Selected card is visually highlighted; Directions button on every card invokes the existing destination flow.

## 9. Map States

| State | Trigger | Camera behavior (reuse existing `_animatedMapMove` patterns) |
|---|---|---|
| Campus overview | No selection | Fit all buildings / keep initial GPS centering (existing) |
| Building zoom | Building selected | Animate to building, zoom ≈ 16.5 (existing) |
| Floor zoom | Floor selected | Center on floorplan bounds when valid, `MapConfig.indoorFloorplanZoom` (existing `_checkFloorplanCameraCenter`) |
| POI focus | POI selected | Animate to POI, zoom ≈ 18 (existing) |
| Service location focus | Service result selected | Same as POI focus |

Follow-mode / navigation camera logic remains untouched and continues to take priority during active sessions.

## 10. Bottom Sheet

- Always-present dynamic content area docked to the bottom of the map screen.
- Collapsed (~12–14%): drag handle + one-line context title (e.g. building name, service type, "Campus").
- Expanded (~45%): the full context content; drag on handle/header only (existing pattern), body scrolls freely.
- Snap points with animation (reuse `MapBottomSheet` mechanics).
- During active navigation the sheet yields to NavigationStatusBar/ArrivalBanner exactly as today.

## 11. Visual Design

- Keep `AppTheme` (red primary #D32F2F, white cards, thin borders #E8E8E8, Material 3).
- Rounded 14–20px radii consistent with existing cards/chips.
- Segmented switch: pill-style toggle using primary color for the active segment.
- Service tiles: icon in tinted rounded square (existing `EntityCategory.icon/color`) + label.
- Result cards: reuse `SearchResultCard` proportions; selected card gets primary border/tint.
- Typography: existing weights (w700/w800 titles, 12–13px secondary text).

## 12. Implementation Phases

| Phase | Name | Depends on |
|---|---|---|
| 0 | Investigation & Planning | — |
| 1 | Main Screen / Layout Foundation (map-first shell + dynamic area container) | 0 |
| 2 | Search + From/To UI | 1 |
| 3 | Campus Buildings UI (Buildings\|Services switch, building list) | 1 |
| 4 | Building → Floors → POIs | 3 |
| 5 | Services UI + Context Filtering | 3 |
| 6 | Service Results + Carousel | 5 |
| 7 | Map ↔ Selection Synchronization | 6 |
| 8 | Visual Polish + Responsive UX | 1–7 |
| 9 | Final Integration & Verification | 0–8 |

Global verification command for every phase:

```
flutter analyze
flutter test
```

Run from the app root (`clients/flutter/anyplace_campusfind`). Phases must additionally run any phase-relevant test
files named in their prompts.

---
---

# Phase Prompts

Each prompt below is self-contained and must be executed one phase at a time, in order, each followed by its own
report under `docs/ui-ux-redesign/`.

---

## Phase 0 — Investigation & Planning

### Implementation Prompt

**Responsible for:** read-only investigation of the codebase and production of this plan document plus the Phase 0
report. NO feature code changes.

**Must implement:** architectural assessment (what exists / reusable / needs redesign / files likely to change /
functionality that must remain untouched); this plan; report scaffolding.

**Must NOT modify:** any file under `lib/`, `test/`, `android/`, `pubspec.yaml`.

**Acceptance criteria:**
1. Plan document exists with all required sections (1–12) and one prompt per phase.
2. Phase 0 report exists with the assessment.
3. Master report exists with status IN PROGRESS.
4. Zero source modifications (verifiable via git status).

**Verification:** `git status` shows only new files under `docs/ui-ux-redesign/`.

---

## Phase 1 — Main Screen / Layout Foundation

### Implementation Prompt

**This phase is responsible for:** converting the app landing experience from the two-tab `MainShell` (Home/Map)
into the single map-first screen with the always-present dynamic content area container.

**Must implement:**
1. New main screen layout: full-screen `MapScreen` body + top bar placeholder (empty search-styled field, reserved
   for Phase 2; avatar button opening the existing `ProfileScreen`) + bottom dynamic content area widget
   (`CampusContentPanel`) with collapsed/expanded snap behavior (collapsed ≈ handle+context title, expanded ≈ 45%),
   reusing the drag mechanics of `MapBottomSheet`.
2. Campus context content initially renders the existing building list (name + bucode rows) so the screen is usable;
   the Buildings|Services switch itself arrives in Phase 3 — for now a simple "Buildings" section title suffices.
3. Preserve, without modification where possible: offline banner, bulk-load progress bar, NavigationStatusBar +
   ArrivalBanner layering, error banner, `MapControls` (zoom/recenter/reload), GPS initial centering.
4. Retain Quick Access + Recent Waypoints by mounting the existing `_QuickAccessList`/`_RecentWaypointsList` widgets
   (promote them from private to library-public in `home_screen.dart` or move them to `lib/widgets/` — mechanical move
   only) inside the campus panel below the building list.
5. Remove the bottom `NavigationBar` tabs. The leave-map-tab navigation-termination policy becomes a no-op; document
   this in the phase report (navigation termination still exists via explicit End controls).
6. Update the directly affected tests (`widget_test.dart`, `shell_gate_test.dart`) to the new shell reality without
   weakening their assertions about navigation safety; `home_quick_access_test.dart` should keep passing via the moved
   widgets.

**Must NOT modify:** `SpaceProvider`, `NavigationController`, `LocationProvider`, repositories, route request logic,
floorplan overlay pipeline, marker rendering internals, positioning of any kind.

**Reuse:** `MapScreen` (as-is), `MapBottomSheet` snap/drag mechanics, `AppTheme`, `ProfileScreen`,
Quick Access/Recents widgets, `shellTabProvider` (kept for compatibility; map index constant preserved).

**Acceptance criteria:**
- App lands directly on the map-first screen; no bottom tab bar.
- Dynamic area is present at launch (campus context), draggable between ≥2 snap points.
- Selecting a building from the list still selects the space and the map animates to it (existing provider calls).
- Active-navigation overlays still render above/below the panel without overlap regressions.
- `flutter analyze` clean; `flutter test` passes including updated shell tests.

**Verification steps:** `flutter analyze`; `flutter test test/widget_test.dart test/shell_gate_test.dart test/home_quick_access_test.dart`; manual run checklist recorded in the phase report.

**Expected report:** `docs/ui-ux-redesign/phase-1-report.md`.

---

## Phase 2 — Search + From/To UI

### Implementation Prompt

**Responsible for:** the top Search/Directions bar with From/To semantics, wired ONLY to existing features.

**Must implement:**
1. Top bar: tappable search field ("Search buildings, rooms, services…") opening a search overlay (full-screen modal
   route is acceptable, mirroring current `SearchScreen` push pattern).
2. From/To row inside the search overlay:
   - From: defaults to "My Location"; tap opens a picker listing search results + recents; custom From is stored as
     either My Location or a resolved POI.
   - To: free-form search field; selecting a result resolves the destination chain (buildings via `selectSpace`,
     POIs via existing `navigateToPoi`), closes the overlay, and switches the dynamic area to the matching context.
3. Suggestions while typing come from the existing `SearchService.query` (POIs today); when the query is empty show
   OPTIONAL recommendations (recents/quick access/top matches). Recommendations are never mandatory.
4. Swap action to exchange From/To values (UI-level only).
5. "Directions" confirmation: when both From and To are set, expose a Directions action:
   - From == My Location → call the existing flow (`navigateToPoi` then `requestRouteToSelectedPoi`, i.e. what
     PoiDetailCard already does — no new routing code).
   - From == a POI → NEW additive method on `SpaceProvider`
     (e.g. `requestRouteBetweenPois(PoiModel origin, PoiModel destination)`) that wraps the EXISTING
     `NavigationRepository.getRouteBetweenPois(fromPuid:, toPuid:)` used today as Strategy 2. No algorithm edits.
   - From is a building (not a POI) → fall back to My Location with a visible notice.
6. Search independence: opening/dismissing search never mutates the dynamic content state.
7. Extend `SearchService.query` with an optional `includeSpaces`/`includeFloors` flag (default false = unchanged) so
   buildings and floors can appear as suggestions; the legacy directory page behavior stays byte-identical by default.

**Must NOT modify:** route calculation internals (`requestRouteToSelectedPoi` strategy cascade), positioning,
radiomap/floorplan pipelines, `NavigationController` state machine.

**Reuse:** `SearchService`, `SearchResultCard`, `openSearchResult` resolution logic, `QuickAccessItem` recents,
`SpaceProvider.navigateToPoi/_navigateToIdentifier`, `NavigationRepository.getRouteBetweenPois`.

**Acceptance criteria:**
- From shows "My Location" by default and can be changed; To search works for POIs and buildings.
- Selecting To lands the map on the destination and updates the dynamic area context.
- Directions with From=My Location produces a route via existing flows (visible polyline).
- Directions with From=custom POI uses POI-to-POI routing (observable in logs/polyline) without touching algorithms.
- Dismissing search leaves the previous dynamic-area context intact.
- `flutter analyze` clean; `flutter test` passes; add a focused unit test for the additive `requestRouteBetweenPois`
  wrapper and the extended query flag.

**Verification:** `flutter analyze`; `flutter test test/search_filter_test.dart` plus full suite; manual checklist in report.

**Expected report:** `docs/ui-ux-redesign/phase-2-report.md`.

---

## Phase 3 — Campus Buildings UI

### Implementation Prompt

**Responsible for:** the campus context of the dynamic area: `Buildings | Services` segmented switch (Buildings
default) and the Buildings browsing experience.

**Must implement:**
1. Segmented switch widget (pill style, `AppTheme`-based). State held in a small Riverpod `StateProvider`
   (e.g. `campusPanelTabProvider`, enum {buildings, services}); Buildings is the default.
2. Buildings tab: scrollable list of `SpaceProvider.spaces` (name, bucode, distance-if-available later), tap =
   existing `selectSpace(space)`; the map animates (Phase 1 wiring already does this via map screen listener or direct
   call consistent with current `_onBuildingTapped`).
3. Selecting a building switches the dynamic area context from Campus → Building (context state added in this phase,
   e.g. `panelContextProvider`) and shows the building title in the collapsed bar.
4. Back affordance from Building context to Campus (chevron/back row).
5. Services tab renders a placeholder empty-state ("Services arrive in Phase 5") — no service logic yet.
6. Map tap-on-empty-area currently clears selection; keep behavior but ensure clearing returns the panel to Campus
   context.

**Must NOT modify:** `SpaceProvider` selection internals, markers, camera logic beyond calling the existing animate
helper, search, services data.

**Reuse:** `SpaceModel`, `SpaceProvider.spaces/selectedSpace/selectSpace/clearSelection`, `AppTheme`,
`EntityCategory` icons where helpful, Phase 1 panel container.

**Acceptance criteria:**
- Switch toggles Buildings/Services; Buildings is default at cold start.
- Tapping a building zooms the map and moves the panel to Building context with correct title.
- Back returns to Campus context without losing the building selection unless the user clears it.
- No regression in navigation overlays.
- `flutter analyze` clean; `flutter test` passes.

**Verification:** `flutter analyze`; `flutter test`; manual checklist in report.

**Expected report:** `docs/ui-ux-redesign/phase-3-report.md`.

---

## Phase 4 — Building → Floors → POIs

### Implementation Prompt

**Responsible for:** the Building context content (floors) and Floor context content (POIs), converging on the
Destination state.

**Must implement:**
1. Building context: floors chip row driven by `SpaceProvider.floors` incl. loading/error/empty states (same states as
   `BuildingDetailCard._buildFloorsSection`, restyled; extract or duplicate minimally — prefer extraction into a shared
   widget if trivially safe, otherwise restyled copy is acceptable and must be documented).
2. Selecting a floor calls existing `selectFloor(floor)`; panel transitions to Floor context; map centers per the
   existing floorplan camera logic (no camera edits).
3. Floor context: POI list for the loaded floor (`SpaceProvider.pois`) filtered with the SAME navigable rules as today
   (exclude connector/entrance/door via `PoiClassification`), tap = `selectPoi(poi)` → Destination context.
4. Destination context: reuse `PoiDetailCard` (or a thin wrapper around it) with Directions invoking the EXISTING
   preview/start/retarget flow exactly as `map_bottom_sheet.dart` does today.
5. Back chain: Floor → Building → Campus; selecting another building resets floor context (provider already does this).
6. Keep status badges (floorplan/POI/route) available in expanded state — reuse existing badge builders if extraction
   is safe, else document duplication.

**Must NOT modify:** floor/RadioMap/floorplan/POI loading pipelines, `selectFloor` internals, route cascade,
connector handling in navigation.

**Reuse:** `SpaceProvider.floors/selectedFloor/selectFloor/pois/selectPoi`, `PoiClassification`,
`PoiDetailCard` actions incl. `startRoutePreview/startActiveNavigation/retargetDestination`, badge widgets.

**Acceptance criteria:**
- Building select → floors appear; floor select → floorplan overlay + POIs appear; POI select → destination card with
  working Directions (polyline + start/stop navigation intact).
- Loading/error/empty floors and POIs states render sensibly.
- Back chain works; map tap-clear semantics preserved.
- Existing navigation tests unaffected: `flutter test test/navigation_ui_test.dart test/navigation_state_machine_test.dart`.
- `flutter analyze` clean; `flutter test` passes.

**Expected report:** `docs/ui-ux-redesign/phase-4-report.md`.

---

## Phase 5 — Services UI + Context Filtering

### Implementation Prompt

**Responsible for:** the Services tab of the campus context: service-type grid + scope rules.

**Must implement:**
1. Replace the Phase 3 placeholder with a service-type grid derived from `SearchService.discoverCategoriesFromIndex()`
   (existing method) rendered with `EntityCategory.icon/color/label`.
2. NEW pure helper `lib/services/service_query.dart` (or `lib/utils/`): given (category, selectedSpace?, selectedFloor?,
   campus index items, current-floor pois) return scoped results:
   - campus scope: POIs of that category from the bulk-loaded index (exclude connectors/doors);
   - building scope: same filtered by `buid`;
   - floor scope: filtered by `buid + floorNumber` (prefer `SpaceProvider.pois` when that floor is the selected one).
   Pure function + unit tests; NO repository/API changes.
3. Choosing a service type stores the active service (Riverpod StateProvider, e.g. `activeServiceProvider`) and moves
   the panel to the Service context (results arrive in Phase 6 — interim: show count summary).
4. Scope indicator line in Service context showing current scope (Campus / building name / floor name).
5. If a floor/building selection changes while a service is active, recompute scope reactively (watch providers).
6. Zero-result categories render a disabled-looking tile or an explanatory empty state.

**Must NOT modify:** bulk-load pipeline, repositories, POI models, classification utilities.

**Reuse:** `SearchService` index + `discoverCategoriesFromIndex`, `EntityCategory`, `PoiClassification`,
`SpaceProvider.selectedSpace/selectedFloor/pois`, theme.

**Acceptance criteria:**
- Grid lists real categories present in the loaded dataset.
- Unit tests prove scoping: campus vs building vs floor produce correctly filtered results for a fixed fixture.
- Choosing a type enters Service context with scope label reflecting current selection.
- Changing building/floor while a service is active updates the scope/results reactively.
- `flutter analyze` clean; new tests pass; full `flutter test` passes.

**Expected report:** `docs/ui-ux-redesign/phase-5-report.md`.

---

## Phase 6 — Service Results + Carousel

### Implementation Prompt

**Responsible for:** rendering service results with single/multiple behavior and the carousel widget.

**Must implement:**
1. Service context content = results of the active service via Phase 5 helper:
   - 0 results → empty state (scope-aware copy).
   - 1 result → single result card (name, category, building/floor subtitle) + Directions button; selecting focuses
     map on it (call `selectPoi` + existing focus zoom pattern used by POI taps).
   - ≥2 results → horizontal carousel (`PageView` with viewportFraction < 1): cards identical to single card.
2. First result is auto-selected on entering results: `selectPoi(first)` once (guard against repeat selection loops).
3. Camera focuses the selected result using the existing POI-focus approach (animate to `poi.latLng`, zoom ≈18) —
   implemented via the same callback channel the map screen exposes; no new camera subsystem.
4. Every card has Directions invoking the existing destination flow (same as Phase 4 destination card).
5. Back from results returns to service-type grid; changing service type resets selection cleanly.

**Must NOT modify:** marker rendering internals, camera follow-mode logic, route cascade.

**Reuse:** `SpaceProvider.selectPoi`, existing `_animatedMapMove` exposure pattern, `PoiDetailCard`-style actions,
theme/card styling.

**Acceptance criteria:**
- Single-result service shows one focused card; multi-result service opens carousel with FIRST selected and focused.
- Card Directions triggers the existing route flow (observable polyline).
- No redundant `selectPoi` churn (selection stable across rebuilds).
- `flutter analyze` clean; `flutter test` passes; add widget/unit coverage for carousel selection initialization.

**Expected report:** `docs/ui-ux-redesign/phase-6-report.md`.

---

## Phase 7 — Map ↔ Selection Synchronization

### Implementation Prompt

**Responsible for:** bidirectional sync between carousel/cards and map markers within service scope, plus scoped
marker display.

**Must implement:**
1. Carousel → map: page change (swipe settle) selects that POI (`selectPoi`) and animates camera to it. Debounce/guard
   so programmatic selection caused by marker taps does not fight the user's swipe.
2. Map → carousel: tapping a service-scope marker selects the POI; carousel animates to the corresponding card
   (controller.animateToPage). Marker ids already use `puid` — reuse.
3. Scoped markers: while a service is active, map shows markers for CURRENT SCOPE results (category-filtered) instead
   of all floor POIs, implemented by feeding the filtered list into the existing marker build path; restore normal
   markers when service deactivated. Connector exclusion identical to today.
4. Selected marker visual distinction (existing selected-icon mechanism or highlight color) consistent with building
   selection treatment.
5. Deactivating the service (back to grid, switching to Buildings tab, clearing selection) restores prior marker
   behavior with no stale selections.

**Must NOT modify:** marker bitmap generation, floorplan overlays, polylines, navigation follow-camera.

**Reuse:** existing marker sets/cache in `_MapScreenState`, `MarkerId(puid)` convention, `selectPoi/clearSelectedPoi`,
camera helpers.

**Acceptance criteria:**
- Swipe A→B: camera follows B; B→C likewise (manual verification script in report).
- Tap marker C: carousel scrolls to C's card and marks it selected.
- Markers during active service match the scoped result set; exiting service restores previous markers.
- No selection feedback loop/jitter (guard test or documented manual evidence).
- `flutter analyze` clean; `flutter test` passes.

**Expected report:** `docs/ui-ux-redesign/phase-7-report.md`.

---

## Phase 8 — Visual Polish + Responsive UX

### Implementation Prompt

**Responsible for:** final visual/behavioral refinement pass across the redesigned surfaces.

**Must implement:**
1. Consistent snap points, paddings, radii, shadows across top bar, panel, cards, carousel.
2. Small-screen checks: panel expanded height ≤ 45%, lists scroll, carousel cards readable at 360dp width; large
   phones: no stretched emptiness (cap content width where sensible).
3. Empty/loading/error parity everywhere (buildings, floors, POIs, services, results, search suggestions).
4. Accessibility basics: min touch targets 44dp, contrast per existing palette, semantic labels on icon buttons.
5. Motion polish: snap animations ~250–300ms easeOutCubic (match existing), camera animations unchanged.
6. Remove dead UI left behind by the redesign (old floating search button in `MapControls` if superseded, unused
   imports), keeping `MapControls` zoom/recenter/reload.

**Must NOT modify:** any state/logic layer; polish is presentation-only except dead-code removal tied to replaced UI.

**Acceptance criteria:**
- Checklist in report covering all contexts on phone-size viewport.
- No analyzer warnings introduced; `flutter test` green.

**Expected report:** `docs/ui-ux-redesign/phase-8-report.md`.

---

## Phase 9 — Final Integration & Verification

### Implementation Prompt

**Responsible for:** end-to-end verification of the whole target UX and closure documentation.

**Must implement:**
1. Execute the full acceptance walkthrough of PART 9 behaviors (initial campus, buildings, floors, POIs, services
   single/multi/carousel/scope) and record results.
2. Run full gates: `flutter analyze`, `flutter test` (all files), record outcomes verbatim in the report.
3. Cross-check the strict scope boundary: confirm via diff review that no positioning/routing/backend files were
   functionally modified (list exceptions with justification — expected: none beyond documented additive wrappers).
4. Finalize Master Report: overall status, cumulative issues/deviations/files, final assessment.

**Must NOT modify:** feature behavior; fixes discovered here go through a targeted mini-cycle with its own notes in
the Phase 9 report.

**Acceptance criteria:** every PART 9 bullet demonstrably works or is explicitly listed as an issue with impact;
Master Report completed with final assessment.

**Expected report:** `docs/ui-ux-redesign/phase-9-report.md` + updated `UI_UX_REDESIGN_MASTER_REPORT.md`.

---

## Appendix A — Functionality That Must Remain Untouched

- `lib/data/datasources/*` (positioning, GPS, heading, caches) — call-only.
- `lib/data/repositories/*` (routing, cross-building router, radiomap, floorplan, space, poi) — call-only; the ONLY
  permitted addition is the Phase 2 additive POI→POI wrapper exposed on `SpaceProvider` wrapping the existing
  repository method.
- `NavigationController` state machine, follow mode, retarget protocol — call-only.
- RadioMap/floorplan download + overlay cache pipeline — call-only.
- INV-4/INV-5 browsing-neutrality guarantees — must not be weakened.
- Server, other clients, Android-native code — untouched.

## Appendix B — Known Risks

| Risk | Mitigation |
|---|---|
| Shell change (removing tabs) breaks navigation-termination policy assumptions in tests | Phase 1 updates affected tests explicitly; policy becomes no-op and is documented |
| Campus-wide service results depend on progressive bulk-load completion | Scope indicator + partial-results note; queries hit whatever index exists (same data the directory search already uses) |
| `poisType` is free-form (no backend validation) | Reuse `CategoryDeriver` substring mapping; unknowns bucket into `other` exactly like today |
| Dual state management could cause context drift | All new panel state centralized in Riverpod providers; domain state remains the single source of truth |
