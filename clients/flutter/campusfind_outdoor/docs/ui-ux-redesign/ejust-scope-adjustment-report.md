# E-JUST Scope Adjustment Report

Post-Phase-9 scope refinement — **small filtering change only**; no UI/UX redesign, no behavior change, no
re-run of Phases 0–9.

## What was changed

The app now treats **E-JUST** as the explicit global parent scope of every browsing/search surface:

1. **Campus identity** (`lib/config/constants.dart`): `primaryCampusCuid` / `primaryCampusName` now represent
   E-JUST (`ejust` / `E-JUST`) instead of the stale upstream UCY defaults. Both remain overridable at build time
   via `--dart-define=CAMPUS_CUID=... --dart-define=CAMPUS_NAME=...`. The single-campus design is unchanged —
   still no campus picker.
2. **Single filtering point** (`SpaceProvider.loadSpaces`): after fetching buildings, the list is narrowed with
   `CampusScope.filterSpaces(...)`. Because the panel list, map building markers, search index
   (`SearchService.addSpaces/addFloors/addPois` + bulk-load) and service scoping all consume `_spaces`, floors,
   POIs and services inherit E-JUST scope structurally — one rule, applied once.
3. **Optional campus ownership field**: `SpaceModel` now parses an optional backend-supplied `cuid`
   (fromJson/toJson/copyWith). Nothing is invented client-side; payloads without a campus id are untouched.
4. **Scope indicator text**: the services scope line now shows the global parent explicitly —
   `E-JUST` (campus), `E-JUST › <Building>`, `E-JUST › <Building> · Floor <floor>` — replacing the previous
   "Entire campus"/building-only wording. Behavior (reactive re-scoping) unchanged.

Everything else — layout, From/To search UX, carousel, camera zooms, Directions/navigation flows, Quick Access,
Recent Waypoints, Profile, snap behavior, theme — is byte-identical to the completed redesign.

## How E-JUST scope is determined

Isolated helper `lib/utils/campus_scope.dart` (`CampusScope`), data-driven with a safe fallback:

- Entity carries a campus id (`space.cuid`) **and it differs** from `AppConstants.primaryCampusCuid`
  → excluded (foreign campus on a shared backend).
- Entity carries **no** campus id → treated as in-scope (a dedicated E-JUST deployment's payloads belong to
  E-JUST by definition; keeps the app working against an E-JUST-only server without any identifier knowledge).
- The active campus id/name come from `AppConstants.primaryCampusCuid/primaryCampusName`
  (`--dart-define` overridable).

Floors and POIs are never filtered separately: they are only loaded per `buid` of in-scope buildings
(`loadFloorsForSelectedSpace`, bulk-load iterates `_spaces`), so ownership is inherited structurally.

## Files modified

| File | Change |
|---|---|
| `lib/config/constants.dart` | Campus identity = E-JUST (dart-define overridable); docs updated |
| `lib/data/models/space_model.dart` | Optional parsed `cuid` field (fromJson/toJson/copyWith only) |
| `lib/utils/campus_scope.dart` | **NEW** — isolated `CampusScope` helper (~40 lines) |
| `lib/state/space_provider.dart` | One filter line in `loadSpaces` (+ import) |
| `lib/services/service_query.dart` | Scope label shows global E-JUST parent (text only) |
| `test/ejust_scope_test.dart` | **NEW** — 7 tests for helper/model/provider filtering |
| `test/service_query_test.dart` | Label expectations updated |
| `test/campus_panel_test.dart` | One label expectation updated |

Not modified: repositories, datasources/API client, navigation/routing logic, `NavigationController`,
`LocationProvider`, all widgets/UI of the redesign, theme.

## Tests executed and results

| Gate | Result |
|---|---|
| `flutter analyze` | **56 issues — identical to the pre-adjustment baseline**, all in pre-existing legacy files or the foreign `remediation_*` test files. Zero issues in any file touched by this adjustment. |
| New scope tests (`ejust_scope_test.dart`) | 7/7 pass (null-cuid inclusion, foreign-cuid exclusion, payload filter, cuid parse/normalize/round-trip, provider-level downstream scoping) |
| Updated suites (`service_query_test`, `campus_panel_test`) | all pass (label expectations updated) |
| Full bundle (all redesign suites) | **77/77 pass** |
| Full `flutter test` | **310 pass / 7 fail** — same 3 pre-existing floorplan failures + 4 foreign remediation-file loading failures as before this adjustment; zero new failures |

Manual verification mapping (per brief):

- Campus view shows only E-JUST buildings → enforced by the single filter point (unit-tested).
- Services (no building) → E-JUST services only → index derives from filtered spaces (structurally guaranteed).
- Building → Services restricted to that building → existing Phase-5 scoping, unchanged, still passing.
- Floor → Services restricted to that floor → unchanged, still passing.
- Search returns no entities outside E-JUST → search index built exclusively from in-scope spaces/floors/POIs.
- Carousel / map sync / Directions / navigation flows → all existing suites green, zero code changes to those paths.
- No positioning/routing/backend logic changed → diff audit: only the files listed above.

## Issues encountered

- The public Anyplace endpoint could not be probed from this machine (HTTP 404 via curl/PowerShell, likely
  network/UA restrictions), so live payload inspection wasn't possible. The implementation therefore uses the
  defensive dual-mode rule above: precise exclusion when the backend identifies campus ownership, pass-through
  when it doesn't. If the E-JUST deployment later exposes per-building `cuid`s with a different id than the
  configured default, override once via `--dart-define=CAMPUS_CUID=<real>` — no code change needed.
- Two stale UCY references remain intentionally: `ApiConfig._defaultBaseUrl` (the actual server this client
  currently points at; changing endpoints is a deployment concern, not scope filtering) and historical comments in
  old phase reports (immutable history).

## Preservation confirmation

Diff audit confirms the ONLY functional delta of this adjustment is the load-time building filter plus optional
`cuid` parsing and label text. Map-first layout, From/To bar, dynamic panel, Buildings|Services switch, hierarchy,
destination card, service grid, scope reactivity, single/multi result behavior, carousel, first-result
auto-selection, both synchronization directions, camera behavior, Directions/navigation flows, Quick Access,
Recent Waypoints, Profile, snap behavior, theme and responsive behavior are preserved exactly as delivered by
Phases 1–8 (verified by the full redesign test bundle).
