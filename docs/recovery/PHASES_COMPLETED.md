# E-JUST Anyplace — Recovery Phases Completed

**Date completed:** 2026-08-11
**Final HEAD commit:** `acaadeb`
**Branch:** `main`
**Full evidence:** [EXECUTION_LOG.md](EXECUTION_LOG.md)

---

## Status at a Glance

| Phase | Title | Status | Primary commits |
|-------|-------|--------|-----------------|
| 0 | Contain Secrets & Freeze Baseline | ✅ DONE | `e00b496`, `172a0b4` |
| 1 | Pin Linux/Ubuntu Toolchains | ✅ DONE | `1971e3f`, `2ba13a8` |
| 2 | Backend Startup & MongoDB Connectivity | ✅ DONE | `279c19c`, `2d1a0e8` |
| 3 | Backend Test & Core API Baseline | ✅ DONE | `ecfbe6b`, `0ef265f` |
| 4 | Web Assets & Developer API | ✅ DONE | `a0508e2`, `cbb9015` |
| 5 | Empty Data Baseline & Hydration Contract | ✅ DONE | `64fe617`, `549a01a` |
| 6 | Floorplan / Tiler Pipeline | ✅ DONE | `73ed02a`, `d1af442` |
| 7 | Android Logger & Navigator | ✅ DONE | `c544857`, `611775c` |
| 8 | Detach from Legacy Domains | ✅ DONE | `f11f095`, `f7d17b0` |
| 9 | Security & End-to-End Regression Gate | ✅ DONE | `29153c6`, `acaadeb` |
| 10 | Deferred Cleanup & Modernization | ⏸ NOT STARTED — requires explicit owner approval |

---

## What Each Phase Did

### Phase 0 — Contain Secrets & Freeze Baseline
- Removed exposed `APPLICATION_SECRET`, `MAPS_API_KEY`, and password literals from all `.env.example` templates.
- Added `app.private.conf`, `clients/.env`, `server/.env` to `.gitignore`.
- Enforced `APPLICATION_SECRET` environment variable check in `dist/deploy_to_vm.sh` and `build`.

### Phase 1 — Pin Linux/Ubuntu Toolchains
- Confirmed: Ubuntu 22.04.5 LTS, OpenJDK 11, MongoDB 6.0.29, ImageMagick 6.9, Python 3.10, `advpng`.
- Installed and pinned: `grunt-cli 1.5.0`, `bower 1.8.14`.
- Documented toolchain versions in the execution log.

### Phase 2 — Backend Startup & MongoDB Connectivity
- Created `server/conf/app.private.conf` (gitignored) with staging connection settings.
- Created `server/conf/app.private.example.conf` (tracked) as a copy template.
- Disabled external analytics by default (`analytics.enabled=false`).
- Fixed `logback.xml` syntax error that prevented server startup.

### Phase 3 — Backend Test & Core API Baseline
- Unignored `server/test/` in `.gitignore`.
- Added `play-specs2` test dependency to `build.sbt`.
- Wrote `server/test/ApplicationSpec.scala` with gzip-aware response helper.
- Verified `sbt test` 3/3: redirect, `/api/version`, `/api/mapping/space/public`.

### Phase 4 — Web Assets & Developer API
- Resolved `angular-aria` missing `bower.json` dependency in all three web apps.
- Built production Grunt bundles for Architect, Viewer, Campus Viewer.
- Wired `build_web_apps` into the `./build` packager script.
- Confirmed static routes and Swagger UI return HTTP 200.

### Phase 5 — Empty Data Baseline & Hydration Contract
- Created `server/database/init_schema.js` — 15 domain collections and 2DSphere spatial indexes.
- Created `server/database/init_database.sh` — reproducible `--drop` + re-init script.
- Wrote `server/test/DatabaseBaselineSpec.scala` — verifies first user gets admin, second gets user, `/api/mapping/space/public` returns empty-but-valid payload.
- `sbt test` 6/6 passed.

### Phase 6 — Floorplan / Tiler Pipeline
- Added `python3` fallback detection in both tiler `start-anyplace-tiler.sh` scripts.
- Fixed Python 3 `bytes` decoding bug in `anyplace-tiler.py` (`dim.decode('utf-8')`).
- Installed missing `zip` system dependency for `fix-tile-structure.sh`.
- Changed `advpng` from `-4` (zopfli, hangs) to `-2` (libdeflate, fast).
- Verified end-to-end tile generation: zoom 19–22, `bounds.txt`, `tiles_archive.zip`.

### Phase 7 — Android Logger & Navigator
- Installed Android SDK (`platforms;android-29`, `build-tools;29.0.2`) at `/opt/android-sdk`.
- Rebranded package IDs to `eg.edu.ejust.anyplace.logger` / `eg.edu.ejust.anyplace.navigator`.
- Set default server URL to `http://anyplace.ejust.edu.eg:443` in `build.gradle` and `clients/.env`.
- Generated Gradle 6.5.1 wrapper JAR; pinned wrapper properties.
- `./gradlew assembleDebug` and `assembleRelease` both `BUILD SUCCESSFUL`.
- `aapt dump badging` confirmed E-JUST package identity on all four APKs.

### Phase 8 — Detach from Legacy Domains
Changed **active runtime references only** (license/copyright headers left intact):

| File | Change |
|------|--------|
| `.env.example`, `server/.env.example` | `map.beout.ai` → `anyplace.ejust.edu.eg` |
| `build` | Header comment, banner echo, fallback defaults |
| Logger `AnyplaceApp.java` | `ap-dev.cs.ucy.ac.cy` → `anyplace.ejust.edu.eg` |
| Logger `AnyplaceAboutActivity.java` | onClick URLs → E-JUST URLs |
| Logger `LoggerPrefs.java` | Architect link → E-JUST Architect URL |
| Navigator `AnyplaceAboutActivity.java` | onClick URLs → E-JUST URLs |
| Navigator `AndroidManifest.xml` | Intent-filter host `ap.cs.ucy.ac.cy` → `anyplace.ejust.edu.eg` |
| Viewer `app.js` + `PoiController.js` | Share URLs → `window.location.origin` |
| Campus Viewer `app.js` + `PoiController.js` | Share URLs → `window.location.origin` |

Old Android client (`clients/android/`) left unchanged (D-03 excluded scope).

### Phase 9 — Security & End-to-End Regression Gate
- **CSP** updated from `default-src 'self'` to permit known CDN origins (Google Maps/Fonts/APIs, cdnjs).
- **CORS** `allowedOrigins` changed from open `null` to configurable `${?cors.allowedOrigins}`; staging set to `localhost:9000` / `localhost:443`.
- **Referrer-Policy** `strict-origin-when-cross-origin` added.
- **`DatabaseBaselineSpec`** fixed: unique per-run email/username (via `System.nanoTime()`) prevents duplicate-email 400s across repeated `sbt test` runs.
- **`SecurityRegressionSpec`** written and all 13 tests passing:
  - `X-Frame-Options: DENY` on API responses
  - `X-Content-Type-Options: nosniff` on API responses
  - `X-XSS-Protection: 1; mode=block` on API responses
  - `Content-Security-Policy` header present
  - Allowed CORS origin (`localhost:9000`) echoed
  - Disallowed external origin (`evil.example.com`) NOT echoed
  - Second registrant always gets `"user"` role, never `"admin"`
  - Plaintext password value absent from register response
  - Missing required fields return 400 Bad Request
  - Public endpoints accessible without authentication
  - Protected building creation endpoint rejects unauthenticated request
- **Full `sbt test` result: 19/19 PASSED**

---

## What Was Explicitly Left Alone

| Item | Reason |
|------|--------|
| `clients/android/` (old Android) | D-03: excluded from launch scope |
| Standalone SMAS | Excluded from launch scope |
| License/copyright header strings in source files | Historical attribution; no runtime impact |
| Phase 10 modernization | Requires explicit owner approval — do not start |
| Google Sign-In flows | D-05: bypassed in favour of standard credentials |

---

## How to Run the Tests

```bash
cd /root/anyplace_EJUST/server
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 sbt test
# Expected: Passed: Total 19, Failed 0, Errors 0
```

## How to Build & Deploy

```bash
# 1. Copy and edit staging private config
cp server/conf/app.private.example.conf server/conf/app.private.conf
# edit app.private.conf: APPLICATION_SECRET, cors.allowedOrigins, MongoDB creds

# 2. Initialise the database (first deploy only)
mongod --dbpath /data/db &
cd server/database && ./init_database.sh

# 3. Build everything
cd /root/anyplace_EJUST
./build --server      # builds Play dist zip + deploy_to_vm.sh
./build --clients     # builds Android APKs

# 4. Deploy server
cd dist && APPLICATION_SECRET=<secret> ./deploy_to_vm.sh 443
```

## Key Configuration Files

| File | Purpose |
|------|---------|
| `server/conf/app.private.conf` | Gitignored — secrets, CORS origins, DB credentials |
| `server/conf/app.private.example.conf` | Tracked template — copy and fill in |
| `server/conf/app.play.conf` | Security headers, CORS, CSP, GZip settings |
| `server/database/init_schema.js` | MongoDB schema and spatial indexes |
| `server/database/init_database.sh` | Reproducible DB reset + init |
| `clients/android-new/local.properties` | Android SDK path (`sdk.dir=/opt/android-sdk`) |
| `clients/.env` / `clients/.env.example` | Android default server URL |

---

## Next Step (if any)

Phase 10 (Deferred Cleanup & Modernization) covers AngularJS/Bower/Grunt upgrades,
Play/sbt/JDK version bumps, old Android deletion, Docker/deprecated client removal,
and tiler redesign.

**Do not start Phase 10 without an explicit owner decision and a separate ADR.**
