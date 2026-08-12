# CampusFind (anyplace_campusfind) — Technical Documentation

## 1. Project Overview and Purpose

**CampusFind** is a Flutter mobile student companion app for E-JUST (Egyptian Japanese University for Science and Technology) indoor navigation. It is Android-only for MVP. All real data comes from the existing Anyplace backend — no fake or hardcoded business data.

**Key constraints** (from `docs/CAMPUSFIND_PLAN.md`):
- No backend schema changes (all rich data encoded in existing `description` fields)
- No user authentication for MVP
- Indoor positioning requires fingerprint data collection (external prerequisite)
- Self-hosted tile server for outdoor maps (infrastructure task)
- Outdoor routing via OSRM public demo (no API key needed)

**Product scope (MVP)**:
- Campus selection on first launch (multi-campus, user picks, stored locally)
- Home screen — greeting, search bar, quick access cards, recent waypoints
- Campus map — `flutter_map` with building/POI markers, marker clustering, tiled floorplan overlay with floor switcher, GPS blue-dot and nearest-location card
- Search — live cross-entity search (buildings + POIs) with category filters
- Building detail — parsed metadata, floor directory, room search, accessibility & facilities, navigate buttons
- Professor profile — parsed metadata, office location, office hours, navigate buttons
- Navigation — indoor routes via the Anyplace backend, outdoor legs via OSRM, combined blue/red polyline display with per-floor switching
- Positioning — GPS + Wi-Fi fingerprint estimates with graceful fallbacks
- Offline support — campus dataset snapshot + cached floorplan tiles keep the app usable without a connection

**Non-MVP (excluded per plan)**:
- User authentication / login
- Saved bookmarks / Profile tab
- Push notifications
- Building photos (hero placeholder used instead)
- iOS support
- Voice guidance / step-by-step directions
- Real-time crowd data for cafeterias
- Menu data for cafeterias
- Time-based heatmap visualization
- Self-hosted OSRM (use public demo server for MVP)

---

## 2. Complete Folder/File Structure and Responsibility of Important Files

```
lib/
  config/           API endpoints, constants, theme
    api_config.dart    — centralized SERVER_URL + all endpoint constants
    constants.dart     — app name, prefs keys, tile URL template, indoor zoom threshold
    theme.dart         — Material 3 light/dark themes
  models/           Campus, Space, Floor, Poi, Route, Position, RoutePoint, NavigationRoute
    campus.dart        — Campus model with cuid, name, spaces list
    space.dart         — Space model (building), fields: buid, name, coordinates, space_type, etc.
    floor.dart         — Floor model, fields: fuid, buid, floorNumber, floorName, description
    poi.dart           — POI model, fields: puid, buid, name, coordinates, floorNumber, pois_type, etc.
    route.dart         — RoutePoint + NavigationRoute models
    position.dart      — PositionEstimate model
  services/         API client, cache, tiles, positioning, outdoor routing
    api_service.dart   — Dio-based HTTP client, gzip, timeouts, typed ApiException
    cache_service.dart — In-memory dataset + SharedPreferences + offline JSON snapshot
    tile_service.dart  — Downloads/extracts floorplan tile zip, serves from local cache
    positioning_service.dart — Wraps GPS/wifi scanning + server estimate endpoint
    outdoor_routing_service.dart — OSRM public demo client for outdoor legs
  providers/      Riverpod providers for state management
    providers.dart     — apiServiceProvider, cacheServiceProvider, cacheVersionProvider
    campus_provider.dart — CampusLoader for first-launch campus picker
    bulk_load_provider.dart — BulkLoader: fetch spaces → floors+POIs per building
    search_provider.dart — SearchIndex (cross-entity client-side index), searchQuery, category filter
    route_provider.dart  — RouteNotifier/RouteState: indoor+outdoor combined route logic
    position_provider.dart — PositionNotifier/PositionState: GPS + Wi-Fi positioning stream
    map_view_provider.dart — MapViewState: selectedSpace, selectedFloor, poiCategory
  screens/        UI screens (Consumer/ConsumerWidget)
    main_shell.dart    — 3-tab bottom nav (Home/Map/Search/Saved/Profile) with bulk-load/error/offline gates
    home_screen.dart   — Greeting, search bar, dynamic quick-access cards, recent waypoints
    map_screen.dart    — flutter_map with outdoor tiles, building/POI markers, filter chips, floorplan overlay, floor switcher
    search_screen.dart — Search input, dynamic filter chips, cross-entity results with type badges
    campus_selection_screen.dart — First-launch campus picker
    building_detail_screen.dart — Hero placeholder, building info (parsed from description), floors directory, room search, navigate button
    professor_profile_screen.dart — Avatar placeholder, parsed name/title/dept/hours, navigate button
    detail_navigation.dart — Routes tap to correct detail screen (professor→profile, building→detail)
  widgets/        Reusable UI components
    search_result_card.dart — Card with name, category badge, distance, location details
    filter_chips.dart     — Horizontal category chips (All + derived categories)
    local_floorplan_tile_provider.dart — Serves extracted floorplan tiles from local dir
  utils/          Utility functions and classes
    category_deriver.dart — Derives EntityCategory from POI architect `pois_type` + name/desc keywords
    parsing.dart         — Safe double parsing
    map_focus.dart       — Building/floor focus + route start functions
    distance_calculator.dart — Haversine distance + nearest space
    description_parser.dart — Parses `|`-delimited description fields (professors, building tags)

Root-level files of note:
- `pubspec.yaml` — Flutter deps: flutter_map, latlong2, wifi_scan, http, dio, shared_preferences, path_provider, archive, geolocator, riverpod
- `README.md` — Features, setup (dart-define SERVER_URL, CAMPUS_IDS), build commands, tests, offline behaviour
- `analysis_options.yaml` — Lint configuration (flutter_lints)
- `clients/.env.example` — For android-new apps: MAPS_API_KEY, SERVER_HOST, SERVER_PORT, SERVER_URL, API_USERNAME/PASSWORD
- `docs/` — Roadmap (CAMPUSFIND_PLAN.md), audit (IMPLEMENTATION_AUDIT.md), recovery phases
- `android/app/build.gradle.kts` — Flutter build config, AGP settings
- `.gitignore` — Build/ artifacts