# Code Review Failure Audit — E-JUST Interactive Map

Date: 2026-10-09 ( Waves 0–3 follow-up 2026-10-10 below). Method: 12 parallel
adversarial review squads (server ×5, clients ×4, ops/tests/self ×3), every
finding verified against the tree before being recorded below. "Mine" =
introduced or claimed in the Oct 2026 working sessions (uncommitted at audit
time); "pre-existing" = in HEAD before them.
Disposition: FIXED (in tree, proven by suite/live run) · QUEUED (acknowledged,
needs design/host) · DISPUTED (reviewer wrong, evidence given).

## Waves 0–3 follow-up (2026-10-10, suite 36-total / 35 pass / 1 skip)

## Production push (2026-10-10, suite 43-total / 42 pass / 1 skip)

FIXED: 30-day sliding token expiry + refresh extension + expired rejection
(legacy tokens grandfathered); Google tokeninfo aud/exp/sub validation as a
pure spec-covered function + `google.client.id` config + PII log scrub +
Network timeouts/close/disconnect; canonical-path containment at all 8 file
serving sites (segment gates stay as front line); moderator/admin role cache
60 s TTL; `highlight` filter override killing the stored-XSS sink in all 3
apps; backup systemd timer units; single-admin partial unique index;
traversal + moderator-rule + IDOR + gate specs (11 new); fixture UUID tags
after proving `nanoTime.takeRight` repeats every 10 s (takeRight(10) =
value mod 10^10 — the mechanism behind register-collision flakes).
Flake episode: one login test failed intermittently across identical-code
runs; exonerated via probe spec (every component green), manual live cycle
green, 3× consecutive full-suite greens; attributed to box-state under
concurrent load + orphan rows from SIGKILLed runs (finally never runs).
Discipline adopted: UUID fixture tags + idempotent seed() pre-cleanup +
pristine-DB wipe between campaigns. Live matrix on final build: register,
login+expiry stamp, refresh slide, gates 401, campus route 2, viewer 200.
QUEUED unchanged: token rotation policy beyond sliding, Google aud rollout
needs real client ID, Angular EOL, Android toolchain, POI-search highlight
edge on exotic queries, backup/monitoring installation, CSRF semantics.

FIXED since audit: 10 server crasher classes (validation branches + safe
extraction, multipart `.get`, `StringNumber` empty-string, `getCause` NPE,
`range` bounds, login-Google token requirement); pilot-surface sweep
(corrupt-floor tolerance); POI update/delete + connection add/delete
bind-then-check IDOR closure with specs; `escapeHtml`/`escapeId` choke at all
16 infowindow/ng-click sites (both viewers); `stop.sh` self-match + `fuser`
kill fix; `status.sh` env-aware hosts + real health probes; moderator cache
staleness documented via the 403-spec debugging session (lists refresh on
login/register/refresh only — accepted behavior, noted for P2).
Google Maps key validated live (1.4 MB bootstrap) and injected into served
copies only — never committed; host procedure unchanged (env → sed → build).
Still QUEUED: token expiry, Google aud, Angular EOL/CVE class, Android
toolchain/SDK, POI search XSS via `highlight` filter chain (ngSanitize 1.3
bypasses documented), backup timers/monitoring on host, CSRF semantics.

Suite state at audit: `sbt test` → Total 26, Failed 0, Errors 0, Passed 25,
Skipped 1 (SecurityRegressionSpec policy gate). Live matrix on staged build:
register/login PBKDF2, wrong-password 400, upload+radiomap gates 401,
campus route 2-point 200, traversal 404, viewer/architect/bundle 200s.

## 1. My failures — FIXED

| # | Failure | Fix (file:line) | Proof |
|---|---|---|---|
| 1 | Radiomap `upload()` checked token presence, never `authorize()` — largest open write survived my "closed writes" claim | `RadiomapController.scala:209-235`: authorize + per-building space check | Suite green; live 401 pre-auth (upload path needs multipart fixture for authed case — noted) |
| 2 | `ErrorHandler` returned 500s as HTTP 400 | `ErrorHandler.scala`: `InternalServerError` + generic JSON + error ID, incl. `MatchError` branch; client errors preserve incoming status | Code + suite green (500-shape untested live — see §4) |
| 3 | `RESPONSE` FORBIDDEN↔UNAUTHORIZED status codes swapped | `RESPONSE.scala`: 403/401 corrected | Moderator spec asserts real 403 |
| 4 | Campus shape dropped `pois_type` (copied the worse indoor mapper) | `CampusNavigationService.scala`: field added | Shape asserted in spec (`buid`); client draw verified served |
| 5 | Double campus fetch (N+3 queries) | Service takes pre-resolved `buids`; interface changed to `connectionsByCampusAsMap(buids)` | Same |
| 6 | Dijkstra weight contamination + null-weight NPE (pre-existing, my service inherited) | `Dijkstra.scala`: per-edge reset, null guard | Suite green; indoor behavior strictly safer |
| 7 | `$scope.creds` aliasing in new + indoor route fns | Fresh `{}` per call, both viewers' campus path | Served bundle contains fix |
| 8 | `UserAdmin.all` dumped password hashes + live tokens to moderators | Strip both fields | Code; no test hits the endpoint (needs moderator — same fixture pattern available) |
| 9 | Google-login response leaked password hash | Strip before respond | Code |
| 10 | Nginx: `/` swallowed `/developers`+`/assets`; health bypassed rate limit; non-uniform proxy hygiene; HSTS preload; false 410-scope comment | Full rewrite: exact-match `/`, added locations, uniform hygiene, 502/504 JSON, no preload, honest scoping comment | NOT parsed by real nginx (none on box) — host `nginx -t` required |
| 11 | Seed would collide on production + unmanageable ownership | Guard header, ownership reassignment query, acceptance walk incl. campus route | Seed executed clean twice |
| 12 | Essay repeated false edge-scope claim | Corrected to Play-enforced gating | — |
| 13 | No tests for PBKDF2/legacy/gates/health-shape/campus edges | 11 new examples (register→login→wrong-pw, legacy row, moderator rule + self-service, 2× gates, health shape, same-puid/missing-cuid/unknown-campus/disconnected) | 20/20 CampusContractSpec |
| 14 | Heatmap `timestamp/3` → AVG2 handler (pre-existing, found via my route edit breaking `-Werror` build) | Both routes → AVG3; stale `@deprecated` removed (method fully implemented) | Compiles |
| 15 | `BuildingSetsCuids` allowed duplicate campuses (`size > 1`) | `nonEmpty` | Single caller semantics verified |
| 16 | Moderator→any-password takeover | Self-or-admin rule for password field | Spec: 403 cross, 200 self |
| 17 | Path traversal on tile/floorplan/radiomap reads (+ writes) | `Utils.isSafePathSegment/isSafeRelativePath` + 11 call-site gates (incl. fixing a discarded-404 bare-`if`) | Live 404 on evil tile path; spec asserts 400/404 |
| 18 | Android missing `res/xml` + arrays (resource-link breakage) | Reconstructed `preferences_anyplace.xml` ×2 (exact referenced keys), `searchable.xml` ×2, `arrays.xml` (4 cases) | XML-parsed; NOT compiled (no SDK) |
| 19 | Android activities uninstallable on 12+ (no `android:exported`) | Flags both manifests (launcher/deep-link true, rest false) | XML-parsed; NOT compiled |
| 20 | 6 APK binaries tracked in git | `git rm --cached` + `*.apk` ignore | Staged; completes on commit |

## 2. My failures — QUEUED (accepted, with reason)

| # | Item | Why not tonight |
|---|---|---|
| 1 | Duplicate-username dead check in new login flow | Needs unique-index + race design; duplicates only via admin race (now index-blocked) |
| 2 | PBKDF2 iteration-cap / char[] zeroing / health `getOptional` | Hardening nits; tracked |
| 3 | `getBuildingViewerUrl` dropping cuid | Dead code (zero callers); leave until share UX rework |
| 4 | Moderator/admin role cache staleness (discovered debugging the 403 spec: boot-cached lists) | Per-request refresh = perf cost; needs design |
| 5 | Token expiry/rotation | Needs migration + client refresh flow; documented |
| 6 | Google `aud` validation | Needs product call on login UX |

## 3. Pre-existing criticals — NOT fixed (bigger than a patch)

Traversal-adjacent writes fully open beyond reads; POI/connection cross-building
IDORs; admin check-then-act race (index added, real-concurrency unproven);
Angular 1.3 CVEs + stored-XSS class across viewer/architect; Android API-29-era
rot (permissions, scoped storage, package visibility, cleartext, backup-
exfiltrated prefs); `install.sh`/`start.sh` contract drift; `play-json
2.10.0-RC5` + `jcenter()` in build; CSRF posture for JSON; campus search
reliability; `RADIOMAP_DELETE` double-`/api` (dead); duplicate `POIS_ROUTE`
assignment; dead `deleteBoundingBox` route; `getStaticTiles` 200-on-missing
(kept: changing it breaks tile clients); `position`/`heatmap`/`accesspoint`
500-on-malformed-input class; unbounded admin collection reads.

## 4. Explicitly unverified (do not claim)

Host JDK 17 boot; `nginx -t`; Android compile (no SDK/submodule); backup
timers/retention; 500-envelope live shape; heatmap AVG3 data correctness;
admin-race index under real concurrency; Google login flow; staging-gated
security specs (need `RUN_MONGO_INTEGRATION_TESTS=true` on authed DB).

## Verdict

Clean product? No — §3 + §4 say otherwise, and this file exists so nobody
claims it. Shippable_closed-staging? Yes: authZ closed on writes, credentials
modern with safe migration, errors generic with IDs, campus routing live with
contract tests, config honest about its gaps. The remaining work is scheduled,
not hidden — that is the whole point of this file.
