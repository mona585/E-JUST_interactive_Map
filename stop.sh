#!/usr/bin/env bash

echo "=== Stopping Anyplace Local Environment ==="

# Stop systemd service if active
if command -v systemctl &>/dev/null && systemctl is-active --quiet anyplace 2>/dev/null; then
    echo "[*] Stopping anyplace systemd service..."
    systemctl stop anyplace 2>/dev/null || true
fi

PID=$(pgrep -f "play.core.server.ProdServerStart" || pgrep -f "target/universal/stage/bin/anyplace" || true)

if [ -n "$PID" ]; then
    echo "[*] Stopping Anyplace server process ($PID)..."
    kill -15 $PID 2>/dev/null || kill -9 $PID 2>/dev/null
    sleep 1
fi

# Ensure port 9000 is freed
if command -v fuser &>/dev/null; then
    fuser -k 9000/tcp 2>/dev/null || true
fi

# Clean up lock files
rm -f server/target/universal/stage/RUNNING_PID RUNNING_PID 2>/dev/null

echo "[✓] Anyplace server stopped."
