#!/bin/bash
#
# Disposable Campus -> Space -> Floor -> POI -> Connection fixture
# (Phase 5 "isolated synthetic ... fixture"; also the input Phase 6 needs to
# exercise the floorplan/tiler pipeline end to end).
#
# This creates throwaway data through the real API - never real E-JUST
# content - so Architect/Viewer/navigation/tiler workflows can be verified
# against something. Run only against a disposable/staging database, never
# against a database already carrying official hydrated data.
#
# Usage:
#   cp config.example.sh config.sh   # once, then edit API_BASE_URL etc.
#   ./create_fixture.sh              # creates the fixture, prints its IDs
#   ./create_fixture.sh --cleanup    # removes everything the last run made
#
# IDs of everything created are written to fixture_state.env (gitignored)
# next to this script, so --cleanup can find and remove them again.
set -euo pipefail

cwd="$(dirname "$0")"
source "$cwd/config.sh"
stateFile="$cwd/fixture_state.env"

extract() {
  # extract '"key":"value"' from $1's JSON body, for the given key ($2)
  echo "$1" | grep -o "\"$2\":\"[^\"]*\"" | head -n1 | cut -d'"' -f4
}

api() {
  # api METHOD PATH JSON_BODY
  curl -sS -X "$1" "$API_BASE_URL$2" -H 'Content-Type: application/json' -d "$3"
}

do_cleanup() {
  if [ ! -f "$stateFile" ]; then
    echo "No fixture_state.env found - nothing to clean up."
    return
  fi
  # shellcheck disable=SC1090
  source "$stateFile"

  echo "Removing fixture data (direct MongoDB deletes - the mapping API has no bulk delete) ..."
  mongosh --host "$MDB_HOST" --port "$MDB_PORT" --authenticationDatabase admin \
    --username "$MDB_USER" --password "$MDB_PASS" --quiet "$MDB_DATABASE" --eval "
      db.edges.deleteMany({buid: '${FIXTURE_BUID:-}'});
      db.pois.deleteMany({buid: '${FIXTURE_BUID:-}'});
      db.floorplans.deleteMany({buid: '${FIXTURE_BUID:-}'});
      db.spaces.deleteMany({buid: '${FIXTURE_BUID:-}'});
      db.campuses.deleteMany({cuid: '${FIXTURE_CUID:-}'});
      db.users.deleteMany({username: '${FIXTURE_USERNAME:-}'});
    "
  rm -f "$stateFile"
  echo "[✓] Fixture cleaned up."
}

if [ "${1:-}" = "--cleanup" ]; then
  do_cleanup
  exit 0
fi

if [ -f "$stateFile" ]; then
  echo "fixture_state.env already exists - run '$0 --cleanup' first, or remove it, to avoid orphaned duplicate fixtures."
  exit 1
fi

tag=$(date +%s)
FIXTURE_USERNAME="fixture_user_${tag}"
FIXTURE_EMAIL="fixture_${tag}@example.invalid"
FIXTURE_PASSWORD="FixturePassword123!"

echo "[1/6] Registering disposable mapping user ..."
regResp=$(api POST /api/user/register "$(printf '{"name":"Fixture User","email":"%s","username":"%s","password":"%s"}' "$FIXTURE_EMAIL" "$FIXTURE_USERNAME" "$FIXTURE_PASSWORD")")
echo "$regResp" | grep -q '"status":"success"' || { echo "Registration failed: $regResp"; exit 1; }

echo "[2/6] Logging in to get an access token ..."
loginResp=$(api POST /api/user/login "$(printf '{"username":"%s","password":"%s"}' "$FIXTURE_USERNAME" "$FIXTURE_PASSWORD")")
ACCESS_TOKEN=$(extract "$loginResp" "access_token")
[ -n "$ACCESS_TOKEN" ] || { echo "Login failed: $loginResp"; exit 1; }

echo "[3/6] Creating disposable Space (building) ..."
spaceResp=$(api POST /api/auth/mapping/space/add "$(printf '{
  "access_token":"%s","is_published":"true","name":"Fixture Building %s",
  "description":"Disposable Phase 5/6 fixture - not official data",
  "url":"https://example.invalid","address":"Fixture Address",
  "coordinates_lat":"33.5000","coordinates_lon":"32.5000","space_type":"building"
}' "$ACCESS_TOKEN" "$tag")")
FIXTURE_BUID=$(extract "$spaceResp" "buid")
[ -n "$FIXTURE_BUID" ] || { echo "Space creation failed: $spaceResp"; exit 1; }

echo "[4/6] Creating disposable Floor 0 ..."
floorResp=$(api POST /api/auth/mapping/floor/add "$(printf '{
  "access_token":"%s","is_published":"true","buid":"%s",
  "floor_name":"Ground Floor","description":"Fixture floor","floor_number":"0"
}' "$ACCESS_TOKEN" "$FIXTURE_BUID")")
echo "$floorResp" | grep -q '"status":"success"' || { echo "Floor creation failed: $floorResp"; exit 1; }

echo "[5/6] Creating two disposable POIs on Floor 0 ..."
poiAResp=$(api POST /api/auth/mapping/pois/add "$(printf '{
  "access_token":"%s","is_published":"true","buid":"%s","floor_name":"Ground Floor",
  "floor_number":"0","name":"Fixture Entrance","pois_type":"room",
  "is_door":"false","is_building_entrance":"true",
  "coordinates_lat":"33.5001","coordinates_lon":"32.5001"
}' "$ACCESS_TOKEN" "$FIXTURE_BUID")")
FIXTURE_PUID_A=$(extract "$poiAResp" "puid")
[ -n "$FIXTURE_PUID_A" ] || { echo "POI A creation failed: $poiAResp"; exit 1; }

poiBResp=$(api POST /api/auth/mapping/pois/add "$(printf '{
  "access_token":"%s","is_published":"true","buid":"%s","floor_name":"Ground Floor",
  "floor_number":"0","name":"Fixture Office","pois_type":"room",
  "is_door":"false","is_building_entrance":"false",
  "coordinates_lat":"33.5002","coordinates_lon":"32.5002"
}' "$ACCESS_TOKEN" "$FIXTURE_BUID")")
FIXTURE_PUID_B=$(extract "$poiBResp" "puid")
[ -n "$FIXTURE_PUID_B" ] || { echo "POI B creation failed: $poiBResp"; exit 1; }

echo "[6/6] Connecting the two POIs (same-floor edge, for navigation tests) ..."
connResp=$(api POST /api/auth/mapping/connection/add "$(printf '{
  "access_token":"%s","is_published":"true","edge_type":"hallway",
  "buid":"%s","pois_a":"%s","floor_a":"0","buid_a":"%s",
  "pois_b":"%s","floor_b":"0","buid_b":"%s"
}' "$ACCESS_TOKEN" "$FIXTURE_BUID" "$FIXTURE_PUID_A" "$FIXTURE_BUID" "$FIXTURE_PUID_B" "$FIXTURE_BUID")")
echo "$connResp" | grep -q '"status":"success"' || { echo "Connection creation failed: $connResp"; exit 1; }

cat > "$stateFile" <<EOF
FIXTURE_USERNAME=$FIXTURE_USERNAME
FIXTURE_BUID=$FIXTURE_BUID
FIXTURE_PUID_A=$FIXTURE_PUID_A
FIXTURE_PUID_B=$FIXTURE_PUID_B
FIXTURE_ACCESS_TOKEN=$ACCESS_TOKEN
EOF

echo
echo "[✓] Fixture ready."
echo "    buid=$FIXTURE_BUID floor=0 poi_a=$FIXTURE_PUID_A poi_b=$FIXTURE_PUID_B"
echo "    Use FIXTURE_ACCESS_TOKEN from $stateFile to upload a floorplan for"
echo "    this floor (Phase 6) or exercise navigation between poi_a and poi_b."
echo "    Run '$0 --cleanup' when done - this is disposable test data only."
