#!/bin/bash
# Verified MongoDB backup for Anyplace.
# - Works with native mongod or a Dockerized mongo (MDB_MODE=docker).
# - Writes a single gzip archive, then validates it with mongorestore --dryRun.
# - Records per-collection document counts so an empty backup is visible.
# - Optionally encrypts (GPG) and copies off-host; refuses to leave plaintext
#   behind when encryption is requested.
set -euo pipefail

cwd="$(dirname "$0")"
if [ ! -f "$cwd/config.sh" ]; then
  echo "Missing $cwd/config.sh — copy config.example.sh and fill in values." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$cwd/config.sh"

MDB_MODE="${MDB_MODE:-native}"
MDB_DOCKER_CONTAINER="${MDB_DOCKER_CONTAINER:-}"
BACKUP_DIR="${BACKUP_DIR:?BACKUP_DIR is required}"
MAX_BACKUPS="${MAX_BACKUPS:-14}"
BACKUP_GPG_RECIPIENT="${BACKUP_GPG_RECIPIENT:-}"
BACKUP_OFFHOST_TARGET="${BACKUP_OFFHOST_TARGET:-}"
timestamp="$(date +'%Y.%m.%d-%H.%M')"
base="$BACKUP_DIR/backup.$timestamp"
archive="$base.archive.gz"
manifest="$base.manifest.txt"

mkdir -p "$BACKUP_DIR"

run_mongo_tool() {
  # $1 = mongodump|mongorestore|mongosh, rest = arguments
  local tool="$1"; shift
  if [ "$MDB_MODE" = "docker" ]; then
    [ -n "$MDB_DOCKER_CONTAINER" ] || { echo "MDB_DOCKER_CONTAINER is required for docker mode" >&2; exit 1; }
    docker exec -i "$MDB_DOCKER_CONTAINER" "$tool" \
      --host 127.0.0.1 --port 27017 \
      --username "$MDB_USER" --password "$MDB_PASS" --authenticationDatabase admin "$@"
  else
    "$tool" --host "$MDB_HOST" --port "$MDB_PORT" \
      --username "$MDB_USER" --password "$MDB_PASS" --authenticationDatabase admin "$@"
  fi
}

run_mongo_tool_stdin() {
  # Same as run_mongo_tool but the archive is read from stdin.
  local tool="$1"; shift
  if [ "$MDB_MODE" = "docker" ]; then
    docker exec -i "$MDB_DOCKER_CONTAINER" "$tool" \
      --host 127.0.0.1 --port 27017 \
      --username "$MDB_USER" --password "$MDB_PASS" --authenticationDatabase admin "$@"
  else
    "$tool" --host "$MDB_HOST" --port "$MDB_PORT" \
      --username "$MDB_USER" --password "$MDB_PASS" --authenticationDatabase admin "$@"
  fi
}

echo "==> Backing up database '$MDB_DATABASE' ($MDB_MODE) to $archive"
run_mongo_tool mongodump --db "$MDB_DATABASE" --archive --gzip > "$archive"

# 1) Structural validation: mongorestore parses the whole archive without writing.
echo "==> Validating archive"
if ! run_mongo_tool_stdin mongorestore --archive --gzip --dryRun < "$archive" > "$manifest.raw" 2>&1; then
  echo "BACKUP VALIDATION FAILED: $archive" >&2
  cat "$manifest.raw" >&2
  rm -f "$archive" "$manifest.raw"
  exit 1
fi

# 2) Content signal: record source document counts. A zero count is legitimate
#    for an empty database but must be explicit, never silent.
echo "==> Recording collection counts"
counts=$(run_mongo_tool mongosh "$MDB_DATABASE" --quiet --eval '
  const out = {};
  db.getCollectionNames().sort().forEach(function (name) {
    out[name] = db.getCollection(name).countDocuments({});
  });
  print(JSON.stringify(out));
')
echo "$counts" > "$manifest"
echo "$counts"
rm -f "$manifest.raw"

# 3) Optional encryption: never leave plaintext when a recipient is configured.
if [ -n "$BACKUP_GPG_RECIPIENT" ]; then
  echo "==> Encrypting archive for $BACKUP_GPG_RECIPIENT"
  gpg --batch --yes --trust-model always --recipient "$BACKUP_GPG_RECIPIENT" \
    --output "$archive.gpg" --encrypt "$archive"
  rm -f "$archive"
  archive="$archive.gpg"
fi

ln -sfn "$archive" "$BACKUP_DIR/backup.latest"
ln -sfn "$manifest" "$BACKUP_DIR/backup.latest.manifest"

# 4) Optional off-host copy.
if [ -n "$BACKUP_OFFHOST_TARGET" ]; then
  echo "==> Copying to $BACKUP_OFFHOST_TARGET"
  rsync -a --partial "$archive" "$manifest" "$BACKUP_OFFHOST_TARGET"/
fi

# 5) Retention: keep the newest MAX_BACKUPS archives (and their manifests).
mapfile -t archives < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup.*.archive.gz*' -type f -printf '%T@ %p\n' \
  | sort -rn | awk '{print $2}')
if [ "${#archives[@]}" -gt "$MAX_BACKUPS" ]; then
  for old in "${archives[@]:$MAX_BACKUPS}"; do
    echo "==> Removing old backup: $old"
    rm -f "$old" "${old%.archive.gz*}.manifest.txt" "${old%.archive.gz*}.manifest.txt.gpg" 2>/dev/null || true
  done
fi

echo "==> Backup complete: $archive"
