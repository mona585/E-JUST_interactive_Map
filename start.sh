#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"

if [ -e "/var/run/docker.sock" ]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
fi

# Ubuntu 22.04 recovery target: use the pinned OpenJDK 17 runtime.
if [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Java 17 reflection permissions required by Guice / CGLIB
export JDK_JAVA_OPTIONS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED ${JDK_JAVA_OPTIONS:-}"

echo "=== Starting Anyplace Local Environment ==="

# The D-06 baseline is an authenticated MongoDB service bound to loopback.
# Never create a Docker MongoDB instance from this script: its default port
# publishing can expose the database on every host interface.
for required_var in APPLICATION_SECRET MONGODB_HOST MONGODB_PORT MONGODB_DATABASE MONGODB_USERNAME MONGODB_PASSWORD; do
    required_value="${!required_var:-}"
    if [ -z "$required_value" ] || [[ "$required_value" == CHANGE_ME_* ]]; then
        echo "[x] $required_var is missing. Set it in the protected environment before startup."
        exit 1
    fi
done

if [[ "$MONGODB_HOST" != "127.0.0.1" && "$MONGODB_HOST" != "localhost" && "$MONGODB_HOST" != "::1" ]]; then
    echo "[x] MONGODB_HOST must be a loopback address for the D-06 baseline."
    exit 1
fi

if ! command -v nc &> /dev/null || ! nc -z "$MONGODB_HOST" "$MONGODB_PORT" &> /dev/null; then
    echo "[x] MongoDB is not reachable at $MONGODB_HOST:$MONGODB_PORT. Start the authenticated local service first."
    exit 1
fi
echo "[✓] MongoDB is reachable on the configured loopback address."

# Check if Anyplace is already running on port 9000
if (command -v nc &> /dev/null && nc -z 127.0.0.1 9000 &> /dev/null); then
    echo "[✓] Anyplace server is already running and listening on port 9000!"
    echo "    - Backend API: http://localhost:9000/api"
    echo "    - Architect Web App: http://localhost:9000/architect/"
    echo "    - Viewer Web App: http://localhost:9000/viewer/"
    exit 0
fi

# Remove stale RUNNING_PID lockfile if present from a previous run/crash
rm -f "$SERVER_DIR/target/universal/stage/RUNNING_PID"
rm -f "$ROOT_DIR/RUNNING_PID"

# Configuration is resolved from the protected environment through
# server/conf/app.private.conf. Do not fall back to a tracked or generated key.
APP_SECRET="$APPLICATION_SECRET"

echo "[*] Launching Anyplace Backend on port 9000..."
setsid nohup "$SERVER_DIR/target/universal/stage/bin/anyplace" \
    -J--add-opens=java.base/java.lang=ALL-UNNAMED \
    -J--add-opens=java.base/java.util=ALL-UNNAMED \
    -J--add-opens=java.base/java.lang.invoke=ALL-UNNAMED \
    -J--add-opens=java.base/java.io=ALL-UNNAMED \
    -Dplay.http.secret.key="$APP_SECRET" \
    -Dapplication.secret="$APP_SECRET" \
    -Dhttp.port=9000 > "$ROOT_DIR/anyplace.log" 2>&1 &
disown || true

sleep 4
if (command -v nc &> /dev/null && nc -z 127.0.0.1 9000 &> /dev/null) || pgrep -f "play.core.server.ProdServerStart" > /dev/null; then
    echo "[✓] Anyplace server started successfully!"
    echo "    - Backend API: http://localhost:9000/api"
    echo "    - Architect Web App: http://localhost:9000/architect/"
    echo "    - Viewer Web App: http://localhost:9000/viewer/"
    echo "    - Log output: $ROOT_DIR/anyplace.log"
else
    echo "[✗] Anyplace server failed to start. Check $ROOT_DIR/anyplace.log"
    exit 1
fi
