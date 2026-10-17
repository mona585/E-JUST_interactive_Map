# FORENSIC AUDIT — MASTER REPORT

Anyplace CampusFind (`clients/flutter/anyplace_campusfind`)
Execution date: **2026-08-24**. Methodology: `docs/FORENSIC_AUDIT_PLAN.md`.
Phase reports (this execution): `docs/forensic-audit/PHASE-01..12-*.md`.
Ledger: `docs/FORENSIC_AUDIT_OUT_OF_SCOPE.md`. Register:
`docs/forensic-audit/GLOBAL_FINDINGS_REGISTER.md`.

This report reflects ONLY what this execution established; prior reports were
treated as claims. Where the prior audit's evidence could not be reproduced,
claims are explicitly downgraded to PENDING FIELD VALIDATION rather than
inherited.

---

## 1. Executive summary

The navigation stack's engineering core is real and largely proven: single
route store with fenced write-through, session-identity fencing on every async
continuation, an explicit 10-state machine with edge table, evidence-gated
positioning and arrival, never-throw total teardown, and a cross-building
composer whose healthy path anchors indoor legs at an OSRM-scored entrance.
272 automated tests pass as of this execution.

This execution also established three things the prior record did not:

1. **The default backend is dead** (API-007, RUNTIME-PROOF): `ap.cs.ucy.ac.cy`
   serves no API anymore — out of the box the app cannot load buildings,
   routes, or radiomaps. Every deployment-data claim of the prior audit is now
   unverifiable from here.
2. **The reachable data store is damaged** (DATA-PROOF): the local
   authoritative Mongo has a fragmented navigation graph (Theater + a connector
   chain unreachable from the entrance ⇒ empty routes), one duplicate edge, and
   zero radiomap coverage anywhere.
3. **Several correctness defects at composition/selection level are confirmed
   by code reading** that tests do not cover: outdoor legs terminating inside
   rooms (OUTDOOR-001, P1), in-session browsing taps stranding exit detection
   (INDOOR-001→ACTIVE-001/X-1, P1), unscored exit doors (NAV-002), degenerate
   cross-floor connector loops (NAV-003), and a retarget write-path that
   bypasses the declared single choke point (ACTIVE-002).

Overall status: **PARTIAL** — proven-correct machinery on clean data, blocked
in production configuration by API-007, and carrying open P1/P2 composition
and integration defects.

## 2. Overall architecture

Flutter client + native Kotlin positioning + Scala/Play + MongoDB backend.
Single `SpaceProvider` store with per-resource request-id fencing; delegating
controller getters; unified arbiter (`LocationProvider`) owning `currentFix`;
native LRU KNN engine (≤4 resident maps) behind MethodChannel/EventChannel;
three-tier outdoor composer (KMZ graph → hybrid snap → OSRM splice → straight
line); segment-typed cross-building composer; server Dijkstra over POI+edge
graph; floors derived from floorplans collection.

## 3. Phase-by-phase verdicts

| # | Phase | Verdict |
|---|---|---|
| 01 | Data integrity | PARTIAL (reachable store: graph fragmented DATA-009, dup edge DATA-010, zero radiomaps DATA-011; deployment claims PENDING FIELD VALIDATION) |
| 02 | Positioning | PASS (static/test) — PENDING FIELD VALIDATION for accuracy/cadence; POS-003 open |
| 03 | Indoor map | PARTIAL (INDOOR-001 P1 selection wipe; loaders/fencing proven) |
| 04 | Outdoor | PARTIAL (OUTDOOR-001 P1 terminus; OUTDOOR-002 door pick; geometry stack itself solid) |
| 05 | Navigation | PARTIAL (composer honesty flags proven; cascade tails defective; NAV-002/003 new) |
| 06 | Route Here | PASS (pipeline mechanics) — content bounded by composer defects; PREVIEW-003 open |
| 07 | Active navigation | PARTIAL (session machinery proven ×69 tests; ACTIVE-001/002 open; ACTIVE-004 content lost) |
| 08 | Map rendering | PASS (MAP-001 P3 recorded; prior BUG-16b claim corrected by this execution) |
| 09 | API/backend | PARTIAL (API-007 P1 dead default endpoint; contract parity statically proven; live re-verification impossible) |
| 10 | Stability | PASS (no P0 crash path; STABILITY-001 P2 error propagation open) |
| 11 | Logger | OUT OF SCOPE / BLOCKED (intentional separation; LOGGER-001 missing health indicator) |
| 12 | Cross-feature | PARTIAL (X-1..X-4 boundary defects documented; ownership map verified) |

## 4. Feature-by-feature verdict

| Feature | Verdict |
|---|---|
| Building/space browsing & search | PASS (static+test) |
| Floor/RadioMap/Floorplan/POI loading | PASS (fencing proven) / field pending |
| Wi-Fi indoor positioning engine | PASS (static/test) — PENDING FIELD VALIDATION; blocked by zero radiomap data |
| GPS positioning & gating | PASS (static/test) — POS-002/003 open |
| Outdoor routing (KMZ/OSRM) | PASS for raw paths; PARTIAL composed tails (OUTDOOR-001) |
| Cross-building journeys | PARTIAL (scored entrance proven; exit door NAV-002; connector-loop NAV-003) |
| Route Here preview | PASS mechanics / PARTIAL content |
| Active navigation session | PARTIAL (ACTIVE-001/002) |
| Arrival detection | PASS (evidence-gated, stable anchor) |
| Rendering & camera | PASS (MAP-001 P3) |
| Teardown/lifecycle | PASS (stress-proven) |
| Logger/data collection | OUT OF SCOPE (LOGGER-001 UX gap) |

## 5. Proven-correct components (do not touch casually)

Arbiter internals and ingestion gates (location_provider.dart:245–603);
identity-safe native listener clear (PositioningEngine.kt:63–69); LRU≤4 atomic
upsert/evict (Engine:80–161); WKNN k=4 localization (KnnLocalizer.kt); scanner
event-driven lifecycle (WifiScanner.kt); state machine + dynamic edges
(navigation_state_model.dart); session fencing `_isCurrent` + all await sites;
never-throw `terminateNavigation`; KMZ graph + OSRM splice tiers
(54 green tests vs real asset); cross-building scored entrance selection
(OSRM cost+bearing); partial-honesty flags (BUG-14); truncation guard;
INV-7 identity-free outdoor points; floor-transition stage machine with
phantom-boundary immunity; arrival anchor stability + evidence gates;
`fromSegments`/`hybrid` projection rules; rendering purity + visibility rules +
span-zoom table (BUG-10); camera coalescing + programmatic-tail (BUG-11);
floorplan overlay generation fencing; Quick Access buid-exact seeding;
Dijkstra core incl. isolated-node semantics (server + client KMZ).

## 6. Confirmed bugs (code)

| ID | Sev | One-line | Origin phase |
|---|---|---|---|
| API-007 | P1 | Default backend serves no API (404 everywhere) | 09 |
| INDOOR-001 | P1 | In-session building tap wipes floor/POI context (INV-4 gap) | 03 |
| OUTDOOR-001 | P1 | Outdoor leg terminates at room coords; hybrid jumps back to entrance (+reversed loop variant S7) | 04/05 |
| ACTIVE-001 | P1 | Same tap strands exit/approach detection (X-1 cluster) | 07 |
| POS-002 | P3 | Sub-3-tick GPS degradation lacks PAUSED hint | 02 |
| NAV-002 | P2 | Exit door = candidates.first (no scoring) | 05 |
| NAV-003 | P2 | Connector-chain fallback substitutes entrance for cross-floor targets ⇒ complete-marked loops | 05 |
| ACTIVE-002 | P2 | Retarget commits bypass single write choke point; no commit event/revision bump | 07 |
| STABILITY-001 | P2 | StateError propagation from identifier navigation (UI awaits unguarded) | 10 |
| MAP-001 | P3 | BUG-16b ineffective (heading consumes raw fix over held position) | 08 |
| STABILITY-002 | P3 | `.then` without mounted guard in `_animatedMapMove` | 10 |

## 7. Data defects

| ID | Sev | One-line | Status |
|---|---|---|---|
| DATA-001 | P1 | G13 entrance mis-flag (deployment DB) | PENDING FIELD VALIDATION |
| DATA-002 | P2 | B7/F1 radiomap absent (deployment DB) | PENDING FIELD VALIDATION |
| DATA-003 | P2 | Six QA-default buildings floorless (deployment DB; buids hardcoded constants.dart:46–77) | STATIC half proven |
| DATA-004 | P2 | B3/Silent Infotech empty POIs; mona entrance-less | PENDING FIELD VALIDATION |
| DATA-009 | P2 | Reachable nav graph fragmented (10/16 reachable from entrance; Theater isolated) | OPEN (DATA-PROOF) |
| DATA-011 | P1 | Zero fingerprint/radiomap collections in reachable store | OPEN (DATA-PROOF) |
| DATA-005/006/007/010 | P3 | `is_door` unused · string booleans · "Connector" name collisions · duplicate edge row | OPEN (DATA-PROOF) |

## 8. Design issues

POS-001 (confirmed≠inside), NAV-001 (entrance dual encoding), OUTDOOR-003
(Dijkstra mutable-key ordering hazard), OUTDOOR-004 (dual circle-containment),
OUTDOOR-005 (silent straight-line ready), API-001 (reroute↔coordinate-endpoint
floor cliff, by-design), API-004 (message-substring error taxonomy), API-008
(app-wide cleartext), STABILITY-003/004 (log hook; bridge pattern divergence),
PREVIEW-003/X-3 (initial-commit observability), ACTIVE-003/X-2 (guidance anchor
ownership).

## 9. Missing functionality

POS-003/X-4 (GPS-silence watchdog / freshness ownership), LOGGER-001 (radiomap
health indicator), INDOOR-003 (batch-sync idle resume). Turn-by-turn maneuvers
and foreground service remain documented non-goals.

## 10. Runtime unknowns

All items in §16 matrix below; plus historical lost descriptions INDOOR-002 /
ACTIVE-004 (UNKNOWN-content IDs retained for continuity).

## 11. Cross-feature defects

X-1 (P1 cluster: tap-wipe×visibility×exit-context — all legs independently
verified), X-2 (P2 guidance-vs-composer root ownership), X-3 (=PREVIEW-003),
X-4 (NEW P2 freshness unowned at consumption). Compensation patterns: INV-4
partial masking of INDOOR-001; guidance swap masking outdoor tails;
LRU-residency absorbing selection resets; server argmin projection would mask
empty entrance pools indoors (documented, not relied upon).

## 12. Global findings register

See `docs/forensic-audit/GLOBAL_FINDINGS_REGISTER.md` (live table, 44 entries:
historical IDs preserved; aliases PREVIEW-001=OUTDOOR-001,
PREVIEW-002=OUTDOOR-002, X-3=PREVIEW-003; content-lost IDs INDOOR-002,
ACTIVE-004 marked UNKNOWN; superseded API-006 folded into API-007).

## 13. Severity distribution

Unique defects (aliases counted once):

- **P0: 0**
- **P1: 7** — API-007, DATA-011, INDOOR-001, OUTDOOR-001, ACTIVE-001,
  DATA-001 (pending field), X-1 (compounding cluster, distinct from its legs)
- **P2: 19** — DATA-002/003/004 (pending field), DATA-009, POS-001, POS-003,
  OUTDOOR-002, NAV-001/002/003, ACTIVE-002/003, API-004, STABILITY-001,
  LOGGER-001, X-2, X-4, plus content-lost INDOOR-002/ACTIVE-004
  (severity inherited from register, content UNKNOWN)
- **P3: 19** — DATA-005/006/007/008/010, POS-002, INDOOR-003,
  OUTDOOR-003/004/005, MAP-001, API-002/003/005/008, STABILITY-002/003/004,
  X-3

Register bookkeeping: 50 rows total = 45 unique defects (7+19+19) + API-001
(P1-severity BY-DESIGN seam, not a defect) + 3 alias rows
(PREVIEW-001=OUTDOOR-001, PREVIEW-002=OUTDOOR-002, PREVIEW-003=X-3)
+ 1 superseded row (API-006, folded into API-007).

## 14. Dependency/compensation risks

- Removing the guidance swap (X-2 fix) will EXPOSE outdoor tail damage
  (OUTDOOR-001) to users unless the terminus substitution lands first.
- Fixing INDOOR-001 without an exit-context owner will leave ACTIVE-001's
  geometry reads fragile; consider session-owned destination geometry.
- API-007 remediation unblocks every deferred data validation; until then no
  deployment-data claim can be upgraded regardless of client fixes.
- LRU residency currently shields positioning from selection wipes; any future
  "clear on exit" policy must preserve that decoupling.

## 15. Recommended remediation order (NOT implemented)

1. **API-007** — point `SERVER_URL` default/build config at a live deployment
   (or restore one); everything else data-shaped stays frozen until this lands.
2. **DATA sweep of the authoritative store** — repair fragmented graph
   (DATA-009), dedupe edge (DATA-010), collect radiomaps via logger
   (DATA-011/DATA-002), verify entrance flags fleet-wide (DATA-001 class).
3. **OUTDOOR-001** — substitute outdoor terminus with the selected/scored
   entrance before composing hybrid tails (also cures reversed-loop variant).
4. **INDOOR-001 + ACTIVE-001 (X-1)** — make in-session taps navigation-safe:
   preserve displayed-floor/POI context or move exit/approach geometry into
   session ownership.
5. **ACTIVE-002** — funnel retarget content through `_adoptNavigatedRoute` with
   ROUTE_COMMIT event + revision bump.
6. **NAV-002/NAV-003 + ACTIVE-003/X-2** — score exit doors; stop substituting
   entrance for unresolved targets; prefer entrance/connector anchors for
   guidance.
7. **POS-003/X-4** — add GPS-silence watchdog + consumer age checks.
8. **API-004** — replace message-substring taxonomy with status-code/typed
   errors.
9. **STABILITY-001** — typed failure results from identifier navigation.
10. **P3 hygiene batch** — MAP-001 heading source, PREVIEW-003 commit event,
    LOGGER-001 health badge, remaining design notes.
11. **Field-validation matrix below** after 1–2 land.

## 16. Runtime/field validation matrix

| Item | Procedure | Expected evidence | Status |
|---|---|---|---|
| Live contract re-verification | Restore SERVER_URL; run sweep harness across all endpoints incl. auth'd POI update | All contracts return expected shapes | PENDING FIELD VALIDATION (blocked by API-007/OOS-2) |
| Post-fix Route Here | Route Here → ground-floor POI with TEMP-DIAG logging | First indoor segment anchors at scored entrance coords | PENDING FIELD VALIDATION |
| Scan cadence | Walk perimeter; logcat `Scan:` deltas | ≳2 Hz effective, no >15 s stall | PENDING FIELD VALIDATION |
| WKNN accuracy | Stand at ≥5 known POIs/floor; record deltas | median err < ~4 m indoor | PENDING FIELD VALIDATION (also blocked by DATA-011) |
| Elevator timing | Ride F0↔F1 mid-route | CONFIRMED ≤30 s or ABORTED + re-detect | PENDING FIELD VALIDATION |
| Doorway premature-confirm | Linger 60 s at threshold | ≤1 dwell cycle, no flapping | PENDING FIELD VALIDATION |
| GPS canyon | Canyon walk mid-route | PAUSED via streak; no reroute storm | PENDING FIELD VALIDATION |
| Multi-door scoring | Cross-building route to multi-entrance building | Chosen door minimizes logged composite score | PENDING FIELD VALIDATION |
| Tab-flap stress ×50 | Automated (race battery) | unique sids, zero residue | TEST-PROOF (green); device feel pending |
| Battery/thermal 30 min | Continuous navigation walk | drain within platform norms | PENDING FIELD VALIDATION |
| Cold start→first fix | Timed launch | baseline vs budget | PENDING FIELD VALIDATION |
| Camera/arrow feel | Mixed in/outdoor leg; floor boundaries | No follow-exit from programmatic moves; no arrow swing at transitions (post-MAP-001 fix) | PENDING FIELD VALIDATION |

## 17. Final project verdict

**PARTIAL**

- Navigation/session machinery: **PASS (static+test)** — production readiness
  still requires the field matrix above (**PENDING FIELD VALIDATION**).
- Shipped default configuration: **FAIL** as-is (API-007: no reachable
  backend).
- Composed route correctness: **FAIL on clean-room reading** for the most
  common flows (OUTDOOR-001 family) despite green suites — the test gap, not
  the passing tests, defines current confidence.
- Production readiness claim is NOT supportable while any P1 remains open and
  mandatory field validation is unperformed.

---
*Generated from the artifacts of the 2026-08-24 forensic audit execution. No
application code, data, or configuration was modified during the audit.*
