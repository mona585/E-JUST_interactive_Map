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
- **Commit**: `[Phase 3]` (to be committed)

---


