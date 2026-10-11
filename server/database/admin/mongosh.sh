#!/bin/bash
cwd="$(dirname "$0")"
source "$cwd/config.sh"

host="$MDB_HOST"
port="$MDB_PORT"
user="$MDB_USER"
pass="$MDB_PASS"

mongosh --host "$host" --port "$port" --username "$user" --password "$pass" --authenticationDatabase admin
