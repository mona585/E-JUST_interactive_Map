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

  # Requires single-node replica set (rs.initiate()) so --oplog is available;
  # standalone mongod has no oplog and this backup fails loudly by design.
  echo -e "Backup (mongodump --oplog --gzip) to: $backupFolder"
  if ! mongodump --host $host --port $port \
    --db $database --authenticationDatabase admin \
    --username $user --password $pass \
    --oplog --gzip --out $backupFolder; then
    echo -e "BACKUP FAILED for: $backupFolder" >&2
    exit 1
  fi
  # mkdir $backupFolder # fake testing backup

 echo -e "Compressing to:        $backupTar"
 tar -C $backupDir -czf $backupTar $backupName > /dev/null
 if [ -d $backupFolder ]; then
   rm -rf $backupFolder
 fi

  ln -s $backupTar $backupLatest
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

  # RestorePreparation
  backedupDatabaseName=$(ls $data)
  mv $data/$backedupDatabaseName $data/$newName
}

function restoreBackup() {
backupData=$1
backupTmp=$2

# Restore
# INFO: --drop: drops all previous data..
# --oplogReplay matches --oplog backups; harmless if the dump has no oplog.
echo -e "Restoring (mongorestore --oplogReplay) from: $backupData"
if ! mongorestore --host=$host --port=$port \
   --authenticationDatabase admin \
   --username $user --password $pass --oplogReplay $backupData; then
  echo -e "RESTORE FAILED from: $backupData" >&2
  exit 1
fi

# restoreCleanup
if [ -d $backupData ]; then
  echo -e "Cleaning up tmp dir"
  rm -rf $backupTmp
fi

}
