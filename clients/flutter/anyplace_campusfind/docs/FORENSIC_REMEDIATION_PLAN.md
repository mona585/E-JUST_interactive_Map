# FORENSIC REMEDIATION PLAN

Baseline: HEAD `0da8033a`, clean tracked tree (audit docs untracked).
Source findings: `docs/forensic-audit/GLOBAL_FINDINGS_REGISTER.md` (50 rows) +
phase reports of the 2026-08-24 execution.
Regression baseline: 272/272 green.

Classification legend: A code bug→FIX · B data/config→FIX if repo/system-owned ·
C external dependency→BLOCKED · D field validation→cannot claim fixed without
field evidence · E design→decide if change required · F duplicate/cluster→
consolidate · G expected/not-a-bug→close.

## Matrix

| Finding | Sev | Class | Root cause | Owner layer | Dependency | Fix required? | Fix strategy | Validation | Status |
|---|---|---|---|---|---|---|---|---|---|
| API-007 | P1 | C | UCY production API retired (404); no authoritative endpoint exists in-repo to switch to (AGENTS D-07 forbids inventing host) | Deployment/config | none | NO fake fix; config path already exists (`--dart-define=SERVER_URL`) | Document BLOCKED EXTERNAL + exact unblock procedure | Live probe (already captured 404) | BLOCKED EXTERNAL |
| DATA-011 | P1 | D | No fingerprint collection ever run on reachable store | External logger process | logger app | NO (code cannot create fingerprints) | FIELD DATA REQUIRED + procedure doc | Field collection | FIELD VALIDATION REQUIRED |
| INDOOR-001 | P1 | A | Browsing selectSpace wipes floor/POI context; INV-4 covers route fields only | SpaceProvider/Controller ownership | ACTIVE-001 (same fix) | YES | Session-owned destination geometry cache in controller (ownership fix, not restore-after-destroy) | New regression test + browsing suite | OPEN |
| OUTDOOR-001 | P1 | A | Cascades compose outdoor leg to room coords then concatenate entrance-rooted indoor leg | SpaceProvider cascade | ACTIVE-002 refactor (same code region) | YES | Outdoor terminus = selected entrance; explicit fail when no entrance; building-flow drops reversed indoor tail | New composition regression tests | OPEN |
| ACTIVE-001 | P1 | A | Exit/approach reads browsing context that INDOOR-001 wipe destroys | NavigationController | INDOOR-001 | YES | Session geometry cache (bounds/entrances/centroid) captured for destination building; survives foreign selection | New regression test | OPEN |
| X-1 | P1 | F | Cluster = INDOOR-001×visibility×exit-context | — | INDOOR-001+ACTIVE-001 | Consolidated | Resolved by those two fixes | Their tests | OPEN |
| DATA-001..004 | P1/P2 | C/D | Deployment dataset unreachable (API-007) + field collection gaps | Deployment DB / logger | API-007 | NO (unreachable; cannot verify or edit) | Document BLOCKED EXTERNAL / FIELD REQUIRED | Restore backend first | BLOCKED EXTERNAL |
| ACTIVE-002 | P2 | A | Retarget commits route via legacy cascade store-write, bypassing choke point/event/revision | Controller+SpaceProvider | OUTDOOR-001 refactor (same function split) | YES | Split cascade into compute+commit; retarget adopts candidate through choke point w/ ROUTE_COMMIT + revision bump | New retarget event/fencing test + retarget_test | OPEN |
| NAV-002 | P2 | A | Exit door = candidates.first, no proximity scoring | CrossBuildingRouter | none | YES | Nearest-to-user deterministic pick among ground-preferred candidates | New test via @visibleForTesting selector | OPEN |
| NAV-003 | P2 | A | `_routeViaConnectors` substitutes entrance when target puid unresolved ⇒ complete-marked loop | CrossBuildingRouter | none | YES | Unresolvable target ⇒ return null ⇒ honest incomplete fallback | New test | OPEN |
| POS-003 | P2 | A | GPS freshness enforced only at sample arrival; silence never degrades | LocationProvider | X-4 closure | YES | Generation-guarded watchdog timer converts silence age into degraded ticks/demotion; injectable evaluation for tests | New synthetic-time test | OPEN |
| X-4 | P2 | F | Split ownership POS-003 × consumers | — | POS-003 | Consolidated | Consumers already honor gpsDegraded/status; watchdog supplies signal | POS-003 test | OPEN |
| OUTDOOR-002 | P2 | A(+F PREVIEW-002) | Cascade entrance pick = firstOrNull, no preference | SpaceProvider cascade | OUTDOOR-001 (same functions) | YES | Deterministic nearest-entrance-to-user among flag/type matches (cross-building scorer untouched) | Composition tests assert chosen anchor | OPEN |
| ACTIVE-003 | P2 | A(E resolved→change warranted per §14: arbitrary nearest POI origin forbidden) | Guidance anchor = nearest any-type POI | SpaceProvider.requestIndoorRouteForSession | none | YES | Prefer connector/entrance/stair-elevator anchors on confirmed scope; deterministic; fallback nearest-any only if class empty | Extend handoff_guidance_test | OPEN |
| X-2 | P2 | F | Ownership conflict composer(entrance-rooted) vs guidance(nearest-POI-rooted) | — | ACTIVE-003 (+OUTDOOR-001 makes composer root correct) | Consolidated | Anchor preference aligns guidance root semantics; composer terminus fix removes discontinuity source | handoff_guidance_test | OPEN |
| API-004 | P2 | E | Message-substring error taxonomy | Loaders/cascades + server copy | typed backend codes | DEFERRED | Needs backend error-code contract; current status-code-first checks already gate behavior safely | — | DEFERRED (reason logged) |
| STABILITY-001 | P2 | A | firstWhere/orElse throw escapes unguarded async UI closures | SpaceProvider | none | YES | Return false + debugPrint instead of StateError (typed-failure contract) | Extend quick_access/navigation-ui tests | OPEN |
| LOGGER-001 | P2 | A | RadioMapStatus/error never surfaced in UI | BuildingDetailCard | none | YES | Minimal status/error text line using existing card text styles (verified zero consumers today) | Widget test asserting surfaced text | OPEN |
| MAP-001 | P3 | A | Heading source prefers raw location over displayed held position | MapScreen | none | YES | headingSource = display (BUG-16b documented intent) | navigation_ui display-rule extension | OPEN |
| POS-002 | P3 | G | Sub-3-tick degradation shows stale dot sans PAUSED | LocationProvider semantics | INV-8 tradeoff | NO — documented design tradeoff; changing thresholds violates §17 evidence rule | WONTFIX rationale | — | WONTFIX / EXPECTED |
| PREVIEW-003/X-3 | P3 | A | Initial adoption lacks commit event | Controller | none | YES | Emit ROUTE_COMMIT source=preview-seed at seed | navigationLog capture test | OPEN |
| INDOOR-003 | P3 | A | _batchPaused unbounded until clearSelection | SpaceProvider batch sync | none | YES | Bounded continuous pause (auto-resume after cap) keeping priority semantics | Unit-testable wait-loop extraction or behavioral test | OPEN |
| OUTDOOR-003 | P3 | A | SplayTreeSet keyed on mutable dist[] (ordering/livelock hazard) | CustomRouteGraph | none | YES | Deterministic array-scan Dijkstra (graph scale tiny); equivalence vs existing suite | custom_routes suites green | OPEN |
| OUTDOOR-004 | P3 | A | Duplicate circle-containment under polygon names | SpaceProvider | none | YES | Single shared distance helper; both call it | Existing suites | OPEN |
| OUTDOOR-005 | P3 | A | All-tier failure silently ready straight-line | SpaceProvider cascades | none | YES | Surface degradation message on fallback tail (status stays ready) | Composition test asserts message | OPEN |
| STABILITY-002 | P3 | A | `.then` without mounted guard | MapScreen | none | YES | Add mounted guard | analyze + existing widget tests | OPEN |
| DATA-010 | P3 | B | Exact-duplicate edge row in reachable local store | Local Mongo (project dev store) | DATA-009 measurement | YES (dedupe only; no fabrication) | Delete verbatim-duplicate row; recount | Re-run BFS/analysis probe | OPEN |
| DATA-009 | P2 | B/D | Graph fragmented (Theater chain isolated from entrance component) | Local Mongo topology | measure gap first | CONDITIONAL | If min inter-component gap ≈ existing edge lengths ⇒ add single bridging edge mirroring cuid/weight schema; else FIELD DATA REQUIRED | BFS reachability probe post-fix | OPEN (measure first) |
| DATA-005 | P3 | G | is_door false everywhere | Schema future-proofing | — | NO | EXPECTED (field reserved) | — | WONTFIX / EXPECTED |
| DATA-006/API-003/API-005 | P3 | G | String booleans + migration skew | Contract preservation §19 | — | NO | EXPECTED preserve contract | — | WONTFIX / EXPECTED |
| DATA-007 | P3 | B | Connector name collisions | Deployment DB naming | — | DEFERRED | Display-only; renaming needs owner intent | — | DEFERRED |
| DATA-008 | P3 | E | 'door' substring latent hazard | poi_classification | — | DEFERRED | Latent (no triggering data); tighten only with type-vocabulary evidence | — | DEFERRED |
| POS-001 | P2 | E | Confirmed≠inside doorway bleed | Arbiter/nav boundary | field evidence | DEFERRED | Downstream neutralized post-DATA-001-era fix; threshold/boundary change needs field data (§17) | — | DEFERRED |
| NAV-001 | P2 | E | Entrance dual encoding ambiguity | Data model | schema migration | DEFERRED | Structural; requires backend schema work | — | DEFERRED |
| API-001 | P1* | G | Outdoor reroute↔coordinate-endpoint cliff | Documented seam | — | NO | BY-DESIGN (BUG-12 honesty choice) | — | EXPECTED (BY-DESIGN) |
| API-002 | P3 | G | num_of_pois ignored | Client parser | — | NO | Informational field only | — | WONTFIX / EXPECTED |
| API-006 | — | — | Historical curl asymmetry | — | — | NO | Superseded by API-007 | — | CLOSED-SUPERSEDED |
| API-008 | P3 | A | App-wide cleartext for OSRM HTTP tier | Manifest/network config | Android build verify (SDK present ✓) | YES | Scoped network_security_config allowing cleartext only for router.project-osrm.org; drop global flag | flutter build apk --debug | OPEN |
| STABILITY-003 | P3 | G | Global test log hook unsynchronized | Test infra | — | NO | Test-only by contract | — | WONTFIX / EXPECTED |
| STABILITY-004 | P3 | G | Bridge lifecycle pattern divergence (benign) | Native bridges | — | NO | Benign under channel replacement semantics | analysis documented PHASE-10 | WONTFIX / EXPECTED |
| INDOOR-002 | P2 | — | Description unrecoverable | — | — | Cannot fix unknown | CLOSED-UNRECOVERABLE (kept in register) | — | WONTFIX (UNRECOVERABLE) |
| ACTIVE-004 | P3 | — | Description unrecoverable | — | — | Cannot fix unknown | CLOSED-UNRECOVERABLE | — | WONTFIX (UNRECOVERABLE) |
| PREVIEW-001/002 | P1/P2 | F | Aliases of OUTDOOR-001/002 | — | same | Consolidate | — | — | consolidated |

## Dependency-ordered remediation clusters

| # | Cluster | Findings | Rationale |
|---|---|---|---|
| 1 | Composition core rewrite (terminus + entrance preference + compute/commit split) | OUTDOOR-001, OUTDOOR-002, PREVIEW-001/002, ACTIVE-002, OUTDOOR-005 | Same functions; choke-point split is prerequisite for honest retarget adoption and terminus fix lands in the extracted composer |
| 2 | Cross-building selectors + guidance anchor | NAV-002, NAV-003, ACTIVE-003, X-2 | Depends on #1's correct composer roots |
| 3 | Session-owned context ownership | INDOOR-001, ACTIVE-001, X-1 | Independent of #1/#2 but largest behavioral change; sequenced after composition correctness so tests observe stable routes |
| 4 | Positioning watchdog | POS-003, X-4 | Independent |
| 5 | Rendering heading source | MAP-001 | After #3 stabilizes held-position flows |
| 6 | Stability/error propagation | STABILITY-001, STABILITY-002, PREVIEW-003 | Small, independent |
| 7 | P3 engineering batch | OUTDOOR-003/004, INDOOR-003, LOGGER-001, KmzLoader comment | Quality pass |
| 8 | Local data repair (measure→dedupe→conditional bridge) | DATA-010, DATA-009 | Requires measurement step before deciding fix vs field |
| 9 | Android scoped cleartext | API-008 | Verified via debug APK build |
| 10 | Documentation closeout | register statuses, remediation log, final report, analyze, full suite | Last |

Explicitly NOT fixed (documented): API-007 (external), DATA-001..004/011
(external/field), POS-001/NAV-001/API-004/DATA-007/DATA-008 (deferred w/
reasons), POS-002/API-001/002/003/005/STABILITY-003/004 (expected/wontfix),
INDOOR-002/ACTIVE-004 (unrecoverable content).

## Non-negotiables honored

§12 case semantics, §13 terminus rules (fail-explicit over invented anchors),
§14 indoor-origin determinism (ACTIVE-003 anchor classes), §15 ownership fix
(not restore-after-destroy), §16 single route-adoption choke point preserved,
§17 arbiter gates untouched, §18 rendering stays projection.
