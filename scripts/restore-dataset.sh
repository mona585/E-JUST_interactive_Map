#!/usr/bin/env bash
# Restore the committed E-JUST mapping dataset and floorplan sources.
#
# Defaults:
#   - mapping collections are replaced with the committed snapshot (--drop)
#   - the bundled user record is excluded, so no shared credentials are imported
#   - floorplan source images are copied to <floorplans-root>/<buid>/fl_<n>/fl_<n>
#
# Usage:
#   sudo scripts/restore-dataset.sh [options]
#     --db <name>              target database (default: MONGODB_DATABASE or anyplace)
#     --keep-users             also restore the bundled user record (lab only)
#     --reassign-owner <id>    rewrite owner_id on restored spaces and campuses
#     --floorplans-root <dir>  destination for source floorplans (default /opt/anyplace/floorplans)
#     --skip-floorplans        database only
#     --tiles                  regenerate tiles after copying sources
#     --dry-run                validate the archive without writing
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
ARCHIVE="$REPO_ROOT/server/database/dump/anyplace.archive.gz"
SCHEMA="$REPO_ROOT/server/database/init_schema.js"
FLOORPLANS_SRC="$REPO_ROOT/server/database/floorplans"
TILER="$REPO_ROOT/server/anyplace_tiler/start-anyplace-tiler.sh"

DB=""
KEEP_USERS=0
REASSIGN_OWNER=""
FLOORPLANS_ROOT="/opt/anyplace/floorplans"
SKIP_FLOORPLANS=0
MAKE_TILES=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --db) DB="${2:?}"; shift 2 ;;
    --keep-users) KEEP_USERS=1; shift ;;
    --reassign-owner) REASSIGN_OWNER="${2:?}"; shift 2 ;;
    --floorplans-root) FLOORPLANS_ROOT="${2:?}"; shift 2 ;;
    --skip-floorplans) SKIP_FLOORPLANS=1; shift ;;
    --tiles) MAKE_TILES=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -f "$ARCHIVE" ] || { echo "missing committed archive: $ARCHIVE" >&2; exit 1; }

# --- connection settings -----------------------------------------------------
SERVICE_ENV=""
for f in /etc/anyplace/anyplace.env /etc/ejust-maps/ejust-maps.env; do
  [ -f "$f" ] && SERVICE_ENV="$f" && break
done
envv() {
  local file="$1" key="$2"
  awk -F= -v k="$key" '$1==k{sub(/^[^=]*=/,"",$0);gsub(/^"|"$/,"",$0);print;exit}' "$file"
}
# Explicit environment wins, then the protected service file, then defaults.
MDB_HOST="${MDB_HOST:-${MONGODB_HOST:-}}"
MDB_PORT="${MDB_PORT:-${MONGODB_PORT:-}}"
MDB_DB="${MDB_DB:-${MONGODB_DATABASE:-}}"
MDB_USER="${MDB_USER:-${MONGODB_USERNAME:-}}"
MDB_PASS="${MDB_PASS:-${MONGODB_PASSWORD:-}}"
if [ -n "$SERVICE_ENV" ]; then
  [ -n "$MDB_HOST" ] || MDB_HOST="$(envv "$SERVICE_ENV" MONGODB_HOST)"
  [ -n "$MDB_PORT" ] || MDB_PORT="$(envv "$SERVICE_ENV" MONGODB_PORT)"
  [ -n "$MDB_DB" ] || MDB_DB="$(envv "$SERVICE_ENV" MONGODB_DATABASE)"
  [ -n "$MDB_USER" ] || MDB_USER="$(envv "$SERVICE_ENV" MONGODB_USERNAME)"
  [ -n "$MDB_PASS" ] || MDB_PASS="$(envv "$SERVICE_ENV" MONGODB_PASSWORD)"
fi
MDB_HOST="${MDB_HOST:-127.0.0.1}"
MDB_PORT="${MDB_PORT:-27017}"
MDB_DB="${MDB_DB:-anyplace}"
DB="${DB:-$MDB_DB}"

MDB_MODE="${MDB_MODE:-}"
MDB_DOCKER_CONTAINER="${MDB_DOCKER_CONTAINER:-anyplace-mongo}"
if [ -z "$MDB_MODE" ]; then
  if command -v mongorestore >/dev/null 2>&1; then
    MDB_MODE=native
  elif command -v docker >/dev/null 2>&1 && docker inspect "$MDB_DOCKER_CONTAINER" >/dev/null 2>&1; then
    MDB_MODE=docker
  else
    echo "no mongorestore and no '$MDB_DOCKER_CONTAINER' container found" >&2
    exit 1
  fi
fi

AUTH_ARGS=()
if [ -n "$MDB_USER" ]; then
  AUTH_ARGS=(--username "$MDB_USER" --password "$MDB_PASS" --authenticationDatabase admin)
fi

mongo_tool_stdin() {
  local tool="$1"; shift
  if [ "$MDB_MODE" = "docker" ]; then
    docker exec -i "$MDB_DOCKER_CONTAINER" "$tool" \
      --host 127.0.0.1 --port 27017 "${AUTH_ARGS[@]}" "$@"
  else
    "$tool" --host "$MDB_HOST" --port "$MDB_PORT" "${AUTH_ARGS[@]}" "$@"
  fi
}

mongo_eval() {
  local js="$1"
  if [ "$MDB_MODE" = "docker" ]; then
    docker exec -i "$MDB_DOCKER_CONTAINER" mongosh \
      --host 127.0.0.1 --port 27017 "${AUTH_ARGS[@]}" \
      --quiet "$DB" --eval "$js"
  else
    mongosh --host "$MDB_HOST" --port "$MDB_PORT" "${AUTH_ARGS[@]}" \
      --quiet "$DB" --eval "$js"
  fi
}

echo "==> Restoring $ARCHIVE into database '$DB' ($MDB_MODE mode, dry-run=$DRY_RUN)"
args=(--archive --gzip)
if [ "$DRY_RUN" -eq 1 ]; then
  args+=(--dryRun)
else
  args+=(--drop)
  [ "$KEEP_USERS" -eq 1 ] || args+=("--nsExclude=$DB.users")
fi
if [ "$DB" != "anyplace" ]; then
  args+=("--nsFrom=anyplace.*" "--nsTo=$DB.*")
fi
mongo_tool_stdin mongorestore "${args[@]}" < "$ARCHIVE"

if [ "$DRY_RUN" -eq 0 ]; then
  if [ -n "$REASSIGN_OWNER" ]; then
    echo "==> Reassigning restored mapping data to owner '$REASSIGN_OWNER'"
    mongo_eval "db.spaces.updateMany({}, {\$set: {owner_id: '$REASSIGN_OWNER'}});
                db.campuses.updateMany({}, {\$set: {owner_id: '$REASSIGN_OWNER'}});"
  fi

  echo "==> Applying indexes"
  mongo_tool_stdin mongosh --quiet "$DB" < "$SCHEMA"

  echo "==> Verifying restored counts"
  mongo_eval "const c = function (n) { return db.getCollection(n).countDocuments({}); };
    print(JSON.stringify({spaces: c('spaces'), floorplans: c('floorplans'), pois: c('pois'),
      edges: c('edges'), campuses: c('campuses'), users: c('users')}));"
fi

if [ "$DRY_RUN" -eq 0 ] && [ "$SKIP_FLOORPLANS" -eq 0 ]; then
  [ -d "$FLOORPLANS_SRC" ] || { echo "missing floorplan sources: $FLOORPLANS_SRC" >&2; exit 1; }
  echo "==> Copying floorplan sources to $FLOORPLANS_ROOT"
  mkdir -p "$FLOORPLANS_ROOT"
  rsync -a --exclude '.gitignore' "$FLOORPLANS_SRC"/ "$FLOORPLANS_ROOT"/
  if [ "$MAKE_TILES" -eq 1 ]; then
    [ -x "$TILER" ] || { echo "tiler not executable: $TILER" >&2; exit 1; }
    echo "==> Regenerating map tiles"
    ( cd "$REPO_ROOT/server/anyplace_tiler" && ./start-anyplace-tiler.sh )
  else
    echo "==> Skipped tile generation (pass --tiles to regenerate)"
  fi
fi

echo "==> Dataset restore complete"
