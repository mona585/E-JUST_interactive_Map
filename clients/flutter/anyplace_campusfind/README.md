# anyplace_campusfind

E-JUST campus navigation companion app (Flutter, Android-first). Built on the
[Anyplace](https://github.com/dmsl/anyplace) indoor-navigation platform: browse
campus buildings, search rooms/professors, view floorplans, get indoor +
outdoor directions, and use GPS/Wi-Fi positioning.

## Features

- **Campus selection** on first launch (campuses configured at build time)
- **Home** — quick access by category and recent waypoints
- **Map** — `flutter_map` with building/POI markers, marker clustering, tiled
  floorplan overlay with floor switcher, GPS blue-dot and nearest-location card
- **Search** — live cross-entity search (buildings + POIs) with category filters
- **Building detail / Professor profile** — parsed metadata, floor directory,
  room search, accessibility & facilities, navigate buttons
- **Navigation** — indoor routes via the Anyplace backend, outdoor legs via
  OSRM, combined blue/red polyline display with per-floor switching
- **Positioning** — GPS + Wi-Fi fingerprint estimates with graceful fallbacks
- **Offline support** — campus dataset snapshot + cached floorplan tiles keep
  the app usable without a connection (with an "offline" banner)

## Prerequisites

- Flutter (stable) — this project pins Dart `^3.12`
- An Anyplace backend (see the repo root `AGENTS.md` / recovery docs)
- Android SDK 29+ (build-tools 29.0.2)

## Setup

```bash
cd clients/flutter/anyplace_campusfind
flutter pub get
```

### Build-time configuration

The app reads three `--dart-define` values; all default to sensible dev values.

| Define | Default | Purpose |
| --- | --- | --- |
| `SERVER_URL` | `http://anyplace.ejust.edu.eg:443` | Backend base URL |
| `CAMPUS_IDS` | *(empty)* | Comma-separated campus cuids offered on first launch. When empty, the app auto-derives a single default campus from all published buildings (`space/public`), so a zero-config build shows the E-JUST campus on first launch. |
| `CAMPUS_NAME` | `E-JUST Campus` | Name of the auto-derived default campus |

```bash
flutter run \
  --dart-define=SERVER_URL=http://10.0.2.2:9000 \
  --dart-define=CAMPUS_IDS=cuid_ejust
```

> `10.0.2.2` is the emulator alias for the host machine's `localhost`. The
> debug manifest and `usesCleartextTraffic` allow plain-HTTP during
> development; production should use HTTPS.

## Running the app

```bash
# No config needed — the default campus is auto-derived from the backend.
flutter run

# Multi-campus deployments can pin the offered campuses explicitly.
flutter run --dart-define=CAMPUS_IDS=<cuid-a>,<cuid-b>
flutter build apk --debug
```

## Tests

```bash
flutter test
```

Coverage includes: models (JSON parsing), API service (endpoints + error
mapping), cache + offline snapshot, search index, route/OSRM logic, tile
service (caching/offline), and widget tests for the main-shell gates, campus
selection (error/retry), building detail and professor profile.

## Offline behaviour

- The bulk campus dataset is snapshotted to `<appSupport>/campus_data_snapshot.json`
  after each successful fetch and restored when the live fetch fails.
- Floorplan tiles are cached under `<appSupport>/floorplan_tiles/` and are
  served from disk without a network call once downloaded.
- When running on cached data the app shows an "Offline" banner with a Retry
  action.

## Data collection (fingerprints)

Indoor positioning depends on Wi-Fi radiomap data collected with the legacy
Logger app. See the repo-level documentation under `docs/` for the full
data-collection process (Anyplace standard workflow).

## Project structure

```
lib/
  config/     API endpoints, constants, theme
  models/     Campus, Space, Floor, Poi, Route, Position
  services/   API, cache, tiles, positioning, outdoor routing
  providers/  Riverpod providers (bulk load, map view, route, search, position)
  screens/    Campus selection, Home, Map, Search, detail screens
  utils/      DescriptionParser, CategoryDeriver, DistanceCalculator, map focus
  widgets/    FilterChips, local tile provider, search result card
```

See `docs/CAMPUSFIND_PLAN.md` for the roadmap and per-phase completion records.
