#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"

if [ -e "/var/run/docker.sock" ]; then
    export DOCKER_HOST="unix:///var/run/docker.sock"
fi

# Prioritize Java 11/17 for Anyplace Play framework compatibility
if [ -d "/usr/lib/jvm/java-11-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
elif [ -d "/usr/lib/jvm/java-17-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
    export PATH="$JAVA_HOME/bin:$PATH"
fi

# Java 17 reflection permissions required by Guice / CGLIB
export JDK_JAVA_OPTIONS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED ${JDK_JAVA_OPTIONS:-}"

echo "=== Starting Anyplace Local Environment ==="

# Check MongoDB
if nc -z 127.0.0.1 27017 &> /dev/null; then
    echo "[✓] MongoDB is running on port 27017."
elif command -v docker &> /dev/null; then
    echo "[!] MongoDB not detected. Starting MongoDB Docker container..."
    docker start anyplace-mongodb 2>/dev/null || docker run -d --name anyplace-mongodb -p 27017:27017 -v anyplace_mongo_data:/data/db mongo:latest 2>/dev/null
    sleep 3
    echo "[✓] MongoDB container started."
else
    echo "[!] WARNING: MongoDB is not running on port 27017. Backend may fail to connect."
fi

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

# Use an explicit environment value when supplied; otherwise read the private
# configuration. A missing or placeholder secret must stop startup.
CONF_PATH="$SERVER_DIR/conf/app.private.conf"
APP_SECRET="${APPLICATION_SECRET:-$(grep -E '^(play\.http\.secret\.key|application\.secret)' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -n 1 || true)}"
if [ -z "$APP_SECRET" ] || [[ "$APP_SECRET" == CHANGE_ME_* ]] || [[ "$APP_SECRET" == "APPLICATION_SECRET_KEY" ]] || [[ "$APP_SECRET" == "YOUR_APPLICATION_SECRET" ]]; then
    echo "[x] APPLICATION_SECRET is missing. Set it in server/conf/app.private.conf or the environment."
    exit 1
fi

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
