# Release 5.0.0 - E-JUST Production Upgrade

**Milestone:** `M5.0.0` - Production Readiness
**Previous version:** `4.2.6`
**Release date:** 2026-10-26
**Status:** Code-complete; production rollout pending.
**Deployment tag:** `v5.0.0-deploy` (adds the hostname/TLS-mode preparation).

## Why this is a major upgrade

5.0.0 is the first release that combines the E-JUST deployment work with the
security, reliability, and performance work needed to run the service in
production. It upgrades the runtime stack, hardens every public surface, adds
verified backup/restore tooling, ships the E-JUST dataset, and removes the
database and request-path bottlenecks measured on the 4.2.6 baseline.

## Highlights

### Security and correctness
- Upgraded to Play 2.8.13, Scala 2.13.6, and the Mongo Scala driver 4.4.0.
- Restricted CORS to the configured production origin and hardened auth,
  role, and ownership checks.
- Removed query-injection and information-leak paths; error envelopes no longer
  echo internal exception details.
- Public endpoints now return `application/json` consistently.
- JSON and floorplan responses honor `Accept-Encoding`; clients that do not
  advertise gzip receive an uncompressed body.

### Performance
- Added compound indexes for access points, same-floor edges, and POI lookups;
  `explain` confirms `IXSCAN` for each hot query.
- Moved read-heavy controller work to the blocking I/O dispatcher.
- Cached floorplan tiles, the combined all-floors payload, short-lived search
  results, and routing POI/edge snapshots, with explicit invalidation on writes.
- Added server-side field projections to edge and floor queries.
- Nginx now gzips static assets and never caches entry documents.
- Campus viewer caches floorplans and prefetches adjacent floors.

Measured on the local staging dataset:

| Path | Before | After |
|---|---|---|
| Same-floor route | 42 ms cold | 10-13 ms warm |
| Combined 3-floor payload | 1.68 s cold | 0.13 s warm |
| POI search (repeat) | 60 ms | 10 ms |
| Small navigation response | 952 B plain | 952 B plain (gzip skipped below 1 KB) |

### Operations and data
- Added a self-healing systemd unit with restart limits and JVM GC/OOM flags.
- Added verified, optionally encrypted backups plus restore tooling and a
  production rollout runbook.
- Committed the E-JUST dataset (1 campus, 8 buildings, 228 POIs, 249 edges,
  3 floorplans) and a restore script.
- Added IT handover, requirements, installation, operations, and recovery docs.
- Web clients rebuilt with the Node 24 / Grunt 0.4 shim; campus floorplan images
  decode asynchronously.

## Compatibility and upgrade notes

- Existing API paths and JSON field names are unchanged. Clients should send
  `Accept-Encoding: gzip` to receive compressed payloads.
- CORS now allows only the configured origin; update `cors.allowed.origins` if
  the public hostname changes.
- Apply `server/database/init_schema.js` before starting the new build; indexes
  are idempotent.
- Deploy the updated Nginx configuration so entry documents are not cached and
  static assets are compressed.
- Take a verified backup and follow `docs/deploy/PRODUCTION_ROLLOUT.md`.

## Validation

- 69 backend unit tests: 66 passed, 3 skipped (Mongo-gated).
- 137 Mongo integration tests passed.
- Live smoke: version, health, public spaces, POI search, indoor route, gzip and
  plain responses, and all web entry points.
- Nginx configuration validated with `nginx -t`.

## Milestone boundary - stop here

`M5.0.0` is the terminal optimization milestone. Stop implementation when:

1. Version is `5.0.0` and the release commit is tagged.
2. `sbt dist` produces the distributable and the staged build passes smoke.
3. The production rollout checklist completes with `/api/version` reporting
   `5.0.0`.

Do not start another feature or performance wave. Remaining work is deployment,
acceptance, and operational fixes only. Any new work after this point requires a
separate milestone and a fresh baseline measurement.
