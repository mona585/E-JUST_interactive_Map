#!/usr/bin/env bash
# ==============================================================================
# Anyplace Database Initialization & Reset Script
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

HOST="${MDB_HOST:-127.0.0.1}"
PORT="${MDB_PORT:-27017}"
DB="${MDB_DATABASE:-anyplace}"
DROP_FIRST=false

for arg in "$@"; do
    case $arg in
        --drop)
            DROP_FIRST=true
            shift
            ;;
    esac
done

echo "[+] Initializing Anyplace MongoDB Database at $HOST:$PORT/$DB..."

if [ "$DROP_FIRST" = true ]; then
    echo "[!] --drop specified. Wiping database '$DB'..."
    mongosh "mongodb://$HOST:$PORT/$DB" --eval "db.dropDatabase()" > /dev/null
    echo "[✓] Database '$DB' dropped."
fi

mongosh "mongodb://$HOST:$PORT/$DB" "$SCRIPT_DIR/init_schema.js"

echo "[✓] Anyplace Database Baseline Initialization Complete."
