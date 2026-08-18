#!/bin/bash
#
# Phase 6 end-to-end floorplan/tiler verification.
#
# Exercises the full documented path:
#   Architect/API upload -> MapFloorplanController.uploadWithZoom
#   -> MongoDB `floorplans` metadata -> filesystem -> tiler
#   -> generated tiles/archive -> backend retrieval (base64 / static tiles / zip)
#
# Requires:
#   - the Play server running and reachable at API_BASE_URL
#   - a fixture Space/Floor already created: run create_fixture.sh first
#   - the native tiler toolchain on THIS host (bash, python3, ImageMagick
#     `convert`/`identify`, `advpng`, `zip`) - this is the Ubuntu/Linux
#     target from D-01, not the Windows development machine. On a host
#     missing these tools this script fails at the tiling step and that is
#     the correct, expected result: tiling is a Linux-only dependency.
set -euo pipefail

cwd="$(dirname "$0")"
source "$cwd/config.sh"
stateFile="$cwd/fixture_state.env"
[ -f "$stateFile" ] || { echo "Run create_fixture.sh first."; exit 1; }
# shellcheck disable=SC1090
source "$stateFile"

api() { curl -sS "$@"; }

# A minimal valid 1x1 PNG, so this script needs no local image tooling.
testImage="$cwd/.fixture_test_image.png"
base64 -d > "$testImage" <<'PNGB64'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YA
AAAASUVORK5CYII=
PNGB64

echo "[1/4] Uploading fixture floorplan (buid=$FIXTURE_BUID floor=0) ..."
jsonPart=$(printf '{"buid":"%s","floor_number":"0","bottom_left_lat":"33.4999","bottom_left_lng":"32.4999","top_right_lat":"33.5003","top_right_lng":"32.5003","zoom":"19"}' "$FIXTURE_BUID")
uploadResp=$(api -X POST "$API_BASE_URL/api/mapping/floor/floorplan/upload" \
  -F "floorplan=@$testImage;type=image/png" \
  -F "json=$jsonPart")
echo "    response: $uploadResp"
echo "$uploadResp" | grep -qi "uploaded floorplan" || { echo "[FAIL] Upload did not report success."; exit 1; }

echo "[2/4] Verifying MongoDB floorplans metadata was updated ..."
mongosh --host "$MDB_HOST" --port "$MDB_PORT" --authenticationDatabase admin \
  --username "$MDB_USER" --password "$MDB_PASS" --quiet "$MDB_DATABASE" --eval "
    printjson(db.floorplans.findOne({buid: '$FIXTURE_BUID', floor_number: '0'}, {zoom:1, top_right_lat:1, bottom_left_lat:1}))
  "

echo "[3/4] Waiting for the native tiler to finish, then checking generated tiles ..."
zipLinkResp=$(api -X POST "$API_BASE_URL/api/floortiles/$FIXTURE_BUID/0" -H 'Content-Type: application/json' -d '{}')
echo "    zip link response: $zipLinkResp"
tilesArchive=$(echo "$zipLinkResp" | grep -o '"tiles_archive":"[^"]*"' | cut -d'"' -f4)
[ -n "$tilesArchive" ] || { echo "[FAIL] No tiles_archive link returned - tiling likely failed. Check anyplace_tiler_*.log next to the uploaded image."; exit 1; }
echo "    tiles_archive: $tilesArchive"
echo "$tilesArchive" | grep -q '/api/floortiles/' || { echo "[FAIL] Link does not use the live /api/floortiles route (R-10 regression)."; exit 1; }
echo "$tilesArchive" | grep -q '\\' && { echo "[FAIL] Link contains a backslash - OS path separator leaked into a URL (R-10 regression)."; exit 1; }

echo "[4/4] Downloading the generated archive through the actual HTTP route ..."
httpStatus=$(api -s -o /dev/null -w '%{http_code}' "$tilesArchive")
[ "$httpStatus" = "200" ] || { echo "[FAIL] GET $tilesArchive returned HTTP $httpStatus."; exit 1; }

rm -f "$testImage"
echo
echo "[✓] Floorplan pipeline verified end to end: upload -> metadata -> filesystem -> tiler -> retrieval."
