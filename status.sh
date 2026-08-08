#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Anyplace Service Status ==="

# Check MongoDB
if nc -z 127.0.0.1 27017 &> /dev/null; then
    echo " [✓] MongoDB (Port 27017): ONLINE"
else
    echo " [✗] MongoDB (Port 27017): OFFLINE"
fi

# Check Anyplace Server
PID=$(pgrep -f "play.core.server.ProdServerStart" || pgrep -f "target/universal/stage/bin/anyplace" || true)
if [ -n "$PID" ]; then
    echo " [✓] Anyplace Backend (PID $PID): ONLINE (Port 9000)"
else
    echo " [✗] Anyplace Backend: OFFLINE"
fi

echo -e "\n=== Recent Server Logs (last 15 lines) ==="
if [ -f "$ROOT_DIR/anyplace.log" ]; then
    tail -n 15 "$ROOT_DIR/anyplace.log"
else
    echo "No log file found at $ROOT_DIR/anyplace.log"
fi
