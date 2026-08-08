#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="$ROOT_DIR/server"

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
    docker run -d --name anyplace-mongodb -p 27017:27017 -v anyplace_mongo_data:/data/db mongo:latest 2>/dev/null || docker start anyplace-mongodb
    sleep 3
    echo "[✓] MongoDB container started."
else
    echo "[!] WARNING: MongoDB is not running on port 27017. Backend may fail to connect."
fi

# Check if Anyplace is already running
if pgrep -f "target/universal/stage/bin/anyplace" > /dev/null; then
    echo "[!] Anyplace server is already running!"
    exit 0
fi

# Extract application secret from configuration file
CONF_PATH="$SERVER_DIR/conf/app.private.conf"
APP_SECRET=$(grep -E '^(play\.http\.secret\.key|application\.secret)' "$CONF_PATH" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | head -n 1 || echo "AnyplaceSecretKey2026")
if [ -z "$APP_SECRET" ]; then
    APP_SECRET="AnyplaceSecretKey2026"
fi

echo "[*] Launching Anyplace Backend on port 9000..."
nohup "$SERVER_DIR/target/universal/stage/bin/anyplace" -Dplay.http.secret.key="$APP_SECRET" -Dapplication.secret="$APP_SECRET" -Dhttp.port=9000 > "$ROOT_DIR/anyplace.log" 2>&1 &

sleep 3
if pgrep -f "target/universal/stage/bin/anyplace" > /dev/null; then
    echo "[✓] Anyplace server started successfully!"
    echo "    - Backend API: http://localhost:9000/api"
    echo "    - Architect Web App: http://localhost:9000/architect/"
    echo "    - Viewer Web App: http://localhost:9000/viewer/"
    echo "    - Log output: $ROOT_DIR/anyplace.log"
else
    echo "[✗] Anyplace server failed to start. Check $ROOT_DIR/anyplace.log"
    exit 1
fi
