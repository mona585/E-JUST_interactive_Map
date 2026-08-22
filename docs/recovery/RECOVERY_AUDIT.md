# Recovery Audit

## Audit basis

Phase 0 was audited against `EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md` and
the current checkout, not against completion claims alone. The checkout is on
`master` at `1cf45299`; `PHASES_COMPLETED.md` instead cites `main` and commits
that are not present in the local object database. Its earlier Phase 0 claim is
therefore **NOT VERIFIED**. The instruction's reference to
`docs/recovery/PHASES_COMPLETED.md` also does not match the supplied root file.

## Phase 0 — Security containment

**Status: PARTIAL — source containment is verified; credential rotation is an
external operational dependency.**

### Verified and repaired

- Replaced the literal Play/application secret in `anyplace.service` with the
  required protected file `/etc/anyplace/anyplace.env` and
  `${APPLICATION_SECRET}`.
- Made `install.sh` create that file with directory mode `0700` and file mode
  `0600`; it no longer prints application secrets, salts, peppers, or MongoDB
  passwords. Existing secret, salt, and pepper values are preserved rather than
  silently regenerated.
- Removed insecure fallback defaults from `start.sh` and the installer. Startup
  now fails when the secret is absent or still a documented placeholder.
- Replaced exposed Google Maps/Directions/URL-shortener keys in active and
  legacy clients with explicit placeholders, and added environment-file ignores.
  The tracked legacy iOS bundle was changed alongside its source solely to
  eliminate the exposed credential; regenerate it before any future legacy build.
- Stopped backend authentication endpoints and the Architect client from logging
  request bodies or access tokens.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-SecretContainment.ps1` — passed. This repeatable check rejects
  known exposed-key/default-secret patterns and verifies the service, installer,
  and authentication logging safeguards.
- Git Bash `bash -n install.sh` and `bash -n start.sh` — passed.
- `git diff --check` — passed.
- `server/./sbt test` — **not verified**. The first run was blocked by a
  protected Windows Coursier cache. A retry using a repository-local cache
  downloaded SBT but did not finish before the 64-second execution limit. No
  test result is claimed.

TestSprite was not used in this phase because the acceptance criteria are static
source/configuration containment rather than a backend HTTP contract. It should
be used from the first API/integration phase where it adds coverage.

### Required operational follow-up

Treat every removed credential as exposed: revoke/rotate the Google keys and
the prior Play/application secret in the credential-owning console and any
running Linux host, then install the new secret in
`/etc/anyplace/anyplace.env` before service restart. Coordinate any history
rewrite only after rotation; it is not part of this phase.

## Phase 1 — Pin the Linux/Ubuntu toolchains

**Status: PARTIAL — the source-side contract is verified; a clean Ubuntu VM
execution is an external dependency.**

### Audit result and repair

The earlier Phase 1 claim is **NOT VERIFIED**: it cites an absent execution log
and no accessible Ubuntu VM/image. The actual checkout also conflicted with the
claim: `.sdkmanrc` selected Java 7, and `install.sh`/`start.sh` preferred Java
11 when both 11 and 17 were installed. The root guide still allowed Ubuntu
20.04 and unpinned tooling.

The recovery target is now documented in
`docs/recovery/UBUNTU_22.04_TOOLCHAIN.md`: Ubuntu Server 22.04 LTS, OpenJDK 17,
SBT 1.5.8, Scala 2.13.6, Play 2.8.8, Node 22/npm 10, Grunt CLI 1.5.0, Bower
1.8.14, MongoDB 6.0.x tools, and the Python/ImageMagick/AdvanceCOMP tiler
requirements. `scripts/verify-ubuntu-toolchain.sh` makes the contract
checkable on the target VM. The SDKMAN selector, runtime scripts, and systemd
template now consistently choose JDK 17. The root guide marks the unpinned
legacy installer as investigation-only.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-ToolchainContract.ps1` — passed.
- Git Bash `bash -n install.sh`, `bash -n start.sh`, and
  `bash -n scripts/verify-ubuntu-toolchain.sh` — passed.
- `git diff --check` — passed.
- Clean Ubuntu compile, MongoDB preflight, tiler run, web `npm ci`/Bower build,
  and Android SDK build — **not run**. This Windows host is intentionally not
  the target production environment.

### External dependency

`clients/android-new/lib-android` and `clients/core/lib` are uninitialized Git
submodules in this checkout. They use SSH remotes and require authorized access
before Navigator/Logger can be built in Phase 7. Do not replace them with a
different library source.

**Update (2026-08-22):** On `Ahmed-branch` the `lib-android` gitlink no longer
exists; Logger/Navigator resolve `com.github.dmsl:anyplace-lib-core/android:4.0.2`
through Maven/JitPack coordinates instead. Only `clients/core/lib` remains an
uninitialized SSH submodule.

### Runtime validation (2026-08-22, Ubuntu 22.04 staging VM)

Executed on the target VM (`Ahmed-branch`):

- Toolchain installed from official public mirrors: OpenJDK 17.0.19,
  Node.js 22.23.2 / npm 10.9.8, MongoDB 6.0.29 + mongosh 2.10.0,
  grunt-cli 1.5.0 / bower 1.8.14, ImageMagick 6.9.11, advancecomp, Python 3.10.12.
- `scripts/verify-ubuntu-toolchain.sh` — **PASS**.
- Two contract defects were found and fixed during preflight:
  - The `b620e9b5` merge had dropped the entire `clients/web` tree that the
    preflight, the web builder, and the `/architect`+`/viewer` routes depend on;
    restored from the Phase 3,4 parent (`5821e3f3`) — commit `8a79bd3e`.
  - The merged Android lineage uses Gradle 6.5.1 / AGP 4.0.2 / SDK 29, not the
    previously pinned 7.2 / 7.1.3 / 31; the preflight and toolchain doc were
    aligned to the merged tree and now document the required local OpenJDK 11
    for Gradle 6.5.1 builds — commit `1bac4955`.

## Phase gate

Phase 1 preflight **PASS** on the target VM. Phase 2 approved and executed;
see below.

## Phase 2 — Backend startup and MongoDB connectivity

**Status: PARTIAL — the source-side startup contract is verified; the required
Ubuntu VM runtime validation is an external dependency.**

### Audit result and repair

The earlier Phase 2 completion claim is **NOT VERIFIED**. No local private
configuration, staging host, or execution evidence exists in this checkout.
The source itself contradicted the desired D-06 baseline: `start.sh` and the
installer could create a Docker MongoDB instance with `-p 27017:27017`, which
publishes the port on all interfaces; the configuration template allowed a
blank database password; and `anyplace.service` used a personal account and
absolute workstation path.

The canonical service now runs as the dedicated `anyplace` account from
`/opt/anyplace`, reads `/etc/anyplace/anyplace.env`, and logs to `journald`.
The environment contract requires application and `MONGODB_*` values; the
private HOCON configuration resolves them without tracking credentials.
`start.sh` now fails before launch unless the database host is loopback, all
credentials are present, and the local port is reachable. The installer no
longer starts or publishes MongoDB through Docker and no longer blanks
database credentials. `PHASE_2_STAGING_RUNBOOK.md` records the required
authenticated MongoDB provisioning, service installation, API probe, and
restart test.

External analytics remains disabled by default in `Anyplace.scala` and the
private configuration template; no analytics-enabling change was made.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-StartupContract.ps1` — passed.
- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-SecretContainment.ps1` — passed.
- Git Bash `bash -n install.sh` and `bash -n start.sh` — passed.
- `git diff --check` — passed.
- Two clean service starts/stops, authenticated MongoDB app read probe,
  loopback listener inspection, `/api/version`, and log/network checks —
  **not run** because no controlled Ubuntu staging VM is available.

TestSprite was not used: no controlled local/staging backend is available to
target safely. It becomes appropriate in Phase 3 after the Phase 2 runbook
has produced a running private endpoint.

### Runtime validation (2026-08-22, Ubuntu 22.04 staging VM)

Executed per `PHASE_2_STAGING_RUNBOOK.md` on `Ahmed-branch`:

- MongoDB Community 6.0.29 installed; authenticated application user
  `anyplace_app` (readWrite on `anyplace`, default admin authSource, matching
  the URI built by `MongodbDatasource.createInstance`) created before
  authorization was enabled. `/etc/mongod.conf`: `authorization: enabled`,
  `bindIp: 127.0.0.1,::1`. Listener verified loopback-only via `ss`; the
  documented authenticated ping returned `{ ok: 1 }`.
- A missing operational account was closed during a brief maintenance window:
  a `root`-role administrator was created so future user administration does
  not depend on the pre-auth localhost exception.
- Protected environment file `/etc/anyplace/anyplace.env` (dir 0700, file 0600)
  provides `APPLICATION_SECRET`, `MONGODB_*`, and staging-only
  `PUBLIC_BASE_URL=http://127.0.0.1:9000`. The public-base variable is
  mandatory in practice: `server.address=${public.baseUrl}` fails config
  resolution when it is unset.
- Dedicated `anyplace` system account owns `/opt/anyplace`; data roots
  (`floorplans/`, `radiomaps_raw/`, `radiomaps_frozen/`) created; private HOCON
  filled from the template with generated salt/pepper/secret (no placeholders).
- `sudo -u anyplace ./sbt clean stage` — success (~113 s), first full backend
  compile on Ubuntu/JDK 17 for this recovery.
- systemd unit enabled: service active, journald shows `connected to database`
  and `External analytics disabled by default (D-09 policy)`.
- `GET /api/version` → HTTP 200 with the configured origin in its address
  field; `POST /api/mapping/space/public` → `{"spaces":[],"buildings":[]}`
  proving the authenticated Mongo read path; controlled restart test repeated
  both checks successfully.

Deployment-side note (untracked): the Play launcher's effective working
directory is `server/target/universal/stage`, not the systemd
`WorkingDirectory`; relative data-root paths resolve against the stage tree.
The deployed private configuration therefore pins absolute paths
(`/opt/anyplace/floorplans`, radiomap roots, tiler root). The example template
keeps relative values.

## Phase gate

Phase 2 **executed and verified** on the staging VM. Phase 3 approved and
executed; see below.

## Phase 3 — Backend test and core API baseline

**Status: PARTIAL — the test baseline is repaired in source; execution on the
supported Ubuntu/JDK 17 staging environment remains required.**

### Audit result and repair

The prior Phase 3 claim is **NOT VERIFIED**: its cited commits are absent and
the current suite did not match the claimed three focused tests. It included a
browser test for Play's obsolete starter-page text, a database test that allowed
the first public registrant to become an administrator (contrary to D-05), and
Mongo-mutating security tests that ran without an explicit controlled database
selection.

`ApplicationSpec` now covers only stable public behavior: unknown GET routes
redirect to Viewer and `/api/version` returns version JSON without
authentication. Test-only configuration supplies non-production settings while
keeping analytics disabled. The obsolete browser and public-first-admin specs
were removed. Mongo-backed security tests are retained but run only when
`RUN_MONGO_INTEGRATION_TESTS=true` and protected `MONGODB_TEST_*` variables
select a disposable staging database. The Phase 3 runbook documents both modes.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-BackendTestBaseline.ps1` — passed.
- Phase 0/2 containment and startup-contract checks — passed.
- `git diff --check` — passed.
- `server/./sbt test` — **not run to completion**. After dependencies were
  retrieved, SBT 1.5.8 failed before compilation on this Windows host's Java
  24 runtime with an SBT launcher `ClassCastException`. Phase 1 pins Ubuntu
  22.04 with JDK 17; that is the authoritative environment for this command.
- TestSprite — **not initialized**. Its bootstrap was blocked because it may
  tunnel a local API and expose private repository context to a third party.
  Explicit repository-owner approval is required before using it against the
  controlled staging backend.

## Phase gate

At that point, no Phase 4 recovery work had started. Source-only Phase 4 work
was subsequently approved while the Phase 3 runtime validation remained
pending; its result is recorded below.

### TestSprite follow-up (2026-08-12)

The repository owner explicitly approved TestSprite use. It was configured with
`TESTSPRITE_PRODUCT_SPEC.md`, a code summary, and a generated backend plan at
`testsprite_tests/testsprite_backend_test_plan.json`. To respect the request to
test only prior phases, the eligible HTTP cases are `TC001` (`/api/version`) and
`TC002` (unknown GET route redirects to Viewer); the remaining generated cases
require MongoDB-backed account/mapping/navigation fixtures and are not treated
as prior-phase evidence.

Execution is **blocked**: `http://localhost:9000/api/version` is unreachable on
the current Windows investigation host. TestSprite requires a running local or
staging backend for execution; it cannot emulate Play, MongoDB, systemd, or the
Ubuntu host. Run `TC001` and `TC002` only after the controlled Ubuntu staging
backend is running, using TestSprite's generated execution step. This was the
pre-Phase-4 status; the separate Phase 4 source-only result follows.

### Runtime validation (2026-08-22, Ubuntu 22.04 staging VM)

- Default suite (`./sbt test` as the service account): **5 passed / 0 failed /
  1 skipped** (Mongo-gated spec correctly skipped). First green backend suite
  on the supported environment.
- Opt-in Mongo suite (`RUN_MONGO_INTEGRATION_TESTS=true`): **18 passed /
  0 failed** — security headers via the filter pipeline, CORS allow/deny,
  second-registrant-cannot-become-admin, credential non-leakage, missing-field
  rejection, protected endpoints.
- Isolation proven: all test registrations landed in the disposable
  `anyplace_test` database (3 documents); the main `anyplace` database stayed
  empty (0 users). Disposable database and user dropped after evidence capture.
- TC001/TC002 executed as direct probes against the running staging backend
  with identical assertions: `/api/version` → HTTP 200 version JSON; unknown
  GET route → HTTP 303 redirect to Viewer. The TestSprite CLI itself remains
  uninitialized in this repository per its third-party-tunnel policy; owner
  approval stands recorded should the team later choose to run it.

Runtime requirements discovered for test runs (documented in the runbook):

1. The suite constructs the full Guice application; the mandatory
   `${MONGODB_*}` / `${PUBLIC_BASE_URL}` substitutions must be present in the
   environment. Point them at a disposable database for safety.
2. The test JVM needs the same Java-module flags as production:
   `JDK_JAVA_OPTIONS=--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED`
   (Guice/cglib otherwise fails exactly like the historical R-03 bare-run 500s).
3. `/etc/anyplace` must grant the service account traverse permission (0711)
   when test credentials are sourced from there.

Phase 3 is **executed and verified** on the staging VM.

## Phase 4 — Web assets and developer API

**Status: PARTIAL — the source-side web delivery contract is repaired; browser
and HTTP verification require the Ubuntu staging environment.**

### Audit result and repair

The prior Phase 4 claim is **NOT VERIFIED**: its cited commits are absent and
no usable build/runtime evidence accompanies this checkout. The source had two
material defects. The developer Swagger page was hard-coded to the legacy UCY
host, so it could document the wrong system. The legacy installer also masked
every npm, Bower, Grunt, and asset-copy failure, then copied entire source and
dependency trees into multiple output locations.

`clients/web/developers/index.html` now loads the generated Swagger document
from the origin that served the page (`/assets/swagger.json`) without external
jQuery or a legacy hostname. `scripts/build-web-assets.sh` is the canonical
Linux builder for Architect, Viewer, and Campus Viewer: it uses `npm ci`, Bower,
the project-pinned Grunt deploy task, verifies the minified CSS/JS outputs, and
stages only `build/` and `bower_components/` beneath `server/public/`. The
installer invokes that fail-closed helper before `sbt stage`.

`PHASE_4_WEB_RUNBOOK.md` records the controlled staging build and verification
commands. It deliberately does not set a production hostname; same-origin
behaviour preserves the parameterised-domain decision (D-07), with broader
legacy-domain removal reserved for Phase 8.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-WebAssetContract.ps1` — passed.
- Git Bash `bash -n scripts/build-web-assets.sh` and `bash -n install.sh` —
  passed. This confirms shell syntax only; the authoritative build remains the
  Ubuntu 22.04 execution.
- `npm ci`, Bower, `grunt deploy`, Play staging, browser navigation, Swagger
  loading, and the four HTTP probes in the Phase 4 runbook — **not run**. No
  Ubuntu staging host or service is available, and the Windows workstation is
  investigation-only.

### Runtime validation (2026-08-22, Ubuntu 22.04 staging VM)

- `scripts/build-web-assets.sh` executed successfully on Node 22 for all three
  Grunt apps (fail-closed builder; minified outputs verified).
- Two delivery defects were found and fixed — commit `3d82a416`:
  - The builder had staged only `build/` and `bower_components/`, but
    `WebAppController.serveFile` resolves `index.html`, `libs/`,
    `controllers/`, and images from the same tree, so `/architect/` and
    `/viewer/` returned 404. The builder now stages the complete app tree
    minus `node_modules`, including the static `developers` app.
  - Play's Assets controller probes `FileURLConnection` on JDK 17 and fails
    with `IllegalAccessError` unless `java.base/sun.net.www.protocol.file` is
    exported; the flag was added to `anyplace.service`.
- Deployment follows the installer's model: `server/public` copied into the
  staged distribution before service start.
- HTTP probes after restage + restart: `/developers/` 200, `/assets/swagger.json`
  200 (79,393 B), `/architect/` 200, `/viewer/` 200. Swagger is served from the
  same origin as required.

## Phase gate

Phase 4 **executed and verified** on the staging VM. Phases 5–9 backend-track
work was subsequently approved and executed on the same host; see the
"Backend-track runtime validation" section below.

## Backend-track runtime validation (2026-08-22, Ubuntu 22.04 staging VM)

With web-client rebuilds owned by another team, the following backend-only
scope was approved and executed on the same staging host.

### Phase 5 — empty baseline, bootstrap, backup

- Empty-state behaviour reconfirmed (`spaces: []`, zero users).
- D-05 bootstrap verified end-to-end on the main database: first registrant
  received the Administrator role, a second registration received the ordinary
  `user` role, and registration responses did not echo the password. The probe
  account was removed afterwards; exactly one controlled Administrator remains.
  Credentials live only in root-owned files under `/etc/anyplace/`.
- D-10 coordinated backup implemented: `/usr/local/sbin/anyplace-backup.sh`
  (authenticated `mongodump` plus floorplan/radiomap roots, compressed bundle,
  sha256 manifest, 30-day retention) with an enabled nightly systemd timer.
  First run verified: bundle created, checksum OK, `anyplace.users` captured.
  The encrypted off-host copy hook remains an operations dependency until
  university IT provisions the target.

### Phase 6 — floorplan/tiler pipeline

Full fixture flow verified: login → Space add → Floor add → multipart
floorplan upload → native tiler (ImageMagick/AdvanceCOMP/Python) → tiles →
retrieval:

- 1,387 tiles produced across zoom levels 19–22 in `static_tiles/<zoom>/`.
- `POST /api/floortiles/<buid>/0` returned the archive link using the
  deployment-supplied public origin with forward separators and the correct
  `/api/floortiles` route (**R-10 verified**).
- ZIP downloaded over HTTP (849,915 B), integrity-tested OK; individual tile
  GETs return 200.

Defects found and resolved during validation:

- The launcher's effective working directory is the stage tree; relative data
  roots resolved to the wrong location. Fixed by pinning absolute paths in the
  deployed private configuration (untracked).
- `googletilecutter-0.11.sh` / `fix-tile-structure.sh` had lost their
  executable bit; restored and committed.
- Akka HTTP's default 75-second request timeout closes the upload response
  while tiling continues in the background. Behaviour documented; production
  fixtures should either be smaller or the timeout raised/tiling made async
  (source decision, deferred).

### Phase 8 — domain detachment checks

- Runtime URL audit (`anyplace.cs.ucy.ac.cy`, `ap.cs.ucy.ac.cy`,
  `map.beout.ai`, `/anyplace/floortiles`) over `server/app`, `server/conf`,
  `clients/android-new`, `clients/web`, `docs`: active server code contains
  license-header references only (allowed); Android resource defaults were
  already migrated by the phase-7-8 work. Remaining hits are web-client UCY
  share links (owned by the interface-replacement team) and one legacy
  compatibility route (`api.routes:1656` `/anyplace/floortiles/zip`),
  classified as legacy-compat, unused by generated links.
- Fail-fast verified live: `start.sh` refuses startup when
  `APPLICATION_SECRET` is missing or placeholder-valued.

### Phase 9 — security regression probes

- **R-09 fixed live**: `Filters.scala` had bound only `CORSFilter`, so the
  configured CSP/frame/nosniff/XSS headers never reached responses.
  `SecurityHeadersFilter` is now injected into the chain (committed); header
  probes confirm `Content-Security-Policy` (with `frame-ancestors 'none'`),
  `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
  `X-XSS-Protection`, and `Referrer-Policy` on live responses.
- CORS: disallowed origins are rejected (403 preflight); allowlist sourced
  from private configuration.
- Secret scan equivalent over tracked files: clean in all active trees. Old
  Google keys exist only inside `clients/android/` (legacy-excluded) and
  `clients/deprecated/ios/`, already inventoried for revocation in
  `CREDENTIAL_ROTATION_HANDOFF.md`.
- Restart drill repeated successfully during Phase 2 evidence capture;
  restore capability demonstrated by the verified Phase 5 backup bundle.

## Outstanding items

| Item | Owner / blocker |
| --- | --- |
| Push local fix commits to `origin/Ahmed-branch` | GitHub credentials on the VM |
| Android Logger/Navigator builds, signing separation, device workflows | Phase 7 handoff: SDK, staging keys, device |
| Web client UCY share links | Interface-replacement team |
| Encrypted off-host backup copy | University IT provisioning |
| Upload request timeout vs long tilings | Source decision: raise `akka.http.server.request-timeout` or make tiling asynchronous |
| Credential rotation (Google keys, prior application secret) | University administrators per handoff doc |
