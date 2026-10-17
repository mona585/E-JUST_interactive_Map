# AGENTS.md

E-JUST fork of the Anyplace indoor-navigation platform. Two independent systems share this repo:
a Scala/Play backend + web suite (`server/`, `clients/web/`), and an **active Flutter Android app**
(`clients/flutter/anyplace_campusfind`). Current branch: `navigation-app`.

## Flutter app: `clients/flutter/anyplace_campusfind` (active)

Android-first app, hard-coded to the E-JUST campus, backend `https://map.beout.ai`.
Needs Flutter >=3.44.0 / Dart ^3.12 (`pubspec.lock`). Run from that directory:

```bash
flutter pub get
flutter analyze        # lint (flutter_lints)
flutter test
flutter run
```

- Config via `--dart-define` only: `SERVER_URL`, `CAMPUS_CUID`, `CAMPUS_NAME`, `OSRM_URL` (defaults in `lib/config/api_config.dart`). There is no campus picker.
- `MAPS_API_KEY` is **not** a Dart define; set it natively in `android/.../AndroidManifest.xml` / iOS `Info.plist`.
- `lib/` layout: `config/ models/ repositories/ datasources/ services/ providers/ viewmodels/ views/ widgets/ utils/`. The app README's `data/ state/ screens/ ui/` tree is stale.
- Tests: `flutter test` uses fakes only. The live-backend smoke test is opt-in: `flutter test --dart-define=LIVE_SMOKE=true test/live_integration_smoke_test.dart`.
- `test/*_test.dart.disabled` files are intentionally excluded by the Dart runner — do not rename them to "restore" coverage.
- Widget tests that mount the map shell must install `FakeGoogleMapsPlatform` from `test/helpers/fake_google_maps_platform.dart` (the real `GoogleMap` has no native renderer in tests).
- **Trap:** the repo root also contains a stale duplicate Flutter app (`lib/{core,data,state,ui}/`, linux-only, no `android/`). Do not run `flutter` commands from the repo root; use `clients/flutter/anyplace_campusfind`.

## Backend: `server/` (Scala 2.13.6 / Play 2.8.8 / MongoDB)

- Pinned toolchain: SBT 1.5.8, Scala 2.13.6, Play 2.8.8 (`server/project/build.properties`, `server/build.sbt`); **OpenJDK 17** for build/run.
- Java 17 needs Guice/CGLIB reflection opens (`--add-opens=java.base/java.lang=ALL-UNNAMED` etc.) — see `start.sh` and `anyplace.service`.
- Tests: `cd server; sbt test`. Mongo-backed specs (`SecurityRegressionSpec`, `CampusContractSpec`) are skipped unless `RUN_MONGO_INTEGRATION_TESTS=true` and `MONGODB_TEST_*` are set (`server/test/resources/application.conf`). `ApplicationSpec`/`ValidateSpec` run without Mongo.
- Specs receive **gzip-compressed** responses; decompress before parsing (see `extractString` helpers).
- Config is layered: `conf/application.conf` includes `app.base.conf` + `app.play.conf` + `app.private.conf`. Copy `conf/app.private.example.conf` -> `app.private.conf`; it reads env refs (`${?PUBLIC_BASE_URL}`, `${MONGODB_*}`, `${?GOOGLE_CLIENT_ID}`). Never commit it or real secrets.
- Local run: `./start.sh` requires `APPLICATION_SECRET` + `MONGODB_*` (rejects `CHANGE_ME_*`, enforces loopback Mongo, selects Java 17); logs to `anyplace.log`. `./stop.sh` / `./status.sh` manage it.
- `server/anyplace_tiler/` is a Linux-only bash/Python/ImageMagick pipeline; it will not run on Windows.

## Web suite: `clients/web/`

- Legacy AngularJS/Bower/Grunt apps (`anyplace_architect`, `anyplace_viewer`, `anyplace_viewer_campus`, `developers` Swagger UI, `shared`).
- Build + stage into `server/public/` with `scripts/build-web-assets.sh` (runs `npm ci`, `bower install --allow-root`, `npx --no-install grunt deploy`). Node 22 / npm 10 pinned — always `npm ci`, never unlocked `npm install`.

## Android apps: `clients/android-new/`

- `logger` / `navigator`, package IDs `eg.edu.ejust.anyplace.{logger,navigator}` (see `docs/adr/0001-*.md`).
- Requires submodules `clients/android-new/lib-android` and `clients/core/lib` (`git submodule update --init --recursive`; SSH remotes = external dependency).
- Gradle 6.5.1 wrapper cannot run on JDK 17 — Android builds need a separate local **OpenJDK 11** for Gradle, even though the backend uses 17.
- `clients/android/` and `clients/deprecated/` are legacy — do not modify.

## Verification (Windows dev host)

Contract checks run under PowerShell and read the repo; run them after changing server config, startup scripts, toolchain pins, or web build:

```powershell
powershell scripts/Test-ToolchainContract.ps1
powershell scripts/Test-StartupContract.ps1
powershell scripts/Test-SecretContainment.ps1   # needs ripgrep (rg) on PATH
powershell scripts/Test-BackendTestBaseline.ps1
powershell scripts/Test-WebAssetContract.ps1
```

On the Ubuntu VM, `scripts/verify-ubuntu-toolchain.sh [--with-android]` validates the toolchain without starting services.

## Deployment / operations

- Production target is **Ubuntu Server 22.04 LTS only**; the Windows host is dev/investigation. Toolchain contract: `docs/recovery/UBUNTU_22.04_TOOLCHAIN.md`. Deploy flow (manual host provisioning): `docs/recovery/PHASE_2_STAGING_RUNBOOK.md`, then Phase 3/4 runbooks.
- `install.sh` is legacy/unmaintained, and `dev-start.ps1` has hardcoded paths from another machine — do not rely on either.
- `anyplace.service` runs as user `anyplace` from `/opt/anyplace`, loading secrets from `/etc/anyplace/anyplace.env` (0600). Secrets must never be embedded in the unit or committed.
- MongoDB must stay authenticated and loopback-bound; analytics is disabled by default. Never expose port 27017.

## Repo notes

- No CI is configured; verification is the manual commands above.
- The working tree currently has unstaged deletions of retired root docs (`CONTEXT.md`, `CONTRIBUTING.md`, several `*-PLAN.md`/`*-REPORT.md`, `changes/`, `plans/`). Leave them deleted; do not recreate.
- `.env`, `server/.env`, `clients/.env` are gitignored copies of `.env.example`; `.sdkmanrc` pins `java=17.0.19-tem`.
- Do not fabricate official DNS, TLS, map keys, or signing material — mark dependent work `EXTERNAL DEPENDENCY`.
