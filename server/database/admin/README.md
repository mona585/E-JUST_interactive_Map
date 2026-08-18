# Administration of MongoDB (Phase 5: Empty Data Baseline & Hydration Contract)

Copy `config.example.sh` to `config.sh` and adapt it before using anything
below. `config.sh` is gitignored - never commit real credentials or paths.

## 1. Empty baseline

`../init_database.sh` (optionally `--drop`) applies `../init_schema.js`:
creates the 15 domain collections and their indexes (including the
`2dsphere` spatial indexes Spaces/POIs/fingerprints need) against an empty
MongoDB. Run once per new environment before anything else here.

## 2. [mongosh.sh](mongosh.sh)
A thin wrapper around `config.sh` for ad-hoc `mongosh` access.

## 3. [bootstrap_admin.sh](bootstrap_admin.sh) - controlled Administrator bootstrap (R-14 / D-05)

The backend has no admin-provisioning hook of its own: whoever is the FIRST
caller of the public `POST /api/user/register` endpoint on an empty database
is automatically made Administrator
(`MongodbDatasource.isFirstUser`/`UserController.register`). If public
ingress is opened before an operator claims that slot, anyone can become
Administrator.

**Required sequencing before exposing the backend publicly:**

1. Start the backend bound to localhost only (no public ingress yet).
2. Run `./bootstrap_admin.sh` with `ADMIN_NAME`/`ADMIN_EMAIL`/
   `ADMIN_USERNAME`/`ADMIN_PASSWORD` set (or let it prompt for the
   password). It:
   - fails closed if the `users` collection is not empty;
   - refuses to run against anything but `API_BASE_URL=http://127.0.0.1:...`;
   - registers the Administrator over loopback;
   - re-verifies the result directly in MongoDB (not just the API response);
   - registers and deletes one disposable second account to prove
     subsequent registrants receive the ordinary `user` role;
   - only then prints that it is safe to proceed.
3. Only after the script reports success, open the firewall/reverse proxy
   to the public registration/login endpoints.

If the script fails at any step, public ingress must stay closed until the
cause is understood - do not open ingress "to try again"; a failed bootstrap
run does not roll back a partially-created account by itself.

## 4. [create_fixture.sh](create_fixture.sh) / `--cleanup` - disposable workflow fixture

Creates one throwaway Space -> Floor -> two POIs -> Connection through the
real mapping API, for exercising Architect/Viewer/navigation and the
floorplan/tiler pipeline (Phase 6) against something other than a
permanently-empty database. Never run against a database already carrying
official hydrated data. `--cleanup` removes everything the last run created
(tracked in the gitignored `fixture_state.env`).

## 5. [verify_floorplan_pipeline.sh](verify_floorplan_pipeline.sh)

Uploads a 1x1 test image against the fixture's Space/Floor through
`POST /api/mapping/floor/floorplan/upload`, then checks the MongoDB
`floorplans` metadata, invokes the native tiler (requires the Linux
toolchain from `../../anyplace_tiler/README.md`), and downloads the
resulting archive back through the live `/api/floortiles/...` route. See
`docs/recovery/RECOVERY_AUDIT.md` for the Phase 6 write-up including what
could/couldn't run on the Windows development host.

## 6. Coordinated backup (D-10)

A MongoDB-only backup is not a faithful snapshot: floorplan/radiomap
metadata lives in MongoDB while the actual images/tiles/fingerprint files
live on disk, and both must come from the same point in time.

### 6.1 [backup.sh](backup.sh)
For each run, under `$BACKUP_DIR/backup.<timestamp>/`:
- `mongo/` - `mongodump` of `MDB_DATABASE`;
- `filesystem/` - a copy of `FLOOR_PLANS_ROOT_DIR`, `RADIOMAP_RAW_DIR`, and
  `RADIOMAP_FROZEN_DIR` (each must match `app.private.conf`'s equivalent
  keys);
- `MANIFEST.txt` - a timestamp plus a SHA-256 checksum of every captured
  file, so a restore can be verified rather than trusted blindly.

The bundle is then tar.gz'd, encrypted to `GPG_RECIPIENT` if set (required
for anything beyond local/disposable testing), copied to
`OFFHOST_COPY_TARGET` if set, symlinked as `backup.latest`, and old backups
beyond `MAX_BACKUPS` are pruned. Schedule this nightly (D-10: 30-day
retention, 24-hour RPO) plus before every deployment and before every
official-data hydration.

### 6.2 [restore.sh](restore.sh) - isolated restore drill
Restores the latest (or a named) bundle into `RESTORE_MDB_DATABASE` /
`RESTORE_FILESYSTEM_DIR` only - it refuses to run if those are identical to
the production `MDB_*` target, so a drill can never overwrite live data. It
decrypts if needed, verifies the manifest checksums, restores the
filesystem roots into the disposable directory, and `mongorestore`s into
the disposable database. Run this quarterly (D-10) and after any change to
the backup scripts themselves.

## 7. Future official-data hydration

When a coordinated MongoDB + floorplan/radiomap bundle from the real
E-JUST source of truth arrives (not the disposable fixture above and not
this checkout's own local database - see `docs/recovery/RECOVERY_REPORT.md`
"MongoDB Startup/Data Path"):

1. Treat it exactly like a `backup.sh` bundle and restore it with
   `restore.sh` into an **isolated** environment first.
2. Compare document/file counts and `MANIFEST.txt` checksums against what
   the source system reports, to confirm nothing was dropped or duplicated
   in transit.
3. Spot-check the Campus -> Space -> Floor -> POI -> Connection
   relationships and that every referenced floorplan/radiomap file exists
   on disk.
4. Take a fresh `backup.sh` snapshot of the target production environment
   immediately before cutover, so a bad hydration can be rolled back.
5. Cut over (point production `MDB_DATABASE`/filesystem roots at the
   verified data) only after 1-4 pass; keep the pre-cutover snapshot until
   the new data is confirmed healthy in production.
6. Rollback: restore the pre-cutover snapshot with `restore.sh` targeted at
   production if the hydration proves faulty after cutover.
