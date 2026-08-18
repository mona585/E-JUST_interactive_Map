#!/bin/bash
cwd="$(dirname "$0")"
source $cwd/config.sh

###
# BACKUP METHODS:
###

function checkBackupTaken() {
  backup=$1
  if [ -d $backup ]; then
    echo "Backup was already taken for this timestamp: $backup"
    exit 1
  fi
}


function backupPrepare() {
 backupDir=$1
 backupLatest=$2

 mkdir -p $backupDir/
 if [ -L $backupLatest ]; then
   rm $backupLatest
 fi
}

function createBackup() {
 backupFolder=$1
 backupName=$(basename $backupFolder)
 mongoFolder="$backupFolder/mongo"

 mkdir -p "$mongoFolder"
 echo -e "Backup (mongodump) to: $mongoFolder"
 mongodump --host $host --port $port \
   --db $database --authenticationDatabase admin \
   --username $user --password $pass --out $mongoFolder >/dev/null 2>&1
}

function finalizeBackup() {
 backupFolder=$1

 echo -e "Compressing to:        $backupTar"
 tar -C $backupDir -czf $backupTar $(basename $backupFolder) > /dev/null
 if [ -d $backupFolder ]; then
   rm -rf $backupFolder
 fi

 encryptBundle "$backupTar"
 if [ -f "$backupTar.gpg" ]; then
   ln -sf "$backupTar.gpg" $backupLatest
   copyOffHost "$backupTar.gpg"
 else
   ln -sf $backupTar $backupLatest
   copyOffHost "$backupTar"
 fi
}

###
# COORDINATED FILESYSTEM + MANIFEST METHODS (D-10):
#
# A MongoDB-only backup is not a faithful snapshot: floorplan/radiomap
# metadata lives in MongoDB while the actual images/tiles/fingerprint
# files live on disk. Both must be captured from the same point in time
# and travel together, or a restore silently mixes mismatched state.
###

function backupFilesystemRoots() {
  fsFolder=$1

  mkdir -p "$fsFolder"
  for root in "$FLOOR_PLANS_ROOT_DIR" "$RADIOMAP_RAW_DIR" "$RADIOMAP_FROZEN_DIR"; do
    if [ -z "$root" ]; then
      continue
    fi
    name=$(basename "$root")
    if [ -d "$root" ]; then
      echo -e "Copying filesystem root: $root"
      cp -a "$root" "$fsFolder/$name"
    else
      echo -e "[!] Configured root does not exist, skipping: $root"
    fi
  done
}

function writeManifest() {
  bundleDir=$1
  manifestFile="$bundleDir/MANIFEST.txt"

  {
    echo "# Anyplace coordinated backup manifest"
    echo "timestamp_utc: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    echo "mongodb_database: $database"
    echo "floorplans_root: $FLOOR_PLANS_ROOT_DIR"
    echo "radiomap_raw_root: $RADIOMAP_RAW_DIR"
    echo "radiomap_frozen_root: $RADIOMAP_FROZEN_DIR"
    echo
    echo "# SHA-256 checksums of every captured file (verify after restore)"
  } > "$manifestFile"

  ( cd "$bundleDir" && find . -type f ! -name "MANIFEST.txt" -exec sha256sum {} \; ) >> "$manifestFile"
}

function encryptBundle() {
  bundleTar=$1

  if [ -z "$GPG_RECIPIENT" ]; then
    echo -e "[!] GPG_RECIPIENT not set - skipping encryption (only acceptable for local/disposable testing)."
    return
  fi
  echo -e "Encrypting bundle for: $GPG_RECIPIENT"
  gpg --yes --batch --trust-model always --recipient "$GPG_RECIPIENT" \
    --output "$bundleTar.gpg" --encrypt "$bundleTar"
  rm -f "$bundleTar"
  echo -e "Encrypted bundle:      $bundleTar.gpg"
}

function copyOffHost() {
  bundleFile=$1

  if [ -z "$OFFHOST_COPY_TARGET" ]; then
    echo -e "[!] OFFHOST_COPY_TARGET not set - bundle stays on the application host only."
    echo -e "    A single-host backup does not satisfy the D-10 'encrypted off-host' policy."
    return
  fi
  echo -e "Copying off-host to:   $OFFHOST_COPY_TARGET"
  rsync -a "$bundleFile" "$OFFHOST_COPY_TARGET"
}

function deleteOldBackups() {
backupDir=$1

numBackups=$(ls $backupDir -l | grep -v ^l | grep -v "tmp.*$" | grep -v "total"| wc -l)

numBackups=$(($numBackups + 0))
maxBackups=$(($MAX_BACKUPS + 0))
#echo "NumBackups: "$numBackups
#echo "MaxBackups: "$maxBackups
if [ $numBackups -ge $maxBackups ]; then
  deleteNum=$(expr $numBackups - $maxBackups)
  #echo "DeleteNum: "$deleteNum
  toDelete=$(ls -tp $backupDir | grep -v ^l | grep -v "tmp.*$" | tail -n $deleteNum)
  if [ ! -z "$toDelete" ]; then
    echo -e "Clearing old backups:"
    for f in $toDelete;
    do
      file=$backupDir/$f
      if [ ! -z $f ] && [ -f $file ]; then
        echo -e "\t - "$file
        rm -rf $file
      fi
    done
  fi
fi
}

###
# RESTORE METHODS:
###

function checkBackupExists() {
  backup=$1

if [ ! -f $backup ]; then
  echo "Backup file does not exist: "$backup
  echo "Available backups:"
  ls $backupDir -l | grep -v ^l
  exit 1
fi
}


function decryptIfNeeded() {
  # Callers capture this function's stdout as the resulting path
  # ($(decryptIfNeeded ...)), so all status text must go to stderr.
  backup=$1

  case "$backup" in
    *.gpg)
      decrypted="${backup%.gpg}"
      echo "Decrypting: $backup" >&2
      gpg --yes --batch --output "$decrypted" --decrypt "$backup" >&2
      echo "$decrypted"
      ;;
    *)
      echo "$backup"
      ;;
  esac
}

function untarBackup() {
  backup=$1
  backupTmp=$2

  echo "Restoring from: "$backup
  mkdir -p $backupTmp

  tar -zxvf $backup -C $backupTmp > /dev/null

  backupData=$backupTmp/$(ls $backupTmp)
}


function renameRestoreDatabase() {
  data=$1
  newName=$2
  mongoDir="$data/mongo"

  # RestorePreparation: mongodump wrote a folder named after the original
  # database under mongo/; rename it so mongorestore creates the disposable
  # restoreToDatabase instead of overwriting a database with the original name.
  backedupDatabaseName=$(ls $mongoDir)
  mv $mongoDir/$backedupDatabaseName $mongoDir/$newName
}

function restoreBackup() {
backupData=$1
backupTmp=$2

# Restore
# INFO: --drop: drops all previous data..
echo -e "Restoring (mongorestore) from: $backupData/mongo"
mongorestore --host=$host --port=$port \
   --authenticationDatabase admin \
   --username $user --password $pass "$backupData/mongo" >/dev/null 2>&1

# restoreCleanup
if [ -d $backupData ]; then
  echo -e "Cleaning up tmp dir"
  rm -rf $backupTmp
fi

}

function restoreFilesystemRoots() {
  backupData=$1
  targetDir=$2

  if [ -z "$targetDir" ]; then
    echo -e "[!] RESTORE_FILESYSTEM_DIR not set - skipping filesystem restore."
    return
  fi
  if [ ! -d "$backupData/filesystem" ]; then
    echo -e "[!] No filesystem/ directory in this backup bundle - MongoDB-only backup."
    return
  fi
  echo -e "Restoring filesystem roots to: $targetDir"
  mkdir -p "$targetDir"
  cp -a "$backupData/filesystem/." "$targetDir/"
}

function verifyManifest() {
  backupData=$1

  manifestFile="$backupData/MANIFEST.txt"
  if [ ! -f "$manifestFile" ]; then
    echo -e "[!] No MANIFEST.txt in this backup bundle - checksum verification skipped."
    return
  fi
  echo -e "Verifying checksums against MANIFEST.txt ..."
  # Manifest lines are "sha256sum ./relative/path"; filter the header lines out.
  ( cd "$backupData" && grep -E '^[0-9a-f]{64}  ' "$manifestFile" | sha256sum -c - )
}
