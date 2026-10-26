# Production Rollout Runbook

This is the controlled rollout procedure for the E-JUST campus deployment. It
assumes the existing Ubuntu VM described in `docs/it-handover/INSTALLATION.md`
and `docs/it-handover/OPERATIONS.md`: native Play service under systemd, Nginx
in front, MongoDB on loopback, and application data under `/opt/anyplace`.

Run every command from the repository root unless a step says otherwise. Use a
maintenance window: the data-hydration path stops the service and briefly makes
the API unavailable.

Read `docs/deploy/PRODUCTION_PREP_5.0.0.md` first for the release state, the
off-campus DNS/TLS findings, and the TLS-mode decision gate.

## 0. Preflight (read-only)

Set the public hostname for this session and run the automated preflight from a
campus-networked workstation:

```bash
export MAP_HOST="ejustgo.ejust.edu.eg"
./scripts/prod-preflight.sh --host "$MAP_HOST" --expected-ip 196.219.57.237 \
  --ssh <deploy-user>@<vm-address> | tee "prod-preflight-$(date +%F).txt"
```

The script is read-only. It verifies DNS, TCP 80/443/22, the TLS certificate,
the public API and web entries, the release tag/artifact, and (with `--ssh`) the
VM state. If it reports a critical failure, stop before changing anything.

Record the current state before changing anything:

```bash
sudo systemctl status anyplace.service --no-pager
curl -fsS http://127.0.0.1:9000/api/version
curl -fsS http://127.0.0.1:9000/api/health
sudo -u anyplace /opt/anyplace/status.sh || true
df -h / /opt /var
free -m
java -version
```

Confirm these deployment inputs:

| Input | Where to check | Expected |
|---|---|---|
| Public DNS | `getent hosts "$MAP_HOST"` | Points at this VM |
| Ports 80/443 | `ss -ltnp \| grep -E ':(80|443)\s'` | Nginx listening |
| Play bind | `ss -ltnp \| grep 9000` | Loopback only |
| MongoDB | `systemctl is-active mongod` or container | Running, loopback only |
| Runtime env | `sudo ls -l /etc/anyplace/anyplace.env` | Mode `0600` |
| Private config | `sudo test -f /opt/anyplace/server/conf/app.private.conf` | Present, untracked |
| JDK | `readlink -f /usr/lib/jvm/java-17-openjdk-amd64` | Exists, or update the unit |
| Disk | `df -h /opt` | At least 20 GB free |

If DNS, port 80 reachability, or the JDK path is not what this runbook expects,
stop and record the difference before proceeding.

## 1. Verified backup (mandatory)

Create a coordinated backup of MongoDB and the filesystem roots. The previous
archive at `/var/backups/anyplace/pre-hardening-2026-10-20-1036.archive.gz` is
empty and must not be used.

```bash
set -a; . /etc/anyplace/anyplace.env; set +a
STAMP="$(date +%Y%m%d-%H%M)"
BK="/var/backups/anyplace/predeploy-$STAMP"
sudo install -d -m 700 "$BK"

sudo mongodump --host 127.0.0.1 --port 27017 \
  --username "$MONGODB_USERNAME" --password "$MONGODB_PASSWORD" \
  --authenticationDatabase admin --db anyplace \
  --archive --gzip > "/tmp/anyplace-$STAMP.archive.gz"
sudo mv "/tmp/anyplace-$STAMP.archive.gz" "$BK/"
sudo mongorestore --host 127.0.0.1 --port 27017 \
  --username "$MONGODB_USERNAME" --password "$MONGODB_PASSWORD" \
  --authenticationDatabase admin --archive --gzip --dryRun \
  < "$BK/anyplace-$STAMP.archive.gz" >/dev/null

sudo tar -C /opt/anyplace -czf "$BK/files-$STAMP.tar.gz" \
  floorplans radiomaps_frozen 2>/dev/null || true
sudo ls -lh "$BK"
```

Verify the archive is not empty and the dry run succeeded before continuing.

## 2. Stage the release

```bash
cd /opt/anyplace
sudo -u anyplace git fetch origin
# v5.0.0-deploy includes the hostname and TLS-mode preparation for this rollout.
sudo -u anyplace git checkout v5.0.0-deploy

sudo -u anyplace ./scripts/build-web-assets.sh
cd server
sudo -u anyplace env JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
  ./sbt clean stage
```

`build-web-assets.sh` builds Architect, Viewer, and Viewer Campus and stages
them under `server/public/`. The build is fail-closed: if any client or required
minified asset is missing, it stops before the backend is staged.

Keep `server/conf/app.private.conf` in place; it is untracked and is not
replaced by `git checkout`. Confirm the public origin and CORS before starting:

```bash
sudo grep -E 'public.baseUrl|server.address|server.port|cors.allowedOrigins' \
  /opt/anyplace/server/conf/app.private.conf
```

For this deployment the browser clients are served same-origin, so the CORS
entry must be exactly `https://$MAP_HOST` (no trailing slash, no `http://`).

## 3. Hydrate the mapping dataset (first rollout or data refresh)

Stop the service before replacing data so no request observes a partial graph:

```bash
sudo systemctl stop anyplace.service
```

Restore the committed snapshot. The script preserves existing users by default,
applies the schema indexes, copies floorplan sources, and verifies counts:

```bash
cd /opt/anyplace
sudo -u anyplace env MDB_MODE=native \
  ./scripts/restore-dataset.sh --db anyplace --tiles
```

If the data must be owned by an existing account, add
`--reassign-owner <owner_id>`. If the tiler is unavailable, omit `--tiles`;
tiles can be regenerated later without touching the graph.

Expected verification output: `8 spaces, 3 floorplans, 228 POIs, 249 edges,
1 campus`. A different count means the wrong archive was used; stop and restore
the backup from step 1.

Do not use `--keep-users` on a shared database: it would re-import the bundled
administrator account from the snapshot.

## 4. Start and smoke-test the service

```bash
sudo systemctl daemon-reload
sudo systemctl start anyplace.service
sudo systemctl status anyplace.service --no-pager
sudo journalctl -u anyplace.service -n 50 --no-pager
```

Local checks (loopback):

```bash
curl -fsS http://127.0.0.1:9000/api/health
curl -fsS http://127.0.0.1:9000/api/version
curl -fsS --compressed -H 'Content-Type: application/json' \
  -d '{}' http://127.0.0.1:9000/api/mapping/space/public | head -c 300
```

Public checks (after TLS is configured):

```bash
curl -fsS "https://$MAP_HOST/api/health"
curl -fsS "https://$MAP_HOST/api/version"
curl -fsSI "https://$MAP_HOST/architect/" | head -5
curl -fsSI "https://$MAP_HOST/viewer/" | head -5
curl -fsSI "https://$MAP_HOST/campus/" | head -5
```

Browser checks:

1. Open `https://$MAP_HOST/architect/`, sign in, and confirm the space list loads.
2. Open a floorplan; it should render once and return quickly when revisited.
3. Open `https://$MAP_HOST/viewer/?buid=<buid>` and switch floors rapidly; the
   correct floorplan must stay visible.
4. Use the Architect Restore tab with a backup ZIP on a disposable space and
   confirm POIs, connectors, and floorplans return.
5. Confirm `/api/floorplans64/<buid>/<floor>` returns `Content-Type: text/plain`
   with `Content-Encoding: gzip` (not `application/octet-stream`).

## 5. TLS and Nginx

First decide who terminates TLS. The off-campus probe sees the university
wildcard certificate (`CN=*.ejust.edu.eg`, Sectigo), which suggests a campus
gateway, but confirm the forwarding path with IT before installing a vhost.

**Mode A - university gateway terminates TLS (likely):**

```bash
# Replace the set_real_ip_from placeholder with the gateway address from IT.
sudo cp docs/deploy/nginx-anyplace-gateway.conf \
  /etc/nginx/sites-available/anyplace
sudo ln -sfn /etc/nginx/sites-available/anyplace \
  /etc/nginx/sites-enabled/anyplace
sudo nginx -t && sudo systemctl reload nginx
```

Do not run certbot on the VM in this mode. Do not redirect HTTP to HTTPS; the
gateway already provides HTTPS and a redirect would loop. Confirm the gateway
preserves `Host` and sends `X-Forwarded-Proto: https`.

**Mode B - the VM terminates TLS:**

```bash
sudo cp docs/deploy/nginx-anyplace-bootstrap.conf \
  /etc/nginx/sites-available/anyplace
sudo ln -sfn /etc/nginx/sites-available/anyplace \
  /etc/nginx/sites-enabled/anyplace
sudo nginx -t && sudo systemctl reload nginx

sudo certbot certonly --webroot -w /var/www/html -d "$MAP_HOST"

sudo cp docs/deploy/nginx-anyplace-campus.conf \
  /etc/nginx/sites-available/anyplace
sudo nginx -t && sudo systemctl reload nginx
sudo certbot renew --dry-run
```

If public port 80 is not reachable, use the DNS-01 challenge instead of
`--webroot` and record that change in the handover notes.

Both modes must keep `/api/` and the three web apps on the same origin; the
clients call `/api` relatively. Verify that `X-Forwarded-Proto` reaches Play so
generated links use `https`.

## 6. Backups and monitoring

Install or refresh the nightly backup units:

```bash
sudo cp docs/deploy/anyplace-backup.service /etc/systemd/system/
sudo cp docs/deploy/anyplace-backup.timer   /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now anyplace-backup.timer
systemctl list-timers anyplace-backup.timer
```

Confirm `/etc/anyplace/backup.env` exists with mode `0600`, a real
`BACKUP_DIR`, and an off-host target if one is available. Run one backup by hand
and verify the manifest counts are non-zero.

## 7. Rollback

If smoke tests fail:

```bash
sudo systemctl stop anyplace.service
cd /opt/anyplace
sudo -u anyplace git checkout <previous-commit>
sudo -u anyplace ./scripts/build-web-assets.sh
cd server && sudo -u anyplace env JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
  ./sbt clean stage
sudo systemctl start anyplace.service
```

If the data changed, restore the step-1 archive with `mongorestore --drop` and
untar the filesystem backup into `/opt/anyplace`. Re-run the local smoke checks
before reopening the service to users.

## 8. Post-rollout record

Record in the handover log:

- release commit and build time;
- backup path and verified document counts;
- public hostname and certificate expiry;
- smoke-test results, including the floorplan content type;
- any deviation from this runbook (DNS-01, skipped tiling, JDK path);
- remaining deferred items: `APPLICATION_SECRET` rotation, MongoDB password
  rotation, and Android endpoint update.
