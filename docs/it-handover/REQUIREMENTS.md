# Requirements Specification

## 1. Purpose and scope

E-JUST Go provides indoor and campus navigation, mapping administration,
and Wi-Fi positioning for the E-JUST campus. The system is a deployment of the
Anyplace platform, adapted as E-JUST Go with campus data and IT operations.

In scope:

- Web map viewer for buildings and the campus.
- Architect tools for creating buildings, floors, POIs, and connections.
- Indoor shortest-path navigation and campus outdoor routing.
- Floorplan upload, storage, and tile generation.
- Wi-Fi fingerprint upload and positioning endpoints used by the Android client.
- Local user registration and login, plus Google login when configured.
- Operational tooling: health checks, backups, restores, and dataset seeding.

Out of scope for this handover:

- Android application distribution through Google Play.
- Surveying new buildings or collecting new Wi-Fi fingerprints.
- Google Maps billing, Cloudflare/WAF, and campus DNS administration.
- High-availability clustering, multi-node database replication, and horizontal
  scaling. The current design is a single application node.

## 2. Users and roles

| Role | Description | Main surfaces |
|---|---|---|
| Visitor / student / staff | Finds buildings, rooms, and services; requests routes. | Viewer, campus viewer, Android app |
| Mapping editor | Creates and edits spaces, floors, POIs, and connections. | Architect |
| Co-owner | Shares editing rights on a space. | Architect |
| Administrator | Manages users and all mapping data; first registered local account becomes the administrator. | Architect, API |
| IT operator | Deploys, monitors, backs up, and restores the service. | systemd, Nginx, MongoDB, scripts |

## 3. Functional requirements

### 3.1 Mapping and content

- FR-1: Publish buildings and campus POIs; unpublished spaces are hidden from
  public listings.
- FR-2: Store floorplan source images on the filesystem and generate raster
  tiles for the viewer and Android clients.
- FR-3: Support POI search by name, including Greeklish transliteration, with
  bounded input and result sizes.
- FR-4: Store indoor connections and campus outdoor edges for routing.
- FR-5: Restrict edits to the owner, co-owners, and administrators.

### 3.2 Navigation and positioning

- FR-6: Compute the shortest indoor route between coordinates or POIs.
- FR-7: Compute campus routes over the outdoor connector graph.
- FR-8: Accept Wi-Fi fingerprints and expose floor prediction and position
  estimation endpoints used by the Android client.

### 3.3 Identity

- FR-9: Register and authenticate local users with PBKDF2-HMAC-SHA256 password
  hashes and per-user salts; legacy hashes remain verifiable but are not issued.
- FR-10: Issue and refresh access tokens for local sessions.
- FR-11: Support Google login only when a Google client ID is configured; the
  server validates the token audience and issuer.
- FR-12: Enforce a single-administrator invariant at the database level.

### 3.4 Operations

- FR-13: Start automatically at boot and restart after a crash.
- FR-14: Expose `/api/health` (no database dependency) and `/api/version`.
- FR-15: Produce verified, optionally encrypted, off-host MongoDB backups and
  support tested restores.
- FR-16: Seed a fresh deployment from the committed E-JUST mapping snapshot
  without importing shared credentials.

## 4. Non-functional requirements

### 4.1 Availability and recovery

- The service restarts automatically after failure (`Restart=always`) and
  survives reboots (`WantedBy=multi-user.target`).
- Stale `RUNNING_PID` files never block a restart.
- Target recovery point objective (RPO): one backup interval, default daily.
- Target recovery time objective (RTO): under one hour using the documented
  restore procedure, assuming the host and database are available.

### 4.2 Security

- Play listens on loopback only; Nginx or the campus TLS gateway terminates TLS.
- MongoDB listens on loopback only and requires authentication.
- Secrets are provided through `/etc/anyplace/anyplace.env` (mode `0600`).
- CORS is restricted to the configured public origin.
- Floorplan and tile paths are validated to prevent traversal outside the
  configured storage roots.
- Error responses do not disclose internal exception messages.
- Authentication lookups are indexed; admin creation is race-safe.

### 4.3 Performance and capacity

The original requirements target 1,000 concurrent active users and roughly
350-500 requests per second during peaks. **These figures are planning targets,
not results of a formal load test.** Capacity must be validated against real
traffic before being used as a contractual SLA.

Measured on the development host with JDK 11, synthetic data with 5,000 POIs,
and a local MongoDB:

| Operation | Median latency |
|---|---|
| `/api/health` | 3.51 ms |
| Public space listing | 4.94 ms |
| POI search, 500 results | 19.45 ms |
| Campus search, 500 of 5,000 POIs | 29.55 ms |

Design measures that support the targets:

- Database queries use projections and indexed filters; POI search is pushed
  down to MongoDB rather than filtering in memory.
- Campus and navigation graph construction batch database reads to avoid
  per-item queries.
- Result sizes and search inputs are capped.
- Response compression is enabled.
- Floorplan images and tiles are cached in the application.

### 4.4 Maintainability

- Backend tests run with `sbt test`; MongoDB integration tests are enabled with
  `RUN_MONGO_INTEGRATION_TESTS=true`.
- CI runs unit tests on JDK 11 and integration tests against MongoDB 6.0.
- Index creation is idempotent (`server/database/init_schema.js`).
- Backups are validated with `mongorestore --dryRun` before being accepted.

## 5. Data requirements

| Data | Location | Notes |
|---|---|---|
| Campuses, spaces, floors, POIs, edges, users | MongoDB `anyplace` | Primary operational data |
| Floorplan source images | `/opt/anyplace/floorplans/<buid>/fl_<n>/fl_<n>` | Committed seed in `server/database/floorplans/` |
| Generated tiles | `/opt/anyplace/floorplans/<buid>/fl_<n>/tiles/` | Regenerable, never committed |
| Radiomaps | `/opt/anyplace/radiomaps_frozen/` | Wi-Fi positioning data |
| Backups | `/var/backups/anyplace/` | Verified archives, optional GPG encryption |

The committed mapping snapshot contains 1 campus, 8 buildings, 228 POIs,
249 edges, and 3 floorplans. It excludes user credentials by default when
restored.

## 6. Acceptance criteria

The deployment is accepted when:

1. `anyplace.service` is `active (running)` and enabled at boot.
2. `/api/health` returns success locally and through Nginx over HTTPS.
3. `/api/version` reports `5.0.0`.
4. `/architect/`, `/viewer/`, `/campus/`, and `/developers/` load over HTTPS.
5. The seeded campus and buildings are visible in the viewer.
6. A POI search and an indoor route succeed.
7. A manual backup completes, passes validation, and a restore into a scratch
   database succeeds.
8. If the VM terminates TLS, `certbot renew --dry-run` succeeds; otherwise IT confirms the gateway certificate renewal path.
9. No plaintext secrets exist in the repository or documentation.
10. The IT operator has completed one restore drill and one service restart.

## 7. Known limitations

- Single application node; no built-in high availability.
- Wi-Fi positioning depends on fingerprint coverage and device behaviour; it is
  not a substitute for GPS outdoors.
- The committed snapshot covers the surveyed E-JUST buildings only.
- Capacity targets are not yet backed by a formal load test.
- Android distribution and device support are handled separately.
