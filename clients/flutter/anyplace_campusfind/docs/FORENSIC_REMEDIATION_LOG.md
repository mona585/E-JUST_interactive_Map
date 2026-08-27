# FORENSIC REMEDIATION LOG

Companion to `docs/FORENSIC_REMEDIATION_PLAN.md`. One entry per finding/cluster;
statuses mirrored into `docs/forensic-audit/GLOBAL_FINDINGS_REGISTER.md`.

---

## [OUTDOOR-001 + OUTDOOR-002 + OUTDOOR-005 + ACTIVE-002 (+aliases PREVIEW-001/002)] — Composition core rewrite

Status: CODE FIXED → TEST VERIFIED
Severity: P1 / P2 / P3 (per finding)
Root cause:
- OUTDOOR-001: `requestRouteToSelectedPoi` composed the outdoor leg to the
  destination POI's room coordinates (`destLatLng = poi.latLng`) and then
  concatenated an entrance-rooted indoor leg after it; `requestRouteToBuilding`
  additionally appended a reversed `interior→entrance` indoor tail after an
  outdoor arrival at the same entrance.
- OUTDOOR-002: cascade entrance pick was `_pois.where(entrance).firstOrNull`
  (load-order dependent).
- OUTDOOR-005: all-tiers-failure silently produced a ready straight-line route.
- ACTIVE-002: retarget committed content through
  `SpaceProvider.requestRouteForRetarget → requestRouteToSelectedPoi`, writing
  the route store directly — bypassing the declared single adoption choke
  point, with no ROUTE_COMMIT event and no revision bump.

Affected files:
- `lib/state/space_provider.dart` (cascade split into committing wrapper +
  non-committing `_runPoiRouteCascade`; entrance-anchored Strategy 3; gated
  inside-building-only Strategy 2; building-flow pure-outdoor composition;
  nearest-entrance helper; OSRM test seams)
- `lib/state/navigation_state_model.dart` (new abstract scope member
  `requestRouteCandidateForRetarget`)
- `lib/state/navigation_controller.dart` (`retargetDestination` adopts the
  candidate through `_adoptNavigatedRoute` + revision bump + ROUTE_COMMIT)

Old behavior: walk-through-wall outdoor tails; teleport-back/reversed loops;
arbitrary doors; silent straight-line "ready"; retarget store-write outside the
choke point with zero observability.
New behavior (§12/§13 compliant):
- CASE A/B/C/D/E semantics preserved; outdoor legs terminate ONLY at the
  selected destination entrance (deterministic nearest to the user among
  flag/type matches); buildings without an entrance FAIL EXPLICITLY
  (status=error + explanatory message); building-level destinations terminate
  at entrance or centroid with NO appended indoor tail; all-tier failure
  degrades visibly ("direct line" message) while still anchoring on the
  entrance; retarget computes candidates without store writes and commits via
  the choke point with ROUTE_COMMIT + revision bump.

Why this fix is correct: it implements the audit's terminus substitution at
the composition origin rather than masking downstream; §15-style ownership fix
(single writer) instead of post-hoc restoration; §14 determinism for anchors
(nearest-by-distance, documented tie-break).

Tests added:
- `test/remediation_composition_test.dart` (5 semantic tests: CASE-B S2 root,
  outdoor S3 nearest-anchor/no-room-coords, no-entrance fail-explicit,
  degraded-visible straight line anchored on entrance, building-flow
  pure-outdoor no-reversed-tail).
Tests modified (documented per remediation rule §10E):
- 13 fake scopes across test/ gained `requestRouteCandidateForRetarget`
  overrides (interface extension; behavior-preserving).
- `test/handoff_guidance_test.dart:386` now expects `routeRevision == 1` after
  retarget — the old `0` encoded the bypass (commit without bump) that this
  fix removes.
Tests executed: targeted suites green; FULL SUITE **277/277** (2026-08-24).
Runtime verification: N/A here (no backend/device); covered by field matrix.
Remaining limitations: cross-building router's own centroid-fallback entrance
remains flagged-partial by design (BUG-14 honesty), unchanged.
Related findings: NAV-002/NAV-003/X-2 handled in next cluster.

---

## [NAV-002 + NAV-003 + ACTIVE-003 (+X-2)] — Cross-building selectors and guidance anchor

Status: CODE FIXED → TEST VERIFIED
Severity: P2 / P2 / P2
Root cause: exit door committed as `candidates.first` before any cost was
measured; `_routeViaConnectors` substituted the ENTRANCE for unresolvable
cross-floor targets producing complete-marked degenerate loops; session
guidance anchored on nearest ANY-type POI (violating the indoor-origin rule).
Affected files: `lib/data/repositories/cross_building_router.dart`
(`_selectExitPoi` nearest-to-user; explicit target resolution returning null;
@visibleForTesting seams), `lib/state/space_provider.dart`
(`requestIndoorRouteForSession` anchor preference: connector → entrance →
nearest-any fallback with log).
Old behavior: far-side doors; entrance→c1→c2→entrance loops marked ready;
guidance rooted behind walls.
New behavior: deterministic nearest exit door (ground-preferred); unresolvable
targets fall through to the FLAGGED incomplete fallback (§13 degraded-safely);
guidance origin is a semantically valid transition point, deterministic,
scope/floor/building-correct.
Tests added: `test/remediation_crossbuilding_test.dart` (2).
Tests executed: targeted + full suite. Runtime: N/A field.
Related: X-2 closed via anchor semantics + OUTDOOR-001 composer root fix.

---

## [INDOOR-001 + ACTIVE-001 + X-1] — Session-owned destination geometry

Status: CODE FIXED → TEST VERIFIED
Severity: P1
Root cause: exit detection (`_isOutsideBuilding`) and entrance proximity read
BROWSING state (scope selectedSpace/activeFloorplan/pois) that an ordinary
in-session building tap wipes (INDOOR-001), stranding the checks against the
wrong building and defeating INV-9's preserved-context intent.
Affected files:
- `lib/state/navigation_controller.dart`: session-scoped cache
  (`_destCentroid/_destEntrances/_destFloorplan`) captured while the scope
  points at the destination, refreshed per tick, reset on preview/retarget/
  end; `_isOutsideBuilding` and `checkEntranceProximity` consume the CACHE
  first (scope consulted only while it still matches the destination);
  absence-of-entrances fallback only trusted after destination POIs observed
  (preserves original wait-for-POIs semantics); two @visibleForTesting
  observability getters.
Old behavior: mid-session tap silently re-targeted exit/approach geometry.
New behavior: §15 ownership fix — browsing can no longer alter navigation's
geometric reference; no restore-after-destroy hack.
Tests added: `test/remediation_context_test.dart` (2 end-to-end controller
tests reproducing the hostile tap then asserting exitingBuilding /
enteringBuilding still fire from cached geometry).
Tests executed: targeted + full suite. Runtime: field walk-through pending.
Related: rendering visibility during foreign-floor browsing remains a correct
projection of displayed context (not a defect).

---

## [POS-003 + X-4] — GPS silence watchdog

Status: CODE FIXED → TEST VERIFIED
Severity: P2
Root cause: fix freshness evaluated only at sample arrival; OS stream silence
never produced ticks, so a `fresh` fix was believed indefinitely and no
consumer age-checks fixes.
Affected files: `lib/state/location_provider.dart` (periodic watchdog armed
with tracking/disposed with stop/dispose; `_evaluateGpsFreshness(DateTime)`
converts each elapsed staleness window into one degraded tick + stale demotion
and rebuilds the canonical projection via `_evaluateArbitration`; synthetic-
time test hooks), consumers unchanged (they already honor gpsDegraded/status).
Old behavior: frozen fresh dot feeding deviation/arrival during outages.
New behavior: after `gpsPausePoorTicks` silence windows the same PAUSED
signal fires that delivered-sample degradation produces; coordinates are
preserved for display only.
Tests added: `test/remediation_gps_silence_test.dart` (2, synthetic time).
Tests executed: targeted + full suite. Runtime: real chip-outage behavior is
field-validation (matrix unchanged).

---

## [MAP-001] — Heading consumes displayed position

Status: CODE FIXED → TEST VERIFIED
Severity: P3
Root cause: BUG-16b rewrite used `location ?? display`, so the EMA consumed
the RAW fix whenever available — i.e., exactly during floor transitions —
contradicting its own comment.
Affected files: `lib/ui/screens/map_screen.dart` (`_onNavigationChanged`
heading source = display).
Validation: navigation_ui display-rule battery + full suite green; on-device
arrow-feel check remains in the field matrix.

---

## [STABILITY-001 + STABILITY-002 + PREVIEW-003/X-3] — Stability/observability batch

Status: CODE FIXED → TEST VERIFIED
Severity: P2 / P3 / P3
Root cause & fixes: `_navigateToIdentifier` returns typed `false` instead of
throwing StateError through unguarded UI closures (callers' existing snackbar
paths now reachable); `_animatedMapMove` completion gains the same `mounted`
guard as the follow path; preview seeding emits
`ROUTE_COMMIT source=preview-seed` closing the initial-adoption observability
gap.
Files: space_provider.dart, map_screen.dart, navigation_controller.dart.
Validation: quick-access/navigation-ui suites + full suite green.

---

## [OUTDOOR-003 + OUTDOOR-004 + INDOOR-003] — Engineering hygiene batch

Status: CODE FIXED → TEST VERIFIED
Severity: P3 ×3
Fixes: Dijkstra rewritten as deterministic linear-scan selection (removes the
mutable-key ordering/livelock hazard at identical practical complexity for
campus-scale graphs; all 54 custom-route tests unchanged-green); containment
unified into one shared helper with an honest constant name
(`kBuildingContainmentRadiusMeters`) and both call sites delegating; batch
sync pause bounded by `kBatchPauseResumeSeconds = 45 s` auto-resume so a
permanently selected building cannot starve whole-campus indexing.
Files: custom_route_graph.dart, space_provider.dart ×2.
Validation: analyzer clean; custom-route suites + full suite green.

---

## [LOGGER-001] — Radiomap health surfaced

Status: CODE FIXED → TEST VERIFIED (widget text)
Severity: P2
Root cause: RadioMapStatus/error existed client-side with ZERO UI consumers
(verified by grep during audit).
Fix: building detail card renders a status line per floor —
ready/unsupported("No Wi-Fi radiomap…GPS")/error/loading — using existing
text styles only (no styling overhaul).
Files: lib/ui/widgets/building_detail_card.dart.
Validation: analyzer clean; navigation_ui + composition suites green.

---

## [API-008] — Scoped cleartext policy

Status: CODE FIXED → BUILD VERIFIED (runtime traffic check = field)
Severity: P3
Fix: replaced global `android:usesCleartextTraffic="true"` with
`network_security_config.xml` allowing cleartext ONLY for
router.project-osrm.org; base config forbids cleartext and trusts system CAs.
Verification: `flutter build apk --debug` succeeds (resource merge +
manifest validation); live OSRM request over the policy is a field item.

---

## [DATA-009 + DATA-010] — Local authoritative store repair

Status: RUNTIME VERIFIED (direct collection evidence)
Severity: P2 / P3
Evidence-driven repair of the REACHABLE dev store (mongo_dart scripts outside
the repo):
- DATA-010: deleted ONE verbatim-duplicate edge row (same cuid twice; kept
  first _id). Post-check: unique cuids 15/15.
- DATA-009: measured min cross-component gap = 6.3 m between connector
  poi_6873a2c6(main) and poi_23076c9c(chain head) — inside the dataset's own
  edge-length distribution (min 3.9 / median 9.2 / max 13.5 m). Inserted ONE
  hallway edge mirroring the schema (cuid/floors/buid/weight/is_published).
  Post-BFS: 16/16 reachable from the entrance; isolated=0. Theater and the
  southern chain now routable.
Why legitimate: dedupe removes an unintended duplicate; the bridge matches
the dataset's own adjacency pattern at its own characteristic length — no
coordinates or topology invented beyond what measurement supports.
Not touched: deployment DB claims (DATA-001..004) — unreachable; radiomaps
(DATA-011/DATA-002) require logger field collection (FIELD DATA REQUIRED).

---

## Explicitly NOT fixed (documented decisions)

- API-007 (P1): default UCY backend retired externally; no authoritative
  endpoint exists in-repo to switch to (AGENTS D-07 forbids inventing host).
  Config override path (`--dart-define=SERVER_URL`) already exists.
  **BLOCKED EXTERNAL.**
- DATA-001..004 (deployment DB): unreachable — **BLOCKED EXTERNAL / FIELD**.
- DATA-011/DATA-002 (radiomaps): **FIELD DATA REQUIRED** — run legacy logger,
  verify `/api/radiomap/space` returns map_url_mean, then re-run WKNN matrix.
- POS-001 (confirmed≠inside): semantic-boundary change requires field
  evidence (§17) — DEFERRED.
- NAV-001 dual encoding / DATA-007 connector names / DATA-008 'door'
  substring / API-004 error taxonomy: structural or backend-contract work —
  DEFERRED with reasons in the plan matrix.
- POS-002, API-001/002/003/005, STABILITY-003/004, DATA-005/006:
  EXPECTED/WONTFIX with rationale in the plan matrix.
- INDOOR-002 / ACTIVE-004: descriptions unrecoverable — WONTFIX(UNRECOVERABLE),
  IDs preserved.