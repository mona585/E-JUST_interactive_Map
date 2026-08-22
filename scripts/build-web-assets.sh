#!/usr/bin/env bash
# Build the three browser clients and stage only the runtime assets Play serves.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$ROOT_DIR/clients/web"
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
        bower install --allow-root
        npx --no-install grunt deploy
        test -f build/js/anyplace.min.js
        test -f build/css/anyplace.min.css
    )

    rm -rf "$target_dir"
    mkdir -p "$target_dir"
    (
        cd "$app_dir"
        # WebAppController/Assets serve the whole app tree (index.html, libs,
        # controllers, images, build/, bower_components/), so stage everything
        # except development-only dependencies.
        tar --exclude=node_modules --exclude=.git -cf - . | tar -xf - -C "$target_dir"
        test -f "$target_dir/index.html"
    )
done

printf 'Web assets staged in %s\n' "$SERVER_PUBLIC"
