#!/usr/bin/env bash
# Build the three browser clients and stage only the runtime assets Play serves.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/clients/web"
SERVER_PUBLIC="$ROOT_DIR/server/public"
APPS=(anyplace_architect anyplace_viewer anyplace_viewer_campus)

for app in "${APPS[@]}"; do
    app_dir="$WEB_DIR/$app"
    target_dir="$SERVER_PUBLIC/$app"

    printf 'Building %s\n' "$app"
    (
        cd "$app_dir"
        npm ci --no-audit --no-fund
        bower install --allow-root
        npx --no-install grunt deploy
        test -f build/js/anyplace.min.js
        test -f build/css/anyplace.min.css
    )

    mkdir -p "$target_dir"
    rm -rf "$target_dir/build" "$target_dir/bower_components"
    cp -R "$app_dir/build" "$app_dir/bower_components" "$target_dir/"
done

printf 'Web assets staged in %s\n' "$SERVER_PUBLIC"
