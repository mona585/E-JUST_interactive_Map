# UI/UX Redesign Master Report

> **POST-PHASE-9 CORRECTION PASS — Map/Markers/Services/Routing/Panel:** Quick Access & Recent Waypoints removed
> from the redesigned UI (destinations now served by a new **Places** service type over real E-JUST buildings);
> service-result routing root-cause fixed (full building→floor→POI chain via existing `navigateToPoi` before
> preview/start); Building context regained **Route Here** (existing `requestRouteToBuilding`); route-preview clamp
> bug fixed (`[19,19]`→`[14,19]`) with pure unit-tested `computeRouteCamera`; modern pin markers (square building
> badges / circular category POI badges + selected states); building zoom 17; floor fallback centering; initial
> panel confirmed collapsed. Gates: bundle 79/79+new tests (**camera 5/5, nav-bar 2/2**), full suite
> **325 pass / 7 known failures**, analyzer 56 = unchanged baseline. Details:
> `navigation-and-campus-ui-correction-report.md`.
>
> **ADDENDUM to Correction Pass:** initial camera now fits the provided **E-JUST campus bounds**
> (SW 30.8554722,29.5613611 · NE 30.8625556,29.5677222) on every campus-overview entry (first frame
> included, GPS-camera one-shot suppressed while overview owns the camera; all other camera states
> untouched), and entity markers were rebuilt as hi-res bitmaps displayed at compact logical sizes
> (POI 20dp / selected 22dp / building 24dp / selected building 26dp) fixing size+pixelation.
> Bounds conversion pinned by test. Full suite **326 pass / 7 known**; analyzer baseline unchanged.
>
> **ADDENDUM 2:** Buildings grid now **4 cards/row** on phones (compact cards, responsive to 5 on wide);
> service-type grid responsive (4 cols ≥430dp); visible edge-aware **carousel arrows** added to both
> result carousels, synchronized through the existing PageController listener (no second state source).
> Bundle/gates unchanged (326 pass / 7 known).

> **POST-PHASE-9 REFINEMENT 1 — E-JUST scope:** campus identity `ejust`/E-JUST, single load-time building filter via
> new `CampusScope` helper, optional `cuid` parsing, E-JUST parent in the scope label. Details:
> `ejust-scope-adjustment-report.md`.
>
> **POST-PHASE-9 REFINEMENT 3 — Backend migration to the E-JUST server:** default `baseUrl` switched to
> **`https://map.beout.ai`** (`--dart-define=SERVER_URL` override preserved); one-time silent dataset-epoch
> migration wipes old-backend Quick Access / Recent Waypoints / disk caches (Quick Access re-seeded from the new
> server's six verified entities); fallback map center moved to the E-JUST centroid. Verified live: spaces/floors/
> POIs/floorplans all green; ⚠️ **no radiomaps published yet** on the new server (indoor Wi-Fi positioning reports
> unsupported and the app degrades to GPS — existing graceful path, no client workaround added; flagged for the
> Architect). Gates: new server_config tests 7/7, bundle 77/77, full suite **319 pass / 7 known failures**
> (unchanged), analyzer 56 = unchanged baseline. Details: `ejust-server-migration-report.md`.
>
> **POST-PHASE-9 REFINEMENT 2 — Navigation UX + Campus Panel:** viewport-aware whole-route fit on "Route Here";
> "Start Directions" switches to the EXISTING follow-mode camera (nav zooms, lower-third) instead of refitting;
> compact navigation bottom bar replaces the panel during active navigation (✕ = existing termination, ↑/tap
> re-opens panel without ending navigation); Buildings rendered as a responsive card grid with the duplicate count
> removed. Details: `navigation-and-campus-ui-refinement-report.md`. Gates: bundle 79/79, full suite 312 pass /
> 7 known failures (unchanged), analyzer 56 = unchanged baseline, zero new issues.

## Overall Status

COMPLETED WITH ISSUES

All 10 phases (0–9) executed. The complete UI/UX is implemented and every redesign-scoped test passes.
Residual issues are (a) pre-existing failures outside the redesign, (b) foreign files contaminating full-suite
counts, and (c) device-visual confirmations queued for a manual run — none block the delivered functionality.

Scope honored strictly: Flutter client only; positioning/routing algorithms/backend untouched
(one additive wrapper around an EXISTING repository API, documented).

## Phase Status

| Phase | Status | Major Issues |
|-------|--------|--------------|
| 0 — Investigation & Planning | PASS | None |
| 1 — Main Screen / Layout Foundation | PASS WITH ISSUES | Pre-existing baseline documented |
| 2 — Search + From/To UI | PASS WITH ISSUES | Foreign remediation files contaminate gates (#7) |
| 3 — Campus Buildings UI | PASS | None |
| 4 — Building → Floors → POIs | PASS | None |
| 5 — Services UI + Context Filtering | PASS | ISSUE-9 narrow-host overflow found & fixed |
| 6 — Service Results + Carousel | PASS | None |
| 7 — Map ↔ Selection Synchronization | PASS | Marker visuals: device confirmation in Phase 9 checklist |
| 8 — Visual Polish + Responsive UX | PASS | None |
| 9 — Final Integration & Verification | PASS WITH ISSUES | See Final Assessment |

## Completed Phases (summary)

- **0 Planning** — read-only audit; plan + per-phase prompts; no source changes.
- **1 Layout foundation** — map-first single screen: `MapTopBar` over full-screen `MapScreen` with always-present
  `CampusContentPanel` (14/45% snap). Navigation banners layered above panel; building-focus camera centralized;
  Quick Access/Recent Waypoints extracted to public widgets; shell tests rebuilt on a Google Maps platform fake.
- **2 Search + From/To** — overlay with From (My Location default, POI origins), To across POIs/buildings/floors via
  opt-in `includeSpacesAndFloors`, optional recents/suggestions, swap, Directions through existing flows + additive
  `SpaceProvider.requestRouteBetweenPois` (unit-tested).
- **3 Campus buildings** — Buildings|Services pill switch (default Buildings), Building context with Back that
  preserves selection/zoom, same-buid re-entry handled UI-side.
- **4 Floors → POIs → Destination** — floors chips w/ state parity, navigable POI list (connector/entrance/door
  filtered), Destination view embedding existing `PoiDetailCard` with retarget/preview wiring; route-bounds fitting
  restored behind `routeBoundsFitterProvider`.
- **5 Services scoping** — pure `service_query.dart` (campus/building/floor; connector+door excluded) unit-tested;
  type grid from existing index with scoped counts & disabled zero-results; active-service state; reactive scope.
- **6 Results + carousel** — single card / PageView carousel (.88), one-shot first-result auto-select + camera focus
  bridge (`mapFocusRequesterProvider`), shared `_startDirectionsForPoi` for cards & destination.
- **7 Map↔selection sync** — scoped markers during active service (same helper as panel), selected-result hueOrange,
  cache signature update; map→carousel via external-selection sync (tested).
- **8 Polish** — dead sheets deleted; floating search button removed; touch targets ≥44dp; phone-viewport layout
  verified by tests.
- **9 Verification** — gates recorded verbatim; scope-boundary diff audit clean; PART-9 walkthrough table completed.

## Global Problems / Issues

| # | Phase | Problem | Impact | Current status | Resolution / workaround | Related files |
|---|-------|---------|--------|----------------|--------------------------|---------------|
| 1 | pre-existing | `floorplan_state_pipeline_test.dart` fails to compile (fake override signature); `floorplan_download_resilience_test.dart` ×2 timing failures | Suite always ≥3 red | UNRESOLVED (out of scope) | Proven unrelated via import graph; flagged for owner | `poi_repository.dart`, two floorplan tests |
| 2 | 1 tooling | `flutter test` crashes when run from repo root (Windows native-assets collision) | None from app dir | RESOLVED (workflow) | Gates run from app dir | repo-root layout |
| 3 | 1 | Mojibake legacy bytes defeated exact-match edits in `map_screen.dart` | Editing friction | RESOLVED for touched blocks | UTF-8 line-splice | `map_screen.dart` |
| 4 | 0→1 | Two-tab shell vs map-first target; tab-leave termination obsolete | Resolved by design | RESOLVED | Tabs removed; sessions end via explicit End controls | `main_shell.dart` |
| 5 | 0 (obs.) | Campus service results rely on progressive bulk-load index (partial until synced) | Minor UX after cold start | MITIGATED | Scope line + reactive queries over indexed data | `search_service.dart`, `bulk_load_provider.dart`, `space_provider.dart` |
| 6 | 2 | Custom "From" functional only POI→POI (existing API constraint); else My Location fallback w/ notice | Documented limitation | MITIGATED | Additive wrapper; visible fallback notice | `space_provider.dart`, `directions_provider.dart` |
| 7 | 2 | FOREIGN untracked `test/remediation_*_test.dart` appeared mid-session referencing non-existent APIs → 4 loading failures + 17 analyzer errors | Inflates failure counts | UNRESOLVED here (fixing = writing unrelated production APIs, forbidden) | Scoped gates quoted separately; owner must relocate/remove | `test/remediation_*.dart` |
| 8 | 3→5 | Nested-scroller gesture flakiness + synthetic-viewport geometry in widget tests | Test-only friction | RESOLVED | Domain-driven steps where gesture wasn't the subject; phone-size test surface | panel tests |
| 9 | 5 | `PoiDetailCard` metadata rows overflowed (~49px) at panel width (previously hosted only in wide sheet) | Destination view broken at narrow widths | **RESOLVED** | Chips + coordinates made shrink-to-fit (Flexible+FittedBox); regression covered at 360dp | `lib/ui/widgets/poi_detail_card.dart` |

Pre-existing analyzer baseline (recorded once): all remaining analyzer output lives outside the redesign diff;
every phase gate verified ZERO new issues in touched files.

## Global Deviations

- Top-bar search interim target was the legacy directory page in Phase 1 → replaced by From/To overlay in Phase 2.
- `_fitRouteBounds` removed in Phase 1 (caller gone), restored Phase 4 behind `routeBoundsFitterProvider`.
- Error banner replaced by top-bar status line (same retry action) — old position permanently occluded by panel.
- Home-tab content re-hosted inside campus panel; `shellTabProvider` kept as inert compatibility no-op.
- Phase 2: dedicated overlay instead of extending the legacy directory page; destinations may be whole buildings.
- Phase 4: floor status badges replaced by inline loading/error rows (info now surfaced contextually).
- Phase 7: selected-marker uses `hueOrange` instead of a new palette entry.

## Files Changed Across All Phases

Created:

- Docs: this report, plan, phase reports 0–9
- `lib/providers/directions_provider.dart`
- `lib/providers/panel_provider.dart`
- `lib/screens/search_overlay.dart`
- `lib/services/service_query.dart`
- `lib/ui/widgets/campus_content_panel.dart`
- `lib/ui/widgets/map_top_bar.dart`
- `lib/widgets/quick_access_list.dart`
- `lib/widgets/recent_waypoints_list.dart`
- `test/helpers/fake_google_maps_platform.dart`
- `test/search_directions_test.dart`
- `test/service_query_test.dart`
- `test/campus_panel_test.dart`

Modified:

- `lib/screens/main_shell.dart` (rewritten)
- `lib/screens/home_screen.dart`
- `lib/ui/screens/map_screen.dart`
- `lib/ui/widgets/map_top_bar.dart`
- `lib/ui/widgets/campus_content_panel.dart`
- `lib/ui/widgets/map_controls.dart`
- `lib/ui/widgets/poi_detail_card.dart` (presentation-only shrink fix)
- `lib/services/search_service.dart` (opt-in flag + additive accessor)
- `lib/state/space_provider.dart` (one ADDITIVE method)
- `test/widget_test.dart`, `test/shell_gate_test.dart`

Deleted (dead UI):

- `lib/ui/widgets/building_search_sheet.dart`
- `lib/ui/widgets/map_bottom_sheet.dart`

## Verification Summary

| Phase | Checks | Result |
|---|---|---|
| 0 | Read-only audit; clean git; toolchain | PASS |
| 1 | analyze 0-new; shell suites 9/9; suite 286/(3 pre-existing) | PASS WITH ISSUES |
| 2 | analyze 0-new; scoped 57/57; suite 290/(3+4 foreign) | PASS WITH ISSUES |
| 3 | analyze 0-new; panel 4/4; bundle 61/61 | PASS |
| 4 | analyze 0-new; panel 5/5 incl. ladder; bundle 62/62 | PASS |
| 5 | analyze 0-new; scoping 6/6; panel 6/6; bundle 63/63; suite 301/(3+4 known) | PASS |
| 6 | analyze 0-new; carousel/swipe/single covered; bundle 70/70 | PASS |
| 7 | analyze 0-new; external-sync asserted; bundle 70/70 | PASS |
| 8 | deletions proven reference-free; bundle 70/70 | PASS |
| 9 | Full `flutter analyze` (56 issues, 0 in diff); full `flutter test` 303 pass / 7 fail (=3 pre-existing + 4 foreign); PART-9 walkthrough; scope audit | PASS WITH ISSUES |

## Remaining Work

- Owner actions (outside redesign scope): relocate/remove foreign remediation tests; optionally repair the
  pre-existing floorplan test compile error and timing cases.
- Optional on-device run of the PART-9 walkthrough (marker colors/scoped set visuals, camera feel, live GPS flows) —
  code paths already covered by tests where feasible.

## Final Assessment

**Successfully implemented (all verified by automated tests):**
map-first single screen with top From/To search (My-Location default, changeable origin incl. functional POI→POI
directions via the existing repository API), destination resolution through the existing selection chain,
Buildings|Services switch, Building→Floors→POIs→Destination ladder, service-type grid with campus/building/floor
scope filtering, single-vs-multi result behavior with auto-focused first result and swipe/marker bidirectional sync,
existing navigation entry points fully wired (preview/start/retarget/end + route-bounds fitting), Quick Access &
Recent Waypoints preserved, offline/error/loading states preserved.

**Not implemented:** nothing from the approved scope. Deliberate limitations per spec: custom origin only between
two resolved places (else My-Location fallback with notice); services limited to categories derivable from existing
`poisType` data.

**Remaining issues:** #1 pre-existing floorplan test failures/analyzer noise; #7 foreign remediation test files
(owner action); manual device-visual confirmations pending.

**Acceptance criteria:** all satisfied at code/test level; the only non-automatable items are explicitly listed as
MANUAL-PENDING above. Technical limitations stem from pre-existing free-form `poisType` categorization order
(e.g., "Restroom" buckets to Room before Toilets) — inherited unchanged, matching current app behavior.
