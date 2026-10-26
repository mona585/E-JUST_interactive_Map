# Project Handover and Acceptance

## 1. Delivery summary

This document records the handover of the E-JUST Anyplace deployment from the
development team to the E-JUST IT Department. It covers the delivered software,
the runtime inventory, the credential policy, operational responsibilities, and
the acceptance checklist.

| Item | Value |
|---|---|
| Product | E-JUST Anyplace indoor and campus navigation |
| Application version | `5.0.0` |
| Source repository | `git@github.com:mona585/E-JUST_interactive_Map.git` |
| Handover date | Fill at sign-off |
| Receiving department | E-JUST Information Technology Department |
| Support owner | Fill at sign-off |

## 2. Delivered components

- Play/Scala backend and REST API (`server/`).
- Web applications: architect, viewer, campus viewer, developers (`clients/web/`).
- Mapping seed: 1 campus, 8 buildings, 228 POIs, 249 edges, 3 floorplans
  (`server/database/`).
- Idempotent schema and index script (`server/database/init_schema.js`).
- Dataset restore tooling (`scripts/restore-dataset.sh`).
- Verified backup and restore tooling (`server/database/admin/`).
- systemd unit and lifecycle scripts (`anyplace.service`, `start.sh`, `stop.sh`,
  `status.sh`, `install.sh`).
- Nginx bootstrap and hardened vhosts, backup timer, and backup environment
  template (`docs/deploy/`).
- Recovery and deployment runbooks (`docs/recovery/`,
  `docs/deploy/PRODUCTION_ROLLOUT.md`).
- This IT handover set (`docs/it-handover/`).
- Backend test suite and CI configuration (`server/test/`,
  `.github/workflows/server.yml`).

## 3. Runtime inventory

Complete this table on the production host during acceptance. Do not record
secret values here.

| Parameter | Observed value |
|---|---|
| Hostname / FQDN | |
| Virtualization platform and VM identifier | |
| Operating system and kernel | |
| vCPU / RAM | |
| Root disk size and free space | |
| Application root | `/opt/anyplace` |
| Service unit | `anyplace.service` |
| Java runtime | `java -version` output: |
| Play listener | `127.0.0.1:9000` |
| MongoDB version and mode | |
| MongoDB bind address and port | `127.0.0.1:27017` |
| Database name | `anyplace` |
| Nginx version | |
| Public hostname | |
| TLS certificate issuer and expiry | |
| Backup directory | `/var/backups/anyplace` |
| Backup schedule | `anyplace-backup.timer` |

## 4. Credential and secret policy

No credential is delivered in this repository or in this document. The following
items must exist only on the host, with mode `0600`, owned by `root`:

| Item | Location | Rotation impact |
|---|---|---|
| Application secret | `/etc/anyplace/anyplace.env` (`APPLICATION_SECRET`) | Invalidates active sessions |
| MongoDB application password | `/etc/anyplace/anyplace.env` and `server/conf/app.private.conf` | Requires a coordinated database password change |
| Password salt and pepper | `server/conf/app.private.conf` | Invalidates legacy hashes; PBKDF2 hashes remain valid |
| Google client ID | `/etc/anyplace/anyplace.env` / `app.private.conf` | Google login only |
| Backup GPG recipient | `/etc/anyplace/backup/config.sh` | Future backups only |
| Off-host backup target | `/etc/anyplace/backup/config.sh` | Future copies only |

Rules:

- Never commit `server/conf/app.private.conf`, `server/.env`,
  `/etc/anyplace/backup/config.sh`, private keys, or backup archives.
- Rotate any credential that has ever been committed or shared in plaintext.
- Use a unique MongoDB password for `anyplace_app`; do not reuse the admin
  password.
- Keep the GPG private key offline or in the IT key escrow process. Losing it
  makes encrypted backups unrecoverable.
- Grant the service account only the permissions it needs; do not run Play as
  root.

## 5. Responsibility matrix

| Task | IT (NOC / sysadmin) | Facilities / surveyors | Development (Tier 3) |
|---|---|---|---|
| VM sizing, OS patching, network, DNS | A/R | I | C |
| TLS certificate and Nginx | A/R | I | C |
| Service monitoring and restarts | A/R | I | C |
| MongoDB availability and backups | A/R | I | C |
| Backup restore drills | A/R | I | C |
| Mapping content and floorplans | C | A/R | C |
| Wi-Fi surveys and fingerprints | I | A/R | C |
| Application defects and upgrades | I | I | A/R |
| Security incident response | A/R | I | C |

A = accountable, R = responsible, C = consulted, I = informed.

## 6. Acceptance checklist

Mark each item during the acceptance session.

- [ ] Repository cloned at the agreed commit; `git status` is clean.
- [ ] `/etc/anyplace/anyplace.env` exists with mode `0600` and contains no
      placeholder values.
- [ ] `systemctl is-enabled anyplace.service` returns `enabled`.
- [ ] `systemctl is-active anyplace.service` returns `active`.
- [ ] `/api/health` succeeds locally and over HTTPS.
- [ ] `/api/version` returns `5.0.0`.
- [ ] `/architect/`, `/viewer/`, `/campus/`, and `/developers/` return `200` over
      HTTPS.
- [ ] The seeded campus and buildings are visible in the viewer.
- [ ] A POI search returns results and an indoor route succeeds.
- [ ] The first administrator account is registered and can log in.
- [ ] `cors.allowedOrigins` matches the public origin.
- [ ] MongoDB is reachable only on loopback and requires authentication.
- [ ] A manual backup completes and its manifest contains non-zero counts.
- [ ] A restore drill into a scratch database succeeds.
- [ ] `certbot renew --dry-run` succeeds if the VM terminates TLS; otherwise IT confirms the gateway renewal path.
- [ ] `anyplace-backup.timer` is enabled and scheduled.
- [ ] Disk usage is below 80% and the backup retention policy is configured.
- [ ] The IT operator has performed a service restart and read the logs.
- [ ] No secrets exist in the repository (`git grep` spot check).

## 7. Known limitations and open items

- Single application node; no high-availability clustering.
- Capacity targets (1,000 concurrent users) are planning figures; no formal load
  test has been completed.
- The production host's available disk must be confirmed before bulk imports or
  long backup retention.
- Android client distribution and device support are handled separately.
- Wi-Fi positioning quality depends on survey coverage.
- Credential rotation for the application secret and MongoDB password is
  deferred; schedule it with IT after acceptance.
- If the public hostname changes, update `public.baseUrl`,
  `cors.allowedOrigins`, the Nginx server name, and the certificate.

## 8. Support and escalation

| Level | Contact | Scope |
|---|---|---|
| Tier 1 | IT service desk | Service availability, access, basic checks |
| Tier 2 | IT systems / database administrators | Host, Nginx, MongoDB, backups, TLS |
| Tier 3 | Development team | Application defects, upgrades, data model changes |

Record contact names and phone numbers in the signed copy of this document, not
in the repository.

## 9. Sign-off

| Role | Name | Signature | Date |
|---|---|---|---|
| Development lead | | | |
| IT operations manager | | | |
| IT security representative | | | |
