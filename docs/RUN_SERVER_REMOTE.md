# Run Anyplace Server — Ahmed-branch (Remote & Local) — Campus Burst-Optimized

This guide reproduces the **exact remote launch** done on `2026-09-24` (`Ahmed-branch` `1c5f5cfd` + `PR1` campus burst fixes, `http://192.168.1.6:9000` local + `https://<trycloudflare>.trycloudflare.com` remote). No uni VM required for teammate testing.

## 1. Current Branch

```bash
git checkout Ahmed-remote-launch   # this branch: 1c5f5cfd + 8-file PR1 (blocking-io 64, DB_TIMEOUT 10s, Gzip, LOG by-name)
# or git checkout Ahmed-branch for pure origin without PR1
```

`server/conf/app.private.conf` is **ignored** (`server/conf/.gitignore:12`) — you create it from template, never commit secrets.

## 2. Prerequisites (Ubuntu 22.04 / 26.04)

```bash
java -version  # 11.0.32 (this VM) or 17 (/usr/lib/jvm/java-17-openjdk-amd64) — either works with JDK_JAVA_OPTIONS
ls server/sbt-dist/bin/sbt-launch.jar  # bundled sbt 1.5.8
docker --version  # 29.7.2
# ImageMagick convert optional for tiler
```

## 3. MongoDB (Docker unauth, local test)

```bash
docker ps -a | grep anyplace-mongodb || docker run -d --name anyplace-mongodb -p 127.0.0.1:27017:27017 mongo:6.0
docker start anyplace-mongodb
nc -z 127.0.0.1 27017 && echo "mongo 27017 reachable"
docker logs anyplace-mongodb --tail 20  # mongod startup complete
```
> Uni VM final uses `mongod` loopback-auth (`docs/recovery/PHASE_2_STAGING_RUNBOOK.md:22` `bindIp:127.0.0.1` `authorization:enabled` + `/etc/anyplace/anyplace.env:600`), not Docker. For teammate test Docker unauth is fine.

## 4. Cloudflare Tunnel (Remote, free, no router forward)

```bash
# first time only
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /tmp/cloudflared
chmod +x /tmp/cloudflared

# every launch (device reboot clears /tmp)
rm -f /tmp/cloudflared.log
nohup /tmp/cloudflared tunnel --url http://localhost:9000 > /tmp/cloudflared.log 2>&1 &
sleep 10; cat /tmp/cloudflared.log | grep trycloudflare.com
# → https://<random>-ben-...trycloudflare.com  (e.g. https://illinois-ben-golden-flex.trycloudflare.com 2026-09-24)
```
Tunnel is **ephemeral** `trycloudflare.com` (account-less `QUIC` to `198.41.192.27`). If you restart device/`cloudflared`, URL changes → give teammates new URL. For persistent `anyplace.ejust.edu.eg`, use `cloudflared tunnel create ejust-anyplace` with your Cloudflare account (not needed now).

## 5. Configure Server (Public, not remote push)

```bash
cp server/conf/app.private.example.conf server/conf/app.private.conf
# edit server/conf/app.private.conf:
public.baseUrl="https://<your-tunnel>.trycloudflare.com"  # e.g. https://illinois-ben-golden-flex.trycloudflare.com
server.address=${public.baseUrl}
server.port="443"   # public 443, process still binds 9000
# for LAN-only test use: public.baseUrl="http://192.168.1.6:9000" server.port="9000"

# keep local-test values (Docker unauth):
mongodb.hostname="localhost"
mongodb.app.username=""
mongodb.app.password=""
mongodb.port=27017
mongodb.database="anyplace"
# cors must include tunnel:
cors.allowedOrigins = ["https://<your-tunnel>.trycloudflare.com", "http://192.168.1.6:9000", "http://localhost:9000"]
```

`server/conf/app.private.example.conf:8` `public.baseUrl=${?PUBLIC_BASE_URL}` is the template; `public.baseUrl` is what `AnyplaceServerAPI.scala:44` (`normalizePublicBase`) and `MainController.scala:73` use for `SERVER_FULL_URL` and `/api/version` `address`.

## 6. Build & Stage

```bash
cd server
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64  # or java-17 path if available
export JDK_JAVA_OPTIONS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED"

java -jar sbt-dist/bin/sbt-launch.jar clean  # 69 Scala + 6 Java
java -jar sbt-dist/bin/sbt-launch.jar stage   # → target/universal/stage/bin/anyplace (8s)
# copy private conf to staged conf (stage copies at build time)
cp conf/app.private.conf target/universal/stage/conf/app.private.conf
```

`PR1` changes in this branch: `MongodbDatasource.scala:97` `DB_TIMEOUT 10s` + `maxPoolSize 40`, `ProxyDataSource.scala:60` `this` not leak, `LOG.scala:79` by-name, `Utils.scala:226` `UTF-8` gzip, `Filters.scala:40` `+Gzip`, `app.play.conf:158` `blocking-io 64`, `logback.xml:4` `RollingFile 30d/1GB`.

## 7. Launch

```bash
# from repo root
rm -f server/target/universal/stage/RUNNING_PID
nohup server/target/universal/stage/bin/anyplace \
  -Dhttp.port=9000 -Dhttp.address=0.0.0.0 \
  -Dplay.http.secret.key=local-test-secret -Dapplication.secret=local-test-secret \
  > anyplace.log 2>&1 &
sleep 10; cat anyplace.log | tail -n 20
# → Anyplace: starting server.. / MongodbDatasource$: connected to database. / External analytics disabled
```

Alternative `install.sh` path (requires `PUBLIC_BASE_URL` env):
```bash
PUBLIC_BASE_URL=https://<your-tunnel>.trycloudflare.com ./install.sh  # generates secrets, web assets, stage
./start.sh  # checks 27017/9000, handles RUNNING_PID, -Dhttp.port=9000
./status.sh # MongoDB ONLINE, Backend ONLINE
```

## 8. Verify (same as Mas / PHASE_7_8_VALIDATION.md:57)

```bash
curl -fsS http://127.0.0.1:9000/api/version
# → {"version":"4.2.6","port":"443","address":"https://<your-tunnel>.trycloudflare.com"}

curl -fsS https://<your-tunnel>.trycloudflare.com/api/version
# → same 200 via Cloudflare (QUIC 198.41.192.27)

curl -fsS -X POST https://<your-tunnel>.trycloudflare.com/api/mapping/space/public \
  -H 'Content-Type: application/json' -d '{}' | head -c 200
# → gzip {"spaces":[],"buildings":[]} (empty DB expected)

curl -i -X POST https://<your-tunnel>.trycloudflare.com/api/auth/mapping/space/access \
  -H 'Content-Type: application/json' -d '{}'
# → 401 {"Must provide access_token"} + CSP/X-Frame-DENY/nosniff

# same IP local (same Wi-Fi only):
curl -fsS http://192.168.1.6:9000/api/version  # 192.168.1.6 from hostname -I
```

`anyplace.log` tail and `server/target/universal/stage/logs/application.log` (rolling) show `Space: all:` etc.

## 9. Hand Off to Teammates (Remote, not same Wi-Fi)

**Give them this one URL:**
```
https://<your-tunnel>.trycloudflare.com  # e.g. https://illinois-ben-golden-flex.trycloudflare.com
```

**Ahmed-branch (recommended, simple):**
```bash
# teammate
echo "PUBLIC_BASE_URL=https://<your-tunnel>.trycloudflare.com" > clients/android-new/local.properties
./gradlew :logger:assembleDebug :navigator:assembleDebug
# → BuildConfig.PUBLIC_BASE_URL/SERVER_HOST/SERVER_PORT/API_BASE_URL (AnyplaceServerAPI.java:35 BuildConfig)
```

**navigation-app (hardcoded ap.cs.ucy.ac.cy:44, requires patch):**
```bash
echo "SERVER_URL=https://<your-tunnel>.trycloudflare.com" > clients/.env  # build.gradle:28
# + patch AnyplaceServerAPI.java:38 SERVER_HOST/BASE_URL → BuildConfig (one-line)
```

Or you build `Ahmed-branch` APK with that `PUBLIC_BASE_URL` and send `navigator-debug.apk` — they just `adb install -r`, no rebuild.

Teammate quick check before app: `curl -fsS https://<your-tunnel>/api/version` must be `200`; if `502` tunnel expired → ask you for new `https://<new>.trycloudflare.com` (ephemeral).

## 10. Stop / Uni VM Next

```bash
pkill -f "play.core.server.ProdServerStart"  # or ./stop.sh
docker stop anyplace-mongodb
kill $(ps aux | grep cloudflared | awk '{print $2}')
```

**Uni VM final:** `docs/recovery/PHASE_2_STAGING_RUNBOOK.md:22` `mongod` loopback-auth + `/opt/anyplace` `useradd anyplace` + `/etc/anyplace/anyplace.env:600` + `anyplace.service:436` `EnvironmentFile` + `Nginx 443→9000` (`LOCAL_SETUP_NGINX_PROXY_MANAGER.md:69`) + `certbot --nginx -d anyplace.ejust.edu.eg` or named `cloudflared tunnel create`.
