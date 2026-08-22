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

## Execution status

**Executed successfully on the Ubuntu 22.04 staging VM on 2026-08-22**
(`Ahmed-branch`): all three Grunt apps built fail-closed on Node 22, assets
staged into `server/public` and copied into the staged distribution per the
installer model, and after a service restart every probe returned HTTP 200:
`/developers/`, `/assets/swagger.json`, `/architect/`, `/viewer/`. Swagger is
served same-origin.

Two fixes were required (commit `3d82a416`):

- The builder now stages the complete app tree minus `node_modules`
  (`WebAppController.serveFile` needs `index.html`, `libs/`, `controllers/`,
  images — not only `build/` and `bower_components/`) plus the static
  `developers` app.
- `anyplace.service` exports
  `--add-exports=java.base/sun.net.www.protocol.file=ALL-UNNAMED`; without it
  Play's Assets controller fails on JDK 17 with `IllegalAccessError`.

The accompanying PowerShell contract check remains source-only:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/Test-WebAssetContract.ps1
```
