# Phase 2 Staging Runbook

Use this on the private Ubuntu 22.04 staging VM after Phase 1 preflight passes.
It prepares the co-located, authenticated, loopback-only MongoDB baseline and
the canonical Anyplace systemd service. Do not expose port 27017 publicly.

## 1. Prepare MongoDB

Install MongoDB Community 6.0.x and `mongosh` from the university-approved
mirror. Before enabling authentication, create a limited application account
interactively on the local VM:

```javascript
// Start with: mongosh --host 127.0.0.1
use admin
db.createUser({
  user: "anyplace_app",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "anyplace" }]
})
```

Set these MongoDB options in `/etc/mongod.conf`, then restart `mongod`:

```yaml
net:
  bindIp: 127.0.0.1,::1
  port: 27017
security:
  authorization: enabled
```

Validate the listener and prompt-based authenticated access:

```bash
sudo ss -ltnp 'sport = :27017'
mongosh --host 127.0.0.1 --username anyplace_app \
  --authenticationDatabase admin --password \
  --eval 'db.getSiblingDB("anyplace").runCommand({ping: 1})'
```

`ss` must show only `127.0.0.1:27017` and/or `[::1]:27017`; the `mongosh`
command must return `ok: 1`.

## 2. Configure the application

Create the service account and install the source at `/opt/anyplace`. Copy the
private configuration template; it contains environment references, not secrets.

```bash
sudo useradd --system --home /opt/anyplace --shell /usr/sbin/nologin anyplace
sudo install -d -o anyplace -g anyplace /opt/anyplace
sudo install -o root -g anyplace -m 0640 \
  server/conf/app.private.example.conf server/conf/app.private.conf
sudo install -d -m 0700 /etc/anyplace
sudoedit /etc/anyplace/anyplace.env
sudo chmod 0600 /etc/anyplace/anyplace.env
```

The protected environment file must contain this shape, with real values only
on the VM:

```dotenv
APPLICATION_SECRET=<new-high-entropy-value>
MONGODB_HOST=127.0.0.1
MONGODB_PORT=27017
MONGODB_DATABASE=anyplace
MONGODB_USERNAME=anyplace_app
MONGODB_PASSWORD=<password-entered-during-user-creation>
```

## 3. Build and start

Build the staged backend as the service account, then install the committed
unit. The service logs are in `journald`.

```bash
sudo -u anyplace -H bash -lc 'cd /opt/anyplace/server && ./sbt clean stage'
sudo install -m 0644 anyplace.service /etc/systemd/system/anyplace.service
sudo systemctl daemon-reload
sudo systemctl enable --now anyplace
sudo systemctl status anyplace --no-pager
curl --fail --silent http://127.0.0.1:9000/api/version
sudo journalctl -u anyplace -n 100 --no-pager
```

Perform one controlled restart and repeat the `curl` check:

```bash
sudo systemctl restart anyplace
curl --fail --silent http://127.0.0.1:9000/api/version
```

Do not configure the official public domain, Nginx, or TLS in this phase; those
are Phase 8 decisions. Do not add official mapping data; the initial dataset is
empty by decision.
