# AGENTS.md

E-JUST fork of the Anyplace indoor-navigation platform, mid-recovery. Phases 0–9 are claimed complete in `docs/recovery/PHASES_COMPLETED.md`; the active contract is a verification audit.

## Read first
- `CONTEXT.md` — required domain vocabulary (Campus, Space, Floor, Floorplan, POI, Connection, Radiomap, Access Point). Use these terms, not synonyms.
- `EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md` — the audit contract. Trust git/source/tests over completion claims.
- `RECOVERY_REPORT.md` — pre-recovery investigation snapshot (partly stale; it predates the completed phases).
- Phase 10 (modernization: AngularJS/Bower/Grunt/Play upgrades, old-client deletion) is OUT OF SCOPE.

## Layout (non-obvious)
- `server/` = Play 2.8 (Scala 2.13) + MongoDB backend. Web clients also live here: `server/public/{anyplace_architect,anyplace_viewer,anyplace_viewer_campus}` (legacy AngularJS/Bower/Grunt) + `developers` (Swagger) + `shared`.
- `clients/android-new/` = current Android apps (`logger`, `navigator`). `clients/android/` = legacy app, excluded launch scope — don't modify its code. `clients/deprecated/`, `docker/` = legacy.
- `server/anyplace_tiler/` = floorplan tiling pipeline (bash/Python/ImageMagick), Linux-only; will not run on Windows.
- `server/database/` = manual MongoDB init/admin tools, not startup migrations.
- Root `build` script + `dist/` produce deployment artifacts.

## Commands
- Backend tests: `cd server; JAVA_HOME=<OpenJDK 11> sbt test` (expect 19 passing). Wrapper: `server/sbt` / `server/sbt.bat`.
- Backend run: pinned JDK is 11. Bare Java 17 startup fails; workaround `--add-opens=java.base/java.lang=ALL-UNNAMED`.
- Build: `./build --server` (also builds all web apps via bower/npm/grunt) | `--clients` (Android APKs → `apk generated/`) | `--all`.
- Single web app: `cd server/public/<app>; bower install; npm install; grunt deploy`.
- DB init: `cd server/database && ./init_database.sh [--drop]` (mongosh).
- Deploy: `cd dist && APPLICATION_SECRET=<...> ./deploy_to_vm.sh <port>`. Fails without `APPLICATION_SECRET` by design.

## Config
- `server/conf/application.conf` includes `app.base.conf` + `app.play.conf` + `app.private.conf`. The private file is gitignored; copy `app.private.example.conf` → `app.private.conf` and fill in (Mongo creds, `cors.allowedOrigins`, `application.secret`, password salt/pepper). Never commit or print it.
- `.env`, `server/.env`, `clients/.env` are gitignored copies of the `.env.example` templates.
- `anyplace.ejust.edu.eg` is illustrative (decision D-07), not the confirmed official hostname. Derive hostnames from environment/config (PUBLIC_BASE_URL style); never do a global domain replacement.

## Android
- Toolchain: Gradle wrapper 6.5.1, AGP 4.0.2, compile/target SDK 29, build-tools 29.0.2.
- Requires `clients/android-new/local.properties` (`sdk.dir=...`) and `clients/.env` (`MAPS_API_KEY`, `SERVER_URL`). `MAPS_API_KEY` is also read from `$HOME/MAPS_API_KEY` as a fallback.
- Shared code comes from JitPack (`com.github.dmsl:anyplace-lib-core:4.0.2`, `com.github.dmsl:anyplace-lib-android:4.0.2`). `settings.gradle` still `include`s `:lib` and `:lib-core` whose directories (`clients/android-new/lib`, `clients/core/lib`) are absent in a fresh checkout — the build needs those dirs present or the includes removed.
- Package IDs: `eg.edu.ejust.anyplace.logger` / `eg.edu.ejust.anyplace.navigator` (D-11).

## Tests & invariants
- Backend specs (ApplicationSpec, DatabaseBaselineSpec, SecurityRegressionSpec, IntegrationSpec) must handle gzip responses — helpers decompress before parsing.
- `DatabaseBaselineSpec` uses unique per-run emails; fixed emails will fail with duplicate-email 400.
- Invariants under test: first registrant = admin, subsequent = user (public bootstrap must stay blocked until admin verified); password never echoed; unauthenticated protected routes rejected.
- MongoDB must be authenticated and localhost-bound only (D-06); analytics disabled by default (D-09); never expose Mongo publicly.

## Environment
- Production target: Ubuntu 22.04 LTS, OpenJDK 11, MongoDB 6.0.29, ImageMagick 6.9, grunt-cli 1.5.0, bower 1.8.14. The Windows host is dev/investigation only.
- Do not fabricate official DNS, TLS, map keys, or signing material — mark dependent work `EXTERNAL DEPENDENCY`.
