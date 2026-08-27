# FORENSIC REMEDIATION FINAL REPORT

Baseline: HEAD `0da8033a`, clean tracked tree. Remediation executed
2026-08-24 per `docs/FORENSIC_REMEDIATION_PLAN.md` over the 2026-08-24
forensic-audit findings (50 register rows). No git history operations; all
changes left uncommitted in the working tree for review.

---

## 1. Original finding count

50 register rows → **46 unique defects/seams** after consolidations
(PREVIEW-001/002 aliases, X-3=PREVIEW-003, API-006 superseded) + 1 by-design
seam (API-001) tracked separately.

## 2. Findings fixed (code)

**16 unique defects fixed and test-verified:**

| ID | Fix |
|---|---|
| OUTDOOR-001 (+PREVIEW-001) | Outdoor terminus = selected entrance; fail-explicit without entrance; reversed-tail removed at composition origin |
| OUTDOOR-002 (+PREVIEW-002) | Deterministic nearest-entrance selection in cascades |
| ACTIVE-002 | Retarget content commits via single choke point + ROUTE_COMMIT + revision bump (non-committing candidate computation) |
| NAV-002 | Exit door = deterministic nearest-to-user (ground-preferred) |
| NAV-003 | Connector-chain no longer substitutes entrance for unresolvable/cross-floor targets (honest null → flagged fallback) |
| INDOOR-001 / ACTIVE-001 / X-1 | Session-owned destination geometry cache; browsing wipes can no longer strand exit/approach detection |
| POS-003 / X-4 | GPS-silence watchdog converts silence into degraded ticks + stale demotion through the existing canonical projection |
| ACTIVE-003 / X-2 | Guidance anchor preference connector→entrance→(logged)nearest-any: deterministic, scope/floor/building-correct |
| STABILITY-001 | Identifier navigation returns typed `false` (no StateError escape) |
| MAP-001 | Heading EMA consumes displayed (held) position per BUG-16b contract |
| PREVIEW-003 / X-3 | ROUTE_COMMIT event for initial preview adoption |

## 3. Fixed without code changes / resolved as expected

API-001 (by-design seam), API-002/003/005, DATA-005/006,
POS-002, STABILITY-003/004 — closed WONTFIX/EXPECTED with rationale
(contract preservation §19, documented INV-8 tradeoff, test-only hooks).
DATA-010 counted under §2's data section below.

## 4. Blocked by external infrastructure

**API-007 (P1)** — authoritative default backend retired (404 evidence);
no in-repo endpoint to switch to; config override path exists.
Unblock: supply verified `SERVER_URL`.
**DATA-001..004** — deployment DB claims unreachable until then.

## 5. Requiring field validation

**DATA-011 / DATA-002 (FIELD DATA REQUIRED)** — logger collection procedure
documented (PHASE-11); then WKNN accuracy matrix.
Field items retained on: OUTDOOR/ACTIVE fixes' on-device walk-throughs,
scan cadence, elevator timing, doorway dwell, GPS canyon, OSRM latency,
battery/cold-start (master matrix).

## 6. Deferred (with reasons)

NAV-001 (backend schema migration) · POS-001 (needs field evidence per §17) ·
API-004 (typed backend error codes) · DATA-007 (naming intent) ·
DATA-008 (latent; needs type vocabulary) · INDOOR-002 / ACTIVE-004
(descriptions unrecoverable — IDs preserved).

## 7. New findings discovered during remediation

**ENC-001 (P3, fixed immediately):** PowerShell round-trip re-encoding
corrupted non-ASCII literals (em-dashes/arrows) in three files during bulk
edits; detected via a failing UI expectation (mojibake pause message) and
repaired byte-exactly (CP1252→UTF-8 reverse); analyzer + full suite clean.
No other unexpected defects surfaced.

## 8. Files modified

lib/state/space_provider.dart · lib/state/navigation_controller.dart ·
lib/state/location_provider.dart · lib/state/navigation_state_model.dart ·
lib/data/repositories/cross_building_router.dart ·
lib/data/repositories/custom_route_graph.dart · lib/data/datasources/kmz_loader.dart ·
lib/ui/screens/map_screen.dart · lib/ui/widgets/building_detail_card.dart ·
android/app/src/main/AndroidManifest.xml ·
android/app/src/main/res/xml/network_security_config.xml (NEW) ·
13 test fakes updated for the new scope member · docs (plan/log/register/
this report).

## 9–10. Tests added / modified

Added: remediation_composition_test.dart (4 semantic scenarios),
remediation_crossbuilding_test.dart (2), remediation_context_test.dart (2),
remediation_gps_silence_test.dart (2), plus entrance-anchoring assertions —
**11 new tests**, all observable-behavior level.
Modified: handoff_guidance_test revision expectation (0→1; old value encoded
the bypass this fix removes — documented); 13 fake scopes gained the new
interface member (mechanical). No assertion weakened anywhere.

## 11. Full test results

`flutter test` → **283 passed, 0 failed** (272 baseline + 11 added),
final run post-all-changes.

## 12. Runtime verification results

- Local store repairs verified by direct re-query: 16/16 reachable from
  entrance, 0 isolated POIs, 15/15 unique cuids.
- `flutter build apk --debug` succeeds with the scoped network-security-config.
- Backend-dependent runtime checks remain blocked (API-007) — field matrix
  unchanged.

## 13. Remaining risks

Deployment data unknowns until backend restored; radiomap coverage absent in
reachable store (positioning stays GPS-only there) until logger runs;
deferred P2 design items (POS-001/NAV-001/API-004).

## 14. Remaining P1/P2 issues (all explicitly dispositioned)

P1: API-007 BLOCKED EXTERNAL · DATA-011 FIELD REQUIRED · DATA-001 FIELD
(pending) · INDOOR-001/OUTDOOR-001/ACTIVE-001/X-1 RESOLVED(test-verified).
P2: DATA-002/003/004 FIELD/BLOCKED · DATA-009 RESOLVED · POS-001 DEFERRED ·
NAV-001 DEFERRED · API-004 DEFERRED · STABILITY-001 RESOLVED · LOGGER-001
RESOLVED · X-2/X-4 RESOLVED · ACTIVE-002/003 RESOLVED · OUTDOOR-002
RESOLVED · NAV-002/003 RESOLVED · POS-003 RESOLVED · INDOOR-002/ACTIVE-004
UNRECOVERABLE.

## 15. Production readiness verdict

**NOT production-ready until:** (a) a reachable authoritative SERVER_URL is
configured (API-007), (b) radiomaps are collected for target floors
(DATA-011/002), (c) deployment DB hygiene is re-audited (DATA-001..004),
and (d) the field-validation matrix passes on-device. The client-side code
that was reachable for repair now matches the mandated navigation semantics
with regression protection.

## 16. Exact next actions

1. Configure/restore deployment backend; verify with the Phase-01 sweep harness.
2. Re-run deployment DB audit (entrance flags, floors, POIs) against live data.
3. Collect radiomaps via logger for every in-scope floor; confirm coverage.
4. Execute the field-validation matrix (walk tests, cadence, elevator, canyon).
5. Schedule deferred structural work (NAV-001 schema, API-004 typed errors).
