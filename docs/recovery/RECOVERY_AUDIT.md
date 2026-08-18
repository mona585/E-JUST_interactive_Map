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


## Environment constraints affecting implementation of Phase 5 & 6

None of the following were available on this Windows checkout, which limits
every "Validation" section below to static/code-level review:

- **No MongoDB instance reachable.** No `mongosh`/`mongo` binary and no
  MongoDB Windows service were present, so no script or test that talks to
  a real database (`bootstrap_admin.sh`, `create_fixture.sh`,
  `backup.sh`/`restore.sh`, `DatabaseBaselineSpec`, `ApplicationSpec`) could
  actually be executed.
- **`sbt Test/compile` fails at the launcher level**, independent of any
  change made here: `sbt.version=1.5.8` (`project/build.properties`)
  crashes under both the local JDK 26 and a side-by-side JDK 21 with
  `ClassCastException: UnsupportedOperationException cannot be cast to
  xsbti.FullReload` inside `XMainConfiguration.run` - a known sbt
  1.5.x-vs-modern-JDK `SecurityManager` incompatibility, not a symptom of
  this session's edits. This blocks `sbt test`/`Test/compile` entirely on
  this host and is Phase 1 toolchain-pinning territory (R-03), not Phase 5/6
  scope.
- **No Linux tiler toolchain** (`convert`/`identify` from ImageMagick,
  `advpng`, `zip`) is available on Windows, matching the original
  investigation's finding and D-01's decision to target Ubuntu LTS rather
  than port the tiler.

Everything below marked "code-verified" was checked by reading the actual
source/config and, where noted, syntax-checking scripts with `bash -n`; it
was not exercised against a live server, database, or tiler.

## Phase 5 — Establish the Empty Data Baseline and Hydration Contract

**Status: PARTIAL — schema/bootstrap/backup code is in place and
code-verified; no step was executed against a live MongoDB in this
environment.**

### Original requirement (RECOVERY_REPORT.md)
Known-empty datastore/filesystem baseline distinguishable from failed
initialization; controlled private Administrator bootstrap that closes the
R-14 "first public caller becomes admin" gap before ingress opens; a second
registrant verified to receive `user`; coordinated (Mongo + filesystem)
nightly backups with checksums, encryption, off-host copy, and a quarterly
isolated restore drill; a disposable Campus→Space→Floor→POI→Connection
fixture; a documented future hydration contract.

### Previous completion claim (PHASES_COMPLETED.md)
Claimed `init_schema.js`/`init_database.sh`, a `DatabaseBaselineSpec`
verifying first-admin/second-user, and `sbt test` 6/6. It did not claim a
private bootstrap script, coordinated filesystem backup, or a restore drill
- exactly the gaps `EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md` flags this
phase for.

### Actual evidence and gaps found
- `server/database/init_schema.js` / `init_database.sh` were already
  present and correct: all 15 collection names match `SCHEMA.scala`'s
  `c*` constants exactly, including the `2dsphere` indexes Spaces/POIs need.
  No change needed.
- `server/test/DatabaseBaselineSpec.scala`'s first test was a **tautology**:
  it asserted `(userType == "admin" || userType == "user") must beTrue`,
  which passes unconditionally and verifies nothing about first-user=admin.
  **Fixed** to read the same precondition the controller uses
  (`MongodbDatasource.isAdmin()`) and assert the registration matches it.
- There was **no bootstrap script at all** - the only path to creating the
  initial Administrator was the public registration endpoint itself, with
  no tooling enforcing the required loopback-only, fail-closed,
  role-verified sequencing from D-05. **Added**
  `server/database/admin/bootstrap_admin.sh`: refuses to run against a
  non-loopback `API_BASE_URL`, fails closed if `users` is non-empty,
  registers the Administrator, re-verifies the role directly in MongoDB
  (not just trusting the API response), and proves a second registrant
  gets `user` via a disposable throwaway account it deletes afterward.
- `backup.sh`/`restore.sh` only ever captured `mongodump` output - never
  the floorplan/radiomap filesystem roots, no manifest/checksums, no
  encryption, no off-host copy, and `restore.sh` had no guard against
  targeting the production database by mistake. This did not satisfy D-10.
  **Rewrote** `helper.sh`/`backup.sh`/`restore.sh`/`config.example.sh` to:
  capture `mongo/` + `filesystem/` (floorplans, raw/frozen radiomaps) per
  run, write a SHA-256 `MANIFEST.txt`, optionally GPG-encrypt the bundle
  and copy it to an off-host target, and refuse to restore into the
  production `MDB_*`/host triple.
- **Added** `create_fixture.sh` (+ `--cleanup`): creates a disposable
  Campus-scale... (Space→Floor→2 POIs→Connection) fixture through the real
  mapping API, which Phase 6's pipeline test also depends on.
- **Documented** the future hydration runbook (restore into isolation →
  verify counts/checksums → spot-check relationships → pre-cutover snapshot
  → cutover → rollback) in `server/database/admin/README.md` section 7.

### Validation
- `bash -n` passed on `bootstrap_admin.sh`, `create_fixture.sh`,
  `backup.sh`, `restore.sh`, `helper.sh`, `verify_floorplan_pipeline.sh`.
- Field/collection names used by `create_fixture.sh` and
  `bootstrap_admin.sh` were cross-checked against `SCHEMA.scala` and the
  corresponding controllers (`UserController`, `MapSpaceController`,
  `MapFloorController`, `MapPoiController`, `MapPoiConnectionController`)
  rather than assumed.
- **Not executed**: no MongoDB or Play server was available to actually run
  `init_database.sh`, `bootstrap_admin.sh`, `create_fixture.sh`,
  `backup.sh`/`restore.sh`, or `sbt test` (blocked by the sbt/JDK
  incompatibility above) in this session.

### Required follow-up (must happen on the D-01 Ubuntu target)
Run `init_database.sh`, then `bootstrap_admin.sh` before opening any public
ingress, then `create_fixture.sh` + a real `backup.sh`/`restore.sh` drill,
then `sbt test` (`DatabaseBaselineSpec`) with a resolved sbt/JDK pin from
Phase 1.

## Phase 6 — Verify and Repair the Floorplan/Tiler Pipeline

**Status: PARTIAL — the confirmed R-10 code defect is fixed and
regression-tested at the unit level; full native tiling was not executed
in this environment (Linux-only toolchain, D-01).**

### Original requirement (RECOVERY_REPORT.md)
One floorplan reproduced end to end: upload → MongoDB metadata → filesystem
→ tiler → generated tiles/archive → backend retrieval → Viewer overlay,
with `/api/floortiles` URLs using `/` separators (R-10) and the
`uploadWithZoom`/tiler argument count already consistent (R-08 partially
addressed by targeting Linux rather than porting the tiler to Windows).

### Previous completion claim (PHASES_COMPLETED.md)
Claimed a `python3` fallback, a `bytes.decode('utf-8')` fix, an `advpng`
flag change, a `zip` dependency install, and an end-to-end tile-generation
run - all on a Linux host this session does not have access to and cannot
re-verify.

### Actual evidence and gaps found
- `anyplace-tiler.py`'s `getImageInfoFromFile2` already uses
  `.decode('utf-8')` and `start-anyplace-tiler.sh` already prefers
  `python3` - consistent with the previous claim; not re-changed.
- **R-10 confirmed still present**: `AnyPlaceTilerHelper.getFloorTilesZipLinkFor`
  (`app/utils/AnyPlaceTilerHelper.scala`) built the link with
  `File.separatorChar` and the legacy prefix `anyplace/floortiles/...`,
  which matches neither the live route
  `GET /api/floortiles/:buid/:floor_number/*file` (`conf/api.routes:610`)
  nor any URL-safe separator on Windows. **Fixed** to
  `SERVER_FULL_URL + "/api/floortiles/" + buid + "/" + floor + "/" +
  FLOOR_TILES_ZIP_NAME`.
- The report's other R-08 note - the deprecated `upload()`/`tileImage()`
  4-argument call versus the tiler's 5-argument requirement - is confirmed
  **unreachable dead code**: no route in `api.routes` maps to
  `MapFloorplanController.upload()`; only `uploadWithZoom()` (5 args, via
  `tileImageWithZoom`) is routed, and `start-anyplace-tiler.sh` requires
  exactly 5 (`[[ "$#" != "5" ]] && usage`). Left as-is per the "smallest
  fix, no rewrite" scope; it is not a live blocker.
- `server/anyplace_tiler/REAME.md` (typo'd filename) claimed "Python 2.7+"
  and omitted the `zip` dependency `fix-tile-structure.sh` actually needs -
  a real environment-provisioning hazard for Phase 1/6 rehearsal on the
  Ubuntu target. **Renamed** to `README.md` and corrected.
- **Added** `test/AnyPlaceTilerHelperSpec.scala`: a MongoDB-free unit test
  asserting the generated link uses `/api/floortiles/...` with `/`
  separators and never the legacy path or a backslash - a permanent
  regression guard for R-10 that doesn't need the tiler or a database to
  run.
- **Added** `database/admin/verify_floorplan_pipeline.sh`: uploads a
  synthetic 1x1 PNG (embedded as base64, no local image tooling needed)
  against the Phase 5 fixture's Space/Floor through
  `POST /api/mapping/floor/floorplan/upload`, checks the MongoDB
  `floorplans` metadata, fetches the generated zip link, asserts it is the
  live `/api/floortiles` path, and downloads it over HTTP.

### Validation
- Confirmed via `grep`/`Read` against `conf/api.routes` and
  `MapFloorplanController.scala` that the fixed link target
  (`GET /api/floortiles/:buid/:floor_number/*file`, matched against
  `FLOOR_TILES_ZIP_NAME`) is the actual route serving the generated archive.
- `bash -n verify_floorplan_pipeline.sh` passed; the embedded base64 PNG was
  decoded and confirmed to be a valid 1x1 PNG on this host.
- **Not executed**: no MongoDB/Play server and no ImageMagick/`advpng`/`zip`
  were available on this Windows host, so `verify_floorplan_pipeline.sh`
  could not actually be run, and the previous session's "verified
  end-to-end tile generation" claim could not be re-confirmed or refuted
  here.

### Required follow-up (must happen on the D-01 Ubuntu target)
Provision the toolchain per the corrected `anyplace_tiler/README.md`, run
`create_fixture.sh` then `verify_floorplan_pipeline.sh` twice from a clean
floorplan directory (Phase 6's Definition of Done), and confirm the Viewer
floor overlay renders the result.

## Phase gate

Phases 5 and 6 are PARTIAL for the reasons above: the code-level defects
identified in the recovery report are fixed and reviewed, but neither phase
has a live-environment execution recorded from this session. Recommend
re-running the "Required follow-up" steps on the Ubuntu target and updating
this file to VERIFIED COMPLETE (or logging what actually failed) before
treating either phase as done.