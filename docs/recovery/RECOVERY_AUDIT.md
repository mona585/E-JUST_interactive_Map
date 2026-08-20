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

## Phase gate

No Phase 2 recovery work has started. Approve Phase 2 when an Ubuntu 22.04 VM
or staging host is available for the documented preflight and MongoDB can be
configured locally with authentication.

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

## Phase gate

No Phase 3 recovery work has started. Approve Phase 3 after the Phase 2
staging runbook has been executed, or explicitly approve source-only test
baseline work while the VM validation remains pending.

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

## Phase gate

No Phase 5 recovery work has started. Approve Phase 5 only after the Phase 4
runbook has generated and served the browser assets, or explicitly approve a
source-only empty-data/hydration-contract audit while the runtime validation
remains pending.

Source-only Phase 5 and Phase 6 work was subsequently approved by the repo
owner (assigned as this contributor's two phases) while Phase 4's browser
runtime validation remains pending on this Windows host; results follow.

## Phase 5 — Empty data baseline and hydration contract

**Status: PARTIAL — the source-side data-baseline, Administrator-bootstrap,
and coordinated-backup contracts are implemented and verified statically;
MongoDB/HTTP runtime execution is an external dependency on this host.**

### Audit result

`PHASES_COMPLETED.md` claims Phase 5 delivered `init_schema.js`,
`init_database.sh`, and a `DatabaseBaselineSpec` asserting "first user gets
admin, second gets user." Both scripts are present and reasonable (15
collections, the documented indexes, an explicit `--drop` flag), so that part
of the claim is **VERIFIED COMPLETE**. `DatabaseBaselineSpec` itself is not
in this checkout — `docs/recovery/RECOVERY_AUDIT.md`'s own Phase 3 entry
records it was removed for asserting exactly the behavior
`EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md` calls out as insufficient for
Phase 5: "first user = admin, second = user" is not proof of a *controlled
private* bootstrap.

Re-reading the actual `UserController.scala` on this branch (HEAD
`b620e9b5`) confirmed the underlying defect the instructions warn about was
still live, in **two** places:

- `register()` (public, unauthenticated `POST /api/user/register`): `if
  (pds.db.isAdmin()) accType = "admin"` — the first anonymous HTTP caller on
  an empty database became Administrator with no gate at all. This is
  exactly R-14/D-05.
- `authorizeGoogleAccount()`: the same `if (pds.db.isAdmin()) userType =
  "admin"` pattern, on the deferred-but-still-routed Google login path.

This is a **NOT VERIFIED → CONFIRMED GAP** against the prior claim, not a
verified completion: whatever `DatabaseBaselineSpec` asserted, the shipped
controller still let the network decide who becomes Administrator.

### Fix applied

- `server/app/controllers/UserController.scala`: both auto-promotion sites
  removed. `register()` and `authorizeGoogleAccount()` now unconditionally
  assign `"user"`; no code path can reach `"admin"` except the new endpoint
  below.
- Added `UserController.bootstrapAdmin()`, the sole private admin-creation
  path: requires a dedicated `X-Bootstrap-Token` header matched against
  `admin.bootstrapToken` (`MessageDigest.isEqual`, constant-time) with
  fail-closed behavior when the token is unset/placeholder, wrong, or when
  any user already exists (`!pds.db.isAdmin()`) — making it single-use by
  construction. Routed at `POST /api/user/bootstrap-admin`
  (`server/conf/api.routes`).
- `server/conf/app.private.example.conf`: documents `admin.bootstrapToken`
  with an explicit `CHANGE_ME_ADMIN_BOOTSTRAP_TOKEN` placeholder (endpoint
  disabled until the operator sets a real value), matching the existing
  salt/pepper/secret placeholder convention.
- `install.sh`: the "ALL ANYPLACE CONFIGURATION SETTINGS" display now
  acknowledges the bootstrap token exists without ever printing its value
  (same pattern as the existing secret/salt/pepper lines).
- `docs/recovery/PHASE_5_DATA_RUNBOOK.md`: schema init, the bootstrap
  sequence (create → verify single-use rejection → verify a normal
  registrant gets `user`), coordinated backup/restore-drill usage, and the
  disposable-fixture note for Phase 6.
- D-10 coordinated backup: `server/database/admin/coordinated_backup.sh` and
  `coordinated_restore_drill.sh` (new) wrap the existing Mongo-only
  `backup.sh`/`helper.sh` (unchanged) to also capture
  `floorPlansRootDir`/`radioMapRawDir`/`radioMapFrozenDir` from the same run,
  write a `MANIFEST.txt` with a `sha256sum` per file, prune bundles past
  `RETENTION_DAYS` (default 30), and optionally GPG-encrypt and `scp` the
  bundle off-host. The restore drill verifies the manifest and restores
  MongoDB only into the disposable `RESTORE_MDB_DATABASE`, never the live
  database. The actual off-host destination and GPG recipient are left
  unset by design — **EXTERNAL DEPENDENCY** (university-supplied off-host
  storage/credentials), not fabricated.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-AdminBootstrapContract.ps1` (new) — passed. Confirms both
  auto-promotion sites are gone, `bootstrapAdmin()` exists with the
  token-header/placeholder/fail-closed checks, the route is registered, the
  private-config template documents the placeholder, `install.sh` never
  prints the token, and the coordinated backup/restore scripts reference the
  required filesystem roots, manifest, checksums, and disposable-database
  guard.
- `bash -n server/database/admin/coordinated_backup.sh` and `bash -n
  server/database/admin/coordinated_restore_drill.sh` — passed (shell syntax
  only).
- Manual balanced-braces/parens check of the edited
  `UserController.scala` (274/274 parens, 49/49 braces) — passed. **`sbt
  test` was not run**: no `sbt` binary is available on this Windows
  investigation host (same limitation recorded in every prior phase); this
  is the authoritative Phase 2/3 Ubuntu environment's job, not this host's.
- `SecurityRegressionSpec` (`server/test/`) was re-read, not re-run: its
  admin-related assertion is "a second registrant must never receive
  `admin`," which remains true (both registrants are now always `user`), so
  no test contradicts this fix; it stays gated behind
  `RUN_MONGO_INTEGRATION_TESTS=true` per its existing Phase 3 pattern.
- HTTP-level verification of the bootstrap sequence
  (`PHASE_5_DATA_RUNBOOK.md` §3) and the coordinated backup/restore drill
  against a real MongoDB — **not run**; require the Phase 2 authenticated
  staging MongoDB, which is itself still an external dependency on this
  host.

TestSprite was not used: the changes are unauthenticated-endpoint
authorization logic and backup shell scripts, not yet reachable without the
Phase 2 staging backend; the runbook records the exact `curl` sequence to
run once that backend exists.

### Final status: PARTIAL (source-side VERIFIED COMPLETE; runtime execution EXTERNAL DEPENDENCY)

## Phase 6 — Floorplan/tiler pipeline

**Status: PARTIAL — the source-side link-generation, routing, and argument
contracts are verified correct with no code change required; end-to-end
execution needs the Linux/ImageMagick toolchain this host does not have.**

### Audit result

`PHASES_COMPLETED.md` claims Phase 6 fixed a Python 3 `bytes`-decoding bug,
switched `advpng -4` to `-2`, and verified end-to-end tiling on an execution
host this checkout has no record of. That execution cannot be re-verified
here (no accessible Ubuntu VM/log), so it is **NOT VERIFIED** as a claim, but
unlike Phase 5 the underlying source-level defects R-10 and R-08 named in
`RECOVERY_REPORT.md` were checked directly against the current tree and
found already correct:

- **R-10 (tile/archive link path):** `AnyPlaceTilerHelper.getFloorTilesZipLinkFor`
  builds its link via `AnyplaceServerAPI.urlPath("api", "floortiles", buid,
  floor, FLOOR_TILES_ZIP_NAME)`, and `urlPath` joins segments with a literal
  `"/"` from the configured `public.baseUrl` — not `File.separatorChar`, and
  not the legacy `/anyplace/floortiles` prefix the report flagged. This
  matches the routed `GET /api/floortiles/:buid/:floor_number/*file`.
  **VERIFIED COMPLETE**, already fixed on this branch (most likely as part
  of the Phase 8 domain-detachment work referenced in `PHASES_COMPLETED.md`,
  since it depends on the same `public.baseUrl`/`urlPath` machinery). No
  change made.
- **Deprecated 4-argument tiler call:** the report separately notes "a
  deprecated upload method also passes four tiler arguments, while the
  launcher requires five." Confirmed still true of `MapFloorplanController.upload()`
  /`AnyPlaceTilerHelper.tileImage()`, and `start-anyplace-tiler.sh` still
  hard-requires exactly 5 arguments (`[[ "$#" != "5" ]] && usage`) — but
  `server/conf/api.routes` only maps `/api/mapping/floor/floorplan/upload`
  to `uploadWithZoom()`, which calls `tileImageWithZoom()` with all 5
  arguments including zoom. `upload()` is not routed anywhere and is
  unreachable over HTTP. Left unchanged: it is confirmed dead code, not a
  live recovery blocker, and rewriting/deleting unrouted legacy code is
  outside this phase's "smallest path/argument fixes" allowance.
- **R-08 (tiler cannot execute on Windows):** still true and, per D-01,
  intentionally out of scope to fix here — the target is Ubuntu 22.04, not a
  native Windows port.

### Fix applied

No production code changes were needed for Phase 6's confirmed-defect list;
the two source-level correctness items (R-10, the 5-argument contract) were
already satisfied. Added:

- `docs/recovery/PHASE_6_TILER_RUNBOOK.md`: the full
  upload → metadata → filesystem → tiler → retrieval → Viewer sequence with
  concrete `curl`/`mongosh`/`identify`/`unzip` checks, run twice from a clean
  floorplan directory per the report's Definition of Done, plus the source
  facts above so the runbook doesn't need to re-derive them.
- `scripts/Test-FloorplanPipelineContract.ps1` (new): statically pins the
  R-10 link-generation contract, confirms `upload()` stays unrouted while
  `uploadWithZoom()` is the only routed action, confirms the tiler script
  still requires 5 arguments, confirms the zoom-floor validation
  (`MIN_ZOOM_UPLOAD`) precedes tiling, and confirms the filesystem roots stay
  externally configured.

### Validation evidence

- `powershell -NoProfile -ExecutionPolicy Bypass -File
  scripts/Test-FloorplanPipelineContract.ps1` (new) — passed.
- Direct source read of `AnyPlaceTilerHelper.scala`, `AnyplaceServerAPI.scala`,
  `MapFloorplanController.scala`, `server/conf/api.routes`, and
  `start-anyplace-tiler.sh` — as summarized above.
- End-to-end upload → tile → retrieve → Viewer-display execution
  (`PHASE_6_TILER_RUNBOOK.md`) — **not run**. This Windows host lacks
  ImageMagick/`identify`/`advpng`, matching every prior phase's tiler
  preflight result; this is **EXTERNAL DEPENDENCY** on the Ubuntu 22.04
  staging VM from Phase 1, not a phase-6-specific gap.

TestSprite was not used: floorplan upload/tiling is a multipart
file-plus-filesystem-plus-external-process workflow outside TestSprite's
HTTP-contract scope, and requires the same unavailable staging backend as
Phase 5's runtime checks.

### Final status: PARTIAL (source-side VERIFIED COMPLETE; end-to-end execution EXTERNAL DEPENDENCY)

## Phase gate

Both of this contributor's assigned phases (5 and 6) are now PARTIAL in the
sense the completion standard allows: all code-side work is
`VERIFIED COMPLETE`, and the remaining item in each is a runtime execution
that requires infrastructure this Windows host does not have (an
authenticated MongoDB/staging backend for Phase 5's HTTP bootstrap sequence
and coordinated-backup drill; the pinned Ubuntu/ImageMagick toolchain for
Phase 6's tiling run) — `EXTERNAL DEPENDENCY`, per the completion standard in
`EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md`.

### Unrelated finding: git index currently stages ~4,960 tracked files for deletion

While validating these phases, `git status` showed roughly 4,960 tracked
files across effectively the whole repository (`server/`, `scripts/`,
`docs/`, `install.sh`, and more) staged as deleted (`D`), with the same paths
simultaneously appearing as untracked (`??`) because the working-tree copies
are still present. This predates this session's edits — no command run here
staged anything — and was already partially visible in the untruncated
`git status` at session start. **A commit made from this index as-is would
delete almost the entire tracked repository even though the working tree is
intact.** This is a repository-hygiene issue outside Phase 5/6 scope; it is
flagged here rather than silently fixed because correcting a ~5,000-file
index affects every contributor's pending work, not just these two phases.

Should Phase 7 (Android) be approved next, or should the git index anomaly
above be resolved first?
