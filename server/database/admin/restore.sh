#!/bin/bash
# Restore drill (D-10 / Phase 5): restores a coordinated backup bundle into
# an ISOLATED database/directory only. It never targets the production
# MongoDB database or the live floorplan/radiomap roots - see
# RESTORE_MDB_DATABASE and RESTORE_FILESYSTEM_DIR in config.sh.
cwd="$(dirname "$0")"
source $cwd/helper.sh

backupDir=$BACKUP_DIR

host=$RESTORE_MDB_HOST
port=$RESTORE_MDB_PORT
user=$RESTORE_MDB_USER
pass=$RESTORE_MDB_PASS
restoreToDatabase=$RESTORE_MDB_DATABASE

if [ "$restoreToDatabase" = "$MDB_DATABASE" ] && [ "$host" = "$MDB_HOST" ] && [ "$port" = "$MDB_PORT" ]; then
  echo "[!] Refusing to restore: RESTORE_MDB_* is identical to the production MDB_* target."
  echo "    Restore drills must use a disposable database (see config.example.sh)."
  exit 1
fi

backupLatest=$backupDir/backup.latest

if [ $# -eq 0 ]; then
  backup=$backupLatest
elif [ $# -eq 1 ]; then
  backup=$backupDir/$1
else
 echo "Usage: $0 [backupFilename]"
 echo "backupFilename: optional. If not given it uses the latest"
 exit 1
fi

backupTmp=$backupDir/tmp

checkBackupExists $backup

backup=$(decryptIfNeeded $backup)

untarBackup $backup $backupTmp

verifyManifest $backupData

restoreFilesystemRoots $backupData "$RESTORE_FILESYSTEM_DIR"

renameRestoreDatabase $backupData $restoreToDatabase

restoreBackup $backupData $backupTmp

echo -e "\n[✓] Restore drill complete: MongoDB -> database '$restoreToDatabase', filesystem -> '${RESTORE_FILESYSTEM_DIR:-<skipped>}'"
