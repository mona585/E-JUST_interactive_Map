#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Anyplace Service Status ==="

# Check MongoDB (honor environment overrides; default loopback baseline)
MDB_HOST="${MONGODB_HOST:-127.0.0.1}"
MDB_PORT="${MONGODB_PORT:-27017}"
if nc -z "$MDB_HOST" "$MDB_PORT" &> /dev/null; then
    echo " [✓] MongoDB ($MDB_HOST:$MDB_PORT): ONLINE"
else
    echo " [✗] MongoDB ($MDB_HOST:$MDB_PORT): OFFLINE"
fi

# Check Anyplace Server (PID + real HTTP probe; never trust PID alone)
PID=$(pgrep -f "[p]lay.core.server.ProdServerStart" || pgrep -f "[s]tage/bin/anyplace" || true)
if [ -n "$PID" ]; then
    echo " [✓] Anyplace Backend (PID $PID): process present"
else
    echo " [✗] Anyplace Backend: no process"
fi
for port in 9000 9001; do
    if curl -fs -m 5 "http://127.0.0.1:$port/api/health" 2>/dev/null | grep -q '"status":"ok"'; then
        echo " [✓] Anyplace API (Port $port): HEALTHY"
    else
        echo " [·] Anyplace API (Port $port): no health response"
    fi
done

echo -e "\n=== Recent Server Logs (last 15 lines) ==="
if [ -f "$ROOT_DIR/anyplace.log" ]; then
    tail -n 15 "$ROOT_DIR/anyplace.log"
else
    echo "No log file found at $ROOT_DIR/anyplace.log"
fi
