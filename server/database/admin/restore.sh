#!/bin/bash
# Restore a verified Anyplace MongoDB archive (native or Docker mongo).
# Usage: restore.sh [archive] [--dry-run]
#   archive    optional; defaults to $BACKUP_DIR/backup.latest
#   --dry-run  validate and report, write nothing
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
RESTORE_MDB_DATABASE="${RESTORE_MDB_DATABASE:-$MDB_DATABASE}"

dry_run=0
archive=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    */*|*\\*|..*) echo "Invalid backup path: $arg" >&2; exit 1 ;;
    *) archive="$arg" ;;
  esac
done

if [ -z "$archive" ]; then
  archive="$BACKUP_DIR/backup.latest"
fi
if [ ! -e "$archive" ]; then
  echo "Backup archive not found: $archive" >&2
  echo "Available backups:" >&2
  ls -1 "$BACKUP_DIR" >&2 || true
  exit 1
fi

work="$archive"
cleanup=""
if [[ "$archive" == *.gpg ]]; then
  work="$(mktemp "${TMPDIR:-/tmp}/anyplace-restore.XXXXXX")"
  cleanup="$work"
  gpg --batch --yes --output "$work" --decrypt "$archive"
fi
trap '[ -n "$cleanup" ] && rm -f "$cleanup"' EXIT

run_mongo_tool_stdin() {
  local tool="$1"; shift
  if [ "$MDB_MODE" = "docker" ]; then
    [ -n "$MDB_DOCKER_CONTAINER" ] || { echo "MDB_DOCKER_CONTAINER is required for docker mode" >&2; exit 1; }
    docker exec -i "$MDB_DOCKER_CONTAINER" "$tool" \
      --host 127.0.0.1 --port 27017 \
      --username "$RESTORE_MDB_USER" --password "$RESTORE_MDB_PASS" --authenticationDatabase admin "$@"
  else
    "$tool" --host "$RESTORE_MDB_HOST" --port "$RESTORE_MDB_PORT" \
      --username "$RESTORE_MDB_USER" --password "$RESTORE_MDB_PASS" --authenticationDatabase admin "$@"
  fi
}

args=(--archive --gzip)
if [ "$dry_run" -eq 1 ]; then
  args+=(--dryRun)
else
  args+=(--drop)
fi
if [ "$RESTORE_MDB_DATABASE" != "$MDB_DATABASE" ]; then
  args+=("--nsFrom=$MDB_DATABASE.*" "--nsTo=$RESTORE_MDB_DATABASE.*")
fi

echo "==> Restoring $archive into '$RESTORE_MDB_DATABASE' (dry-run=$dry_run)"
run_mongo_tool_stdin mongorestore "${args[@]}" < "$work"

echo "==> Restore complete: $RESTORE_MDB_DATABASE"
