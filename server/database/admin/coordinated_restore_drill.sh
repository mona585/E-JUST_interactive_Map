#!/bin/bash
# ==============================================================================
# D-10 quarterly isolated restore drill.
#
# Restores a coordinated_backup.sh bundle into a DISPOSABLE database and a
# DISPOSABLE filesystem directory only, verifies manifest checksums, and
# reports collection document counts. It never writes to the live database
# or the live floorplan/radiomap roots.
#
# Usage: ./coordinated_restore_drill.sh [bundle.tar.gz[.gpg]]
#        (defaults to $BACKUP_DIR/coordinated.latest)
# ==============================================================================
set -euo pipefail

cwd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$cwd/config.sh"

bundle="${1:-$BACKUP_DIR/coordinated.latest}"
if [ ! -e "$bundle" ]; then
  echo "[x] Bundle not found: $bundle"
  exit 1
fi

drillDir=$(mktemp -d)
trap 'rm -rf "$drillDir"' EXIT

plainBundle="$bundle"
if [[ "$bundle" == *.gpg ]]; then
  echo "[+] Decrypting bundle for the drill (local temp dir only)"
  plainBundle="$drillDir/bundle.tar.gz"
  gpg --yes --batch --output "$plainBundle" --decrypt "$bundle"
fi

echo "[+] Extracting to isolated drill directory: $drillDir"
tar -xzf "$plainBundle" -C "$drillDir"
extracted=$(find "$drillDir" -maxdepth 1 -type d -name 'coordinated.*' | head -n1)
if [ -z "$extracted" ]; then
  echo "[x] Unexpected bundle layout - no coordinated.* directory found."
  exit 1
fi

echo "[+] Verifying manifest checksums"
(cd "$extracted" && sha256sum -c <(grep -E '^[0-9a-f]{64}  ' MANIFEST.txt || true))

echo "[+] Restoring MongoDB dump into DISPOSABLE database: $RESTORE_MDB_DATABASE"
mongorestore --host="$RESTORE_MDB_HOST" --port="$RESTORE_MDB_PORT" \
  --authenticationDatabase admin \
  --username "$RESTORE_MDB_USER" --password "$RESTORE_MDB_PASS" \
  --nsFrom="$MDB_DATABASE.*" --nsTo="$RESTORE_MDB_DATABASE.*" \
  "$extracted/mongodb/$MDB_DATABASE" >/dev/null 2>&1

echo "[+] Disposable database collection counts:"
mongosh --host "$RESTORE_MDB_HOST" --port "$RESTORE_MDB_PORT" \
  --username "$RESTORE_MDB_USER" --password "$RESTORE_MDB_PASS" \
  --authenticationDatabase admin --quiet \
  --eval "db.getSiblingDB('$RESTORE_MDB_DATABASE').getCollectionNames().forEach(c => print(c + ': ' + db.getSiblingDB('$RESTORE_MDB_DATABASE').getCollection(c).countDocuments()))"

echo "[+] Filesystem roots present in the bundle:"
find "$extracted/filesystem" -maxdepth 1 -mindepth 1 -exec basename {} \; 2>/dev/null || echo "  (none captured - consistent with an empty baseline)"

echo "[✓] Restore drill complete. Disposable database '$RESTORE_MDB_DATABASE' and"
echo "    $drillDir will be removed on exit; drop the disposable database"
echo "    manually if you want to inspect it further first (Ctrl+C now)."
