#!/bin/bash
cwd="$(dirname "$0")"

MAX_BACKUPS=3
BACKUP_DIR="/full/path/to/mongo/backups"

MDB_HOST=localhost
MDB_PORT=27017
MDB_USER=ADMIN
MDB_PASS=PASS
MDB_DATABASE=anyplace

# YOU MAY USE DIFFERENT RESTORE HOST (OR DATABASE)
RESTORE_MDB_HOST=localhost
RESTORE_MDB_PORT=27017
RESTORE_MDB_USER=admin
RESTORE_MDB_PASS=ADMIN
# Restore drills MUST target a disposable database name, never the
# production database (D-02 / Phase 5 "isolated environment" requirement).
RESTORE_MDB_DATABASE=anyplaceRestored

###
# Coordinated backup (D-10): a nightly snapshot is only trustworthy if the
# MongoDB dump and the floorplan/radiomap filesystem roots come from the
# same point in time. These MUST match the equivalent keys in
# server/conf/app.private.conf.
###
FLOOR_PLANS_ROOT_DIR="/full/path/to/anyplace/floorplans"
RADIOMAP_RAW_DIR="/full/path/to/anyplace/radiomaps_raw"
RADIOMAP_FROZEN_DIR="/full/path/to/anyplace/radiomaps_frozen"

# Restore drills untar/copy the filesystem roots here instead of the live
# directories above, so a drill can never overwrite production floorplans.
RESTORE_FILESYSTEM_DIR="/full/path/to/anyplace/restore-drill"

###
# Administrator bootstrap (R-14 / D-05).
# Must be the server's own loopback address - bootstrap_admin.sh refuses to
# run against anything else so the first-admin gap can't be exploited from
# outside the host.
###
API_BASE_URL="http://127.0.0.1:9000"

###
# Off-host encryption (D-10: "encrypted off-host").
# GPG_RECIPIENT is a public key ID/email the backup is encrypted to.
# Leave empty to skip encryption for local disposable testing only;
# it MUST be set for any staging/production backup.
###
GPG_RECIPIENT=""

# Where the encrypted archive is copied after each backup (e.g. an rsync/scp
# target, a mounted off-host volume, or a cloud-storage sync directory).
# Leave empty to skip the off-host copy step (disposable/local testing only).
OFFHOST_COPY_TARGET=""
