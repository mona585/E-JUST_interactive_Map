#!/usr/bin/env bash

echo "=== Stopping Anyplace Local Environment ==="

PID=$(pgrep -f "play.core.server.ProdServerStart" || pgrep -f "target/universal/stage/bin/anyplace" || true)

if [ -n "$PID" ]; then
    echo "[*] Stopping Anyplace server process ($PID)..."
    kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null
    sleep 2
    echo "[✓] Anyplace server stopped."
else
    echo "[!] Anyplace server is not currently running."
fi
