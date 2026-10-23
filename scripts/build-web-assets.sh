#!/usr/bin/env bash
# Build the three browser clients and stage only the runtime assets Play serves.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/clients/web"

# The campus client pins Grunt 0.4 plugins that call util.isRegExp, removed in
# Node.js v23. Preload a tiny shim so the pinned toolchain builds on current
# Node releases without changing dependency versions.
NODE_SHIM="$ROOT_DIR/scripts/node-legacy-shim.js"
if [ -f "$NODE_SHIM" ]; then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--require $NODE_SHIM"
fi
SERVER_PUBLIC="$ROOT_DIR/server/public"
APPS=(anyplace_architect anyplace_viewer anyplace_viewer_campus)
STATIC_APPS=(developers)

for app in "${STATIC_APPS[@]}"; do
    app_dir="$WEB_DIR/$app"
    target_dir="$SERVER_PUBLIC/$app"
    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    (
        cd "$app_dir"
        tar --exclude=node_modules --exclude=.git -cf - . | tar -xf - -C "$target_dir"
        test -f "$target_dir/index.html"
    )
done

for app in "${APPS[@]}"; do
    app_dir="$WEB_DIR/$app"
    target_dir="$SERVER_PUBLIC/$app"

    printf 'Building %s\n' "$app"
    (
        cd "$app_dir"
        npm ci --no-audit --no-fund
        if [ -x node_modules/.bin/bower ]; then
            ./node_modules/.bin/bower install --allow-root
        else
            npx --yes bower install --allow-root
        fi
        if [ -x node_modules/.bin/grunt ]; then
            npx --no-install grunt deploy
        else
            npx --yes grunt-cli deploy
        fi
        test -f build/js/anyplace.min.js
        test -f build/css/anyplace.min.css
    )

    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    (
        cd "$app_dir"
        # Stage full app tree (Assets serves it); exclude dev-only dependencies.
        tar --exclude=node_modules --exclude=.git -cf - . | tar -xf - -C "$target_dir"
        test -f "$target_dir/index.html"
    )
done

# Stage shared favicon (no app tree provides it; /favicon.ico route needs it).
mkdir -p "$SERVER_PUBLIC/images"
cp -f "$WEB_DIR/shared/images/favicon.png" "$SERVER_PUBLIC/images/favicon.png"
test -f "$SERVER_PUBLIC/images/favicon.png"

printf 'Web assets staged in %s\n' "$SERVER_PUBLIC"
