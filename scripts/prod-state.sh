#!/usr/bin/env bash
# Read-only production state snapshot. Safe to run on the VM or pipe over SSH:
#   ssh user@vm 'bash -s' < scripts/prod-state.sh | tee prod-state.txt
# It never prints secrets and never writes to the system.
set -uo pipefail

section() { printf '\n== %s ==\n' "$*"; }
maybe() { "$@" 2>&1 || echo "[command failed: $*]"; }

section "identity"
date -u
hostname
uname -a
id
uptime

section "release"
if [ -d /opt/anyplace/.git ]; then
  maybe git -C /opt/anyplace rev-parse --short HEAD
  maybe git -C /opt/anyplace describe --tags --always --dirty
  maybe git -C /opt/anyplace status --porcelain
else
  echo "no git checkout at /opt/anyplace"
fi

section "service"
maybe systemctl is-active anyplace.service
maybe systemctl is-enabled anyplace.service
maybe systemctl show anyplace.service -p ActiveEnterTimestamp -p MainPID --no-pager
maybe systemctl status anyplace.service --no-pager -n 0

section "local api"
maybe curl -fsS --max-time 3 http://127.0.0.1:9000/api/version
maybe curl -fsS --max-time 3 http://127.0.0.1:9000/api/health
maybe sh -c "curl -fsS --max-time 5 --compressed -H 'Content-Type: application/json' -d '{}' http://127.0.0.1:9000/api/mapping/space/public | head -c 400"

section "listeners"
maybe sh -c "ss -ltn | grep -E ':(80|443|9000|27017)[[:space:]]' || true"

section "runtime"
maybe java -version
maybe nginx -v
maybe mongod --version
maybe mongosh --version

section "mongodb"
maybe systemctl is-active mongod
maybe systemctl is-enabled mongod
maybe sh -c "mongosh --quiet --host 127.0.0.1 --port 27017 --eval 'db.runCommand({ping:1})' 2>&1 | head -5"

section "nginx"
maybe ls -l /etc/nginx/sites-enabled
maybe sh -c "grep -hE 'server_name|listen|proxy_pass' /etc/nginx/sites-enabled/* 2>/dev/null | head -30"

section "certificates"
maybe ls -l /etc/letsencrypt/live
maybe sh -c "find /etc/letsencrypt/live -maxdepth 2 -name fullchain.pem -printf '%p %TY-%Tm-%Td\n' 2>/dev/null"

section "configuration"
maybe ls -l /etc/anyplace/anyplace.env /etc/anyplace/backup.env
if [ -f /opt/anyplace/server/conf/app.private.conf ]; then
  echo "app.private.conf: present"
  maybe sh -c "grep -hE '^(public.baseUrl|server.address|server.port|cors.allowedOrigins)' /opt/anyplace/server/conf/app.private.conf"
else
  echo "app.private.conf: MISSING"
fi

section "data"
maybe du -sh /opt/anyplace/floorplans /opt/anyplace/radiomaps_frozen
maybe sh -c "mongosh --quiet --host 127.0.0.1 --port 27017 --eval 'const d=db.getSiblingDB(\"anyplace\"); printjson({spaces:d.spaces.countDocuments(), floors:d.floors.countDocuments(), pois:d.pois.countDocuments(), edges:d.edges.countDocuments(), campuses:d.campuses.countDocuments()})' 2>&1 | head -5"

section "resources"
maybe df -h / /opt /var
maybe free -m
maybe nproc

section "backups"
maybe sh -c "ls -lh /var/backups/anyplace 2>&1 | tail -10"

section "recent journal"
maybe journalctl -u anyplace.service -n 20 --no-pager
