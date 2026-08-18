#!/bin/bash
#
# Controlled private Administrator bootstrap (R-14 / D-05 / Phase 5).
#
# The backend has no admin-provisioning hook of its own: the FIRST caller of
# the public POST /api/user/register endpoint is automatically made
# Administrator (MongodbDatasource.isFirstUser / UserController.register).
# On an empty database that means whoever reaches the API first - not
# necessarily the operator - becomes Administrator.
#
# This script closes that gap by performing the first registration itself,
# over loopback only, BEFORE the host's firewall/reverse-proxy is opened to
# the public network. It then verifies the result directly against MongoDB
# (not just the API response), and separately proves that a second
# registration receives the ordinary "user" role. Only after both checks
# pass is it safe to open public ingress.
#
# Usage:
#   cp config.example.sh config.sh   # once, then edit
#   ADMIN_NAME="..." ADMIN_EMAIL="..." ADMIN_USERNAME="..." \
#     ADMIN_PASSWORD="..." ./bootstrap_admin.sh
#
# Credentials are read from environment variables (or an interactive
# password prompt), never from argv, so they don't leak through the process
# list or shell history.
set -euo pipefail

cwd="$(dirname "$0")"
source "$cwd/config.sh"

MONGOSH_AUTH=(--host "$MDB_HOST" --port "$MDB_PORT" \
  --authenticationDatabase admin --username "$MDB_USER" --password "$MDB_PASS" \
  --quiet "$MDB_DATABASE")

fail() {
  echo "[BOOTSTRAP FAILED] $1" >&2
  exit 1
}

# --- Safety: only ever bootstrap over loopback -----------------------------
case "$API_BASE_URL" in
  http://127.0.0.1*|http://localhost*|https://127.0.0.1*|https://localhost*) ;;
  *) fail "API_BASE_URL ($API_BASE_URL) is not loopback. Bootstrap must run on \
the application host itself, before public ingress is opened, or an \
external caller could still win the race for Administrator." ;;
esac

# --- Fail closed if any user already exists ---------------------------------
existingUsers=$(mongosh "${MONGOSH_AUTH[@]}" --eval 'db.users.countDocuments({})' | tail -n1)
if [ "$existingUsers" != "0" ]; then
  fail "users collection already has $existingUsers document(s). This script \
only bootstraps a truly empty database; it will not silently create a second \
admin or run against a partially-seeded one."
fi

: "${ADMIN_NAME:?Set ADMIN_NAME}"
: "${ADMIN_EMAIL:?Set ADMIN_EMAIL}"
: "${ADMIN_USERNAME:?Set ADMIN_USERNAME}"
if [ -z "${ADMIN_PASSWORD:-}" ]; then
  read -r -s -p "ADMIN_PASSWORD: " ADMIN_PASSWORD
  echo
fi
[ -n "$ADMIN_PASSWORD" ] || fail "ADMIN_PASSWORD must not be empty."

echo "[1/4] Registering the initial Administrator over loopback ($API_BASE_URL) ..."
adminPayload=$(printf '{"name":"%s","email":"%s","username":"%s","password":"%s"}' \
  "$ADMIN_NAME" "$ADMIN_EMAIL" "$ADMIN_USERNAME" "$ADMIN_PASSWORD")
adminResp=$(curl -sS -X POST "$API_BASE_URL/api/user/register" \
  -H 'Content-Type: application/json' -d "$adminPayload")
unset ADMIN_PASSWORD adminPayload

adminType=$(echo "$adminResp" | grep -o '"type":"[^"]*"' | head -n1 | cut -d'"' -f4)
[ "$adminType" = "admin" ] || fail "API response did not report type=admin (got: ${adminType:-<none>}). Response: $adminResp"

echo "[2/4] Verifying the Administrator directly in MongoDB (not trusting the API alone) ..."
dbCheck=$(mongosh "${MONGOSH_AUTH[@]}" --eval \
  "JSON.stringify({count: db.users.countDocuments({}), type: (db.users.findOne({username:\"$ADMIN_USERNAME\"}) || {}).type})" \
  | tail -n1)
echo "    users collection: $dbCheck"
echo "$dbCheck" | grep -q '"count":1' || fail "Expected exactly 1 user document after bootstrap; got: $dbCheck"
echo "$dbCheck" | grep -q '"type":"admin"' || fail "Stored user document is not type=admin; got: $dbCheck"

echo "[3/4] Proving a SECOND registration receives the ordinary 'user' role (disposable check) ..."
verifyTag=$(date +%s)
verifyUser="bootstrap_verify_${verifyTag}"
verifyPayload=$(printf '{"name":"Bootstrap Verify","email":"%s@example.invalid","username":"%s","password":"TemporaryVerify123!"}' \
  "$verifyUser" "$verifyUser")
verifyResp=$(curl -sS -X POST "$API_BASE_URL/api/user/register" \
  -H 'Content-Type: application/json' -d "$verifyPayload")
verifyType=$(echo "$verifyResp" | grep -o '"type":"[^"]*"' | head -n1 | cut -d'"' -f4)

# Clean up the disposable verification account regardless of outcome - it is
# throwaway test data, never real production content (recovery-plan rule).
mongosh "${MONGOSH_AUTH[@]}" --eval "db.users.deleteOne({username:\"$verifyUser\"})" >/dev/null

[ "$verifyType" = "user" ] || fail "Second registrant received type='${verifyType:-<none>}' instead of 'user'. \
Do NOT open public ingress: an attacker registering before the real second \
user would otherwise also be able to claim Administrator. Response: $verifyResp"

echo "[4/4] Bootstrap verified."
echo
echo "    Administrator : $ADMIN_USERNAME <$ADMIN_EMAIL> (type=admin, sole user in the database)"
echo "    Second-user policy verified: subsequent registrants receive type=user."
echo
echo "It is now safe to open public ingress (firewall/reverse proxy) to the"
echo "registration endpoint. Running this script again will fail closed,"
echo "since the users collection is no longer empty."
