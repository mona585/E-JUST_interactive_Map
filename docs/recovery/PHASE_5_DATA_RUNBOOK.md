# Phase 5 Runbook — Empty Data Baseline and Hydration Contract

Companion to `docs/recovery/RECOVERY_REPORT.md` Phase 5 and
`EJUST_RECOVERY_AUDIT_INSTRUCTIONS_V2.md`'s Phase 5 review area. Run this on
the Ubuntu 22.04 staging host once the Phase 2 authenticated, loopback-only
MongoDB is available (see `PHASE_2_STAGING_RUNBOOK.md`).

## 1. Initialize the empty schema baseline

```bash
cd server/database
./init_database.sh --drop     # first deploy / disposable staging only
```

Verifies: `users`, `spaces`, `campuses`, `floorplans`, `pois`, `edges`, and
heatmap/fingerprint collections exist with the indexes in `init_schema.js`
(unique `username`/`email`, 2dsphere on `spaces.location`/`pois.location`,
etc.). `--drop` must never be run against a database holding real data.

## 2. Confirm empty-state API behavior

```bash
curl -s -X POST http://127.0.0.1:9000/api/mapping/space/public -H 'Content-Type: application/json' -d '{}'
```

Expect HTTP 200 with an empty result list — not an error. This distinguishes
intentional emptiness from a failed MongoDB connection (which R-14's
investigation baseline already proved returns 200 with zero Spaces).

## 3. Private Administrator bootstrap (D-05 / R-14)

Public `POST /api/user/register` never grants `admin` — every anonymous
registrant always receives the plain `user` role, on every registration path
(local and Google-authenticated). The **only** way to create the initial
Administrator is the private, token-gated bootstrap endpoint added in this
phase: `UserController.bootstrapAdmin()`.

1. In `server/conf/app.private.conf` (never `app.private.example.conf`), set:
   ```
   admin.bootstrapToken="<a random value, e.g. openssl rand -hex 32>"
   ```
   Leaving the documented `CHANGE_ME_ADMIN_BOOTSTRAP_TOKEN` placeholder
   disables the endpoint (`bootstrapAdmin()` returns 403).
2. With ingress still closed to the public internet, call it once:
   ```bash
   curl -s -X POST http://127.0.0.1:9000/api/user/bootstrap-admin \
     -H 'Content-Type: application/json' \
     -H 'X-Bootstrap-Token: <the value from step 1>' \
     -d '{"name":"<admin name>","email":"<admin email>","username":"<admin username>","password":"<strong password>"}'
   ```
   Expect HTTP 200 and `"newUser"` in the response.
3. Verify a second call with the same or any token now fails closed:
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:9000/api/user/bootstrap-admin \
     -H 'Content-Type: application/json' -H 'X-Bootstrap-Token: <token>' \
     -d '{"name":"x","email":"x2@example.test","username":"x2","password":"x"}'
   ```
   Expect `403` ("An Administrator or other user already exists.").
4. Verify a normal registration now receives `user`, not `admin`:
   ```bash
   curl -s -X POST http://127.0.0.1:9000/api/user/register -H 'Content-Type: application/json' \
     -d '{"name":"Test User","email":"user1@example.test","username":"testuser1","password":"x"}'
   ```
   Inspect the stored document (or a subsequent authenticated `/api/user/...`
   read) and confirm `type` is `user`.
5. Rotate/blank `admin.bootstrapToken` back to the placeholder (or a fresh
   unused random value kept offline) before opening public ingress. The
   endpoint is single-use by construction — step 3 above is what verifies
   that — but rotating the token removes any residual value from the
   deployed configuration.

Only after steps 2–4 both pass should the public registration/login routes be
exposed to the internet.

## 4. Coordinated backup (D-10) and restore drill

```bash
cp server/database/admin/config.example.sh server/database/admin/config.sh
# edit config.sh: BACKUP_DIR, MDB_* and RESTORE_MDB_* (a disposable database name)
chmod +x server/database/admin/coordinated_backup.sh server/database/admin/coordinated_restore_drill.sh

OFFHOST_TARGET=<user@offhost:/path> GPG_RECIPIENT=<key-id> \
  ./server/database/admin/coordinated_backup.sh
```

This captures MongoDB (`mongodump`) and the `floorPlansRootDir` /
`radioMapRawDir` / `radioMapFrozenDir` filesystem roots from one run, writes
`MANIFEST.txt` with a `sha256sum` per file, prunes bundles older than
`RETENTION_DAYS` (default 30), and — only when `GPG_RECIPIENT` and
`OFFHOST_TARGET` are supplied — encrypts and copies the bundle off-host.
Neither variable is invented by the script; supplying real off-host
infrastructure and a GPG recipient is a university-IT delivery dependency
(**EXTERNAL DEPENDENCY**), tracked separately from the code-side backup logic.

Quarterly (and before any deployment or official-data hydration), run the
isolated drill:

```bash
./server/database/admin/coordinated_restore_drill.sh
```

It verifies the manifest checksums, restores MongoDB **only** into
`RESTORE_MDB_DATABASE` (never the live database), and reports the per-collection
document counts. It never touches the live floorplan/radiomap directories.

## 5. Disposable fixture for later phases

Phase 6's floorplan/tiler verification needs one mapped Space → Floor. Use
disposable, clearly-fake data (never claim it as official E-JUST content):

```bash
# through the authenticated Architect/API mapping routes, as a bootstrapped admin
# 1) create a Campus and Space
# 2) create a Floor under that Space
# 3) proceed to PHASE_6_TILER_RUNBOOK.md for the floorplan upload
```

Delete the fixture Campus/Space/Floor/POIs afterward, or keep them clearly
labeled as disposable staging fixtures if staging is meant to stay populated
for demos.

## Future official-data hydration (not part of Phase 5)

D-02 explicitly does not authorize using this checkout's local database, its
one local raw floorplan file, or any disposable fixture as production seed
data. When the university supplies an authoritative `mongodump` plus matching
floorplan/radiomap filesystem roots, hydration must: restore into an isolated
environment first (via `coordinated_restore_drill.sh` or equivalent), verify
document/file counts and relationships, and only then follow an approved
cutover-with-rollback procedure into the real production database. That
procedure itself is future work, not something this phase performs.
