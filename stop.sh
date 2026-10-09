#!/usr/bin/env bash

echo "=== Stopping Anyplace Local Environment ==="

# Stop systemd service if active
if command -v systemctl &>/dev/null && systemctl is-active --quiet anyplace 2>/dev/null; then
    echo "[*] Stopping anyplace systemd service..."
    systemctl stop anyplace 2>/dev/null || true
fi

# NOTE: bracket patterns ([p]lay...) never match this script's own command line.
PID=$(pgrep -f "[p]lay.core.server.ProdServerStart" || pgrep -f "[s]tage/bin/anyplace" || true)

if [ -n "$PID" ]; then
    echo "[*] Stopping Anyplace server process ($PID)..."
    # shellcheck disable=SC2086
    for p in $PID; do
        case "$p" in
            ''|*[!0-9]*) echo "[!] Skipping non-PID entry: $p" >&2;;
            *) kill -15 "$p" 2>/dev/null || kill -9 "$p" 2>/dev/null;;
        esac
    done
    sleep 1
fi

# Never fuser -k the port: it would kill whatever unrelated process holds it.
# Report instead; the operator decides.
for port in 9000 9001; do
    if command -v nc &>/dev/null && nc -z 127.0.0.1 "$port" &>/dev/null; then
        echo "[!] Port $port still occupied after stop (left for the operator)."
    fi
done

# Clean up lock files
rm -f server/target/universal/stage/RUNNING_PID RUNNING_PID 2>/dev/null

echo "[✓] Anyplace server stopped."
