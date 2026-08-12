# E-JUST CampusFind — Flutter Student App Plan

## Executive Summary

A Flutter mobile app ("CampusFind") for E-JUST students to browse campus buildings, find professors/rooms/cafeterias, view indoor floorplans, and navigate both indoors and outdoors. Android-only for MVP. All real data comes from the existing Anyplace backend — no fake or hardcoded business data.

**Key constraints:**
- No backend schema changes (all rich data encoded in existing `description` fields)
- No user authentication for MVP
- Indoor positioning requires fingerprint data collection (external prerequisite)
- Self-hosted tile server for outdoor maps (infrastructure task)
- Outdoor routing via OSRM public demo (no API key needed)

---

## Product Scope

### In MVP

| Feature | Implementation |
|---|---|
| Campus selection | Multi-campus, user picks on first launch, stored locally |
| Home screen | Greeting, search bar, quick access cards, recent waypoints |
| Campus map | `flutter_map` + self-hosted outdoor tiles + tiled indoor floorplans |
| Dynamic POI filters | Filter chips derived from backend data (not hardcoded) |
| Cross-entity search | Client-side search across all cached Spaces + POIs |
| Building detail | Hero image placeholder, floors directory, accessibility, navigate button |
| Professor profile | Parsed from POI description: name, title, department, office hours |
| Indoor routing | Dijkstra via `/api/navigation/route`, polylines per floor |
| Outdoor routing | OSRM public demo, GPS → building entrance polyline |
| Combined navigation | Outdoor leg (blue) + indoor leg (red) in single view |
| Wi-Fi positioning | Server-side via `/api/position/estimate` (requires fingerprint data) |
| Floorplan tiles | Download zip → extract → `FileTileProvider` on `flutter_map` |
| Recent waypoints | Local persistence (no API) |

### NOT in MVP

- User authentication / login
- Saved bookmarks / Profile tab
- Push notifications
- Building photos (no image field on Spaces)
- iOS support
- Voice guidance / step-by-step directions
- Real-time crowd data for cafeterias
- Menu data for cafeterias
- Time-based heatmap visualization
- Self-hosted OSRM (use public demo server)

---

## Screen Map

```
┌─────────────────────────────────────────────────┐
│  Bottom Navigation (3 tabs)                     │
│  ┌───────────┬───────────┬───────────┐          │
│  │   Home    │    Map    │  Search   │          │
│  └───────────┴───────────┴───────────┘          │
└─────────────────────────────────────────────────┘

Screens:
  1. Home Screen
  2. Map Screen
  3. Search Screen
  4. Building Detail Screen (push navigation)
  5. Professor Profile Screen (push navigation)
  6. Map Screen with Route overlay (same Map screen, different state)
```

### Screen Details

**1. Home Screen**
- Header: app logo + notification bell (placeholder, no push)
- Greeting: "Welcome back, Student" (generic, no auth)
- Heading: "Where are we headed today?"
- Search bar → navigates to Search tab
- Quick Access cards (dynamic, derived from data): Professors, Cafeterias, Buildings, etc.
- Recent Waypoints list (local persistence)
- Bottom nav: Home, Map, Search

**2. Map Screen**
- Header: "University Map" + notification bell (placeholder)
- Filter chips: All | [dynamic categories from backend data]
- `flutter_map` with:
  - Self-hosted outdoor tiles (base layer)
  - Tiled indoor floorplan overlay (per building/floor)
  - Building markers (tap → Building Detail)
  - POI markers (filtered by selected category)
  - User position marker (GPS blue dot)
  - Route polylines (when navigating)
- Bottom sheet: "Nearest Location" (GPS-based nearest building)
- Floor switcher (when building selected)
- Bottom nav: Home, Map, Search

**3. Search Screen**
- Header: "Search Directory"
- Search input with clear button
- Filter chips: All | [same dynamic categories]
- Results list with type badges (PROF, BUILDING, CAFE, LIB, LAB, etc.)
- Each result shows: name, category badge, subtitle, distance, location details
- Tap result → Professor Profile or Building Detail

**4. Building Detail Screen**
- Header: back button + notification bell
- Hero image placeholder (no real image — use gradient/pattern)
- Building name, subtitle (from description: "Main Campus West Quad · Opened 2021")
- Room search input ("Search rooms inside this building...")
- Floors Directory: list of floors with names/descriptions
- Accessibility & Facilities (parsed from description)
- "Navigate to [Building]" button → Map with route

**5. Professor Profile Screen**
- Header: back button + notification bell
- Profile card: avatar placeholder, name, title, department (parsed from POI description)
- "Available Now" status badge (placeholder — no real-time availability data)
- Save button (placeholder — no auth)
- Office Location: building name, room, floor, map pin
- Weekly Office Hours (parsed from description)
- "Get Directions to Room [X]" button → Map with route

---

## User Flow

```
App Launch
  │
  ├─ First launch → Campus Selection screen
  │     └─ User picks campus → stored in SharedPreferences
  │
  ├─ Subsequent launch → Home Screen
  │
  ▼
Home Screen
  ├─ Tap "Professors" card → Search (pre-filtered to professors)
  ├─ Tap "Cafeterias" card → Search (pre-filtered to cafeterias)
  ├─ Tap "Buildings" card → Search (pre-filtered to buildings)
  ├─ Tap "Recent Waypoint" → Professor Profile or Building Detail
  └─ Tap Search bar → Search tab

Map Screen
  ├─ Tap building marker → Building Detail
  ├─ Tap "Nearest Location" card → Building Detail
  ├─ Tap filter chip → Show/hide POIs by category
  ├─ Tap POI marker → POI info popup + "Navigate" button
  └─ Tap "Navigate" → Map with route overlay

Search Screen
  ├─ Type query → Live search results (client-side)
  ├─ Tap filter chip → Filter results by category
  ├─ Tap PROF result → Professor Profile
  │     └─ "Get Directions" → Map with combined route
  ├─ Tap BUILDING result → Building Detail
  │     └─ "Navigate to Building" → Map with combined route
  └─ Tap CAFE/LIB/LAB result → Building Detail (floor)

Building Detail
  ├─ Tap floor row → Map view on that floor
  └─ "Navigate to Building" → Map with combined route

Map with Route
  ├─ Outdoor leg: blue polyline (GPS → entrance)
  ├─ Indoor leg: red polyline (entrance → destination)
  ├─ Floor up/down → Follow route across floors
  ├─ Wi-Fi positioning → Blue dot (if data available)
  └─ "Clear route" → Back to normal map view
```

---

## Data/API Strategy

**Principle: Reuse existing backend APIs. No new endpoints. No backend schema changes.**

### API Endpoints Used

| Purpose | Endpoint | Auth | Notes |
|---|---|---|---|
| List all spaces | `POST /api/mapping/space/public` | None | Bulk fetch on launch |
| Get campus buildings | `POST /api/mapping/campus/get` | None | Bulk fetch on launch |
| Get floors | `POST /api/mapping/floor/all` | None | Per building |
| Get POIs | `POST /api/mapping/pois/space/all` | None | Per building |
| Search POIs | `POST /api/mapping/pois/search` | None | Per building (iterated) |
| Floorplan tiles | `POST /api/floortiles/zip/:buid/:floor` | None | Download zip |
| Indoor route | `POST /api/navigation/route` | None | POI-to-POI |
| Route from coords | `POST /api/navigation/route/coordinates` | None | User position-to-POI |
| Wi-Fi positioning | `POST /api/position/estimate` | None | Server-side KNN/WKNN |
| Floor prediction | `POST /api/position/predictFloorAlgo1` | None | Server-side |
| Outdoor routing | `GET router.project-osrm.org/route/v1/driving/...` | None | OSRM public demo |

### Data Encoding in Description Fields

**POI description format:**
```
Dr. Elena Rostova | Associate Professor | CS Dept | Office 402, Floor 4 | Mon/Wed 2-3:30PM
```

**Space description format:**
```
Main Campus West Quad | Opened 2021 | Ramps & Elevators | Braille Signage
```

**Floor description format:**
```
Electrical Engineering Dept | Lecture Halls 3A-3C
```

**Category derivation (client-side, dynamic):**
| Signal | Category |
|---|---|
| POI name contains "Prof." or "Dr." | Professor |
| POI name/description contains "Cafeteria" or "Dining" | Cafeteria |
| POI name/description contains "Library" | Library |
| POI name/description contains "Lab" or "Laboratory" | Lab |
| Space.space_type == "building" | Building |
| Other POIs | Other |

Filter chips on Map and Search are built dynamically from whatever POI/entity types exist in the backend data, not hardcoded.

### Data Flow

```
App Launch
  → POST /api/mapping/campus/get (get campus buildings)
  → POST /api/mapping/space/public (get all spaces)
  → For each space: POST /api/mapping/floor/all
  → For each space: POST /api/mapping/pois/space/all
  → Cache everything in memory + local storage
  → Derive categories from POI names/descriptions

Map View (building selected)
  → POST /api/floortiles/zip/:buid/:floor (download tiles)
  → Extract zip → serve via FileTileProvider
  → Show POIs for current floor

Navigation
  → User taps "Navigate"
  → Get GPS position (LocationService)
  → Find nearest is_building_entrance POI
  → GET OSRM outdoor route (GPS → entrance)
  → POST /api/navigation/route/coordinates (entrance → dest)
  → Draw combined route

Wi-Fi Positioning
  → WiFiScan.instance.getScannedResults()
  → POST /api/position/estimate {buid, floor, APs, algorithm_choice: 2}
  → Update user marker position
```

---

## High-Level Architecture

```
lib/
├── main.dart
├── app.dart
├── config/
│   ├── api_config.dart
│   └── constants.dart
├── models/
│   ├── campus.dart
│   ├── space.dart
│   ├── floor.dart
│   ├── poi.dart
│   ├── route.dart
│   └── position.dart
├── services/
│   ├── api_service.dart
│   ├── cache_service.dart
│   ├── positioning_service.dart
│   ├── location_service.dart
│   ├── tile_service.dart
│   └── outdoor_routing_service.dart
├── providers/
│   ├── campus_provider.dart
│   ├── building_provider.dart
│   ├── floor_provider.dart
│   ├── poi_provider.dart
│   ├── route_provider.dart
│   ├── position_provider.dart
│   └── search_provider.dart
├── screens/
│   ├── home_screen.dart
│   ├── map_screen.dart
│   ├── search_screen.dart
│   ├── building_detail_screen.dart
│   └── professor_profile_screen.dart
├── widgets/
│   ├── campus_selector.dart
│   ├── floorplan_overlay.dart
│   ├── poi_marker.dart
│   ├── route_polyline.dart
│   ├── nearest_location_card.dart
│   ├── search_result_card.dart
│   ├── filter_chips.dart
│   └── floor_switcher.dart
└── utils/
    ├── description_parser.dart
    ├── category_deriver.dart
    ├── distance_calculator.dart
    └── tile_extractor.dart
```

### Key Packages

| Package | Purpose |
|---|---|
| `flutter_map` | Map rendering, tile layers, overlays |
| `latlong2` | Coordinate types |
| `wifi_scan` | Wi-Fi scanning (Android only) |
| `http` / `dio` | API calls |
| `shared_preferences` | Local settings (campus selection) |
| `path_provider` | App cache directory |
| `archive` | Zip extraction for floorplan tiles |
| `geolocator` | GPS location |
| `riverpod` | State management |

---

## Implementation Phases

## Phase Overview

```
Phase 0: Bug Fixes & Infrastructure (prerequisite)
Phase 1: Foundation & Project Setup
Phase 2: Data Layer
Phase 3: Core Screens (Home, Map, Search)
Phase 4: Detail Screens (Building, Professor)
Phase 5: Navigation (Indoor + Outdoor)
Phase 6: Positioning (GPS + Wi-Fi)
Phase 7: Polish & Error Handling
```

---

## Phase 0: Bug Fixes & Infrastructure

**Goal:** Fix blocking bugs in the existing backend/Logger pipeline and prepare infrastructure.

**Dependencies:** None (can run in parallel with Phase 1).

**Tasks:**

| # | Task | Effort | Files |
|---|---|---|---|
| 0.1 | Fix Logger upload auth mismatch — add `access_token` HTTP header to `UploadRSSLogTask` | Small | `clients/android/.../UploadRSSLogTask.java` or JitPack lib |
| 0.2 | Fix hardcoded server URL in Logger — read from SharedPreferences/env | Small | `clients/android/.../AnyplaceApp.java` |
| 0.3 | Disable broken MAP/MMSE algorithms (3/4) in `Algorithms.java` or fix sigma parameter | Small | `server/app/location/Algorithms.java` |
| 0.4 | Raise or make configurable the 10K measurement cap in `dumpRssLogEntriesByBuildingFloor` | Small | `server/app/datasources/MongodbDatasource.scala` |
| 0.5 | Fix `getByFloorsAll()` URL construction bug for cached floors | Small | `server/app/controllers/RadiomapController.scala` |
| 0.6 | Set up self-hosted tile server (TileServer GL or similar) with OSM data for E-JUST campus | Medium | Infrastructure (outside codebase) |
| 0.7 | Document fingerprint data collection process (step-by-step guide) | Small | New doc file |

**Exit criteria:**
- All 5 bugs fixed and verified
- Self-hosted tile server running and serving tiles for E-JUST campus
- Data collection guide written

---

## Phase 1: Foundation & Project Setup

**Goal:** Create the Flutter project, configure dependencies, establish architecture.

**Dependencies:** None (can run in parallel with Phase 0).

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 1.1 | Create Flutter project (`flutter create --org eg.edu.ejust anyplace_campusfind`) | Small |
| 1.2 | Configure `pubspec.yaml` with all dependencies (flutter_map, latlong2, wifi_scan, http, dio, shared_preferences, path_provider, archive, geolocator, riverpod) | Small |
| 1.3 | Set up project folder structure (config/, models/, services/, providers/, screens/, widgets/, utils/) | Small |
| 1.4 | Create `ApiConfig` with server URL and all endpoint constants | Small |
| 1.5 | Create base `ApiService` class with HTTP client, error handling, gzip decompression | Medium |
| 1.6 | Configure Android manifest (permissions: INTERNET, ACCESS_FINE_LOCATION, ACCESS_WIFI_STATE, CHANGE_WIFI_STATE) | Small |
| 1.7 | Set up Riverpod providers skeleton | Small |
| 1.8 | Configure `flutter_map` with self-hosted tile URL template | Small |

**Exit criteria:**
- Project compiles and runs on Android
- `flutter_map` renders with self-hosted outdoor tiles
- API service can reach the backend server

---

## Phase 2: Data Layer

**Goal:** Fetch, parse, cache, and model all data from the backend.

**Dependencies:** Phase 1 complete.

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 2.1 | Create data models: `Campus`, `Space`, `Floor`, `Poi`, `Route`, `Position` | Medium |
| 2.2 | Implement `ApiService` methods for all endpoints (campus, spaces, floors, POIs, search, floorplan tiles, navigation, positioning) | Large |
| 2.3 | Implement `CacheService` — in-memory cache + SharedPreferences for campus selection | Medium |
| 2.4 | Implement bulk fetch on launch: campus → spaces → floors → POIs (with loading state) | Medium |
| 2.5 | Implement `DescriptionParser` — parse structured data from description fields (professors, accessibility, floor descriptions) | Medium |
| 2.6 | Implement `CategoryDeriver` — scan POI names/descriptions to discover available categories | Medium |
| 2.7 | Implement `TileService` — download floorplan zip, extract to cache directory, serve via `FileTileProvider` | Medium |
| 2.8 | Implement `DistanceCalculator` — Haversine distance from GPS to POIs/buildings | Small |

**Exit criteria:**
- App fetches all data on launch and caches it
- Categories are dynamically derived from data
- Floorplan tiles are downloaded, extracted, and render on map
- Description parsing extracts professor info, accessibility, floor descriptions

---

## Phase 3: Core Screens (Home, Map, Search)

**Goal:** Build the three main tab screens with full functionality.

**Dependencies:** Phase 2 complete.

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 3.1 | **Campus Selection screen** — show available campuses, user picks one, stored locally | Medium |
| 3.2 | **Home Screen** — greeting, search bar, quick access cards (dynamic categories), recent waypoints (local persistence) | Medium |
| 3.3 | **Map Screen** — `flutter_map` with building markers, POI markers, filter chips, floorplan tile overlay, floor switcher | Large |
| 3.4 | **Search Screen** — search input, dynamic filter chips, cross-entity results with type badges, tap to navigate | Medium |
| 3.5 | **Bottom Navigation** — 3-tab nav (Home, Map, Search) with proper state management | Small |
| 3.6 | **Marker clustering** — cluster building markers at low zoom levels | Small |
| 3.7 | **Indoor/outdoor mode switching** — show/hide POIs based on zoom level (≥19 = indoor) | Small |

**Exit criteria:**
- Campus selection works on first launch
- Home screen shows dynamic quick access and recent waypoints
- Map renders with building markers, POI markers, floorplan tiles
- Search returns cross-entity results with type badges
- Filter chips filter POIs on map and in search results
- Floor switcher changes floorplan overlay

---

## Phase 4: Detail Screens (Building, Professor)

**Goal:** Build the building detail and professor profile screens.

**Dependencies:** Phase 3 complete.

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 4.1 | **Building Detail Screen** — hero placeholder, building info (parsed from description), floors directory, accessibility info, "Navigate" button | Medium |
| 4.2 | **Professor Profile Screen** — avatar placeholder, name/title/department (parsed), office location, office hours, "Get Directions" button | Medium |
| 4.3 | **Floor list in Building Detail** — tap floor → map view on that floor | Small |
| 4.4 | **Room search in Building Detail** — search POIs within building | Small |

**Exit criteria:**
- Building Detail shows parsed metadata and floor list
- Professor Profile shows parsed office info and hours
- Navigation buttons trigger route calculation

---

## Phase 5: Navigation (Indoor + Outdoor)

**Goal:** Implement indoor and outdoor routing with combined route display.

**Dependencies:** Phase 3 complete (map screen must exist).

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 5.1 | **Indoor routing** — call `/api/navigation/route` or `/api/navigation/route/coordinates`, parse response | Medium |
| 5.2 | **Outdoor routing** — call OSRM public demo API, parse GeoJSON response | Medium |
| 5.3 | **Combined route logic** — find nearest `is_building_entrance` POI, calculate outdoor leg (GPS → entrance) + indoor leg (entrance → dest) | Medium |
| 5.4 | **Route display** — draw outdoor polyline (blue) + indoor polyline (red) per floor on map | Medium |
| 5.5 | **Floor switcher for routes** — switch floors to follow indoor route across floors | Small |
| 5.6 | **Clear route** — button to remove route polylines and return to normal map | Small |
| 5.7 | **Fallback handling** — no route available, OSRM failure (show straight line), no entrance POIs (use building center) | Small |

**Exit criteria:**
- Indoor routing works between POIs
- Outdoor routing works from GPS to building entrance
- Combined route displays as blue (outdoor) + red (indoor) polylines
- Floor switcher follows route across floors
- Graceful fallbacks when routing fails

---

## Phase 6: Positioning (GPS + Wi-Fi)

**Goal:** Implement GPS location tracking and Wi-Fi fingerprint-based indoor positioning.

**Dependencies:** Phase 3 complete (map screen must exist).

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 6.1 | **GPS location** — `geolocator` package, continuous position updates, blue dot marker on map | Medium |
| 6.2 | **Wi-Fi scanning** — `wifi_scan` plugin, periodic scans, collect BSSID + RSS | Medium |
| 6.3 | **Server-side positioning** — POST scan results to `/api/position/estimate`, parse response | Medium |
| 6.4 | **Position provider** — combine GPS + Wi-Fi position into single position stream | Medium |
| 6.5 | **"Nearest Location" bottom sheet** — calculate nearest building from GPS, show distance | Small |
| 6.6 | **Graceful fallback** — "Positioning unavailable" when no radiomap data, GPS-only when Wi-Fi fails | Small |

**Exit criteria:**
- GPS blue dot shows on map
- Wi-Fi scanning works on Android
- Server-side positioning returns coordinates (when radiomap data exists)
- Nearest location shows correct building and distance
- Graceful fallback when positioning unavailable

---

## Phase 7: Polish & Error Handling

**Goal:** Error handling, offline support, UI refinement, performance optimization.

**Dependencies:** Phases 3–6 complete.

**Tasks:**

| # | Task | Effort |
|---|---|---|
| 7.1 | **Error handling** — network errors, API failures, empty states, loading states | Medium |
| 7.2 | **Offline support** — cached tiles work offline, cached POIs available, graceful "no network" messages | Medium |
| 7.3 | **UI refinement** — consistent theming, animations, responsive layout | Medium |
| 7.4 | **Performance** — optimize bulk fetch, lazy load floors/POIs, tile caching | Small |
| 7.5 | **Testing** — unit tests for services/utils, widget tests for key screens | Medium |
| 7.6 | **Documentation** — README, setup guide, data collection guide | Small |

**Exit criteria:**
- App handles all error states gracefully
- Offline mode works for cached data
- UI is polished and consistent
- Key paths are tested

---

## Dependency Graph

```
Phase 0 (Bug Fixes)     Phase 1 (Foundation)
    │                        │
    │                        ▼
    │                   Phase 2 (Data Layer)
    │                        │
    │                        ▼
    └──────────────►  Phase 3 (Core Screens)
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
        Phase 4      Phase 5      Phase 6
        (Details)   (Navigation) (Positioning)
              │           │           │
              └───────────┼───────────┘
                          ▼
                    Phase 7 (Polish)
```

**Critical path:** Phase 1 → Phase 2 → Phase 3 → Phase 5 (Navigation) → Phase 7

**Parallel tracks:**
- Phase 0 runs in parallel with Phase 1
- Phase 4, 5, 6 run in parallel after Phase 3
- Phase 5 (Navigation) and Phase 6 (Positioning) are independent of each other

---

## Bugs to Fix (In Scope)

| # | Bug | File | Fix |
|---|---|---|---|
| 1 | Logger auth mismatch | `UploadRSSLogTask.java` | Add `access_token` HTTP header |
| 2 | Hardcoded server URL | `AnyplaceApp.java` | Read from SharedPreferences/env |
| 3 | MAP/MMSE broken (K=4 as sigma) | `Algorithms.java` | Disable algorithms 3/4 or fix sigma |
| 4 | 10K measurement cap | `MongodbDatasource.scala` | Raise limit or make configurable |
| 5 | `getByFloorsAll()` URL bug | `RadiomapController.scala` | Fix URL construction in cached path |

---

## External Dependencies

| Dependency | Status | Action Required |
|---|---|---|
| Anyplace backend server | Running | Verify all endpoints work |
| Self-hosted tile server | Not set up | Infrastructure task (outside Flutter app) |
| OSRM routing | Public demo available | Use `router.project-osrm.org` for MVP |
| Fingerprint data | Not collected | Manual data collection with Logger app |
| Google Maps API key | Not needed | `flutter_map` uses self-hosted tiles |

---

## Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| No fingerprint data for Wi-Fi positioning | HIGH | Graceful fallback ("Positioning unavailable"); document data collection process |
| Self-hosted tile server not set up | MEDIUM | Use Carto Positron as temporary fallback until self-hosted is ready |
| OSRM public demo rate limits | LOW | Cache routes; self-host OSRM for production |
| Description parsing fragile | MEDIUM | Use consistent delimiter (`|`); robust parsing with fallbacks |
| Android scan throttling | MEDIUM | Accept OS-level throttling; position updates at ~7.5s intervals |
| Connection data may be sparse | MEDIUM | Graceful fallback ("No route available"); routing works when data exists |
| `wifi_scan` iOS stub | LOW | Android-only MVP; iOS added later with GPS-only |

---

## Estimated Effort Summary

| Phase | Effort | Dependencies |
|---|---|---|
| Phase 0: Bug Fixes & Infrastructure | Small–Medium | None |
| Phase 1: Foundation | Small | None |
| Phase 2: Data Layer | Large | Phase 1 |
| Phase 3: Core Screens | Large | Phase 2 |
| Phase 4: Detail Screens | Medium | Phase 3 |
| Phase 5: Navigation | Large | Phase 3 |
| Phase 6: Positioning | Medium | Phase 3 |
| Phase 7: Polish | Medium | Phases 3–6 |

**Total estimated effort:** ~4–6 weeks for a single developer, assuming familiarity with Flutter and the Anyplace backend.

---

## Phase Status

| Phase | Status | Notes |
|---|---|---|
| 0 | ⏸ Not started | Parallel-ready; fixes in `clients/android/` + `server/` + infra |
| 1 | ✅ DONE (2026-08-12) | Foundation in `clients/flutter/anyplace_campusfind` |
| 2 | ✅ DONE (2026-08-12) | Data layer in `lib/models`, `lib/services`, `lib/utils`, `lib/providers` |
| **3** | ✅ DONE (2026-08-12) | Core screens (campus selection, Home, Map, Search) |
| **4** | ✅ DONE (2026-08-12) | Detail screens (Building Detail, Professor Profile) |
| **5** | ✅ DONE (2026-08-12) | Navigation (indoor + outdoor, combined route display) |
| 6–7 | ⏸ Not started | — |

**Phase 5 completion record:**
- `lib/services/outdoor_routing_service.dart` — `OutdoorRoutingService` for the
  public OSRM demo (`router.project-osrm.org/route/v1/driving/...`), GeoJSON
  parsing into `OutdoorRoute` (`lib/models/outdoor_route.dart`); throws
  `OutdoorRoutingException` on non-`Ok` status, HTTP errors or empty routes
- `lib/providers/route_provider.dart` — `RouteNotifier`/`RouteState` +
  `routeStateProvider`, `userLocationProvider` (GPS slot for Phase 6),
  `outdoorRoutingServiceProvider`. Combined route logic (task 5.3):
  - indoor leg via `/api/navigation/route` from nearest `is_building_entrance`
    POI → destination, grouped by floor (`indoorPointsByFloor`)
  - no-entrance fallback (5.7): `/api/navigation/route/coordinates` from the
    building center on the destination floor
  - outdoor leg via OSRM `from` (GPS) → entrance/building center, straight-line
    fallback (5.7) when OSRM fails
  - `navigateToPoi` (combined) and `navigateToBuilding` (outdoor-only); error
    state surfaces as `RouteState.error`
- `lib/utils/map_focus.dart` — `navigateToPoiOnMap` / `navigateToBuildingOnMap`
  focus the building on the Map tab and kick off the route
- Map screen (5.4): `_RouteOverlay` draws the blue outdoor polyline always and
  the red indoor polyline for the currently selected floor; `_RouteNotice`
  banner for errors + loading bar; FAB now clears the route (5.6); switching
  floors in the bottom sheet moves the red polyline to that floor (5.5)
- Building Detail "Navigate to Building" and Professor "Get Directions" buttons
  now start real routes
- Verified: `flutter analyze` 0 issues, 41 tests passing (9 new in
  `test/route_test.dart` covering OSRM parsing + combined/fallback/error/clear
  logic), `flutter build apk --debug` success

**Phase 4 completion record:**
- `lib/screens/building_detail_screen.dart` — `BuildingDetailScreen(space)`: gradient
  hero placeholder (no building photos in data), parsed building info via
  `DescriptionParser` (summary), room search field (task 4.4) that filters
  cached POIs of the building live, floors directory (task 4.3) with per-floor
  tap → `showBuildingOnMap` (selects building+floor on the Map tab),
  accessibility/facility chips, and a "Navigate to Building" button
- `lib/screens/professor_profile_screen.dart` — `ProfessorProfileScreen(poi,
  [space])`: avatar placeholder, parsed name/title/department, office location,
  building + floor, weekly office hours (parsed), "Get Directions" button
- `lib/utils/map_focus.dart` — `showBuildingOnMap(context, ref, space, {floor})`:
  selects the building/floor in `mapViewStateProvider`, switches to the Map tab
  and pops back to the shell (route drawing itself lands in Phase 5)
- `lib/screens/detail_navigation.dart` — `openSearchResult` / `openPoi`: route a
  tap to the correct screen (professor → Professor Profile; building → Building
  Detail; other POIs → their building's detail; fallback snackbar)
- Wired tap-through everywhere: Search results, Home recent waypoints, Map POI
  markers, and a "Details" button on the map's building bottom sheet
- Verified: `flutter analyze` 0 issues, 32 tests passing (5 new widget tests in
  `test/detail_screens_test.dart`), `flutter build apk --debug` success

**Phase 3 completion record:**
- `CampusSelectionScreen` — first-launch picker; campuses fetched per-cuid via
  `CAMPUS_IDS` dart-define (no public list-campuses endpoint exists); stored via
  CacheService; restored on launch in `main.dart`
- `MainShell` — 3-tab bottom nav (Home/Map/Search) via IndexedStack +
  `shellTabProvider`; `RootRouter` switches selection flow vs shell
- `HomeScreen` — greeting, search entry, dynamic quick-access cards derived
  from discovered categories, recent waypoints
- `SearchScreen` — live client-side search across buildings + POIs with
  dynamic `FilterChips` and category badges (`SearchResultCard`)
- `SearchIndex`/`SearchIndexProvider` — flat cross-entity index, dedupe by puid
- `MapScreen` — flutter_map with outdoor tiles (Carto fallback), building
  markers, POI markers, filter chips, `_FloorplanOverlay` using
  `LocalFloorplanTileProvider` (local tiles at `z{x}z...` naming), floor
  switcher bottom sheet, selection clear button
- Task 3.6 marker clustering — grid-bucket clustering below zoom 16
- Task 3.7 indoor/outdoor switching — POIs + floorplan only when a
  building+floor is selected AND zoom >= `indoorZoomThreshold` (19)
- Verified: `flutter analyze` clean, 27 tests passing, `flutter build apk
  --debug` success

**Phase 2 completion record:**
- Models mirror backend fields exactly (verified against `server/app/models/*.scala` + `datasources/SCHEMA.scala`):
  - `lib/models/{campus,space,floor,poi,route,position}.dart`
- `ApiService` extended with typed methods for every public endpoint used:
  `fetchPublicSpaces`, `fetchCampus`, `fetchFloors`, `fetchPois`, `searchPois`,
  `fetchNavigationRoute`, `fetchNavigationRouteFromCoords`, `estimatePosition`,
  `fetchFloorTilesZip`
- `CacheService` — in-memory dataset + SharedPreferences (campus id, recent waypoints)
- `BulkLoader` (`lib/providers/bulk_load_provider.dart`) — spaces → floors+POIs per building
  with `FutureProvider` loading state; note: no public "list campuses" endpoint exists,
  so bulk load seeds from `space/public` and campus objects are fetched per-cuid
- `DescriptionParser` — `|`-delimited description parsing (professors, building tags)
- `CategoryDeriver` — dynamic category discovery (professor/cafeteria/library/lab/other)
- `TileService` — downloads zip, extracts `static_tiles/` layout, caches to app support
- `DistanceCalculator` — Haversine + nearest-space
- Verified: `flutter analyze` 0 issues, 23 tests passing, `flutter build apk --debug` success

**Phase 1 completion record:**
- `flutter create --org eg.edu.ejust anyplace_campusfind` (Android-only)
- deps: flutter_map, latlong2, wifi_scan, http, dio, shared_preferences, path_provider, archive, geolocator, flutter_riverpod
- folder structure: `config/ models/ services/ providers/ screens/ widgets/ utils/`
- `lib/config/api_config.dart` — server URL (`--dart-define=SERVER_URL`, default illustrative `http://anyplace.ejust.edu.eg:443`) + all endpoint constants
- `lib/config/constants.dart` — app name, prefs keys, tile URL template (Carto fallback), indoor zoom threshold
- `lib/services/api_service.dart` — Dio-based base client, JSON POST, byte GET, gzip via transport, typed `ApiException`
- `lib/providers/providers.dart` — `apiServiceProvider`, `selectedCampusIdProvider`, initial-load state providers
- `lib/screens/map_preview_screen.dart` — `flutter_map` with configured tile template (temporary Phase 1 proof)
- Android manifest: INTERNET, FINE/COARSE location, WIFI state, CHANGE_WIFI_STATE, `usesCleartextTraffic` for plain-HTTP dev backend
- Verified: `flutter analyze` 0 issues, `flutter test` pass, `flutter build apk --debug` success (build/ is gitignored)
