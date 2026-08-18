#!/bin/bash
cwd="$(dirname "$0")"
source $cwd/helper.sh

backupDir=$BACKUP_DIR
host=$MDB_HOST
port=$MDB_PORT
user=$MDB_USER
pass=$MDB_PASS
database=$MDB_DATABASE

#timestamp=$(date +'%Y.%m.%d-%H.%M.%S')
timestamp=$(date +'%Y.%m.%d-%H.%M')
backup=$backupDir/backup.$timestamp
backupTar=$backup.tar.gz
backupLatest=$backupDir/backup.latest

checkBackupTaken $backup

backupPrepare $backupDir $backupLatest

# Coordinated backup (D-10): MongoDB dump plus the floorplan/radiomap
# filesystem roots, from the same run, plus a checksummed manifest so a
# restore can be verified for completeness rather than trusted blindly.
createBackup $backup
backupFilesystemRoots "$backup/filesystem"
writeManifest $backup

finalizeBackup $backup

deleteOldBackups $backupDir

echo -e "\n[✓] Coordinated backup complete: ${backupTar}(.gpg)"
