# Production Preparation - Release 5.0.0

**Prepared:** 2026-10-26, from outside the campus network.
**Target:** `https://ejustgo.ejust.edu.eg`
**Release:** `v5.0.0` / commit `57745c9e`; deployment tip `v5.0.0-deploy.1`
**Scope:** preparation and state definition only. No production changes were made.

## 1. Release state

| Item | Value |
|---|---|
| Tag | `v5.0.0` (code-complete release) |
| Deployment tag | `v5.0.0-deploy.1` (adds E-JUST Go branding, hostname, TLS-mode, and preflight preparation) |
| Artifact | `server/target/universal/anyplace-5.0.0.zip` |
| SHA-256 | `601cd84af2f7fc33c6145641c7105f34f0246071a9acd14776d39a09e41685ab` |
| Unit tests | 69 total: 66 passed, 3 Mongo-gated skips |
| Mongo integration | 137 passed |
| Nginx configs | `nginx -t` passed for campus, gateway, and bootstrap variants |
| Branding | Phase 1 display name `E-JUST Go`; runtime identifiers unchanged |
| Previous release | `4.2.6` |

Rebuild with `cd server && sbt dist` if the artifact is missing. The checksum
changes if the artifact is rebuilt; record the new value before uploading.

## 2. Public DNS and reachability check (from off-campus)

Checked on 2026-10-26 from a home network:

| Check | Result | Meaning |
|---|---|---|
| `ejustgo.ejust.edu.eg` A record | `196.219.57.237` via local resolver and `8.8.8.8` | Public DNS is correct and globally visible |
| AAAA record | none | IPv4-only path; no AAAA change needed |
| `anyplace.ejust.edu.eg` | no record | Do not use this name; configs now use `ejustgo` |
| TCP 80 | filtered/timeout | Cannot use HTTP-01 from the public Internet as seen from home |
| TCP 443 | open | Something answers TLS at the public address |
| TCP 22 | filtered/timeout | Expected; home access is blocked |
| TLS handshake | TLS 1.3, certificate `CN=*.ejust.edu.eg` | University wildcard certificate, not a Let's Encrypt certificate |
| Certificate issuer/validity | Sectigo Public Server Authentication CA DV R36; 2026-02-04 to 2027-03-07 | Covers `ejustgo.ejust.edu.eg` via the wildcard SAN |
| Certificate chain | incomplete (issuer certificate not sent) | Browsers may reject it; may be a gateway configuration issue |
| HTTP/HTTPS GET | no response within 25 s | Public routing is blocked or incomplete from home |

**Conclusion:** DNS is ready. Public reachability and the final TLS path cannot
be validated from home; this matches the expectation that the service is only
reachable from the campus network. The wildcard certificate strongly suggests
that TLS terminates at a university reverse proxy, but this must be confirmed
on-network before installing either Nginx variant.

Do not change DNS or ask for a new certificate until the TLS termination mode is
confirmed.

## 3. Last recorded VM state (unverified in this session)

These values come from earlier deployment work and repository documentation.
Treat them as a baseline to confirm, not as current facts.

| Item | Last recorded value |
|---|---|
| OS | Ubuntu 22.04 |
| Application root | `/opt/anyplace` |
| Service | `anyplace.service`, Play bound to `127.0.0.1:9000` |
| Running version | `4.2.6` |
| Nginx | 1.28.3, hardened vhost |
| MongoDB | 6.0 on `127.0.0.1:27017`, authentication expected |
| Runtime env | `/etc/anyplace/anyplace.env`, mode `0600` |
| JDK in unit | `/usr/lib/jvm/java-17-openjdk-amd64` |
| CORS | `https://ejustgo.ejust.edu.eg` |
| Data | 1 campus, 8 spaces, 228 POIs, 249 edges, 3 floorplans |
| Prior backup | `/var/backups/anyplace/pre-hardening-2026-10-20-1036.archive.gz` is empty; do not use it |

## 4. What is needed before starting

1. **Network:** on-campus access or VPN that can reach the VM and the public
   hostname. Home access is not sufficient.
2. **SSH:** host, user, port, and a key-based login. Password prompts are not
   usable in the automated session; add a temporary key instead.
3. **Privileges:** `sudo` for service, Nginx, MongoDB backup, and certificate
   checks. Passwordless sudo for the deployment user is simplest.
4. **Maintenance window:** the data hydration step stops the service.
5. **IT confirmation:** whether `196.219.57.237` is the VM or a campus gateway,
   whether the gateway forwards to this VM, and whether it preserves `Host` and
   sets `X-Forwarded-Proto`.
6. **TLS decision:** VM-terminated (certbot) or gateway-terminated (no certbot
   on the VM).
7. **JDK decision:** keep JDK 17 from the unit or point the unit at JDK 11.
   The release artifact was built and tested on JDK 11; the service unit uses 17.
8. **Disk:** at least 20 GB free on `/opt` for the backup, build, and restore.
9. **Credentials:** MongoDB and `APPLICATION_SECRET` stay in
   `/etc/anyplace/anyplace.env`; never print or copy them into logs.

## 5. First actions on the campus network

Run these before changing anything:

```bash
cd /path/to/E-JUST_interactive_Map

# Public DNS, TCP, TLS, API, and web entry points.
./scripts/prod-preflight.sh \
  --host ejustgo.ejust.edu.eg \
  --expected-ip 196.219.57.237 \
  --ssh <deploy-user>@<vm-address> | tee prod-preflight-$(date +%F).txt

# If SSH is not ready, run the state script directly on the VM:
ssh <deploy-user>@<vm-address> 'bash -s' < scripts/prod-state.sh \
  | tee prod-state-$(date +%F).txt
```

The preflight is read-only. It checks DNS, ports, TLS, public endpoints, the
local release tag, and the artifact checksum, then prints the VM state when
`--ssh` is supplied.

## 6. Decision gates

| Gate | Pass condition | If it fails |
|---|---|---|
| G1 DNS/route | `ejustgo` resolves to the VM or to a gateway that forwards to it | Stop; ask IT to correct routing |
| G2 TLS mode | Issuer and forwarding path identify VM or gateway termination | Stop; do not install a config until known |
| G3 Backup | Fresh archive is non-empty and `mongorestore --dryRun` succeeds | Stop; do not deploy |
| G4 Data | Restore reports 8 spaces, 3 floorplans, 228 POIs, 249 edges, 1 campus | Stop; wrong archive or partial restore |
| G5 Release | `/api/version` reports `5.0.0`; health and web entries return 200 | Roll back |
| G6 Security | No plaintext secrets in the repo; env file mode `0600` | Fix before proceeding |

### TLS mode selection

- **University gateway terminates TLS** (likely, given the Sectigo wildcard):
  install `docs/deploy/nginx-anyplace-gateway.conf`. Replace the
  `set_real_ip_from` placeholder with the gateway address from IT. Do not run
  certbot on the VM and do not redirect HTTP to HTTPS.
- **VM terminates TLS** (Let's Encrypt certificate on port 443): install
  `docs/deploy/nginx-anyplace-bootstrap.conf`, obtain the certificate, then
  install `docs/deploy/nginx-anyplace-campus.conf`. If public port 80 is not
  reachable, use the DNS-01 challenge instead of `--webroot`.

## 7. Deployment sequence

Follow `docs/deploy/PRODUCTION_ROLLOUT.md` with the mode chosen above:

1. Preflight and VM state snapshot.
2. Verified backup of MongoDB and `/opt/anyplace` files.
3. Stage `v5.0.0-deploy.1`, rebuild web assets, run `sbt clean stage`.
4. Stop the service, restore the committed dataset, apply indexes.
5. Start the service and run loopback smoke tests.
6. Install the Nginx variant and reload; verify HTTPS and all four web apps.
7. Run public smoke tests: version, health, search, indoor route, gzip.
8. Refresh backup units and record the rollout.
9. Roll back with the step-2 archive and previous commit if any gate fails.

## 8. Stop point

Stop at **M5.0.0 acceptance**: `/api/version` reports `5.0.0`, all web entry
points load over the confirmed public path, an indoor route succeeds, and a
verified backup exists. Do not start another optimization or feature wave.
Remaining work after acceptance is operations only.

## 9. Rollback essentials

```bash
sudo systemctl stop anyplace.service
cd /opt/anyplace
sudo -u anyplace git checkout <previous-commit>
sudo -u anyplace ./scripts/build-web-assets.sh
cd server && sudo -u anyplace env JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
  ./sbt clean stage
sudo systemctl start anyplace.service
```

If data changed, restore the pre-deployment archive with `mongorestore --drop`
and untar the filesystem backup. Re-run loopback smoke tests before reopening
the service.
