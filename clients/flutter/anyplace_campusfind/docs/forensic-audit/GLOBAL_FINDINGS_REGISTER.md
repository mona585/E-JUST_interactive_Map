# GLOBAL FINDINGS REGISTER — Forensic Audit 2026-08-24 execution

Live register maintained across phases. Historical IDs from the 2026-08
implementation review are preserved (per plan). New discoveries continue the
numbering. Status values: OPEN · FIXED (unverified) · FIXED+VERIFIED · BY-DESIGN ·
CLOSED-DUPLICATE · PENDING FIELD VALIDATION.

| ID | Sev | Type | Status | Title | Phase | Evidence class |
|---|---|---|---|---|---|---|
| DATA-001 | P1 | DATA | PENDING FIELD VALIDATION (was: fixed live, verified 2026-08 earlier) | G13 room mis-flagged as building entrance (deployment DB) | PHASE-01 | prior claim; re-verification impossible now (backend unreachable) |
| DATA-002 | P2 | DATA | PENDING FIELD VALIDATION | B7 floor 1 has no radiomap (deployment DB) | PHASE-01 | prior claim |
| DATA-003 | P2 | DATA | PENDING FIELD VALIDATION (buids statically confirmed in constants.dart) | Six Quick-Access default buildings lack floors/indoor data (deployment DB) | PHASE-01 | STATIC-PROOF (ids) + prior claim |
| DATA-004 | P2 | DATA | PENDING FIELD VALIDATION | B3/Silent Infotech empty POIs; `mona` without entrance record | PHASE-01 | prior claim |
| DATA-005 | P3 | DATA | WONTFIX/EXPECTED (schema field reserved) | `is_door` unused — false on every POI incl. door-ish types | PHASE-01 | DATA-PROOF (local) |
| DATA-006 | P3 | DATA | WONTFIX/EXPECTED (contract preserved) | Booleans persisted as strings; Boolean migration unapplied | PHASE-01 | DATA-PROOF (local) |
| DATA-007 | P3 | DATA | DEFERRED (deployment naming intent needed) | Connectors share display name "Connector" | PHASE-01 | DATA-PROOF (local) |
| DATA-008 | P3 | DESIGN | DEFERRED (latent; needs type vocabulary evidence) | `'door'` substring classifier matches "indoor/outdoor" (latent) | PHASE-01 | STATIC-PROOF poi_classification.dart:77–78 |
| DATA-009 | P2 | DATA | RESOLVED (RUNTIME VERIFIED) | Local authoritative nav graph fragmented: Theater + 5-connector chain unreachable from entrance ⇒ empty routes to those POIs | PHASE-01 | DATA-PROOF |
| DATA-010 | P3 | DATA | RESOLVED (RUNTIME VERIFIED) | Duplicate edge row (same cuid stored twice) in local edges collection | PHASE-01 | DATA-PROOF |
| DATA-011 | P1 | DATA | FIELD VALIDATION REQUIRED | Zero fingerprint/radiomap collections in reachable store ⇒ no Wi-Fi positioning coverage at all | PHASE-01 | DATA-PROOF |
| POS-001 | P2 | DESIGN | DEFERRED (needs field evidence, §17) | Scope confirmation satisfiable by doorway Wi-Fi bleed; no geometry gate | PHASE-02 | STATIC-PROOF |
| POS-002 | P3 | BUG | WONTFIX/EXPECTED (INV-8 documented tradeoff) | Sub-3-tick GPS degradation lacks PAUSED hint | PHASE-02 | STATIC+TEST-PROOF |
| POS-003 | P2 | MISSING | TEST VERIFIED | No GPS-silence watchdog; fix stays fresh forever on stream silence; consumers never age-check | PHASE-02 | STATIC-PROOF |
| INDOOR-001 | P1 | BUG | TEST VERIFIED (origin verified) | In-session building tap wipes selectedFloor/POI context; INV-4 covers route fields only | PHASE-03 | STATIC-PROOF |
| INDOOR-002 | P2 | UNKNOWN | WONTFIX (UNRECOVERABLE description) | Historical ID; description unrecoverable from surviving artifacts | PHASE-03 | UNKNOWN |
| INDOOR-003 | P3 | DESIGN | CODE FIXED (bounded pause) (NEW) | Background batch sync pause unbounded until clearSelection | PHASE-03 | STATIC-PROOF |
| OUTDOOR-001 | P1 | BUG | TEST VERIFIED (code fixed; field walk pending) (re-established) | Outdoor leg terminates at POI room coords; hybrid jumps back to entrance | PHASE-04 | STATIC-PROOF |
| OUTDOOR-002 | P2 | BUG | TEST VERIFIED (re-established) | Entrance pick first-match, no proximity/type scoring (multi-door arbitrary) | PHASE-04 | STATIC-PROOF |
| OUTDOOR-003 | P3 | DESIGN | CODE FIXED (deterministic Dijkstra) (NEW) | Dijkstra SplayTreeSet keyed on mutable dist[] — ordering/livelock hazard | PHASE-04 | STATIC-PROOF |
| OUTDOOR-004 | P3 | DESIGN | CODE FIXED (shared helper) (NEW) | Dual duplicated 100m circle containment under "polygon" names | PHASE-04 | STATIC-PROOF |
| OUTDOOR-005 | P3 | DESIGN | TEST VERIFIED (visible degradation) (NEW) | All-tier outdoor failure silently degrades to straight line marked ready | PHASE-04 | STATIC-PROOF |
| NAV-001 | P2 | DESIGN | DEFERRED (backend schema migration) | Entrance dual-encoding (flag XOR type) role ambiguity is structural | PHASE-05 | STATIC-PROOF |
| NAV-002 | P2 | BUG | TEST VERIFIED | Cross-building exit door = candidates.first, no proximity scoring | PHASE-05 | STATIC-PROOF |
| NAV-003 | P2 | BUG | TEST VERIFIED | Connector-chain fallback substitutes entrance for cross-floor target → degenerate complete loops | PHASE-05 | STATIC-PROOF |
| PREVIEW-001 | P1 | BUG | consolidated=OUTDOOR-001 (=OUTDOOR-001) | Preview carries composer terminus defect | PHASE-06 | STATIC-PROOF (alias) |
| PREVIEW-002 | P2 | BUG | consolidated=OUTDOOR-002 (=OUTDOOR-002) | Preview carries arbitrary-entrance defect | PHASE-06 | STATIC-PROOF (alias) |
| PREVIEW-003 | P3 | DESIGN | CODE FIXED (commit event added) (re-verified) | Initial route adoption lacks commit event | PHASE-06 | STATIC-PROOF |
| ACTIVE-001 | P1 | BUG | TEST VERIFIED (consequence chain verified) | In-session tap strands exit/approach detection via browsing-context dependency | PHASE-07 | STATIC-PROOF |
| ACTIVE-002 | P2 | BUG | TEST VERIFIED | Retarget commits bypass single write choke point; no commit event/revision bump | PHASE-07 | STATIC-PROOF |
| ACTIVE-003 | P2 | DESIGN | TEST VERIFIED (anchor preference) (re-verified) | Guidance anchor lacks entrance/connector preference | PHASE-07 | STATIC-PROOF |
| ACTIVE-004 | P3 | UNKNOWN | WONTFIX (UNRECOVERABLE description) | Historical ID; description unrecoverable; nearest provable asymmetry filed as STABILITY-004 | PHASE-07 | UNKNOWN |
| MAP-001 | P3 | BUG | CODE FIXED (test-verified via UI battery) | BUG-16b ineffective: heading EMA prefers raw fix over held position; comment/code mismatch | PHASE-08 | STATIC-PROOF + git history |
| API-007 | P1 | BUG | BLOCKED EXTERNAL | Default backend URL serves no API (404 across endpoints); app cannot load data out of the box | PHASE-09 | RUNTIME-PROOF |
| API-001 | P1* | DESIGN | BY-DESIGN (documented seam) | Outdoor reroute ↔ coordinate-endpoint floor cliff | PHASE-09 | STATIC-PROOF |
| API-002 | P3 | DEAD | WONTFIX/EXPECTED (informational field) | num_of_pois ignored by client | PHASE-09 | STATIC-PROOF |
| API-003 | P3 | DESIGN | WONTFIX/EXPECTED (contract preserved) | String-boolean parser tolerance load-bearing | PHASE-09 | STATIC+TEST-PROOF |
| API-004 | P2 | DESIGN | DEFERRED (needs typed backend error codes) | Error classification by message substring | PHASE-09 | STATIC-PROOF |
| API-005 | P3 | DESIGN | WONTFIX/EXPECTED (contract preserved) | Boolean migration version-skew trap | PHASE-09 | STATIC-PROOF |
| API-006 | — | — | SUPERSEDED by API-007 | Historical curl/Dart asymmetry unobservable post-retirement | PHASE-09 | RUNTIME-PROOF |
| API-008 | P3 | DESIGN | CODE FIXED + BUILD VERIFIED | App-wide cleartext traffic for HTTP OSRM tier | PHASE-09 | STATIC-PROOF |
| STABILITY-001 | P2 | BUG | TEST VERIFIED (re-verified) | StateError propagation from identifier navigation; UI awaits unguarded | PHASE-10 | STATIC-PROOF |
| STABILITY-002 | P3 | BUG | CODE FIXED (analyzer+suite) (re-verified) | _animatedMapMove .then lacks mounted guard | PHASE-10 | STATIC-PROOF |
| STABILITY-003 | P3 | DESIGN | WONTFIX/EXPECTED (test-only hook) | Unsynchronized global navigationLog hook | PHASE-10 | STATIC-PROOF |
| STABILITY-004 | P3 | DESIGN | WONTFIX/EXPECTED (benign divergence) | Heading/positioning native bridge lifecycle pattern divergence (benign today) | PHASE-10 | STATIC-PROOF |
| LOGGER-001 | P2 | MISSING | CODE FIXED (status line rendered) | In-app radiomap-health indicator absent though coverage state known client-side | PHASE-11 | STATIC-PROOF |
| X-1 | P1 | BUG (cluster) | TEST VERIFIED (via INDOOR/ACTIVE fixes) (all legs verified) | Tap-strand compounding: INDOOR-001 × floor-scoped rendering × exit-context loss | PHASE-12 | STATIC-PROOF |
| X-2 | P2 | DESIGN | TEST VERIFIED (anchor semantics aligned) (re-verified) | Guidance-vs-composer indoor-leg root ownership conflict (scored entrance vs nearest POI) | PHASE-12 | STATIC-PROOF |
| X-3 | P3 | DESIGN | CODE FIXED (=PREVIEW-003 commit event) | Initial-commit observability blind spot | PHASE-12 | STATIC-PROOF |
| X-4 | P2 | MISSING | TEST VERIFIED (via POS-003) | Fix freshness unowned at consumption time (split POS-003 × consumers) | PHASE-12 | STATIC-PROOF |

(Entries for POS/INDOOR/OUTDOOR/NAV/PREVIEW/ACTIVE/MAP/API/STABILITY/LOGGER/X are
appended by their phases.)
