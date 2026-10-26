#!/usr/bin/env bash
# Read-only pre-rollout checks for the E-JUST Anyplace deployment.
#
# Usage:
#   scripts/prod-preflight.sh [--host ejustgo.ejust.edu.eg] [--expected-ip 196.219.57.237]
#                             [--ssh user@vm] [--skip-tls]
#
# Runs from a workstation on the campus network. With --ssh it also prints a
# read-only state snapshot from the VM (key-based auth only, no passwords).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

HOST="${MAP_HOST:-ejustgo.ejust.edu.eg}"
EXPECTED_IP="${EXPECTED_IP:-}"
SSH_TARGET="${SSH_TARGET:-}"
SKIP_TLS=0
FAILS=0

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
info() { printf '[INFO] %s\n' "$*"; }
section() { printf '\n== %s ==\n' "$*"; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="${2:?}"; shift 2 ;;
    --expected-ip) EXPECTED_IP="${2:?}"; shift 2 ;;
    --ssh) SSH_TARGET="${2:?}"; shift 2 ;;
    --skip-tls) SKIP_TLS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

section "release checkout"
if [ "$(git -C "$REPO_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
  pass "git checkout: $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  if git -C "$REPO_ROOT" rev-parse -q --verify refs/tags/v5.0.0 >/dev/null; then
    if git -C "$REPO_ROOT" merge-base --is-ancestor refs/tags/v5.0.0 HEAD; then
      pass "tag v5.0.0 exists and is an ancestor of HEAD"
    else
      fail "HEAD does not include tag v5.0.0"
    fi
  else
    fail "tag v5.0.0 is missing"
  fi
  if git -C "$REPO_ROOT" rev-parse -q --verify refs/tags/v5.0.0-deploy.1 >/dev/null; then
    pass "deployment tag v5.0.0-deploy.1 exists"
  else
    warn "deployment tag v5.0.0-deploy.1 is missing"
  fi
  DIRTY="$(git -C "$REPO_ROOT" status --porcelain | head -5)"
  if [ -n "$DIRTY" ]; then warn "working tree has local changes:"; printf '%s\n' "$DIRTY"; else pass "working tree is clean"; fi
else
  fail "$REPO_ROOT is not a git checkout"
fi

ARTIFACT="$REPO_ROOT/server/target/universal/anyplace-5.0.0.zip"
if [ -f "$ARTIFACT" ]; then
  pass "artifact: $ARTIFACT"
  info "sha256: $(sha256sum "$ARTIFACT" | awk '{print $1}')"
else
  warn "artifact missing; run: cd server && sbt dist"
fi

section "DNS"
IPS="$(getent ahostsv4 "$HOST" 2>/dev/null | awk '{print $1}' | sort -u)"
if [ -z "$IPS" ]; then
  fail "$HOST does not resolve"
else
  pass "$HOST -> $(printf '%s ' $IPS)"
  if [ -n "$EXPECTED_IP" ]; then
    if printf '%s\n' "$IPS" | grep -qx "$EXPECTED_IP"; then
      pass "resolved address matches expected $EXPECTED_IP"
    else
      fail "resolved address does not match expected $EXPECTED_IP"
    fi
  fi
fi
if command -v dig >/dev/null 2>&1; then
  AAAA="$(dig +short AAAA "$HOST" 2>/dev/null | sort -u)"
else
  AAAA="$(getent ahostsv6 "$HOST" 2>/dev/null | awk '{print $1}' | grep -v '^::ffff:' | sort -u)"
fi
[ -n "$AAAA" ] && warn "AAAA present ($AAAA); confirm IPv6 path or publish A-only"

section "TCP reachability"
for port in 80 443 22; do
  if timeout 4 bash -c "cat < /dev/null > /dev/tcp/$HOST/$port" >/dev/null 2>&1; then
    pass "tcp/$port reachable"
  else
    case "$port" in
      80) warn "tcp/80 blocked or filtered (HTTP-01 impossible; use DNS-01)" ;;
      443) fail "tcp/443 blocked or filtered" ;;
      22) warn "tcp/22 blocked or filtered (use the campus VPN or a jump host)" ;;
    esac
  fi
done

http_code() {
  local url="$1"; shift
  curl -sS -o /dev/null --connect-timeout 4 --max-time 8 -w '%{http_code}' "$@" "$url" 2>/dev/null || true
}

section "HTTP and HTTPS"
HTTP_CODE="$(http_code "http://$HOST/")"
[ -n "$HTTP_CODE" ] || HTTP_CODE=000
case "$HTTP_CODE" in
  2*|3*) pass "http://$HOST/ -> $HTTP_CODE" ;;
  000) warn "http://$HOST/ did not answer" ;;
  *) fail "http://$HOST/ -> $HTTP_CODE" ;;
esac

HTTPS_CODE="$(http_code "https://$HOST/")"
[ -n "$HTTPS_CODE" ] || HTTPS_CODE=000
HTTPS_VERIFIED_CODE="$HTTPS_CODE"
if [ "$HTTPS_CODE" = "000" ]; then
  HTTPS_INSECURE_CODE="$(http_code "https://$HOST/" -k)"
  [ -n "$HTTPS_INSECURE_CODE" ] || HTTPS_INSECURE_CODE=000
  if [ "$HTTPS_INSECURE_CODE" = "000" ]; then
    fail "https://$HOST/ did not answer (with or without certificate verification)"
  else
    warn "https://$HOST/ answers ($HTTPS_INSECURE_CODE) only with -k; certificate chain is incomplete"
    HTTPS_CODE="$HTTPS_INSECURE_CODE"
  fi
else
  pass "https://$HOST/ -> $HTTPS_CODE"
fi

if [ "$SKIP_TLS" -eq 0 ] && timeout 4 bash -c "cat < /dev/null > /dev/tcp/$HOST/443" >/dev/null 2>&1; then
  section "TLS certificate"
  CERT="$(timeout 10 openssl s_client -connect "$HOST:443" -servername "$HOST" -showcerts </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates 2>/dev/null)"
  if [ -n "$CERT" ]; then
    printf '%s\n' "$CERT"
    if timeout 10 openssl s_client -connect "$HOST:443" -servername "$HOST" -verify_hostname "$HOST" -verify_return_error </dev/null >/dev/null 2>&1; then
      pass "certificate chain and hostname verify"
    else
      warn "certificate chain or hostname does not verify; browsers may reject it"
    fi
  else
    fail "could not read a certificate from $HOST:443"
  fi
fi

if [ "$HTTPS_CODE" != "000" ]; then
  section "public API and web entry points"
  CURL_TLS=()
  if [ "$HTTPS_VERIFIED_CODE" = "000" ]; then CURL_TLS=(-k); fi
  VERSION_BODY="$(curl -fsS --max-time 8 "${CURL_TLS[@]}" "https://$HOST/api/version" 2>/dev/null || true)"
  if [ -n "$VERSION_BODY" ]; then
    pass "api/version: $VERSION_BODY"
    printf '%s' "$VERSION_BODY" | grep -q '"5\.0\.0"' && pass "reported version is 5.0.0" || warn "reported version is not 5.0.0"
  else
    fail "api/version did not return JSON"
  fi
  curl -fsS --max-time 8 "${CURL_TLS[@]}" "https://$HOST/api/health" >/dev/null 2>&1 \
    && pass "api/health" || fail "api/health"
  for path in /architect/ /viewer/ /campus/ /developers/; do
    code="$(http_code "https://$HOST$path" "${CURL_TLS[@]}")"
    [ -n "$code" ] || code=000
    case "$code" in
      2*|3*) pass "$path -> $code" ;;
      *) fail "$path -> $code" ;;
    esac
  done
else
  warn "skipping public API checks because HTTPS did not answer"
fi

if [ -n "$SSH_TARGET" ]; then
  section "remote state: $SSH_TARGET"
  if ssh -o BatchMode=yes -o ConnectTimeout=6 "$SSH_TARGET" true >/dev/null 2>&1; then
    pass "SSH key authentication works"
    ssh -o BatchMode=yes -o ConnectTimeout=6 "$SSH_TARGET" 'bash -s' < "$SCRIPT_DIR/prod-state.sh"
  else
    fail "SSH failed; confirm host, user, key, and campus network/VPN"
  fi
fi

section "summary"
if [ "$FAILS" -eq 0 ]; then
  pass "preflight completed with no failures"
  exit 0
fi
fail "$FAILS critical check(s) failed"
exit 1
