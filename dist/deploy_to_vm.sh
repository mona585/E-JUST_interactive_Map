#!/usr/bin/env bash
# ==============================================================================
# Script to run Anyplace Server on Target VM
# ==============================================================================

set -e
PORT=${1:-9000}

echo "[+] Unpacking Anyplace Server..."
unzip -q -o anyplace-server-production.zip
SERVER_DIR=$(find . -maxdepth 1 -type d -name "anyplace-*" | head -n 1)

cd "$SERVER_DIR"
chmod +x bin/anyplace

# Remove old PID lock if existing
rm -f RUNNING_PID

if [ -z "$APPLICATION_SECRET" ]; then
    echo "[!] Error: APPLICATION_SECRET environment variable must be set to run Anyplace Server." >&2
    exit 1
fi

echo "[+] Starting Anyplace Server on port $PORT..."
./bin/anyplace -Dhttp.port="$PORT" -Dplay.http.secret.key="$APPLICATION_SECRET"
