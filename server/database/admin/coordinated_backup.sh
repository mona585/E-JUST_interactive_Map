#!/bin/bash
# ==============================================================================
# D-10 coordinated backup: MongoDB + floorplan/raw-radiomap/frozen-radiomap
# filesystem roots, captured from the SAME point in time, with a manifest of
# checksums, then (optionally) encrypted and copied off-host.
#
# This wraps the existing mongodump-only backup.sh/helper.sh (Mongo backup is
# unchanged) rather than replacing it, and adds the filesystem+manifest+
# encryption+off-host steps the recovery report identified as missing.
#
# Usage: ./coordinated_backup.sh
# Config: server/database/admin/config.sh (copy from config.example.sh) plus
#         the FS_* and OFFHOST_* variables documented below.
# ==============================================================================
set -euo pipefail

cwd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$cwd/config.sh"

# --- Filesystem roots to capture alongside MongoDB (config.sh may override) ---
# Must match server/conf/app.private.conf: floorPlansRootDir, radioMapRawDir,
# radioMapFrozenDir. Defaults match app.base install layout under $SERVER_DIR.
SERVER_DIR="${SERVER_DIR:-$cwd/../../..}"
FS_FLOORPLANS="${FS_FLOORPLANS:-$SERVER_DIR/server/floorplans}"
FS_RADIOMAPS_RAW="${FS_RADIOMAPS_RAW:-$SERVER_DIR/server/radiomaps_raw}"
FS_RADIOMAPS_FROZEN="${FS_RADIOMAPS_FROZEN:-$SERVER_DIR/server/radiomaps_frozen}"

# --- Off-host copy target (D-10: "encrypted off-host"). External dependency:
# the actual destination/credentials must be supplied by the operator; this
# script never invents one. Leave OFFHOST_TARGET unset to skip the copy step
# (source-side bundle + manifest are still produced and retained locally).
OFFHOST_TARGET="${OFFHOST_TARGET:-}"
# GPG recipient for encrypting the bundle before it leaves the host. Leave
# unset to skip encryption (not recommended for anything sent off-host).
GPG_RECIPIENT="${GPG_RECIPIENT:-}"

RETENTION_DAYS="${RETENTION_DAYS:-30}"

timestamp=$(date +'%Y.%m.%d-%H.%M')
bundleDir="$BACKUP_DIR/coordinated.$timestamp"
mkdir -p "$bundleDir"

echo "[+] Coordinated backup $timestamp -> $bundleDir"

echo "[+] 1/4 MongoDB (mongodump)"
mongodump --host "$MDB_HOST" --port "$MDB_PORT" \
  --db "$MDB_DATABASE" --authenticationDatabase admin \
  --username "$MDB_USER" --password "$MDB_PASS" \
  --out "$bundleDir/mongodb" >/dev/null 2>&1

echo "[+] 2/4 Filesystem roots (floorplans, raw + frozen radiomaps)"
mkdir -p "$bundleDir/filesystem"
for src in "$FS_FLOORPLANS" "$FS_RADIOMAPS_RAW" "$FS_RADIOMAPS_FROZEN"; do
  if [ -d "$src" ]; then
    cp -a "$src" "$bundleDir/filesystem/$(basename "$src")"
  else
    echo "    [!] $src does not exist yet (empty baseline) - skipping, not an error."
  fi
done

echo "[+] 3/4 Manifest and checksums"
manifest="$bundleDir/MANIFEST.txt"
{
  echo "coordinated_backup_timestamp=$timestamp"
  echo "mongodb_host=$MDB_HOST:$MDB_PORT"
  echo "mongodb_database=$MDB_DATABASE"
  echo "captured_from_single_run=true"
} > "$manifest"
find "$bundleDir" -type f ! -name MANIFEST.txt -exec sha256sum {} \; >> "$manifest"

bundleTar="$BACKUP_DIR/coordinated.$timestamp.tar.gz"
tar -C "$BACKUP_DIR" -czf "$bundleTar" "coordinated.$timestamp"
rm -rf "$bundleDir"
echo "    Bundle: $bundleTar"

artifact="$bundleTar"
if [ -n "$GPG_RECIPIENT" ]; then
  echo "[+] Encrypting bundle for $GPG_RECIPIENT"
  gpg --yes --batch --recipient "$GPG_RECIPIENT" --output "$bundleTar.gpg" --encrypt "$bundleTar"
  rm -f "$bundleTar"
  artifact="$bundleTar.gpg"
else
  echo "    [!] GPG_RECIPIENT not set - bundle left unencrypted locally. Do not"
  echo "        copy it off-host until encryption is configured."
fi

echo "[+] 4/4 Off-host copy"
if [ -n "$OFFHOST_TARGET" ]; then
  scp "$artifact" "$OFFHOST_TARGET"
  echo "    Copied to $OFFHOST_TARGET"
else
  echo "    [!] OFFHOST_TARGET not set (EXTERNAL DEPENDENCY: no off-host"
  echo "        destination has been supplied). Local artifact only: $artifact"
fi

echo "[+] Retention: pruning coordinated bundles older than $RETENTION_DAYS days"
find "$BACKUP_DIR" -maxdepth 1 -name 'coordinated.*.tar.gz*' -mtime +"$RETENTION_DAYS" -print -delete

ln -sf "$artifact" "$BACKUP_DIR/coordinated.latest"
echo "[✓] Coordinated backup complete: $artifact"
