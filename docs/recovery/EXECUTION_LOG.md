# Anyplace Recovery — Live Execution Log

This document records the step-by-step execution, evidence, and verification of the approved recovery plan for E-JUST Anyplace.

---

## Initial Forensic Baseline
- **Date**: 2026-08-11
- **Commit SHA**: `6661cf8` (HEAD -> main, origin/main)
- **Target OS**: Linux VM (Ubuntu)
- **Approved Scope**: Backend API, Architect, Viewer, Campus Viewer, Android Logger, Android Navigator.
- **Excluded / Deferred Scope**: Standalone SMAS, legacy `clients/android/`, Google Sign-In, Phase 10 modernization.

---

## Phase 0 — Contain Secrets and Freeze the Baseline

- **Starting state**: Commit `6661cf8`. `.env`, `clients/.env`, `server/.env`, and `.env.example` templates contained exposed credentials (`MAPS_API_KEY`, `APPLICATION_SECRET`). `dist/deploy_to_vm.sh` used hardcoded fallback secret `anyplace_secret_key_2026`.
- **Problems addressed**: R-01 (tracked literal secrets), R-02 (security portion: secret parameterization and safety).
- **Files changed**:
  - `.env.example`
  - `clients/.env.example`
  - `server/.env.example`
  - `.env`
  - `clients/.env`
  - `server/.env`
  - `dist/deploy_to_vm.sh`
  - `build`
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Sanitized all example environment configuration files (`.env.example`, `clients/.env.example`, `server/.env.example`) to replace hardcoded credentials with safe placeholders (`YOUR_GOOGLE_MAPS_API_KEY`, `YOUR_APPLICATION_SECRET`).
  2. Generated a secure random secret for local staging in `.env` / `server/.env` and ensured active `.env` files are ignored by Git.
  3. Modified `dist/deploy_to_vm.sh` to enforce `APPLICATION_SECRET` check rather than using a hardcoded secret fallback.
  4. Scanned workspace to verify no hardcoded application secrets remain in committed template files.
- **Validation**:
  - `git status` scan confirms `.env`, `clients/.env`, `server/.env` are ignored.
  - Secret scan across configuration templates verified clean (no literal production keys).
  - `dist/deploy_to_vm.sh` checked for secret enforcement.
- **Definition of Done result**: PASSED. Exposed values removed from template files, protected environment parameterization enforced, gitignore verified.
- **Commit**: `172a0b4`

---

## Phase 1 — Pin the Linux/Ubuntu Toolchains

- **Starting state**: Commit `172a0b4`. System running Ubuntu 22.04.5 LTS (Jammy Jellyfish).
- **Problems addressed**: R-03 (JVM/startup toolchain contract), R-07 (Android library build setup), R-08 (tiler Linux toolchain), R-12 (web build toolchain).
- **Tool versions pinned**:
  - **Operating System**: Ubuntu 22.04.5 LTS (x86_64)
  - **JVM / Java**: OpenJDK 11 (`/usr/lib/jvm/java-11-openjdk-amd64`, OpenJDK 11.0.26)
  - **sbt**: 1.9.9 (using Scala 2.13.8, Play 2.8.13)
  - **Node / npm**: Node.js v22.23.2, npm 10.9.8
  - **Web Build Tools**: `grunt-cli` v1.5.0, `bower` 1.8.14 installed globally
  - **MongoDB**: `mongod` v6.0.29 bound to `127.0.0.1:27017`
  - **Tiler Tools**: ImageMagick 6.9.11-60 Q16 (`convert`, `identify`), `advpng` (advancecomp), Python 3.10.12
- **Actions taken**:
  1. Ran preflight tool audits for OS, JDK, sbt, Node/npm, MongoDB, and floorplan tiler utilities.
  2. Verified OpenJDK 11 installation at `/usr/lib/jvm/java-11-openjdk-amd64` for Play 2.8 runtime compatibility.
  3. Installed global web build dependencies `grunt-cli` and `bower` via npm.
  4. Executed full backend compilation using `JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 sbt compile` (compiled 69 Scala and 6 Java sources cleanly in 33s).
  5. Validated MongoDB service binding on `127.0.0.1:27017` (localhost-only, no public port exposure).
  6. Validated native floorplan tiler binaries (`convert`, `identify`, `advpng`, `python3`).
- **Validation**:
  - `sbt compile`: PASSED (0 errors).
  - Mongo network check: `127.0.0.1:27017` LISTEN only (PASSED).
  - Tiler tools check: all required binaries present and executable (PASSED).
  - Web tools check: `grunt-cli v1.5.0` and `bower 1.8.14` ready (PASSED).
- **Definition of Done result**: PASSED. Target Linux/Ubuntu toolchain fully pinned, repeatable, and verified with clean backend compile.
- **Commit**: `2ba13a8`

---

## Phase 2 — Make Backend Startup and MongoDB Connectivity Reproducible

- **Starting state**: Commit `2ba13a8`. OpenJDK 11 pinned as JVM target.
- **Problems addressed**: R-02 (service configuration safety), R-03 (JVM/startup stability), R-13 (startup telemetry).
- **Files changed**:
  - `server/app/Anyplace.scala` (disabled Google Analytics telemetry by default under D-09 policy)
  - `server/conf/application.conf` (created canonical configuration aggregator importing `app.base.conf`, `app.play.conf`, and `app.private.conf`)
  - `server/conf/app.private.conf` (created protected local staging configuration)
  - `server/conf/logback.xml` (fixed logback keyword `%5Level` -> `%5level`)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Created `server/conf/application.conf` to explicitly chain configuration files.
  2. Provisioned protected local staging configuration `server/conf/app.private.conf` specifying localhost-bound MongoDB settings and secret keys.
  3. Modified `server/app/Anyplace.scala` to evaluate `analytics.enabled` (defaulting to false under D-09 policy) rather than sending unconditional startup telemetry to Google Analytics.
  4. Fixed logback pattern syntax in `server/conf/logback.xml`.
  5. Performed two consecutive clean server start/stop cycles using `JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 sbt "run 9000"`.
- **Validation**:
  - `GET /api/version`: HTTP 200 `{"version":"4.2.6","variant":"local","port":"9000","address":"localhost"}` (PASSED).
  - `POST /api/mapping/space/public`: HTTP 200 `{"spaces":[],"buildings":[]}` (proves MongoDB connection, database selection, and collection read) (PASSED).
  - Telemetry verification: Server output confirmed `External analytics disabled by default (D-09 policy)` (PASSED).
  - MongoDB network binding: Verified `127.0.0.1:27017` LISTEN only (PASSED).
  - Two consecutive clean start/stop cycles completed cleanly without error (PASSED).
- **Definition of Done result**: PASSED. Backend startup and MongoDB connectivity are reproducible and safe.
- **Commit**: `2d1a0e8`

---

## Phase 3 — Restore the Backend Test and Core API Baseline

- **Starting state**: Commit `2d1a0e8`. `sbt test` failed to compile due to missing `play-specs2` test dependencies (R-04) and `server/test` ignored in `server/.gitignore`.
- **Problems addressed**: R-04 (uncompilable backend test suite), core API verification baseline.
- **Files changed**:
  - `server/build.sbt` (added `"com.typesafe.play" %% "play-specs2" % "2.8.8" % Test` dependency)
  - `server/.gitignore` (unignored `!test/` directory to allow tracking backend test suites)
  - `server/test/ApplicationSpec.scala` (created core API integration specification with gzip-aware response extraction helper)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Updated `server/build.sbt` to add `play-specs2` test dependency.
  2. Modified `server/.gitignore` to allow tracking `server/test/`.
  3. Created `server/test/ApplicationSpec.scala` testing unmapped route redirects (303), `/api/version` (200 JSON), and `/api/mapping/space/public` (200 JSON).
  4. Executed `JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 sbt test` to verify clean compilation and execution of the backend test suite.
- **Validation**:
  - `sbt test`: PASSED (3 examples, 0 failures, 0 errors in 5.9s).
  - Unmapped route test: PASSED (HTTP 303 redirect).
  - `/api/version` endpoint test: PASSED (HTTP 200 JSON).
  - `/api/mapping/space/public` endpoint test: PASSED (HTTP 200 JSON).
- **Definition of Done result**: PASSED. Backend test suite compiles and runs cleanly with green status documenting core API behavior.
- **Commit**: `0ef265f`

---

## Phase 4 — Restore Web Assets and Developer API

- **Starting state**: Commit `0ef265f`. Web apps lacked precompiled `build/` assets (R-05), resulting in 404 responses for bundled JS/CSS; Swagger JSON specification routing was verified (R-06, R-12).
- **Problems addressed**: R-05 (missing frontend web assets), R-06 (stale/broken Swagger specification path), R-12 (installer omitted frontend build step).
- **Files changed**:
  - `server/public/anyplace_viewer_campus/bower.json` (added `"angular-aria": "1.5.8"` resolution for non-interactive automated installs)
  - `build` (added `build_web_apps` routine invoking `bower install --config.interactive=false`, `npm install`, and `grunt deploy` prior to `sbt dist`)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Updated `bower.json` in `anyplace_viewer_campus` to specify missing resolution for `angular-aria`.
  2. Executed Grunt build pipelines (`concat`, `uglify`, `cssmin`, `imagemin`) across `anyplace_architect`, `anyplace_viewer`, and `anyplace_viewer_campus` to generate `build/js/anyplace.min.js` and `build/css/anyplace.min.css`.
  3. Integrated `build_web_apps` into root `./build` script.
  4. Verified runtime routing for `/architect/` (200 OK), `/viewer/` (200 OK), `/developers/` (200 OK), and `/assets/swagger.json` (200 OK with full OpenAPI 2.0 definition).
  5. Verified static web assets load without 404s (`architect/build/js/anyplace.min.js` 200, `viewer/build/js/anyplace.min.js` 200, `developers/js/swagger-ui-bundle.js` 200).
- **Validation**:
  - `architect`, `viewer`, `viewer_campus` Grunt builds: PASSED.
  - `./build --server`: PASSED (Built web assets, generated Swagger spec, created `dist/anyplace-server-production.zip`).
  - Runtime asset HTTP status check: PASSED (All 200 OK).
- **Definition of Done result**: PASSED. Entry pages, required assets, and Swagger return 200 from a clean artifact.
- **Commit**: `cbb9015`

---

## Phase 5 — Establish the Empty Data Baseline and Hydration Contract

- **Starting state**: Commit `cbb9015`. Missing schema initialization tooling (R-07, R-13) and legacy fallback data dependencies (R-18).
- **Problems addressed**: R-07 (empty database seed script missing), R-13 (database tooling out-of-date), R-18 (hardcoded fallback data dependencies).
- **Files changed**:
  - `server/database/init_schema.js` (created MongoDB schema baseline script with collection definitions and 2DSphere spatial indexes)
  - `server/database/init_database.sh` (created reproducible database initialization and reset tool with `--drop` support)
  - `server/test/DatabaseBaselineSpec.scala` (created automated spec verifying empty database baseline, initial admin registration, subsequent user registration, and empty space payload contracts)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Built `init_schema.js` creating core MongoDB collections (`users`, `spaces`, `campuses`, `floorplans`, `pois`, `edges`, `fingerprintsWifi`, `accessPointsWifi`) and 2DSphere geospatial indexes.
  2. Built `init_database.sh` script providing repeatable DB wipe (`mongosh --eval "db.dropDatabase()"`) and baseline creation.
  3. Executed `./server/database/init_database.sh --drop` and verified clean initialization on MongoDB v6.0.29.
  4. Created `DatabaseBaselineSpec.scala` and executed `sbt test`.
- **Validation**:
  - `init_database.sh --drop`: PASSED (Database wiped and 15 collections/indexes initialized clean).
  - First user registration test: PASSED (Assigned `admin` role).
  - Second user registration test: PASSED (Assigned `user` role).
  - Empty space payload test: PASSED (`HTTP 200` with `{"spaces":[],"buildings":[]}`).
  - `sbt test`: PASSED (6 total examples, 0 failures, 0 errors).
- **Definition of Done result**: PASSED. Database baseline initialization script is reproducible and the backend operates cleanly on empty state.
- **Commit**: `549a01a`

---

## Phase 6 — Verify and Repair the Floorplan/Tiler Pipeline

- **Starting state**: Commit `549a01a`. `start-anyplace-tiler.sh` failed under Ubuntu 22.04 LTS (R-08) due to `python` missing (only `python3` available), missing `chmod +x` on helper scripts, Python 2 -> 3 `bytes` parsing error in `getImageInfoFromFile2`, uninstalled `zip` system dependency, and slow `advpng -4` zopfli re-compression.
- **Problems addressed**: R-08 (floorplan/tiler pipeline failures).
- **Files changed**:
  - `server/anyplace_tiler/start-anyplace-tiler.sh` (added `python3` detection fallback and executable invocation)
  - `docker/anyplace/tiler/start-anyplace-tiler.sh` (added `python3` detection fallback and executable invocation)
  - `server/anyplace_tiler/anyplace-tiler.py` (fixed Python 3 stdout `bytes` decoding and quote stripping in `getImageInfoFromFile2`)
  - `docker/anyplace/tiler/anyplace-tiler.py` (fixed Python 3 stdout `bytes` decoding and quote stripping in `getImageInfoFromFile2`)
  - `server/anyplace_tiler/googletilecutter-0.11.sh` (optimized `advpng` compression level from `-4` zopfli to `-2` libdeflate)
  - `docker/anyplace/tiler/googletilecutter-0.11.sh` (optimized `advpng` compression level from `-4` zopfli to `-2` libdeflate)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Updated `start-anyplace-tiler.sh` in both server and docker trees to detect `python3` when `python` binary alias is absent.
  2. Applied `chmod +x` permissions to all tiler `.sh` and `.py` scripts.
  3. Fixed `getImageInfoFromFile2` in `anyplace-tiler.py` to properly decode subprocess stdout bytes (`dim.decode('utf-8')`) and extract integer dimensions.
  4. Installed `zip` utility (`apt-get install -y zip`) required by `fix-tile-structure.sh`.
  5. Updated `googletilecutter-0.11.sh` to use `advpng -2` for fast, reliable tile compression.
  6. Verified end-to-end tile generation on a test floorplan image across zoom levels 19 to 22.
- **Validation**:
  - `start-anyplace-tiler.sh` execution test: PASSED (Successfully generated `static_tiles/19`, `20`, `21`, `22`, `bounds.txt`, and `tiles_archive.zip`).
- **Definition of Done result**: PASSED. End-to-end tile generation creates valid tile tree and archive from reference floorplan image without process hangs or path errors.
- **Commit**: `d1af442`

---

## Phase 7 — Recover Android Logger and Navigator

- **Starting state**: Commit `d1af442`. Legacy package names `cy.ac.ucy.cs.anyplace.*`, missing Android SDK build tools, legacy external server defaults (`map.beout.ai`), missing `gradle-wrapper.jar`.
- **Problems addressed**: R-03, R-04, R-05, R-10, R-14, R-15, R-17 (Android Logger & Navigator recovery, identity rebrand, SDK pinning, default E-JUST server configuration).
- **Files changed**:
  - `clients/android-new/logger/build.gradle` (rebranded `applicationId` to `eg.edu.ejust.anyplace.logger`, updated default server URL)
  - `clients/android-new/navigator/build.gradle` (rebranded `applicationId` to `eg.edu.ejust.anyplace.navigator`, updated default server URL)
  - `clients/android-new/gradle/wrapper/gradle-wrapper.jar` (generated Gradle 6.5.1 wrapper JAR)
  - `clients/android-new/gradle/wrapper/gradle-wrapper.properties` (pinned Gradle distribution URL `gradle-6.5.1-all.zip`)
  - `clients/android-new/local.properties` (configured `sdk.dir=/opt/android-sdk`)
  - `clients/.env` (updated `SERVER_HOST=anyplace.ejust.edu.eg` and `SERVER_URL=http://anyplace.ejust.edu.eg:443`)
  - `clients/.env.example` (updated `SERVER_HOST=anyplace.ejust.edu.eg` and `SERVER_URL=http://anyplace.ejust.edu.eg:443`)
  - `docs/recovery/EXECUTION_LOG.md`
- **Actions taken**:
  1. Installed Android SDK Command Line Tools (`commandlinetools-linux-9477386_latest.zip`) into `/opt/android-sdk`.
  2. Accepted SDK licenses and installed `platforms;android-29` and `build-tools;29.0.2`.
  3. Provisioned `clients/android-new/local.properties` pointing to `sdk.dir=/opt/android-sdk`.
  4. Rebranded Android `applicationId` in `logger/build.gradle` and `navigator/build.gradle` to `eg.edu.ejust.anyplace.logger` and `eg.edu.ejust.anyplace.navigator` under Decision D-01 and D-02.
  5. Configured default API server endpoints to E-JUST infrastructure (`http://anyplace.ejust.edu.eg:443`) under Decision D-06.
  6. Generated Gradle wrapper 6.5.1 JAR.
  7. Executed `./gradlew assembleDebug` and `./gradlew assembleRelease`.
- **Validation**:
  - `./gradlew assembleDebug`: PASSED (`BUILD SUCCESSFUL in 1m 20s`).
  - `./gradlew assembleRelease`: PASSED (`BUILD SUCCESSFUL in 1m 11s`).
  - `aapt dump badging` verification on `logger-debug.apk` & `logger-release-unsigned.apk`: PASSED (`package: name='eg.edu.ejust.anyplace.logger'`).
  - `aapt dump badging` verification on `navigator-debug.apk` & `navigator-release-unsigned.apk`: PASSED (`package: name='eg.edu.ejust.anyplace.navigator'`).
- **Definition of Done result**: PASSED. Both Android Logger and Navigator assemble cleanly into valid APKs with E-JUST package identity and default endpoint URLs.
- **Commit**: `c544857`

---






