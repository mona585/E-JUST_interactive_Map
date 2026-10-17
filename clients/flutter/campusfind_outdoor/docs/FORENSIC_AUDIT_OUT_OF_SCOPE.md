# FORENSIC AUDIT — OUT-OF-SCOPE DISCOVERIES LEDGER

Chronological ledger of issues discovered while executing a phase but belonging
outside that phase's declared scope. Entries stay `UNVERIFIED DISCOVERY` until the
designated phase independently establishes or refutes them.

| # | Discovered | Discovery phase | Provisional ID | Affected file/component | Description | Evidence observed | Evidence class | Why outside current scope | Designated phase | Later independently verified? | Final classification/severity |
|---|---|---|---|---|---|---|---|---|---|---|---|
| OOS-1 | 2026-08-24 ~03:40 | PHASE-01 | API-007 (allocated in PHASE-09) | `lib/config/api_config.dart:6` (`_defaultBaseUrl`) | App default backend `https://ap.cs.ucy.ac.cy:44` no longer serves the Anyplace API; every probed endpoint returns HTTP 404 (HTML from Apache/2.4.41). Viewer homepage still serves statically but its own app JS (`build/js/anyplace.js`) is 404 too. | POST `/api/mapping/space/public` `{}` via the app's own HTTP stack (package:http) → 404 text/html; http:// → 302 → https → 404; alternate context paths (`/anyplace/api/...`, `/apis/...`, `/api/v2/...`, `/backend/...`) all 404 | RUNTIME-PROOF (captured 2026-08-24) | Endpoint/config contract correctness is PHASE-09 scope; recorded here because it blocks PHASE-01's live sweep | PHASE-09 | Yes — verified in PHASE-09 | BUG, P1 |
| OOS-2 | 2026-08-24 ~03:45 | PHASE-01 | — (env limitation) | Deployment DNS (`anyplace.ejust.edu.eg`) | E-JUST hostname does not resolve from this environment (`Failed host lookup … errno 11001`). Consistent with AGENTS.md D-07 (illustrative host). | Dart probe socket failure | RUNTIME-PROOF | Environment/deployment matter, not client code | Master report limitations | n/a | Environment blocker (not a code defect) |
| OOS-3 | 2026-08-24 ~04:05 | PHASE-01 | — (context for DATA findings) | Local MongoDB `anyplace` DB, `users` collection | Single user document holds password hash + long-lived access token; `type: admin` (consistent with "first registrant = admin" invariant). Not reproduced verbatim in any report. | Direct collection read during sweep | DATA-PROOF | Backend security posture is not PHASE-01 scope | PHASE-09 (contract/security seams) | Partially (existence verified; semantics noted PHASE-09 §4) | Context note; no client defect |
| OOS-4 | 2026-08-24 ~04:10 | PHASE-01 | LOGGER dependency note | Local DB absent collections (`fingerprintsWifi`, `heatmapWifi*`, radiomap caches) | Zero fingerprint/radiomap collections exist in the reachable store ⇒ no indoor positioning coverage anywhere in the reachable dataset. Audited as DATA-011 in PHASE-01 (data presence IS Phase-1 scope); the logger-side process gap is Phase-11 scope. | Collection list: users, spaces, floorplans, edges, pois only | DATA-PROOF | Collection-process ownership belongs to PHASE-11 | PHASE-11 | Yes | See DATA-011 (PHASE-01) + LOGGER dependency note (PHASE-11) |
| OOS-5 | 2026-08-24 ~06:20 | PHASE-07 | STABILITY-004 (allocated in PHASE-10) | `DeviceHeadingBridge.kt` vs `PositioningEngine.kt` | Heading bridge lacks identity-safe listener-clear pattern parity with positioning engine. Analyzed in PHASE-07 while reconstructing ACTIVE-004 ("bridge parity" hint); found benign under current channel semantics but filed as design divergence in its proper stability scope. | Native source read of both bridges | STATIC-PROOF | Lifecycle/disposal pattern audit belongs to PHASE-10 | PHASE-10 | Yes | DESIGN, P3 |

## Rules

- Nothing here is fixed during the audit.
- An entry becomes a numbered finding only when its designated phase reaches it.
- Evidence classes follow `docs/FORENSIC_AUDIT_PLAN.md`.
