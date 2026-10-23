# Installation and Deployment

This guide describes the supported deployment: a native Play service managed by
systemd on Ubuntu 22.04 LTS, with Nginx in front and MongoDB on loopback.

For the exact commands used on the current production VM, including TLS
issuance, see `docs/RUN_SERVER_REMOTE.md` and the configuration files in
`docs/deploy/`.

## 1. Prerequisites

### 1.1 Host

- Ubuntu 22.04 LTS x86_64.
- 8 vCPUs and 16 GB RAM minimum; 32 GB recommended for the planning target of
  1,000 concurrent users.
- At least 100 GB of disk for the OS, application, database, floorplans, tiles,
  and backups. The current production host must be checked before bulk imports.
- Static private IP reachable by the campus reverse proxy or directly by clients.

### 1.2 Packages

```bash
sudo apt-get update
sudo apt-get install -y \
  curl ca-certificates gnupg wget rsync git zip unzip openssl \
  python3 python3-pip imagemagick advancecomp \
  openjdk-17-jdk-headless build-essential nginx
```

The systemd unit pins `/usr/lib/jvm/java-17-openjdk-amd64`. If the host uses a
different JDK, update `JAVA_HOME` in the unit and re-run `systemctl daemon-reload`.
JDK 11 is also validated by CI, but do not mix JDKs between build and runtime
without re-testing.

Node.js and npm are required only when rebuilding the web clients. The deployed
`server/public/` assets are sufficient for a backend-only upgrade.

### 1.3 MongoDB

MongoDB 6.0 must be installed and running on `127.0.0.1:27017` with
authentication enabled. The application does not create or expose a database
container in the supported deployment.

Create a least-privilege application user:

```javascript
// mongosh admin
db.createUser({
  user: "anyplace_app",
  pwd: "<generated-strong-password>",
  roles: [{ role: "readWrite", db: "anyplace" }]
});
```

Enable authorization in `/etc/mongod.conf` and bind only to loopback:

```yaml
net:
  bindIp: 127.0.0.1
  port: 27017
security:
  authorization: enabled
```

Restart MongoDB, then verify:

```bash
mongosh -u anyplace_app -p '<password>' --authenticationDatabase admin anyplace \
  --eval 'db.runCommand({ping:1})'
```

### 1.4 DNS and firewall

- DNS record for the public hostname (for example `ejustgo.ejust.edu.eg`).
- Inbound `80/tcp` for ACME and HTTP-to-HTTPS redirect.
- Inbound `443/tcp` for clients.
- Inbound `22/tcp` for administration.
- `9000/tcp` and `27017/tcp` must not be publicly reachable.

## 2. Filesystem layout

```text
/opt/anyplace                 application root and working directory
/opt/anyplace/server          Play project and staged distribution
/opt/anyplace/floorplans      floorplan sources and generated tiles
/opt/anyplace/radiomaps_frozen
/etc/anyplace/anyplace.env    runtime secrets and MongoDB connection (0600 root)
/etc/anyplace/backup/config.sh backup configuration (0600 root)
/var/backups/anyplace         verified backup archives
```

Create the service account and directories:

```bash
sudo useradd --system --home /opt/anyplace --shell /usr/sbin/nologin anyplace
sudo mkdir -p /opt/anyplace /etc/anyplace /var/backups/anyplace
sudo chown -R anyplace:anyplace /opt/anyplace
sudo chown -R root:root /etc/anyplace
sudo chmod 700 /etc/anyplace
```

## 3. Fetch the code

```bash
sudo -u anyplace git clone git@github.com:mona585/E-JUST_interactive_Map.git /opt/anyplace
cd /opt/anyplace
```

If the host uses a deploy key, install it under the service account or root
according to IT policy. Never commit the key.

## 4. Configure secrets

Create `/etc/anyplace/anyplace.env` with mode `0600`, owned by `root`:

```bash
sudo install -m 600 /dev/null /etc/anyplace/anyplace.env
sudo editor /etc/anyplace/anyplace.env
```

Required contents:

```dotenv
APPLICATION_SECRET=<long-random-value>
MONGODB_HOST=127.0.0.1
MONGODB_PORT=27017
MONGODB_DATABASE=anyplace
MONGODB_USERNAME=anyplace_app
MONGODB_PASSWORD=<same-password-as-the-database-user>
PUBLIC_BASE_URL=https://<public-host>
GOOGLE_CLIENT_ID=<client-id-or-empty>
```

Generate the application secret with:

```bash
openssl rand -base64 48
```

Then create `server/conf/app.private.conf` from the example and set:

- `public.baseUrl` to the public HTTPS origin.
- `server.address` to the same value.
- `application.secret` and `play.http.secret.key` to the same random secret.
- `password.salt` and `password.pepper` to long random values. Changing these
  invalidates legacy password hashes; PBKDF2 hashes remain valid.
- `cors.allowedOrigins` to `["https://<public-host>"]`.
- `google.client.id` if Google login is offered.

The `install.sh` script can generate these values, but it requires
`PUBLIC_BASE_URL` and it does not update CORS, so verify CORS manually.

## 5. Build

```bash
cd /opt/anyplace/server
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
./sbt clean stage
```

The staged distribution is written to
`server/target/universal/stage/`. The executable is
`server/target/universal/stage/bin/anyplace`.

For a repeatable build matching CI, use JDK 11:

```bash
JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 ./sbt test
```

## 6. Install the service

```bash
sudo cp /opt/anyplace/anyplace.service /etc/systemd/system/anyplace.service
sudo systemctl daemon-reload
sudo systemctl enable --now anyplace.service
sudo systemctl status anyplace.service
```

The unit:

- runs as `anyplace:anyplace` from `/opt/anyplace`;
- loads `/etc/anyplace/anyplace.env`;
- removes a stale `RUNNING_PID` before start;
- runs `bin/anyplace` on `127.0.0.1:9000` with the PID file disabled;
- restarts always, with a five-failure start limit per minute;
- sets the JVM `--add-opens` and `--add-exports` flags required by Play and the
  Guice/cglib stack on modern JDKs.

Verify locally:

```bash
curl -fsS http://127.0.0.1:9000/api/health
curl -fsS http://127.0.0.1:9000/api/version
```

## 7. Nginx and TLS

Use the bootstrap vhost first so ACME HTTP-01 can succeed:

```bash
sudo cp /opt/anyplace/docs/deploy/nginx-anyplace-bootstrap.conf \
        /etc/nginx/sites-available/anyplace
sudo ln -sfn /etc/nginx/sites-available/anyplace /etc/nginx/sites-enabled/anyplace
sudo nginx -t && sudo systemctl reload nginx
```

Issue the certificate:

```bash
sudo certbot certonly --webroot -w /var/www/html -d <public-host>
```

If HTTP-01 is blocked by the network, use DNS-01 instead. Then install the
hardened vhost:

```bash
sudo cp /opt/anyplace/docs/deploy/nginx-anyplace-campus.conf \
        /etc/nginx/sites-available/anyplace
sudo nginx -t && sudo systemctl reload nginx
```

The hardened vhost terminates TLS, redirects HTTP to HTTPS, serves the web
applications, proxies `/api` to `127.0.0.1:9000`, and sets security headers.

Verify renewal:

```bash
sudo certbot renew --dry-run
```

## 8. Seed the mapping data

On a fresh database:

```bash
cd /opt/anyplace
sudo MONGODB_USERNAME=anyplace_app \
     MONGODB_PASSWORD='<password>' \
     MONGODB_DATABASE=anyplace \
     scripts/restore-dataset.sh --floorplans-root /opt/anyplace/floorplans
```

The script:

- restores `server/database/dump/anyplace.archive.gz` with `--drop` for the
  mapping collections;
- excludes the bundled user record, so no shared credentials are imported and
  existing application users are preserved;
- applies `server/database/init_schema.js` to create indexes;
- copies the committed floorplan sources into the floorplans root;
- prints restored document counts.

Then register the first administrator through `/api/user/register`. The first
local account becomes the administrator. If the restored data must be editable
by that account, run:

```bash
sudo MONGODB_USERNAME=anyplace_app MONGODB_PASSWORD='<password>' \
  scripts/restore-dataset.sh --reassign-owner <new-owner-id>
```

or update `owner_id` on `spaces` and `campuses` directly. Regenerate tiles with
`--tiles` if the tiling toolchain is installed.

## 9. Verification checklist

```bash
systemctl is-active anyplace.service
curl -fsS http://127.0.0.1:9000/api/health
curl -fsS https://<public-host>/api/version
curl -fsS -o /dev/null -w '%{http_code}\n' https://<public-host>/architect/
curl -fsS -o /dev/null -w '%{http_code}\n' https://<public-host>/viewer/
curl -fsS -o /dev/null -w '%{http_code}\n' https://<public-host>/campus/
```

Expected: service active, health succeeds, version `4.2.6`, and each web app
returns `200`.

## 10. Upgrade and rollback

Upgrade:

```bash
cd /opt/anyplace
sudo -u anyplace git fetch --all
sudo -u anyplace git checkout <release-tag-or-commit>
cd server && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./sbt clean stage
sudo systemctl restart anyplace.service
curl -fsS http://127.0.0.1:9000/api/health
```

Before every upgrade, take a verified backup. Rollback:

```bash
cd /opt/anyplace
sudo -u anyplace git checkout <previous-commit>
cd server && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./sbt clean stage
sudo systemctl restart anyplace.service
```

Restore the database only if the release changed data incompatibly; schema
changes in this repository are additive and index creation is idempotent.

## 11. Docker

The `docker/` tree is legacy and is not the supported deployment for this
handover. Do not introduce a database container that publishes MongoDB beyond
loopback. If a containerized deployment is required, reproduce the same
security properties: private network, authenticated MongoDB, loopback-only
application port, and the same environment variables.
