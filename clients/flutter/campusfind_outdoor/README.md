# anyplace_campusfind

E-JUST CampusFind — an indoor/outdoor campus navigation app (Flutter, Android-first)
built on the Anyplace platform. Browse campus buildings, search rooms/places, view
floorplans, and get indoor + outdoor directions using GPS and Wi-Fi fingerprint
positioning.

The app is intentionally connected to the dedicated E-JUST backend
**`https://map.beout.ai`** and is scoped to the **E-JUST campus**, which is
**hard-coded** (there is no campus picker / first-launch selection).

## Features

- **Map** — Google Maps (hybrid) framed on the E-JUST campus, building and POI
  markers, floorplan ground-overlay with a floor switcher, and a user position marker.
- **Building / POI browse** — tap a building to inspect its floors, POIs and
  floorplan; open a POI for details and "Start Directions".
- **Search** — live cross-entity search across buildings, floors and POIs with a
  From/My-Location → To flow.
- **Navigation** — indoor routes from the Anyplace backend (`/api/navigation/route`)
  plus outdoor legs (OSRM), rendered as per-floor polylines with floor switching,
  rerouting, and arrival detection.
- **Positioning** — GPS (outdoor) and Wi-Fi fingerprint estimates (indoor, Android
  native engine) with source arbitration, indoor/outdoor transitions, floor
  transitions and stale/invalid handling. *(Indoor Wi-Fi positioning requires the
  Android native engine; iOS support is not included in this build.)*
- **Offline** — recently viewed floorplans, POIs and radiomaps are cached on disk
  (`<appSupport>/floorplans/`, `pois/`, `radiomaps/`) so they remain available
  without a connection. A connectivity-aware offline banner is shown when the
  network is unavailable.

## Prerequisites

- Flutter (stable); this project pins Dart `^3.12`.
- Android SDK 29+ (build-tools 29.0.2) for device/emulator builds.
- A `MAPS_API_KEY` for Google Maps (supplied natively, see below).

## Setup

```bash
cd clients/flutter/anyplace_campusfind
flutter pub get
```

### Build-time configuration

The app is configured with `--dart-define` values. All have safe defaults.

| Define | Default | Purpose |
| --- | --- | --- |
| `SERVER_URL` | `https://map.beout.ai` | Backend base URL. Override only to point at another Anyplace deployment. |
| `CAMPUS_CUID` | `ejust` | Campus scope. The E-JUST campus is fixed; there is no campus picker. |
| `CAMPUS_NAME` | `E-JUST` | Display name for the fixed campus. |
| `OSRM_URL` | *(public OSRM over HTTPS)* | Outdoor-routing endpoint used for cross-building/outdoor legs. |

> **Note:** `CAMPUS_IDS` is **not** supported — the campus is hard-coded to E-JUST.
> The Google Maps `MAPS_API_KEY` is **not** consumed as a Dart define; it must be
> supplied natively via `android/app/src/main/AndroidManifest.xml`
> (`meta-data android:name="com.google.android.geo.API_KEY"`) and the equivalent
> iOS `Info.plist`/`AppDelegate` configuration.

```bash
flutter run --dart-define=MAPS_API_KEY=YOUR_KEY
```

> `10.0.2.2` is the emulator alias for the host machine's `localhost`.

## Running

```bash
flutter run
flutter build apk --debug
```

## Tests

```bash
flutter test
```

Coverage includes: models (JSON parsing), API service (endpoints + error mapping),
per-entity cache (floorplan/POI/radiomap), search index, route/OSRM logic, navigation
state machine (arrival, floor transitions, rerouting), positioning arbitration, and
widget tests for the main-shell gates, E-JUST scope, building/POI detail and
navigation UI.

## Offline behaviour

- Floorplan images are cached under `<appSupport>/floorplans/<buid>/<floor>/`.
- POI and radiomap data are cached on disk and reused when available.
- When the live network is unavailable the app shows an offline banner with a Retry
  action; previously cached content remains usable.

## Data collection (fingerprints)

Indoor positioning depends on Wi-Fi radiomap data. Radiomaps are fetched from the
backend and pushed to the native positioning engine; see the repo-level
documentation under `docs/` for the data-collection workflow.

## Project structure

```
lib/
  config/     API endpoints, constants, theme, map configuration
  data/
    models/          domain models (space, floor, poi, route, position, ...)
    repositories/    space/poi/floorplan/radiomap/navigation repositories
    datasources/     HTTP API client, disk caches, GPS/Wi-Fi/heading services
  services/    SearchService and other app services
  providers/   Riverpod providers (cache, campus id, search, directions, panel)
  state/       ChangeNotifier state (space_provider, location_provider, navigation_controller)
  screens/     main_shell, home_screen, search_screen
  ui/
    screens/   map_screen (Google Map + overlays + navigation rendering)
    widgets/   map chrome, navigation UI, building/POI cards, arrival banner
    utils/     floorplan overlay cache, navigation display, campus scope
  utils/       description parsing, category derivation, distance, campus scope
  widgets/     quick-access / recent-waypoint / search-result widgets
```

See `docs/CAMPUSFIND_PLAN.md` for the implementation plan and per-phase status.
