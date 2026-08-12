# Phase 4: Web Assets and Developer API Runbook

This runbook is for the Ubuntu 22.04 staging host only. Do not run it on the
Windows investigation workstation.

## Build and stage browser assets

From the checked-out application directory, with the Phase 1 toolchain
installed, run:

```bash
bash scripts/build-web-assets.sh
cd server && ./sbt stage
```

The helper uses each app's `package-lock.json`, restores its Bower dependencies,
runs `grunt deploy`, and stages only `build/` and `bower_components/` under
`server/public/`. It stops on a failed install or missing minified CSS/JS; do
not bypass failures with `|| true`.

## Verify after the controlled Phase 2 service start

With the private staging service running on loopback, verify these endpoints
through the intended reverse proxy or a local SSH tunnel:

```bash
curl -fsS http://127.0.0.1:9000/developers/ -o /dev/null
curl -fsS http://127.0.0.1:9000/assets/swagger.json -o /dev/null
curl -fsS http://127.0.0.1:9000/architect/ -o /dev/null
curl -fsS http://127.0.0.1:9000/viewer/ -o /dev/null
```

Open `/developers/` in a browser and confirm Swagger loads from the same
origin. Then use the browser console/network panel to confirm the documented
specification is `/assets/swagger.json`, not a legacy UCY host. Record the
HTTP status, asset failures, and browser version in the staging evidence.

## Current limitation

No browser build or HTTP probe has been run in this phase. These commands
remain pending until the Ubuntu host and the Phase 2 MongoDB/service runbook
are available. The accompanying PowerShell contract check is source-only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-WebAssetContract.ps1
```
