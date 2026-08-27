# E-JUST Server Migration Report (`map.beout.ai`)

Post-Phase-9 backend migration. Configuration/data-scope change only.
Positioning, Wi-Fi fingerprinting, GPS, route calculation, repositories' algorithms,
`NavigationController`, `LocationProvider` and Android-native code were **not modified**
(diff audit below).

## 1. What was changed

| File | Change |
|---|---|
| `lib/config/api_config.dart` | Compiled-in default `baseUrl`: `https://ap.cs.ucy.ac.cy:44` → **`https://map.beout.ai`**. The `--dart-define=SERVER_URL=…` override is preserved for future environments. |
| `lib/config/constants.dart` | (a) `datasetEpoch = 'beout-2026-08'` + new pref key `dataset_epoch`; (b) `kDefaultQuickAccessLocations` re-pointed to the NEW server's real entities (see table). |
| `lib/services/cache_service.dart` | Additive epoch helpers: `getDatasetEpoch/setDatasetEpoch/consumeDatasetEpochMigration()` — one-time silent wipe of old-backend Quick Access / Recent Waypoints / legacy Saved-POIs prefs, then marker write. Quick Access key is REMOVED (not emptied) so the existing first-run gate re-seeds against the new dataset. |
| `lib/state/space_provider.dart` | (a) `defaultCenter` → E-JUST centroid `30.859877, 29.563241` (fallback-only use unchanged); (b) additive `purgeDatasetCaches()` calling each repository's EXISTING clear-all method (`pois.clearAll / floorplans.clearAll / radiomaps.clearAllCache`). |
| `lib/screens/main_shell.dart` | `_startDataLoading` runs the epoch migration once before anything reads user data or seeds Quick Access; when migrated, purges disk caches. Non-fatal on error. |
| `test/server_config_test.dart` | **NEW** — 7 tests (see §Tests). |

Untouched by this task: Google Maps key/manifest, OSRM outdoor routing, all widgets of the
completed redesign, positioning/navigation state machines, every repository/datasource algorithm.

## 2. How the E-JUST scope is determined on the new server

Live payloads from `map.beout.ai/api/mapping/space/public` carry **no campus id** (fields:
`buid, name, coordinates_lat/lon, is_published, space_type`). The existing `CampusScope` rule
("no cuid ⇒ in scope; mismatched cuid ⇒ excluded") therefore passes the entire new dataset through
with zero configuration — and still protects against foreign campuses if the Architect later adds
`cuid`s. Because floors/POIs are only ever loaded per in-scope `buid`, buildings → services → search
are E-JUST-only by construction.

## 3. New-server verification results (live probes)

| Endpoint | Result |
|---|---|
| `POST /api/mapping/space/public` `{}` | 200 — **6 buildings**: B7, E-JUST Blue Hall, Food court, National Bank branch, E-JUST Administrative Building, E-JUST Library |
| `POST /api/mapping/floor/all` `{buid:B7}` | 200 — floors **0, 1, 2** with bounds metadata |
| `POST /api/mapping/pois/floor/all` `{buid:B7, floor_number:"0"}` | 200 — **28 POIs** (Entrance, Room G01/G02/G06, …) with correct fields |
| `POST /api/floorplans64/{B7}/0` `{}` | 200 — 2,486,788-byte PNG |
| `POST /api/radiomap/space` `{buid,floor}` | ⚠️ **No radiomaps published**: B7 → **500**, other five buildings → **400** |

Re-probe after implementation: spaces 200 / 6 buildings; floorplan B7/0 200 — stable.

### Radiomap constraint (data-readiness issue, reported not worked around)

No building currently has a published radiomap. Consequence: indoor Wi-Fi positioning reports
*unsupported* and the app uses its existing graceful degradation path (GPS sub-state; browsing,
routing UI and GPS navigation unaffected). **No positioning/Wi-Fi/GPS logic was modified** per the
task constraints. Action item for the server owner: upload radiomaps via Architect (and note B7's
500 vs others' 400 suggests a possible server-side difference worth checking).

## 4. Cache migration strategy

Leak-vector audit:

- Spaces & floors caches are in-memory per-process → fresh fetch each launch; no cross-server mixing possible.
- Disk caches (`floorplans/`, `pois/`, `radiomaps/`) are keyed by `buid/floor`; old-server buids can never match new ones → no serving of stale data; files are orphaned space only.
- SharedPreferences were the real leak: persisted Quick Access buids and Recent-Waypoint puids belonged to the old backend.

Migration: `dataset_epoch` marker (`beout-2026-08`). On startup, `MainShell._startDataLoading`
calls `consumeDatasetEpochMigration()`; when it reports a migration, `purgeDatasetCaches()` clears
the three disk caches and Quick Access re-seeds automatically from the updated verified defaults
against the new dataset. Fully automatic and silent; idempotent.

## 5. Quick Access seed re-pointing (confirmed mapping, real buids)

| Label | name (server) | buid (server) |
|---|---|---|
| Library | E-JUST Library | `building_39d12406-5167-4ab6-b01e-1ec5f60e9c48_1787691620141` |
| Blue Hall Cafeteria | E-JUST Blue Hall | `building_90580bbe-a411-47a1-8486-57578e35ffb7_1787691406039` |
| Food Court | Food court | `building_0cee133d-7afc-4c23-8c01-efc53afb33ed_1787691448415` |
| Bank | National Bank branch | `building_d475fb95-a1cb-4d4e-b473-dbc1fedf31a5_1787691464505` |
| B7 *(new)* | B7 | `building_98c4def5-553d-452a-baf2-da184f7b19ee_1787690379788` |
| Administrative Building *(replaces Student Affairs)* | E-JUST Administrative Building | `building_818fac74-6005-4877-bb70-89e307716914_1787691595861` |

Stationery shop removed (entity does not exist on the new server).

## 6. Fallback center

`SpaceProvider.defaultCenter`: `35.1444, 33.4105` (Cyprus) → `30.859877, 29.563241`
(mean of the six live buildings). Used only by existing fallback paths.

## 7. Tests executed

| Suite | Result |
|---|---|
| `test/server_config_test.dart` (**new**, 7 tests) | PASS — default URL pinned to map.beout.ai; fallback center pinned; campus constants pinned; no legacy Quick Access buids remain; epoch migration wipes-and-marks; idempotent second run preserves post-migration data; fresh install touches nothing unrelated |
| Redesign bundle (panel/widget/shell/quick-access/search-directions/search-filter/navigation-ui/service-query/ejust-scope) | **77/77 pass** |
| `flutter analyze` | **56 issues — identical pre-migration baseline**; zero issues in any migration-touched file (`api_config`, `constants`, `cache_service`, `space_provider`, `main_shell`, `server_config_test`) |
| Full `flutter test` | **319 passed / 7 failed** — same 3 pre-existing floorplan failures (#1) + 4 foreign remediation-file failures (#7) as before this migration; zero new failures |

## 8. Delivery

Release APK rebuilt (`build/app/outputs/flutter-apk/app-release.apk`, 53 MB) with the new default
server baked in, installed on CPH2185 (`Success`) and launched. First launch on device performs the
epoch migration silently (old-backend Quick Access/Recent Waypoints cleared, caches purged, defaults
re-seeded against map.beout.ai).

## 9. Scope-preservation confirmation

Diff audit (`git status`/forbidden-set check): the migration delta touches exactly the five lib
files + one test file above. **None** of the protected areas appear in the diff: `LocationProvider`,
`NavigationController`, `navigation_state_model.dart`, `cross_building_router.dart`,
`custom_route_*`, any repository/datasource algorithm file, Android native code, Google Maps config,
redesign widgets. Positioning/routing/navigation/backend-algorithm behavior confirmed unmodified.

## 10. Issues encountered

1. Radiomaps absent server-side (all six buildings) — data-readiness gap, documented above; client
   behavior already graceful.
2. B7's radiomap endpoint returns HTTP 500 while others return 400 — likely a server-side artifact;
   flagged for the Architect.
3. Public UCY endpoint unreachable from this machine during earlier investigation (404 via
   curl/PowerShell) — irrelevant post-migration, noted for history only.
