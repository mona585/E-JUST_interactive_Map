# FORENSIC AUDIT PLAN — Anyplace CampusFind

Permanent methodology for feature-level forensic audits of this repository.
Created after the Route-Here/G13 incident proved that runtime symptoms can originate
in backend data rather than client algorithms.

## Prime directive

The repository and the live backend are the sources of truth.
Documentation, comments, function names, tests and prior reports are claims to be
verified, never proof.

Priority order when sources disagree:

1. Runtime behavior / captured logs
2. Live backend / database content
3. Executable implementation (client, native, server)
4. API contracts / schemas
5. Tests
6. Documentation

## Evidence classes

Every claim in every report must carry one of these labels:

| Label | Meaning |
|---|---|
| STATIC-PROOF | Established by reading executable code end-to-end |
| RUNTIME-PROOF | Established by captured logs / live API responses / device run |
| TEST-PROOF | Established by an automated test against production-path code |
| DATA-PROOF | Established by querying authoritative backend data |
| ASSUMPTION | Reasonable inference, explicitly not proven |
| UNKNOWN | Cannot be established without field/runtime access |

A PASS verdict that requires runtime evidence without that evidence having been
captured must be written as `PASS (static) — PENDING FIELD VALIDATION`.

## Finding classification

Every finding receives exactly one type:

- `BUG` — executable code does something objectively wrong
- `DATA` — persisted/backend content violates its own semantics
- `DESIGN` — architecture invites defects or ambiguity (no immediate wrong behavior)
- `MISSING` — required functionality absent
- `UNKNOWN` — cannot be proven without field/runtime evidence
- `DEAD` — legacy/duplicated/stub code retained

Severity: P0 correctness blocker · P1 major correctness problem · P2 important · P3 cleanup.

## Phases (fixed order)

| # | File | Focus |
|---|---|---|
| 01 | PHASE-01-DATA-INTEGRITY.md | Entire dataset sweep: buildings, floors, POIs, flags, types, connectors, coordinates, associations, floorplans, connections, radiomap coverage |
| 02 | PHASE-02-POSITIONING.md | GPS pipeline + gates, Wi-Fi scan→KNN→engine→bridge→arbiter, source switching, transitions |
| 03 | PHASE-03-INDOOR-MAP.md | Selection, loading, floor switching, coordinate passthrough, visibility |
| 04 | PHASE-04-OUTDOOR.md | Outdoor geometry, KMZ/OSRM tiers, detection heuristics, terminus semantics |
| 05 | PHASE-05-NAVIGATION.md | All eight origin/destination scenarios through the real composers |
| 06 | PHASE-06-ROUTE-HERE.md | Preview-only pipeline; invariant: preview correct BEFORE Start Directions |
| 07 | PHASE-07-ACTIVE-NAVIGATION.md | Session, commits, deviation/handoff/floor/arrival/retarget/teardown |
| 08 | PHASE-08-MAP-RENDERING.md | Projection fidelity: store/model → polylines/markers/camera |
| 09 | PHASE-09-API-BACKEND.md | Every contract: fields, nullability, booleans, floors, errors, native channels |
| 10 | PHASE-10-STABILITY.md | Exceptions, races, disposal, lifecycle, stress — after correctness phases |
| 11 | PHASE-11-LOGGER.md | Determine scope: in-product vs separate collector; audit accordingly |
| 12 | PHASE-12-CROSS-FEATURE-INTEGRATION.md | Boundary defects, compensation patterns, conflicting state owners |

## Per-report skeleton (mandatory)

1. Scope
2. Inputs inspected (code/data/logs/runtime)
3. Code paths inspected
4. Data inspected
5. Tests executed
6. Runtime checks executed
7. Limitations
8. Actual architecture
9. Actual execution flow
10. Proven-correct behavior
11. Confirmed defects
12. Data defects
13. Design weaknesses
14. Missing functionality
15. Unknowns requiring runtime/field testing
16. Findings table (ID/Sev/Type/Finding/Evidence)
17. Verdict (PASS / PARTIAL / FAIL / BLOCKED)

## Global findings register

Stable IDs, never reused for a different finding:

`DATA-xxx · POS-xxx · INDOOR-xxx · OUTDOOR-xxx · NAV-xxx · PREVIEW-xxx · ACTIVE-xxx · MAP-xxx · API-xxx · STABILITY-xxx · LOGGER-xxx · X-xxx`

Findings proven during the 2026-08 navigation implementation review keep their
historical IDs; new discoveries continue the numbering.

## Execution rules

- No code/data/config modification. Diagnostic instrumentation only when strictly
  necessary to discriminate hypotheses, reverted immediately after capture.
- Never stop between phases; field-dependent items are marked
  `PENDING FIELD VALIDATION` with the exact test procedure, and the audit continues.
- A defect compensated by another component is still reported at its origin phase,
  with the compensation noted in PHASE-12.
- Backend data is inspected directly (same endpoints the client uses); absence of
  local seeds is irrelevant when the live collection is reachable.

## Master deliverable

`docs/FORENSIC_AUDIT_MASTER_REPORT.md` — executive summary, per-feature verdicts,
proven-correct inventory, consolidated register, severity distribution, dependency/
compensation risks, remediation order, and the runtime/field validation matrix.
