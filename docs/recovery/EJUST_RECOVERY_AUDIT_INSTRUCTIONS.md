# E-JUST Anyplace — Recovery Audit & Completion Instructions

## Purpose

This file is the execution contract for the next Codex/AGY session.

The previous session documented what it says was completed in:
- `docs/recovery/PHASES_COMPLETED.md`

The original approved recovery requirements are in:
- `docs/recovery/RECOVERY_REPORT.md`

The next session must not assume that every phase marked DONE is truly complete.

Its job is to:
1. compare what was required with what was actually implemented;
2. verify the implementation using code, git history, runtime behavior, tests, and TestSprite where appropriate;
3. identify every real gap or deviation;
4. fix only those verified gaps;
5. stop when Phases 0–9 truly satisfy their approved Definitions of Done.

Phase 10 modernization is OUT OF SCOPE.

---

## Read First

Before changing code, read:
- `CONTEXT.md`
- `docs/recovery/RECOVERY_REPORT.md`
- `docs/recovery/PHASES_COMPLETED.md`
- `docs/recovery/EXECUTION_LOG.md`
- `docs/adr/0001-ejust-android-application-identity.md`
- `AGENTS.md` if present

Then inspect current branch, HEAD, git status, and recovery commits.

Do not trust summaries alone. Verify against the repository.

---

## Strict Rule

Do NOT start by modifying code.

First create:

`docs/recovery/RECOVERY_AUDIT.md`

For each Phase 0–9 classify it as exactly one of:
- `VERIFIED COMPLETE`
- `PARTIAL`
- `PLAN DEVIATION`
- `NOT VERIFIED`
- `EXTERNAL DEPENDENCY`

A phase is complete only when the original validation and Definition of Done in `RECOVERY_REPORT.md` are actually satisfied.

For each phase write:
- what the recovery report required;
- what `PHASES_COMPLETED.md` claims was done;
- what you verified from code, commits, runtime, tests, TestSprite, web, Android, or infrastructure;
- the exact gap, if any;
- the status;
- the smallest required fix, only if a verified gap exists.

Do not fix anything until this audit exists.

---

## Mandatory Review Areas

### Phase 0 — Secrets
Verify the original problems themselves were fixed:
- tracked secret in `anyplace.service`;
- installer/build scripts printing or exposing secrets;
- exposed credentials removed/rotated where applicable;
- no real secrets remain in tracked files.

Do not accept `.env.example` cleanup alone as proof.

### Phase 2 — Backend and MongoDB
Verify:
- one reproducible backend start method;
- selected JDK/runtime works for the recovered deployment;
- MongoDB authentication is enabled;
- MongoDB binds to localhost only;
- port 27017 is not public;
- Mongo host/port/database/credentials remain external configuration;
- analytics are disabled by default.

### Phase 4 — Web and Swagger
Verify:
- Architect assets load;
- Viewer assets load;
- Campus Viewer assets load;
- no recovery-blocking 404s remain;
- current/generated Swagger API output works, not only the static HTML page.

### Phase 5 — Administrator Bootstrap
Do not only verify:
`first user = admin` and `second user = user`.

Verify the approved controlled private bootstrap flow exists and prevents a public first registrant from taking Administrator ownership.

### Phase 6 — Floorplan Pipeline
Standalone tiler success is not enough.

Verify:
Architect/API upload
→ `MapFloorplanController`
→ MongoDB metadata
→ source file on filesystem
→ tiler
→ generated tiles/archive
→ backend retrieval
→ Viewer display.

### Phase 7 — Android
APK build success is not enough.

Where the environment allows, verify Logger and Navigator:
- install/run;
- local authentication;
- Space/Floor/POI loading;
- floorplan retrieval;
- same-floor navigation;
- cross-floor navigation;
- route display;
- Logger/radiomap smoke behavior.

Standalone SMAS and legacy `clients/android/` remain out of scope.

### Phase 8 — Domain Strategy
HIGH PRIORITY.

The approved plan required a deployment-supplied canonical public origin, such as `PUBLIC_BASE_URL`.

Do not assume `anyplace.ejust.edu.eg` is the final official hostname unless university IT actually supplied it.

Inspect active runtime uses of:
- `anyplace.ejust.edu.eg`
- `map.beout.ai`
- `anyplace.cs.ucy.ac.cy`
- `ap.cs.ucy.ac.cy`
- `ap-dev.cs.ucy.ac.cy`

Verify active runtime addresses can be changed without source edits.

Check:
- backend public identity;
- deploy/build scripts;
- Viewer/Campus share URLs;
- Logger endpoint;
- Navigator endpoint;
- Android deep links;
- generated floor tile/archive URLs;
- CORS;
- proxy/TLS assumptions.

A hardcoded replacement of one domain with another does not satisfy the approved plan if deployment still requires source edits.

Explicitly inspect any value shaped like:
`http://<host>:443`

Verify whether protocol and port are correct.

Do not perform a global domain replacement.
Leave historical/license URLs alone unless they affect runtime.

### Phase 9 — End-to-End Gate
Do not treat:
`19/19 sbt tests passed`

as proof that the whole application passed end-to-end validation.

Distinguish:
- backend Scala test suite;
- whole-system recovery validation.

Verify as far as the controlled environment allows:
Campus
→ Space
→ Floor
→ Floorplan
→ POI
→ Connection
→ Navigation

Also verify required web and Android clients participate correctly where launch scope requires them.

---

## TestSprite MCP Requirement

TestSprite MCP is installed and must be used intentionally for backend/API and integration verification where it adds value.

At minimum, use TestSprite for applicable flows such as:
- `/api/version`;
- registration;
- login/authentication;
- authorization failures;
- public Space APIs;
- Floor/POI/Connection APIs when fixture data exists;
- invalid request/error behavior;
- navigation API behavior;
- regression checks for backend endpoints changed during gap fixes.

Rules:
- target only the controlled local/staging E-JUST backend;
- never test original Anyplace infrastructure;
- use disposable users/data;
- never expose secrets;
- do not change application behavior merely to satisfy a bad generated test;
- compare TestSprite failures with approved existing behavior before fixing code;
- record exactly which TestSprite tests were actually executed.

TestSprite does not replace:
- `sbt test`;
- direct HTTP smoke tests;
- MongoDB checks;
- browser/web verification;
- tiler tests;
- Android runtime tests.

---

## Fixing Rules

Only after `RECOVERY_AUDIT.md` identifies verified gaps:

1. Work phase by phase, in order.
2. Fix only gaps required by Phases 0–9.
3. Make the smallest safe change.
4. Do not add features.
5. Do not start Phase 10.
6. Do not modernize unrelated legacy code.
7. Do not upgrade major frameworks just because they are old.
8. Do not rewrite Play, Scala, MongoDB, navigation, authentication, or tiler architecture.
9. Do not globally replace domains.
10. Do not use test/local data as official E-JUST production data.
11. Never commit secrets.
12. Never expose MongoDB publicly.

After every fix:
- run the smallest relevant test;
- rerun affected backend tests;
- use TestSprite where appropriate;
- rerun the original phase validation;
- check previously verified phases for regressions.

Do not move forward while the current required gap remains unverified.

---

## External Dependencies

Do not fabricate:
- official university DNS;
- TLS certificates;
- production Google Maps credentials;
- production Android signing material;
- official university mapping data;
- university infrastructure values.

If a requirement genuinely depends on one of these, mark it:
`EXTERNAL DEPENDENCY`

Complete all code-side preparation possible without inventing the missing value.

The system must remain configurable so the real value can be supplied later without source modification.

---

## Completion Standard

The task is complete only when every Phase 0–9 is either:
- `VERIFIED COMPLETE`
or
- `EXTERNAL DEPENDENCY` where all code-side work is complete.

No phase may remain:
- `PARTIAL`
- `PLAN DEVIATION`
- `NOT VERIFIED`

without being fixed or clearly documented as an unavoidable external blocker.

---

## Final Deliverables

At the end:

1. Update `docs/recovery/RECOVERY_AUDIT.md`.
2. Update `docs/recovery/EXECUTION_LOG.md` with new fixes and evidence.
3. Keep `docs/recovery/PHASES_COMPLETED.md` unchanged as the historical record of what the previous session claimed.
4. Provide:

| Phase | Initial Audit Status | Fix Applied | Final Status | Verification |
|---|---|---|---|---|

5. List TestSprite tests actually run and their results.
6. List remaining E-JUST/IT external dependencies.
7. State explicitly:

`Phase 10 modernization was not started.`

Do not claim production deployment is complete unless production DNS, TLS, credentials, infrastructure, and deployment were actually verified.
