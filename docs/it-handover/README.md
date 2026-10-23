# E-JUST Anyplace IT Handover

This directory is the IT-facing documentation set for the E-JUST Anyplace
deployment. It is written against this repository and the deployed host, not
against upstream Anyplace documentation.

## Document precedence

When documents disagree, use this order:

1. `docs/deploy/PRODUCTION_ROLLOUT.md` and the `docs/deploy/` configuration
   files for the exact host rollout procedure.
2. This handover set for operating the running system.
3. Everything else (including upstream Anyplace documentation) for background.

## Documents

| Document | Purpose |
|---|---|
| [REQUIREMENTS.md](REQUIREMENTS.md) | Scope, users, functional and non-functional requirements, capacity assumptions, acceptance criteria. |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Components, request flows, MongoDB collections and indexes, filesystem layout, security model. |
| [INSTALLATION.md](INSTALLATION.md) | Native systemd installation, optional Docker deployment, dataset seeding, verification, upgrade and rollback. |
| [OPERATIONS.md](OPERATIONS.md) | Service lifecycle, health checks, logs, mapping administration, backup and restore, disaster recovery, troubleshooting. |
| [HANDOVER.md](HANDOVER.md) | Infrastructure inventory, credential policy, RACI matrix, acceptance checklist, known limitations. |

## System snapshot

| Item | Value |
|---|---|
| Application version | `4.2.6` (`server/conf/app.base.conf`) |
| Backend | Scala 2.13.6, Play Framework 2.8.13, MongoDB Scala driver 4.4.0 |
| Build tool | sbt 1.5.8 (repository launcher) |
| Runtime | JDK 17 on the host unit; CI also validates JDK 11 |
| Database | MongoDB 6.0, loopback only (`127.0.0.1:27017`), authentication enabled |
| Service unit | `anyplace.service` |
| Application root | `/opt/anyplace` |
| Play listener | `127.0.0.1:9000` behind Nginx |
| Public entry point | Nginx on `80`/`443`; canonical host configured in `public.baseUrl` (for example `https://ejustgo.ejust.edu.eg`) |
| Web applications | `/architect/`, `/viewer/`, `/campus/`, `/developers/` |
| Mapping data | 1 campus, 8 buildings, 228 POIs, 249 edges, 3 floorplans, committed under `server/database/` |
| Operational scripts | `install.sh`, `start.sh`, `stop.sh`, `status.sh`, `scripts/restore-dataset.sh`, `server/database/admin/{backup,restore}.sh` |

## Quick start

```bash
# Service state and health
sudo systemctl status anyplace.service
/opt/anyplace/status.sh

# Live logs
sudo journalctl -u anyplace.service -f

# Version and liveness
curl -fsS http://127.0.0.1:9000/api/version
curl -fsS http://127.0.0.1:9000/api/health

# Manual backup (requires /etc/anyplace/backup/config.sh)
sudo /opt/anyplace/server/database/admin/backup.sh
```

## Security note

No password, token, private key, or application secret belongs in this
repository or in handover documents. Runtime secrets live in
`/etc/anyplace/anyplace.env` and `/etc/anyplace/backup/config.sh` with mode
`0600`, owned by `root`. If a credential is ever committed, treat it as
compromised and rotate it.
