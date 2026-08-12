#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_ANDROID=false

if [[ "${1:-}" == "--with-android" ]]; then
  WITH_ANDROID=true
elif [[ $# -ne 0 ]]; then
  echo "Usage: $0 [--with-android]" >&2
  exit 2
fi

missing=0
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "MISSING: $1" >&2
    missing=1
  fi
}

if [[ ! -r /etc/os-release ]]; then
  echo "MISSING: /etc/os-release" >&2
  exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "22.04" ]]; then
  echo "FAIL: expected Ubuntu 22.04 LTS; found ${PRETTY_NAME:-unknown}" >&2
  exit 1
fi

for tool in java python3 node npm grunt bower convert identify advpng git; do
  check_command "$tool"
done
[[ $missing -eq 0 ]] || exit 1

java_version="$(java -version 2>&1 | head -n 1)"
python_version="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
npm_major="$(npm --version | cut -d. -f1)"

[[ "$java_version" =~ 17\. ]] || { echo "FAIL: OpenJDK 17 is required; found $java_version" >&2; exit 1; }
[[ "$python_version" =~ ^3\.(1[0-9]|[2-9][0-9])$ ]] || { echo "FAIL: Python 3.10+ is required; found $python_version" >&2; exit 1; }
[[ "$node_major" == "22" ]] || { echo "FAIL: Node.js 22 is required; found $(node --version)" >&2; exit 1; }
[[ "$npm_major" == "10" ]] || { echo "FAIL: npm 10 is required; found $(npm --version)" >&2; exit 1; }

grep -qx 'sbt.version=1.5.8' "$ROOT_DIR/server/project/build.properties" || { echo "FAIL: unexpected SBT version" >&2; exit 1; }
grep -q 'scalaVersion := "2.13.6"' "$ROOT_DIR/server/build.sbt" || { echo "FAIL: unexpected Scala version" >&2; exit 1; }
grep -q '"com.typesafe.play" %% "play" % "2.8.8"' "$ROOT_DIR/server/build.sbt" || { echo "FAIL: unexpected Play version" >&2; exit 1; }

for app in anyplace_architect anyplace_viewer anyplace_viewer_campus; do
  [[ -f "$ROOT_DIR/clients/web/$app/package-lock.json" ]] || { echo "FAIL: missing npm lockfile for $app" >&2; exit 1; }
done

grep -q 'gradle-7.2-bin.zip' "$ROOT_DIR/clients/android-new/gradle/wrapper/gradle-wrapper.properties" || { echo "FAIL: unexpected Android Gradle wrapper" >&2; exit 1; }

if [[ "$WITH_ANDROID" == true ]]; then
  : "${ANDROID_SDK_ROOT:?FAIL: set ANDROID_SDK_ROOT before Android preflight}"
  [[ -d "$ANDROID_SDK_ROOT/platforms/android-31" ]] || { echo "FAIL: Android platform 31 is missing" >&2; exit 1; }
  [[ -d "$ANDROID_SDK_ROOT/build-tools/30.0.3" ]] || { echo "FAIL: Android Build-Tools 30.0.3 is missing" >&2; exit 1; }
  [[ -f "$ROOT_DIR/clients/android-new/lib-android/build.gradle" ]] || { echo "FAIL: Android lib-android submodule is not initialized" >&2; exit 1; }
  [[ -f "$ROOT_DIR/clients/core/lib/build.gradle" ]] || { echo "FAIL: core library submodule is not initialized" >&2; exit 1; }
fi

echo "PASS: Ubuntu 22.04 toolchain contract is satisfied."
