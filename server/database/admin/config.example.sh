#!/bin/bash
# Copy to config.sh on the host (never commit config.sh) and fill in values.

# Keep the newest N archives.
MAX_BACKUPS=14

# Absolute path to the backup directory (created if missing).
BACKUP_DIR="/var/backups/anyplace"

# MongoDB connection used for dumps and restores.
MDB_MODE=native            # native | docker
MDB_DOCKER_CONTAINER=anyplace-mongo
MDB_HOST=127.0.0.1
MDB_PORT=27017
MDB_USER=anyplace_app
MDB_PASS=CHANGE_ME
MDB_DATABASE=anyplace

# Restore target (may point at a different host/database).
RESTORE_MDB_HOST=127.0.0.1
RESTORE_MDB_PORT=27017
RESTORE_MDB_USER=anyplace_app
RESTORE_MDB_PASS=CHANGE_ME
RESTORE_MDB_DATABASE=anyplace

# Optional: when set, archives are GPG-encrypted and no plaintext is kept.
# Generate a key on the host (gpg --gen-key) or import the IT public key.
BACKUP_GPG_RECIPIENT=""

# Optional: rsync destination for off-host copies, e.g. backup@nas:/srv/anyplace.
BACKUP_OFFHOST_TARGET=""
