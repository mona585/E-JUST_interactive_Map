# Anyplace Recovery Investigation

Status: **Investigation complete — D-01 through D-11 accepted; no recovery implementation has been performed.**  
Evidence date: 2026-08-09 to 2026-08-10 (Africa/Cairo).

## Executive Summary

The checked-out backend is recoverable but the repository is not currently a reproducible, functioning whole-system deployment. A clean main-source compile succeeded. With explicit Java module-opening flags, the Play server started, connected to the configured MongoDB instance, and returned HTTP 200 from `/api/version` and the public Spaces endpoint. That endpoint returned no public Spaces, so data-dependent workflows could not be exercised.

Production recovery will target a Linux server or VM, preferably Ubuntu LTS. The current Windows machine is limited to development and investigation; native Windows ports of systemd/Nginx, Bash deployment scripts, and the floorplan tiler are explicitly outside recovery scope.

Initial production may use a new empty MongoDB database and empty floorplan/radiomap roots because no authoritative deployment snapshot is currently available. Official data will be hydrated later from a coordinated MongoDB dump plus matching filesystem data; partial local artifacts are not an authoritative seed.

Launch-blocking clients are Architect, Viewer, Campus Viewer, Android Logger, and Android Navigator, together with the backend API. Navigator's required acceptance behavior is mobile navigation/pathfinding to specific POIs. The standalone SMAS application is deferred and the legacy `clients/android/` application is excluded.

Launch authentication is local Anyplace authentication only. Google Sign-In is deferred, although Google Maps and Navigator's separately named map/shared-service keys remain required. Because the first local registrant in an empty database is automatically made administrator, production must not be exposed before a controlled account-bootstrap policy is decided and executed.

Anonymous self-registration is required at launch for the university user base. The initial Administrator must be created and verified through a controlled private bootstrap before public API ingress is enabled; all later registrants must be verified as ordinary Users.

Initial MongoDB will run on the Ubuntu application VM, authenticated and bound to localhost only. Its hostname, port, database, and credentials must remain external configuration so a later move to a separate or managed host does not require application-code changes.

The service will use one parameterized HTTPS public origin for web clients, API routes, generated links, Android endpoint configuration, TLS, and origin policy. `https://map.ejust.edu.eg` is an example of the expected university-owned form, not an assigned hostname. No production hostname or certificate may be assumed until IT supplies them.

Private staging may use separate temporary map-service credentials so recovery can progress. Production is blocked until the university supplies its own Google Maps credentials restricted to the official web origin and Android application signatures. Temporary credentials must not be committed, copied into production artifacts, or promoted as defaults.

All external analytics are disabled by default in staging and production. Recovery relies on local application and service logs only. External analytics may be reconsidered later only through an explicit university review and opt-in configuration.

The initial backup standard is a coordinated nightly snapshot of MongoDB plus floorplan/radiomap files, encrypted off-host, retained for 30 days, with a 24-hour recovery-point objective. Additional snapshots precede deployments and official-data hydration, and restore drills occur quarterly until university IT supplies another policy.

Android Logger and Navigator will use new E-JUST-owned package IDs, `eg.edu.ejust.anyplace.logger` and `eg.edu.ejust.anyplace.navigator`, with university-controlled release signing keys. Existing UCY-signed installations cannot be updated in place and must be treated as separate applications.

Several failures are verified. The checked-in tests do not compile because their Specs2/Play test dependency is absent. The Architect, Viewer, and Campus Viewer HTML entry points load, but required shared and generated assets return 404. Runtime Swagger generation returns 500. The current Android applications cannot build because required git submodules and the Android SDK/configuration are absent. The floorplan tiler is Linux-oriented and its required image tools are unavailable in the inspected Windows environment.

The most urgent risk is security, not feature code: a literal application secret is tracked in `anyplace.service`, and `install.sh` prints generated secrets. Values are intentionally omitted here and represented as `<REDACTED>`. No source code, configuration, database data, remote system, submodule, or dependency lock state was changed during this investigation.

## Source Identity

| Item | Observed state |
|---|---|
| Repository | `origin` = `https://github.com/mona585/E-JUST_interactive_Map` |
| Branch | `master` |
| HEAD | `7b175e9f0d190d1a458c7bcf6bdc75499430e812` (`testing`, 2026-08-09) |
| Remote relation | Local `master` and the locally recorded `origin/master` are 0 ahead / 0 behind; no network fetch was performed |
| Tags | None found; `git describe --always` returned `7b175e9f` |
| Initial tracked state | No tracked modifications observed |
| Initial untracked state | `AGENTS.md` and pre-existing `dev-start.ps1`; both were preserved |
| Investigation outputs | New `CONTEXT.md`, `docs/recovery/RECOVERY_REPORT.md`, and ADR `docs/adr/0001-ejust-android-application-identity.md` only |
| Submodules | `clients/android-new/lib-android` at `b3782c…`; `clients/core/lib` at `c4267d…` |
| Submodule worktrees | Directories exist but are empty/uninitialized; they were not initialized or updated |

The checkout's `.gitmodules` uses SSH GitHub URLs. A helper `git submodule status` call could not run because the available Git shell lacked expected Unix utilities; the index gitlink commits and empty directories provide the stated evidence instead.

## Architecture

The system is a monorepo with these active or potentially active parts:

- `server/`: Play 2.8 backend in Scala/Java. `server/app/` contains controllers, models, datasource code, navigation, positioning, radiomap, and tiler integration. `server/conf/` contains routes and layered configuration.
- `clients/web/`: AngularJS/Grunt Architect, Viewer, and Campus Viewer applications; shared browser API code; a static Swagger UI; and ancillary examples.
- `clients/android-new/`: Logger, Navigator, and SMAS Gradle applications. Their shared `lib-android` and `clients/core/lib` projects are uninitialized submodules.
- `clients/android/`: older Android application with legacy endpoint shapes; its present compatibility is unverified.
- `server/anyplace_tiler/`: shell/Python/ImageMagick floorplan tiling pipeline.
- `server/database/`: MongoDB installation, administration, backup/restore, and Couchbase-to-Mongo migration utilities. These are manual tools, not application startup migrations.
- Root Linux scripts: installation, service start/stop/status, web assembly, and MongoDB fallback handling. `docker/` and `clients/deprecated/` are explicitly or structurally legacy.

Runtime flow:

1. Browser clients call same-origin `/api`; Android clients use a configured/default host.
2. Play routes requests from `server/conf/api.routes` to controllers.
3. Controllers use `MongodbDatasource` for mapped objects and configured filesystem roots for floorplans/radiomaps.
4. Floorplan upload stores metadata in MongoDB, writes the source image, invokes the external tiler, then serves base64 images, tiles, or a ZIP.
5. Architect writes authenticated Campus, Space, Floor, POI, Connection, floorplan, and radiomap data. Viewer clients read public data and request routes. Navigation builds a graph from POIs and Connections and applies Dijkstra routing.

The eager `Anyplace` Guice binding initializes MongoDB during application construction. Startup therefore depends on MongoDB reachability and credentials. It also sends a Google Analytics event unconditionally.

## Version & Toolchain Matrix

| Component | Project requirement | Evidence | Local version | Compatibility result |
|---|---|---|---|---|
| Application | 4.3.1 | `server/conf/app.base.conf` | 4.3.1 response | Verified at `/api/version` |
| Scala | 2.13.8 | `app.base.conf`, `build.sbt` | Build-managed 2.13.8 | Main compilation succeeded |
| Play | 2.8.13 | `project/plugins.sbt` / build settings | Build-managed 2.8.13 | Compiles; runtime warns that only Java 8/11 are supported |
| sbt | 1.6.1 | `project/build.properties` | Checked-in launcher / available sbt | Works; wrapper warns about a missing `java9-rt-export.jar` |
| Java | Documentation conflicts: `.sdkmanrc` says Java 7; README/scripts prefer 11/17; Play banner says 8/11 | repository files and runtime banner | `java` 24.0.1; `JAVA_HOME` 17.0.14 used by sbt | Compile succeeds on 17; bare startup fails; startup succeeds with `--add-opens` |
| MongoDB | Docs describe Community 5.0 | `server/database/MONGO.INSTALL.md` | Windows service running; server version unknown | Port and authenticated app startup verified |
| Mongo Scala driver | 4.4.0 | `server/build.sbt` | Build-managed 4.4.0 | Compile/startup succeeded |
| Node/npm | Legacy Grunt/Bower apps; no modern engine contract found | web package files | Node 20.17.0, npm 10.8.2 | Unverified; npm was blocked by local profile permissions |
| Grunt/Bower | Required by web build scripts | web READMEs/Gruntfiles, `install.sh` | Not on PATH | Web build blocked locally |
| Android | Gradle 7.2, AGP 7.1.3, Kotlin ~1.6, SDK 31, JVM target 11 | `clients/android-new` Gradle files | Java 17; Android SDK absent | Blocked by SDK, config, and submodules |
| Tiler | Bash, Python, ImageMagick, `advpng`, archive tools | tiler scripts | Python 3.11 exists outside failing Git Bash; required image tools absent | Not runnable in inspected Windows environment |
| Deployment OS | Accepted decision: Linux server/VM, preferably Ubuntu LTS | D-01; root scripts, service file, tiler shell | Windows development/investigation host | Compatible target selected; native Windows port is out of scope |

## Configuration Model

`server/conf/application.conf` includes `app.base.conf`, gitignored `app.private.conf`, and `app.play.conf`. `build.sbt` also reads `app.base.conf`. The private file exists locally; no values were copied into this report.

| Area | Keys / source | Sensitivity and behavior |
|---|---|---|
| Server identity | `server.address`, `server.port` | Environment-specific; used in version output and generated links |
| Public origin | proposed `PUBLIC_BASE_URL` deployment variable | Single HTTPS origin under D-07; official value pending university IT; example values must never become defaults |
| Play secrets | `application.secret`, `play.http.secret.key` | Secret; must not be tracked or printed |
| MongoDB | hostname, port, database, app username/password | D-06 selects authenticated localhost-only MongoDB initially; every value remains environment configuration for future migration |
| Password hashing | `password.salt`, `password.pepper` | Secret; code contains compatibility fallbacks, so explicit values are required for a controlled deployment |
| Filesystem | `floorPlansRootDir`, `radioMapRawDir`, `radioMapFrozenDir`, `tilerRootDir` | Must exist and be writable by the service account |
| Play HTTP | `app.play.conf` | CORS, filters, gzip, security headers, request limits, and related Play settings |
| Service | `anyplace.service`, root scripts | Currently embeds machine-specific user/path assumptions and a tracked secret |
| Android | `local.properties`, resource defaults, missing library config | SDK path and external API keys are expected locally and must stay untracked |
| External map credentials | web Maps key, Android `MAPS_API_KEY`, Navigator `SMAS_API_KEY` | Staging and production values must be injected separately; production values must be university-owned and restricted under D-08 |
| Launch authentication | local register/login/refresh endpoints | D-04 makes local authentication launch-blocking and defers Google Sign-In; first-user bootstrap remains security-sensitive |

`install.sh` generates/replaces secret values and then displays them, including the MongoDB password. It also writes service configuration. Re-running it against an existing installation can therefore rotate application secrets and invalidate sessions. `start.sh` has a predictable fallback secret if private configuration parsing fails. These are recovery/security risks, not acceptable production defaults.

Although `app.play.conf` declares several filters, `Filters.scala` supplies only `CORSFilter`. A live request confirmed arbitrary Origin reflection with credentials and no observed CSP or frame-protection header.

## Current Run Baseline

All application HTTP checks used a temporary local port. Outbound HTTP(S) was redirected to a closed local proxy for the successful startup diagnostic so telemetry and OAuth calls could not reach external systems. The diagnostic server was stopped afterward.

| Diagnostic | Result |
|---|---|
| `git status`, branch/log/remote/index inspection | Source identity above; no tracked source modifications initially |
| Isolated `sbt -batch compile` | First attempt blocked by sandboxed dependency access and warned about missing launcher support JAR; not classified as a project failure |
| Dependency resolution with temporary caches | Completed after a timed-out first pass |
| Fresh main compile to an external temporary target | 69 Scala and 6 Java sources compiled successfully in about 37 seconds |
| `sbt test` / `Test / compile` | Failed with 23 compile errors: `ApplicationSpec` and `IntegrationSpec` import Specs2/Play test helpers absent from build dependencies |
| Bare Play run on Java 17 | Port bound, but requests returned 500 during Guice construction: `IllegalStateException: Unable to load cache item` |
| Run with `--add-opens=java.base/java.lang=ALL-UNNAMED` | Server constructed successfully; establishes the Java module-access cause for the bare-run failure |
| `GET /api/version` | HTTP 200: version 4.3.1, variant `local`; configured response port/address describe configuration rather than the temporary diagnostic port |
| `POST /api/mapping/space/public` | HTTP 200 with zero public Spaces; proves request path and MongoDB read, not that the database is empty or complete |
| Web entry points | `/architect/`, `/viewer/`, Campus Viewer, and `/developers/` returned HTML 200 |
| Required web assets | shared API JavaScript and generated app bundle returned 404; current web UIs are verified broken |
| Swagger | static `developers/data/api.json.txt` returned 200; runtime `/assets/swagger.json` returned 500 and `/swagger.json` returned 404 |
| CORS/header probe | Arbitrary Origin was reflected with credentials; CSP and `X-Frame-Options` were not observed |
| MongoDB environment | Windows MongoDB service running and port 27017 open; app initialization authenticated and queried collections |
| Tiler preflight | Git Bash environment lacked required shell/image/archive tools; Windows `convert.exe` is not ImageMagick |
| Runtime data search | No MongoDB dump/archive found; configured radiomap directories are absent; one local raw floorplan file exists without a complete tile/radiomap snapshot |

## Confirmed Problem Inventory

| ID | Severity | Category | Component | Problem | Evidence | Root Cause Status | Proposed Fix | Risk |
|---|---|---|---|---|---|---|---|---|
| R-01 | Critical | SECURITY/SECRET MANAGEMENT | service/install | A literal application secret is tracked, and installation prints secrets | `anyplace.service` history; `install.sh` secret output paths | CONFIRMED | Rotate exposed values; remove literals; load a protected environment/private config; stop printing secrets | Session invalidation or deployment outage during rotation |
| R-02 | High | CONFIGURATION | service/install | Service user/path are machine-specific; installer replaces existing app secrets | `anyplace.service`; `install.sh` substitutions | CONFIRMED | Parameterize service identity/paths and make secret creation idempotent | Incorrect permissions or stale service file |
| R-03 | High | STARTUP BLOCKER / BUILD/TOOLCHAIN | Play/JVM | Bare Java 17 start produces HTTP 500 during Guice construction | Reproduced stack trace; `--add-opens` run succeeds; Play compatibility warning | CONFIRMED | Select a supported JDK/runtime contract or make required flags canonical in every start path | JVM change may expose dependency incompatibilities |
| R-04 | High | TEST/VERIFICATION GAP | backend tests | Checked-in tests do not compile | 23 errors for missing Specs2/Play test types; no Specs2 test dependency in build | CONFIRMED | Restore the matching Play Specs2 test dependency, without changing assertions | Dependency/version conflict |
| R-05 | High | CLIENT/BACKEND INTEGRATION | web clients | Entry HTML loads but required shared/generated assets are missing | HTTP 404 for shared API JS and app bundle; no build/public assets | CONFIRMED | Establish a deterministic web build/assembly step and serve its output | Legacy Node/Bower incompatibility; stale generated assets |
| R-06 | Medium | CLIENT/BACKEND INTEGRATION | Swagger | Runtime Swagger JSON fails while a static copy loads | `/assets/swagger.json` 500; `/swagger.json` 404; stale static JSON 200 | Root cause not yet confirmed. | Capture server stack trace and trace generated asset route before choosing a fix | Generated and static API definitions may diverge |
| R-07 | High | BUILD/TOOLCHAIN | Android/core | Active Android projects cannot resolve required local libraries | Empty gitlink directories; no Android SDK or `local.properties` | CONFIRMED | After approval, initialize pinned submodules and provision documented SDK/keys | SSH access, upstream drift, key handling |
| R-08 | High | FLOORPLAN/TILER | tiler environment | Tiler cannot execute in the inspected Windows environment | Shell preflight and missing ImageMagick/`identify`/`advpng`/archive tools | CONFIRMED | Reproduce the declared Linux toolchain first; do not rewrite tiler yet | Native tool output can vary by version |
| R-09 | High | SECURITY | HTTP filters | Cross-origin credentials are allowed for arbitrary reflected origins; expected security headers are absent | Live header probe; `Filters.scala` binds only CORS | CONFIRMED | Define explicit allowed origins and restore intended security filters/headers | Misconfiguration can block legitimate clients |
| R-10 | Medium | DOMAIN COUPLING / CLIENT INTEGRATION | tile link generation | Generated ZIP URL uses OS separators and `/anyplace/floortiles`, but route is `/api/floortiles` | `AnyPlaceTilerHelper.scala:64-70`; `api.routes:674-718` | CONFIRMED | Generate URL paths with `/` from the configured public base and actual route | Existing consumers may rely on legacy path |
| R-11 | Medium | CLIENT/BACKEND INTEGRATION | web radiomap | Delete URL becomes `/api/api/auth/radiomap/delete` | `clients/web/shared/js/anyplace-core-js/api.js:29,68-69` | CONFIRMED | Remove the duplicated `/api` from the endpoint fragment | Low; validate authenticated delete request carefully |
| R-12 | Medium | BUILD/TOOLCHAIN | installer/web | Web build failures are suppressed while install continues | `install.sh` uses failure suppression around npm/Bower/Grunt and later reports success | CONFIRMED | Fail fast and report the exact failed web stage | Stricter install will expose currently hidden failures |
| R-13 | Medium | EXTERNAL SERVICE / PRIVACY | startup telemetry | Application construction attempts Google Analytics on every start | eager `Anyplace` initialization and tracker call | CONFIRMED | Disable external analytics by default under D-09; retain local service logs; require explicit future university opt-in | Loss of external usage metrics; local operational logs remain |
| R-14 | Critical | SECURITY/SECRET MANAGEMENT | local account bootstrap | On an empty database, the first anonymous caller of the public registration endpoint becomes administrator | `UserController.register:31-59`; `MongodbDatasource.isFirstUser:643-653`; public `api.routes` registration | CONFIRMED | Privately bootstrap and verify the Administrator before ingress; then open registration and verify later accounts receive `user` | Lockout or unauthorized administrative ownership if sequencing is wrong |
| R-15 | High | SECURITY/CONFIGURATION | MongoDB installer fallback | Installer clears Mongo application credentials and Docker fallback publishes port 27017 on host interfaces | `install.sh:118-132,193-196`; database docs separately describe authenticated users | CONFIRMED | Require an authenticated app user and bind/publish MongoDB only on `127.0.0.1`; preserve configurable host fields | Authentication or bind changes can prevent backend startup if sequenced incorrectly |
| R-16 | High | DOMAIN COUPLING / CONFIGURATION | server/web/Android/deployment | Active runtime origins and generated/share URLs are split across hardcoded `map.beout.ai`, original Anyplace domains, config, and client resources | Domain inventory; `install.sh:191`; Viewer/Campus share links; Android resource defaults | CONFIRMED | Introduce one deployment-supplied public base URL and derive active endpoints/links without global replacement | Incorrect derivation can break clients, CORS, tiles, or share links |
| R-17 | High | SECURITY/CONFIGURATION | web/Android map credentials | Web clients embed a Maps key in HTML and Android requires local key properties; current ownership/restrictions are unverified and cannot satisfy the production policy | three active web `index.html` files; `clients/android-new/README.md:4-16` | CONFIRMED for embedded/config paths; credential restriction status UNKNOWN | Inject separate staging/production values; require university-owned origin/package/signature restrictions before production | Bad restrictions can break maps; leaked keys can create quota/billing exposure |
| R-18 | High | SECURITY/CONFIGURATION | Android release signing | No reproducible Logger/Navigator production signing setup exists; the only release helper handles Logger and points to a personal DMSL keystore path | Android application IDs/build files; `clients/android-new/release/bundle.sh`; checked debug APKs | CONFIRMED | Apply D-11's E-JUST package IDs and university-custodied signing keys; keep staging keys separate | New apps cannot update UCY-signed installs; lost production key threatens future updates |

## Domain Dependency Inventory

Classification: A = our backend, B = original Anyplace infrastructure, C = third party, D = deployment/build, E = documentation, F = test/development, G = dead/history, H = unknown.

| Component | File | Current Address/URL | Purpose | Classification | Configurable? | Must Change? | Future Configuration |
|---|---|---|---|---|---|---|---|
| Browser API | `clients/web/shared/js/anyplace-core-js/api.js:29` | `/api` | Same-origin backend base | A | Hardcoded relative base | Usually no | One web runtime base setting only if split-origin deployment is chosen |
| Server public identity | private config / example | `server.address` (`https://localhost` in example) | Public links/version identity | A | Yes | Yes for deployment | `PUBLIC_BASE_URL` environment-derived config |
| Install target | `install.sh:191` | `https://map.beout.ai` | Writes server public identity | A/D | Hardcoded | Yes | Required `PUBLIC_BASE_URL`; no embedded production default |
| New Android host | `clients/android-new/{logger,navigator}/.../strings.xml` | `map.beout.ai` | Default API host | A | User preference/default resource | Yes | Protected build/runtime injection derived from the deployment public base |
| Old Android host | `clients/android/Anyplace/res/values/strings.xml:42` | `https://map.beout.ai` | Default API base | G / excluded | Preference-backed | No; excluded by D-03 | None unless scope is explicitly reopened |
| Backend generated links | `AnyplaceServerAPI.scala`, `AnyPlaceTilerHelper.scala` | `server.address:server.port` plus constructed paths | Floor tile/archive links | A | Partly | Yes; one path is wrong | URI builder using public base URL |
| Original web share links | Viewer/Campus `app.js` and `PoiController.js` | `https://anyplace.cs.ucy.ac.cy/viewer/...` | Shared Viewer URLs | B | Hardcoded | Yes for active clients | Derive from the browser origin / `PUBLIC_BASE_URL` |
| Original web footer links | Viewer/Campus `index.html` | `https://anyplace.cs.ucy.ac.cy`, `/tos`, `#contact` | About/terms/contact/navigation | B | Hardcoded | Product decision | Public-site content configuration |
| Original Android links | old Android About/Logger activities | `http://anyplace.cs.ucy.ac.cy/...` | About/Architect launch | B | Hardcoded | If old app remains supported | Android resource/build config |
| Source copyright headers | many Scala/Java/JS files | `anyplace.cs.ucy.ac.cy` | Historical attribution | G | Hardcoded text | No | Leave unless legal review decides otherwise |
| API documentation | `Anyplace_API_Documentation.md:21` | assumed `https://api.anyplace.cs.ucy.ac.cy` | Example base URL | E | Documentation | Yes when docs are repaired | Document configured public base, not an assumption |
| Local service/reverse proxy | root scripts, README, local proxy guide | Play `127.0.0.1:9000`, Mongo `127.0.0.1:27017` | Local bind/upstream | D/F | Mostly hardcoded | Keep local binds under D-06 | Service environment and proxy config |
| Health documentation | `README.md:367` | `/api/v4/version` | Health check | E | Documentation | Yes | Actual `/api/version` endpoint |
| Old Android tile endpoint | `clients/android/.../AnyplaceAPI.java:89` | `/anyplace/floortiles/zip` | Floorplan ZIP | H / legacy | Hardcoded | If old app is retained | Actual versioned route in one API client |
| External map/CDN/API URLs | web/Android HTML and source | Google, OSM/CARTO, fonts/CDNs, social endpoints | Maps, assets, sharing | C | Mixed | No domain replacement | Separate third-party allowlist/config |

A global domain replacement would be unsafe: many `anyplace.cs.ucy.ac.cy` occurrences are license/header history, while Google/OSM/CDN URLs are third-party dependencies. Only active runtime references should migrate.

## External Dependency Inventory

| Dependency | Consumer | Role | Classification | Current evidence / recovery treatment |
|---|---|---|---|---|
| MongoDB | backend | Core persistence | Required; co-located under D-06 | Authenticated localhost-only baseline; retain configurable host for later separate/managed migration |
| Google Maps JavaScript/Android APIs | web and Android | Base map/geocoding/navigation UI | Required for launch clients | D-08 allows temporary private-staging keys; production requires university-owned, origin/package/signature-restricted keys |
| Google OAuth token-info | backend user login | Validate Google ID tokens | Deferred by D-04 | Source calls `googleapis.com`; Android OAuth client IDs may remain empty for launch |
| Navigator SMAS API key/config | Android Navigator shared library | Shared map/backend module configuration | Required by current Navigator build path; standalone SMAS remains deferred | Android README states `SMAS_API_KEY` is used by Navigator; value must be supplied through protected build configuration |
| Google Analytics | backend startup | Telemetry | Disabled by D-09 | Current unconditional startup attempt must be suppressed; any future use requires university review and opt-in configuration |
| OpenStreetMap/CARTO | web | Map tiles/layers | Optional/feature-dependent | Runtime URLs exist; not tested |
| Google Directions | old Android | Outdoor route support | Feature-dependent | Source reference only |
| Google URL Shortener | web sharing | Legacy shortened links | Legacy/potentially dead | Hardcoded API key occurrence must be treated as `<REDACTED>` and rotated/removed if active |
| Facebook/Twitter/share endpoints | web | Social sharing | Optional | Source reference only |
| Fonts and JavaScript/CSS CDNs | web | UI assets/libraries | Optional but page-dependent | Not tested; local bundle is already incomplete |
| `ip-api.com` | old Android | Network/location helper | Legacy/unknown | Source reference only |
| Maven/Scala repositories | backend build | Dependencies | Build required | Temporary-cache resolution succeeded when network access was allowed |
| Gradle/JitPack/Google repositories | Android | Dependencies | Build required | Not tested because SDK/submodules are absent |
| GitHub SSH submodules | Android/core | Shared application libraries | Build required | Pinned but uninitialized; access not attempted |
| Docker registry/daemon | install fallback | MongoDB provisioning fallback | Deployment optional | Docker CLI exists; no images were pulled |
| Nginx/systemd/Let's Encrypt | Linux deployment | Proxy, service, TLS | Deployment choice | Repository assumes them; not exercised on Windows |

## Existing Feature Verification Matrix

| Feature | Backend | Client | Dependencies | Status | Evidence / Required Test |
|---|---|---|---|---|---|
| Version/health API | `MainController.version` | scripts/docs | Play startup | VERIFIED WORKING | `/api/version` returned HTTP 200 with JVM workaround; docs use a wrong path |
| Authentication/users | `UserController`, `users` collection | Architect/web/Android | MongoDB; local password salt/pepper | NOT YET TESTED | Launch-blocking local register/login/refresh under D-04; verify controlled first-admin bootstrap and ordinary-user behavior; Google login deferred |
| Campuses | `MapCampusController` | Architect/Campus Viewer | MongoDB `campuses` and Spaces | BLOCKED BY ANOTHER FAILURE | No public Space dataset and web assets missing |
| Spaces/buildings | `MapSpaceController` | all clients | MongoDB `spaces` | VERIFIED WORKING | Public list request returned HTTP 200 with zero results; create/update/display still untested |
| Floors | `MapFloorController` | Architect/Viewers | `floorplans` collection, Space | BLOCKED BY ANOTHER FAILURE | Requires an approved mapped Space/dataset |
| Floorplans | `MapFloorplanController` | Architect/Viewers | MongoDB metadata, filesystem, tiler | BLOCKED BY ANOTHER FAILURE | Tiler unavailable and no mapped Floor |
| Floorplan tiles/ZIP | floor tile routes | Android/other consumers | generated tile tree/archive | VERIFIED BROKEN | Link generator route mismatch; no generated assets; old Android uses legacy path |
| POIs | `MapPoiController` | Architect/Viewers | MongoDB `pois`, Floor | BLOCKED BY ANOTHER FAILURE | Requires approved mapped data and restored client assets |
| POI Connections | `MapPoiConnectionController` | Architect/Viewers/navigation | MongoDB `edges`, POIs | BLOCKED BY ANOTHER FAILURE | Requires at least two POIs and approved test data |
| Navigation | `NavigationController`, Dijkstra | Viewers/Android Navigator | POIs, Connections, Android submodules/map keys | BLOCKED BY ANOTHER FAILURE | Launch-blocking under D-03; verify POI selection, same-floor and cross-floor paths, and mobile route display using disposable data |
| Search | POI/Space read paths and client search controllers | Viewers/Android | mapped data, web assets | BLOCKED BY ANOTHER FAILURE | No searchable public data; client assets 404 |
| Architect mapping operations | authenticated mapping routes | Architect | auth, MongoDB, filesystem/tiler | VERIFIED BROKEN | Browser entry loads but required JS bundle/shared API returns 404 |
| Viewer read/display | public mapping routes | Viewer | mapped data, web assets, map provider | VERIFIED BROKEN | Required assets return 404 |
| Campus Viewer | campus/space/floor/POI routes | Campus Viewer | campus data, web assets | VERIFIED BROKEN | Required generated assets absent |
| Swagger/developer API | generated Swagger routes/assets | static Swagger UI | sbt Play Swagger plugin | VERIFIED BROKEN | Runtime JSON 500/404; static file 200 but may be stale |
| Radiomaps | `RadiomapController`, radiomap modules | Architect/Android logger | MongoDB/filesystem | NOT YET TESTED | Paths configured; browser delete URL is malformed |
| Positioning/localization | `PositioningController`, location algorithms | Android/Viewers | radiomap, fingerprints | NOT YET TESTED | Requires validated radiomap and compatible client |
| Access points/heatmaps | controllers and cache collections | Architect | MongoDB fingerprints/caches | NOT YET TESTED | Source/routes exist; no representative dataset or test execution |

## Floorplan/Tiler Pipeline

The active upload path is `POST /api/mapping/floor/floorplan/upload` to `MapFloorplanController.uploadWithZoom`:

1. Parse multipart part `floorplan` and JSON metadata (`buid`, floor number, bounding coordinates, zoom).
2. Validate the mapped Floor and zoom (minimum 18).
3. Update the corresponding `floorplans` MongoDB record with zoom and geographic bounds.
4. Copy the source image to `floorPlansRootDir/<buid>/fl_<floor>/fl_<floor>`.
5. Invoke `tilerRootDir/start-anyplace-tiler.sh` with the image, top-left coordinates, `-DISLOG`, and zoom.
6. Python/shell tiling uses ImageMagick and PNG optimization tools for zoom levels 22 through 19, producing `static_tiles/<zoom>/z...png`, `bounds.txt`, and `tiles_archive.zip`.
7. Play serves a base64 floorplan, static tile paths, and ZIP/link endpoints. Viewer floor controllers use the base64 overlay; Android is expected to consume the ZIP.

Current state: source flow is traced, but no end-to-end upload was attempted because it would write MongoDB and filesystem data and the toolchain preflight failed. The Windows environment lacks the required Unix/image utilities, but D-01 deliberately resolves this by targeting Linux rather than porting the pipeline. Documentation is internally inconsistent (`REAME.md` filename; Python 2.7 claim versus Python 3 code). The URL helper produces a legacy `/anyplace/floortiles` path with OS separators, which does not match current `/api/floortiles` routes. A deprecated upload method also passes four tiler arguments, while the launcher requires five; the routed `uploadWithZoom` path passes five.

The checkout contains one local raw floorplan file under `server/floorplans/`, approximately 1.4 MB, but no corresponding complete tile archive/tree was identified and the configured raw/frozen radiomap directories are absent. This file is evidence of a partial local runtime artifact, not an authoritative recovery dataset.

## MongoDB Startup/Data Path

`Module.scala` eagerly binds `Anyplace`; its constructor calls `MongodbDatasource.initialize(conf)`. Initialization:

1. Reads host, port, database, username, and password from private configuration.
2. Builds an authenticated URI only when both username and password are non-empty; authentication uses the application database as `authSource`.
3. Creates the Mongo client/database.
4. Blocks on `listCollectionNames` and reads the `users` collection to cache administrators/moderators.

The application then uses collections including `spaces`, `campuses`, `floorplans`, `pois`, `edges`, `fingerprintsWifi`, `accessPointsWifi`, `users`, and heatmap/cache collections. A Floor and its floorplan metadata share a `floorplans` record; the Floor identifier is composed from Space identifier and floor number.

Successful application construction plus the public Spaces HTTP 200 proves network reachability, authentication, collection listing, `users` reads, and a `spaces` query. It does **not** prove expected indexes, collection completeness, user validity, backups, or floorplan/radiomap filesystem consistency. Zero public Spaces does not prove the database is empty.

Database installation/user creation, backup/restore, and Couchbase migration tools under `server/database/` are manual. No automatic migration/bootstrap hook was found in the startup path. Before any data write, recovery needs an approved source dataset/backup, a restore plan, counts/checksums, and a disposable target.

No `mongodump` backup/archive is present in the checkout. Repository scripts can back up and restore MongoDB, but they do not capture floorplan or radiomap filesystem roots. A faithful production snapshot therefore requires coordinated MongoDB plus floorplan, raw-radiomap, and frozen-radiomap data from the same deployment state.

D-02 authorizes an empty initial production state. It does not authorize using the current local database or the lone floorplan artifact as production seed data. When official data arrives, hydration must first target an isolated environment, verify document/file relationships and counts, and then use an approved cutover and rollback procedure.

## Blockers vs Technical Debt

### Must Fix to Recover the Existing System

- Contain and rotate tracked/exposed secrets; make service configuration safe.
- Prevent public exposure before a controlled initial administrator exists and the local-registration policy is enforced.
- Replace the unauthenticated/all-interface MongoDB installer fallback with the D-06 authenticated localhost-only baseline.
- Choose and reproduce the target operating system/JDK contract.
- Restore compilable backend tests, then establish a core API regression baseline.
- Make the web build deterministic and serve all required assets.
- Diagnose runtime Swagger failure if developer API is required.
- Restore a controlled MongoDB dataset or approved seed needed for workflow verification.
- Provision and verify the native floorplan tiler on the target environment.
- Initialize pinned shared-library submodules and Android tooling only for clients confirmed in scope.
- Make Android-new Logger and Navigator launch-blocking; keep standalone SMAS deferred and legacy `clients/android/` excluded.
- Correct active backend/client endpoint mismatches and configure the new public domain without global replacement.
- Restrict CORS and restore security headers before internet exposure.

### Can Wait Until After Recovery

- Modernizing AngularJS, Bower, Grunt, Play, or the tiler implementation.
- Refactoring controller/model architecture or replacing Dijkstra/radiomap algorithms.
- Cleaning copyright-header URLs and deprecated client/Docker trees.
- Consolidating documentation beyond correcting recovery-blocking commands.
- Replacing native tiling with a new service, changing data models, or adding features.

## Risks

| Risk | Likelihood | Impact | Mitigation | Rollback |
|---|---|---|---|---|
| Secret rotation breaks sessions/services | High | High | Inventory consumers; stage new protected config; rotate in a maintenance window | Restore prior protected configuration only if still uncompromised; otherwise roll forward |
| First external registrant captures administrator role | High if exposed empty | Critical | Keep ingress closed until the private bootstrap script succeeds and the Administrator role is verified; then confirm a second registration receives `user` | Remove only the unauthorized disposable-environment account; for production, rotate credentials/tokens and repeat clean bootstrap |
| Co-located application and MongoDB share one failure domain | Medium | High | Resource limits/monitoring, tested backups, and off-host backup copies; preserve remote-host configuration | Restore the VM or move the latest verified backup to a replacement host |
| MongoDB and filesystem backups represent different points in time | Medium | High | Coordinated nightly job, manifest/timestamps/checksums, pre-change snapshots, and quarterly isolated restore drills | Restore the last verified coordinated bundle |
| Ubuntu/JDK package selection does not match legacy runtime | Medium | High | Use Ubuntu LTS per D-01, then pin the exact release/JDK from clean compatibility tests | Revert environment definition, not source/data |
| Legacy web dependencies fail on modern Node | High | High | Recreate the oldest evidenced compatible toolchain in isolation | Return to pinned container/VM image and prior generated artifact |
| Mongo restore damages or mixes data | Medium | Critical | Restore only into a new/disposable database; verify counts/checksums before cutover | Drop disposable target or switch connection back; preserve source backup |
| Native tiler version changes output | Medium | High | Pin OS packages; compare known fixture tiles/bounds/archive | Restore prior tool image and generated floorplan tree |
| Domain change misses an active hardcoded URL | High | Medium | Migrate classified runtime references only; log/scan network requests | Revert public-base configuration and client artifact |
| Example university hostname is mistaken for assigned production DNS | Medium | High | Require `PUBLIC_BASE_URL` at deployment; label examples; block production readiness until IT provides DNS/TLS | Revert to internal staging origin without exposing production |
| Temporary staging credentials enter production | Medium | High | Separate secret scopes/artifacts; production readiness checks ownership and restrictions; rotate staging keys | Revoke temporary keys and redeploy with university credentials |
| University Android signing key is lost or exposed | Low with controls | Critical | Restricted university custody, encrypted backup, access audit, and documented recovery; never store key/password in source | Revoke service credentials; signing identity itself may be unrecoverable without a protected backup |
| CORS tightening breaks clients | Medium | Medium | Inventory actual origins and test authenticated preflight/requests | Restore last known explicit allowlist, never wildcard credentials |
| Submodule upstream is unavailable or changed | Medium | High | Use recorded gitlink commits and verify checksums/licenses | Remove initialized worktree and return to recorded gitlink state |

## Open Human Decisions

### Accepted

**D-01 — Target recovery environment (accepted 2026-08-10):** Production recovery will run on a Linux server or VM, preferably Ubuntu LTS unless compatibility evidence supports another distribution. The current Windows machine remains a development/investigation host. Recovery will not port the Linux-oriented systemd/Nginx deployment, Bash scripts, or floorplan tiler to native Windows. This is recorded here rather than in an ADR because it aligns with the repository's evident operating model and is therefore not a surprising architectural deviation.

**D-02 — Initial data state (accepted 2026-08-10):** Recovered production may start with a new empty dataset because no authoritative backup or active deployment data is available. Official data will be hydrated later when a coordinated MongoDB dump, floorplans, and radiomaps are supplied. The partial local floorplan and current local database are investigation artifacts, not authoritative seed data. This decision is deliberately reversible and therefore does not warrant an ADR.

**D-03 — Launch client scope (accepted 2026-08-10):** Launch requires the backend API, Architect, Viewer, Campus Viewer, Android-new Logger, and Android-new Navigator. Navigator pathfinding to specific locations is a core team requirement, so its pinned submodules and API/configuration requirements must be recovered. Standalone SMAS is deferred and the legacy `clients/android/` tree is excluded. Shared SMAS/CV code used internally by Navigator does not make the standalone SMAS feature set launch-blocking. This milestone boundary can be revised without changing the system architecture, so no ADR is required.

**D-04 — Launch authentication scope (accepted 2026-08-10):** Local Anyplace authentication is launch-blocking; Google Sign-In is deferred to reduce external credential and availability dependencies. Android OAuth client IDs may remain empty for launch. This does not remove the independent Google Maps and Navigator shared-service key requirements. The decision is a reversible milestone boundary and does not warrant an ADR.

**D-05 — Local account bootstrap and registration (accepted 2026-08-10):** Anonymous self-registration remains available at launch because manual provisioning cannot serve the university user base. Before public API access is enabled, a controlled private bootstrap script must create the initial Administrator and verify its role. A subsequent test registration must receive the ordinary `user` role before ingress opens. The bootstrap must be idempotent or fail closed when any user already exists. This follows the existing role model and does not warrant an ADR.

**D-06 — Initial MongoDB topology (accepted 2026-08-10):** Initial recovery and production testing will co-locate MongoDB on the Ubuntu application VM. MongoDB must require an application credential, bind only to localhost, and not expose port 27017 publicly. Host, port, database, and credentials remain external configuration so the database can later move to a separate or managed host if required by IT or operational load. This matches the repository's primary topology and is intentionally reversible, so no ADR is required.

**D-07 — Canonical public origin (accepted 2026-08-10):** The recovered system will use one HTTPS origin controlled by university infrastructure; `https://map.ejust.edu.eg` is illustrative until IT assigns the actual DNS name and TLS material. Server public identity, generated links, deployment/proxy configuration, and Android endpoint configuration must be supplied from environment/build configuration rather than embedded hostnames. Browser API calls should remain same-origin under `/api`. This configuration choice is intentionally replaceable and does not warrant an ADR.

**D-08 — External map credential ownership (accepted 2026-08-10):** Private development/staging may use separate temporary credentials so recovery is not blocked. Production requires university-owned Google Maps credentials restricted to the official HTTPS origin and Android package names/signing certificates. Temporary values must remain outside source control and production artifacts. Navigator's `SMAS_API_KEY` must be protected and its actual service scope verified from the pinned shared libraries before use. Credential rotation is operationally reversible and does not warrant an ADR.

**D-09 — Analytics/telemetry policy (accepted 2026-08-10):** External analytics and tracking are disabled by default in staging and production. The system will rely on local application/service logs during recovery. Analytics may be revisited only if a specific requirement receives university review and is implemented as an explicit opt-in using university-controlled configuration. This policy is reversible and does not warrant an ADR.

**D-10 — Coordinated backup policy (accepted 2026-08-10):** The initial standard is a nightly coordinated backup of MongoDB and floorplan/raw-radiomap/frozen-radiomap filesystem roots, encrypted and copied off the application VM, with 30-day retention and a 24-hour RPO. Additional coordinated snapshots precede deployments and official-data hydration. Restore is tested quarterly in isolation. University IT may later replace frequency or retention requirements. This operational policy is reversible and does not warrant an ADR.

**D-11 — Android application/signing identity (accepted 2026-08-10):** Logger and Navigator will use `eg.edu.ejust.anyplace.logger` and `eg.edu.ejust.anyplace.navigator`, respectively, with production signing keys created, controlled, and backed up by the university. Staging/debug signing identities remain separate. Because the original UCY signing keys are unavailable, UCY-signed installations cannot receive in-place updates and the E-JUST applications are clean institutional identities. Distribution may use a university-managed channel selected later without transferring signing-key custody. See [ADR 0001](../adr/0001-ejust-android-application-identity.md).

### Open

None. The grill resolved every owner decision required to finalize this investigation plan. External values still awaited from university IT—official DNS/TLS, production map credentials, signing-key material, and any future backup-policy override—are delivery dependencies, not unresolved design decisions.

## Recovery Plan

This plan restores existing behavior only. Each phase must produce reviewable evidence before the next begins; source, data, infrastructure, and domain changes remain separate.

### Phase 0 — Contain Secrets and Freeze the Baseline

- **Objective:** Eliminate immediate credential exposure while preserving a forensic baseline.
- **Why now:** A tracked secret and console disclosure make every later deployment unsafe.
- **Problems addressed:** R-01, security portion of R-02.
- **Likely components:** `anyplace.service`, `install.sh`, private config, deployment secret store, Git history review.
- **Allowed change:** Secret rotation and minimal configuration/deployment edits; no feature code or history rewrite without separate approval.
- **Validation:** secret scan; service starts using protected values; installer logs contain no secrets; old values rejected where observable.
- **Expected result:** No live credential is tracked or printed.
- **Rollback:** Preserve encrypted/protected configuration backup; roll forward with a new secret if rotation fails.
- **Definition of Done:** All exposed values rotated, consumers inventoried, protected source documented, repository/log scan clean.
- **Dependency on next phase:** Provides a safe environment definition and credentials for reproducible startup.

### Phase 1 — Pin the Linux/Ubuntu Toolchains

- **Objective:** Produce one reproducible Ubuntu LTS environment contract for backend, co-located MongoDB tools/service, web, tiler, and in-scope clients.
- **Why now:** D-01 fixes Linux as the target; the exact Ubuntu LTS release, Java version, and legacy build tools must now be validated and pinned.
- **Problems addressed:** R-03, R-07, R-08, R-12.
- **Likely components:** README/deployment docs, environment/container/VM definition, JDK/sbt/Node/Grunt/Bower/native package setup; no algorithm changes.
- **Allowed change:** Build/deployment configuration and documentation only.
- **Validation:** clean main compile; tool version report; authenticated localhost-only MongoDB preflight with no public listener; tiler preflight; web dependency install; Android tool check if in scope.
- **Expected result:** A new Linux server/VM can reproduce tool availability without personal paths; Windows remains a non-production investigation host.
- **Rollback:** Discard the environment image/VM and return to the recorded source commit.
- **Definition of Done:** Versions are pinned, setup is repeatable, and no required tool depends on an undocumented workstation state.
- **Dependency on next phase:** Supplies the supported JVM and Mongo tooling needed for reliable backend startup.

### Phase 2 — Make Backend Startup and MongoDB Connectivity Reproducible

- **Objective:** Start Play through one canonical command/service with explicit, protected configuration against the D-06 local MongoDB baseline.
- **Why now:** Every API and client test depends on a stable server and datastore connection.
- **Problems addressed:** R-02, R-03, R-13; Mongo verification gaps.
- **Likely components:** start/service scripts, JVM options, private config contract, `Anyplace` startup telemetry setting.
- **Allowed change:** Minimal startup/configuration changes; no schema or domain behavior change.
- **Validation:** clean start/stop; `/api/version`; authenticated Mongo collection/read probe through the app; confirm Mongo listens only on loopback; prove the application host is configurable; network/log check showing no analytics transmission; restart test.
- **Expected result:** No Guice 500, no fallback secret, deterministic startup failure messages, external analytics disabled, and local service logs available.
- **Rollback:** Restore prior service/start configuration and environment image; database remains untouched.
- **Definition of Done:** Two consecutive clean starts and stops succeed using documented commands and protected config.
- **Dependency on next phase:** Creates the stable server on which tests and API behavior can be restored.

### Phase 3 — Restore the Backend Test and Core API Baseline

- **Objective:** Make existing tests compile and add only narrowly necessary regression coverage for confirmed recovery failures.
- **Why now:** Changes to web, tiler, data, and domain need a trustworthy backend safety net.
- **Problems addressed:** R-04 and core verification gaps.
- **Likely components:** `server/build.sbt`, `server/test/`, route-level test fixtures.
- **Allowed change:** Test dependencies and tests; production code only for separately approved confirmed defects.
- **Validation:** `sbt test`; `/api/version`; local register/login/refresh tests with disposable data, including first-admin and ordinary-user authorization; public Space/floor/POI/Connection/navigation contract tests. Google login is not a launch gate.
- **Expected result:** Existing tests compile and pass; failures identify behavior rather than missing infrastructure.
- **Rollback:** Revert isolated test/build-dependency commit; no production data involved.
- **Definition of Done:** Green repeatable backend suite documents the existing API contract.
- **Dependency on next phase:** Protects web assembly and later endpoint corrections.

### Phase 4 — Restore Web Assets and Developer API

- **Objective:** Build and serve Architect, Viewer, Campus Viewer, shared assets, and accurate Swagger output.
- **Why now:** Browser workflows are currently verified broken even though the backend runs.
- **Problems addressed:** R-05, R-06, R-12.
- **Likely components:** three web Grunt apps, `clients/web/shared`, install/assembly scripts, `WebAppController`, Swagger plugin/routes/static UI.
- **Allowed change:** Build/asset wiring and smallest runtime Swagger repair; no UI redesign.
- **Validation:** clean web build; no 404s in browser/network log; page smoke tests; generated Swagger JSON matches `api.routes`; installer fails on deliberate build error.
- **Expected result:** All three clients initialize against same-origin `/api`; developer UI loads the current API definition.
- **Rollback:** Restore previous packaged static directory/artifact and build scripts.
- **Definition of Done:** Entry pages, required assets, and Swagger return 200 from a clean artifact; smoke tests pass.
- **Dependency on next phase:** Provides the UI needed to verify the existing university mapping workflow against controlled data.

### Phase 5 — Establish the Empty Data Baseline and Hydration Contract

- **Objective:** Create a known-empty production datastore/filesystem baseline and a separate, rehearsable contract for future official-data hydration.
- **Why now:** D-02 permits empty launch, but the system must distinguish intentional emptiness from failed initialization and must not make future hydration ad hoc.
- **Problems addressed:** Database/data verification gap and the absence of an authoritative snapshot; not a confirmed schema defect.
- **Likely components:** new co-located Mongo database, empty configured floorplan/radiomap roots, `server/database/admin`, coordinated off-host backup/hydration runbook, disposable validation database.
- **Allowed change:** Initialize only the explicitly named empty environment; use synthetic fixtures only in disposable test data, never as production content.
- **Validation:** expected empty collection/API behavior; private bootstrap creates and verifies the sole initial Administrator; a second anonymous registration receives `user`; ingress remains closed until both assertions pass; directory ownership; coordinated backup manifest/checksums; encrypted off-host copy; isolated restore drill; isolated synthetic Campus → Space → Floor → POI → Connection fixture; documented checks for a future Mongo/filesystem bundle.
- **Expected result:** Empty production is healthy and observable, while a representative disposable fixture supports workflow tests.
- **Rollback:** Disconnect and remove only the explicitly named new database/filesystem or disposable fixture after preserving diagnostic evidence.
- **Definition of Done:** Empty-state behavior, secure Administrator bootstrap, open post-bootstrap registration, nightly coordinated backups with 30-day retention/24-hour RPO, quarterly restore procedure, permissions, fixture cleanup, future hydration inputs, integrity checks, cutover, and rollback are documented and rehearsed without official data.
- **Dependency on next phase:** The disposable Space/Floor fixture supplies the input required for floorplan tiler verification; official hydration remains a later controlled operation.

### Phase 6 — Verify and Repair the Floorplan/Tiler Pipeline

- **Objective:** Reproduce one floorplan upload through metadata, filesystem, tiling, retrieval, and display.
- **Why now:** The native pipeline needs a real Floor and is a prerequisite for complete Viewer/Android behavior.
- **Problems addressed:** R-08, R-10 and floorplan verification gaps.
- **Likely components:** `MapFloorplanController`, `AnyPlaceTilerHelper`, `server/anyplace_tiler`, configured directories, Viewer floor controller.
- **Allowed change:** Environment pinning and smallest path/argument fixes; no tiler rewrite or floorplan model change.
- **Validation:** known image fixture; upload response; Mongo metadata; file tree; tile dimensions/bounds; ZIP integrity; base64/tile/ZIP HTTP retrieval; Viewer overlay.
- **Expected result:** Deterministic tiles/archive and correct `/api/floortiles` URLs using `/` separators.
- **Rollback:** Restore prior helper/script artifact and delete only fixture records/files in the disposable environment.
- **Definition of Done:** One documented fixture passes end to end twice from a clean floorplan directory.
- **Dependency on next phase:** Enables full client workflow and Android floorplan download tests.

### Phase 7 — Recover Android Logger and Navigator

- **Objective:** Build and connect Android-new Logger and Navigator, including Navigator pathfinding to specific POIs.
- **Why now:** D-03 makes both applications launch-blocking; their pinned submodules, SDK, protected keys, and shared SMAS-derived infrastructure are independent blockers.
- **Problems addressed:** R-07 and Android URL/API/configuration unknowns.
- **Likely components:** `clients/android-new/{logger,navigator}`, application IDs, release signing/build configuration, `clients/core/lib`, `lib-android`, Android SDK config, staging/production key injection, required backend compatibility routes. Standalone `smas` and legacy `clients/android/` are not acceptance targets.
- **Allowed change:** Apply the ADR-0001 package/signing identity, initialize pinned submodules, inject protected keys, and make only minimal endpoint compatibility fixes needed by Logger/Navigator; no standalone SMAS feature recovery.
- **Validation:** assemble/test Logger and Navigator with temporary staging keys; assert package IDs `eg.edu.ejust.anyplace.logger` and `eg.edu.ejust.anyplace.navigator`; verify staging and production signing certificates differ; install as new applications; run local login, Space/Floor/POI load, floorplan download, same-floor and cross-floor POI routing, route display, and logger/radiomap smoke tests. Production artifacts require university signing custody and map-key restrictions. Google Sign-In is excluded from launch acceptance.
- **Expected result:** University-signed E-JUST Logger and Navigator applications use the controlled backend and no original deployment host; Navigator reaches selected locations through the existing route model.
- **Rollback:** Return gitlinks/config to recorded state; uninstall test application; revoke test keys if necessary.
- **Definition of Done:** Both E-JUST package IDs build reproducibly under university-controlled production signing, pass their launch workflows, and document that UCY installs are not upgrade-compatible; standalone SMAS and legacy Android are documented exclusions.
- **Dependency on next phase:** Identifies every active client address that domain detachment must configure.

### Phase 8 — Detach the Active System from Original Domains

- **Objective:** Make one required `PUBLIC_BASE_URL`-style deployment value drive server identity, active web sharing, Logger/Navigator endpoints, proxy/TLS, and docs without assuming the example university hostname.
- **Why now:** Changing addresses before active clients and routes are known would hide defects behind a broad replacement.
- **Problems addressed:** R-10, R-11 and classified A/B runtime references.
- **Likely components:** environment/HOCON bridge, private/deployment config, URI builders, active Viewer share links, Logger/Navigator build/runtime config, reverse proxy/TLS, recovery-blocking docs.
- **Allowed change:** Targeted configuration/URL construction only; preserve third-party and historical references unless separately justified. Do not embed the example hostname.
- **Validation:** fail-fast test when the public base is absent; staging-origin substitution; official-origin substitution when supplied; repository runtime-URL audit; browser/device network capture; share-link test; tile archive link; radiomap delete contract test; TLS/redirect/CORS tests.
- **Expected result:** Active requests and generated links use the deployment-supplied owned origin or deliberate third parties only, with no source edit needed to change the origin.
- **Rollback:** Repoint public-base configuration/DNS/proxy to the last verified artifact; keep previous TLS/config snapshot.
- **Definition of Done:** No active runtime dependency on the original Anyplace or temporary deployment domain remains.
- **Dependency on next phase:** Establishes the final network topology for security and regression verification.

### Phase 9 — Security and End-to-End Regression Gate

- **Objective:** Prove the recovered existing system is safe enough to expose and operates as one integrated deployment.
- **Why now:** CORS, headers, credentials, and client origins can be finalized only after the public topology is fixed.
- **Problems addressed:** R-09 and all remaining verification gaps.
- **Likely components:** Play filters/config, proxy headers, test suites, web/device smoke tests, operational scripts.
- **Allowed change:** Minimal security configuration and regression tests; no new features.
- **Validation:** explicit-origin credentialed CORS tests; CSP/frame/content headers; secret scan; production artifact contains no staging credentials; outbound allowlist confirms no analytics traffic; Google key restriction checks; anonymous-registration abuse/rate tests; proof that no later registrant can become Administrator; dependency audit; restart/backup/restore drill; full Campus-to-Navigation and floorplan workflow.
- **Expected result:** Unauthorized origins fail; approved clients work; secrets stay protected; all required existing features have evidence.
- **Rollback:** Restore last explicit allowlist/security config and verified artifact; never restore exposed secrets.
- **Definition of Done:** Required matrix rows are VERIFIED WORKING or have an owner-approved exclusion, with logs and commands archived.
- **Dependency on next phase:** Separates successful recovery from optional modernization.

### Phase 10 — Deferred Cleanup and Modernization

- **Objective:** Address technical debt only after recovery acceptance.
- **Why now:** Framework upgrades, legacy deletion, and tiler redesign are unnecessary risk during restoration.
- **Problems addressed:** Documentation inconsistencies, deprecated trees, legacy build systems, non-blocking warnings.
- **Likely components:** AngularJS/Bower/Grunt, Play/sbt/JDK versions, old Android, Docker/deprecated clients, docs, tiler implementation.
- **Allowed change:** Separately approved, reversible modernization increments with their own decisions/ADRs.
- **Validation:** Phase 9 regression gate plus migration-specific tests and artifact comparison.
- **Expected result:** Reduced maintenance risk without changing accepted behavior unintentionally.
- **Rollback:** Revert each isolated modernization increment to the recovered release tag/artifact.
- **Definition of Done:** Each chosen debt item has independent evidence, acceptance criteria, and owner approval.
- **Dependency on next phase:** None; this phase is explicitly outside recovery completion.
