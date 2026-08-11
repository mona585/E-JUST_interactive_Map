# E-JUST Anyplace — Recovery Audit Instructions

## Purpose

This file is the execution contract for the next Codex session.

Use:
- `docs/recovery/RECOVERY_REPORT.md` as the approved recovery plan.
- `docs/recovery/PHASES_COMPLETED.md` as the previous Codex session's claim of what was completed.
- the actual git history, source code, configuration, runtime behavior, and tests as the final evidence.

There is NO required `EXECUTION_LOG.md`.

The next session must compare required vs implemented work, verify the real state, and fix only verified gaps.

Phase 10 modernization is OUT OF SCOPE.

---

## Read First

Before changing code, read:

- `CONTEXT.md`
- `docs/recovery/RECOVERY_REPORT.md`
- `docs/recovery/PHASES_COMPLETED.md`
- `docs/adr/0001-ejust-android-application-identity.md` if present
- `AGENTS.md` if present

Then inspect:

- current branch;
- HEAD;
- git status;
- recovery commits;
- relevant changed files;
- current configuration;
- existing tests.

Do not trust the previous completion summary blindly.

---

## Work One Phase at a Time

Start with Phase 0 only.

For the current phase:

1. Read what `RECOVERY_REPORT.md` required.
2. Read what `PHASES_COMPLETED.md` claims was done.
3. Verify the actual implementation from code, commits, configuration, runtime, and tests.
4. Classify the phase as:
   - `VERIFIED COMPLETE`
   - `PARTIAL`
   - `PLAN DEVIATION`
   - `NOT VERIFIED`
   - `EXTERNAL DEPENDENCY`
5. Fix only verified gaps.
6. Run the original phase validation.
7. Use TestSprite for backend/API/integration verification where appropriate.
8. Record the result in `docs/recovery/RECOVERY_AUDIT.md`.
9. STOP and ask before moving to the next phase.

Do not continue automatically.

---

## Mandatory Review Areas

### Phase 0 — Secrets
Verify the original issues themselves were fixed:
- tracked secret in `anyplace.service`;
- scripts printing or exposing secrets;
- exposed credentials removed/rotated where applicable;
- no real secrets in tracked files.

`.env.example` cleanup alone is not enough.

### Phase 2 — Backend and MongoDB
Verify:
- reproducible backend startup;
- selected JDK/runtime works;
- MongoDB authentication enabled;
- MongoDB bound to localhost only;
- port 27017 not public;
- Mongo config remains external;
- analytics disabled by default.

### Phase 4 — Web and Swagger
Verify:
- Architect assets load;
- Viewer assets load;
- Campus Viewer assets load;
- no recovery-blocking 404s;
- current/generated Swagger API output works, not only a static HTML page.

### Phase 5 — Administrator Bootstrap
Do not only verify:
`first user = admin`
`second user = user`

Verify the approved controlled private bootstrap exists and prevents a public first registrant from taking Administrator ownership.

### Phase 6 — Floorplan Pipeline
Standalone tiler success is not enough.

Verify:
Architect/API upload
→ `MapFloorplanController`
→ MongoDB metadata
→ filesystem
→ tiler
→ generated tiles/archive
→ backend retrieval
→ Viewer display.

### Phase 7 — Android
APK build success is not enough.

Where possible verify Logger and Navigator:
- install/run;
- authentication;
- Space/Floor/POI loading;
- floorplan retrieval;
- same-floor navigation;
- cross-floor navigation;
- route display;
- Logger/radiomap smoke behavior.

Standalone SMAS and legacy `clients/android/` remain out of scope.

### Phase 8 — Domain Strategy
HIGH PRIORITY.

The approved plan requires a deployment-supplied canonical public origin such as `PUBLIC_BASE_URL`.

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
- Logger/Navigator endpoints;
- Android deep links;
- generated floor tile/archive URLs;
- CORS;
- proxy/TLS assumptions.

A hardcoded replacement of one domain with another is a plan deviation if deployment still requires source edits.

Explicitly inspect values like:
`http://<host>:443`

and verify protocol/port correctness.

Do not perform a global domain replacement.

### Phase 9 — End-to-End Gate
Do not treat:
`19/19 sbt tests passed`

as proof of full-system recovery.

Distinguish backend tests from whole-system validation.

Verify as far as possible:
Campus
→ Space
→ Floor
→ Floorplan
→ POI
→ Connection
→ Navigation

and required web/Android client behavior.

---

## TestSprite Requirement

TestSprite MCP is installed.

Use it intentionally for backend/API and integration verification where useful, including:
- `/api/version`;
- registration;
- login/authentication;
- authorization failures;
- public Space APIs;
- Floor/POI/Connection APIs when fixture data exists;
- invalid/error requests;
- navigation APIs;
- regression tests for backend fixes.

Rules:
- test only controlled local/staging E-JUST backend;
- never target original Anyplace infrastructure;
- use disposable users/data;
- never expose secrets;
- do not change correct behavior just to satisfy a bad generated test;
- record exactly which TestSprite tests were run.

TestSprite does not replace:
- `sbt test`;
- direct HTTP smoke tests;
- MongoDB checks;
- browser/web verification;
- tiler tests;
- Android runtime tests.

---

## Fixing Rules

Only fix verified differences between the approved Phase 0–9 plan and actual implementation.

Do NOT:
- add features;
- start Phase 10;
- modernize unrelated code;
- upgrade major frameworks merely because they are old;
- rewrite Play/Scala/MongoDB/navigation/tiler architecture;
- globally replace domains;
- use test/local data as official E-JUST data;
- commit secrets;
- expose MongoDB publicly.

After each fix:
- run the smallest relevant test;
- rerun affected backend tests;
- use TestSprite where appropriate;
- rerun the phase validation;
- check for regressions.

---

## External Dependencies

Do not fabricate:
- official university DNS;
- TLS certificates;
- production Google Maps credentials;
- production Android signing material;
- official mapping data;
- university infrastructure values.

If a requirement truly depends on one of these, mark it:
`EXTERNAL DEPENDENCY`

Complete all code-side preparation possible without inventing the missing value.

---

## Audit Output

Create:

`docs/recovery/RECOVERY_AUDIT.md`

For each audited phase record:
- original requirement;
- previous completion claim;
- actual evidence;
- gap;
- fix applied, if any;
- tests;
- TestSprite results, if used;
- final status.

Keep `PHASES_COMPLETED.md` unchanged as the historical record of the previous session's claims.

---

## Completion Standard

A phase is finished only when it is:
- `VERIFIED COMPLETE`

or:
- `EXTERNAL DEPENDENCY` with all possible code-side work complete.

Then STOP and ask:

`Should I continue to Phase N+1?`

Do not start the next phase without explicit approval.

Phase 10 modernization must not be started.
