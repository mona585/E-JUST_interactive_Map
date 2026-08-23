# Phase 5 — Implementation Report

## 1. Objective
Mirror the indoor quality-gate pattern for GPS ingestion: staleness, jump rejection, accuracy classification — without throttling or altering the arbiter (Master Plan §10 PHASE 5; RC5; BUG-6; INV-8 inputs, INV-11).

## 2. Implementation Performed
1. **NavigationConfig** new block: `gpsStaleAfterSeconds=10`, `gpsRejectAccuracyMeters=50`, `gpsPoorAccuracyMeters=30`, `gpsGoodAccuracyMeters=15`, `gpsMaxImpliedSpeedMps=25`, `gpsOutlierHoldTicks=1`, plus `gpsPausePoorTicks=3` (hysteresis count for the pause contract).
2. **LocationProvider `_ingestGps`**: single intake for stream / `setGpsLocation` / initial centering. Gates in order: staleness (never refreshes canonical; demotes existing fix to `PositionFixStatus.stale`), hard reject (>50 m ignored entirely), implied-speed outlier with hold-then-accept semantics (`gpsOutlierHoldTicks`), acceptance bands. Raw always preserved (`_gpsLocation`, `lastRawGpsForDiagnostics`). Canonical GPS fix now built ONLY from accepted samples.
3. **Degraded-streak signal**: `gpsDegraded` true after `gpsPausePoorTicks` consecutive stale/rejected/poor/held fixes; cleared by one accepted fix.
4. **GPS confidence mapping extended** with the poor band (accepted-above-poor → 0.25; good → 0.7; ≤5 m → 0.9).
5. **Service fixes**: `getLastKnownPosition()` fallback now age-checked against the staleness window before use; distance filter maps sub-meter values to the minimum supported int gate of **1 m** (documented platform limitation).
6. **NC pause rewiring**: hardcoded >100 m pause replaced by `gpsDegraded` streak contract; recovery requires streak cleared AND good-band accuracy.

## 3. Files Changed
- `lib/config/navigation_config.dart` — gate constants.
- `lib/state/location_provider.dart` — ingestion gate, hold/demote helpers, degraded signal, intake rewiring (3 call sites), confidence bands.
- `lib/data/datasources/gps_location_service.dart` — lastKnown staleness check + distance-filter floor + config import.
- `lib/state/navigation_controller.dart` — `_checkGpsLoss`/`_checkGpsRecovery` rewritten on the band contract.

## 4. Tasks Completed
| Plan task | Status |
|---|---|
| 1. Config constants | COMPLETED |
| 2. Ingestion filter + hold semantics + raw preservation | COMPLETED |
| 3. Service stamping + distance-filter fix | COMPLETED |
| 4. Pause-band rewiring | COMPLETED |

## 5. Tests Added/Modified
- NEW `test/gps_quality_test.dart` (4): stale never canonical + raw preserved + status demotion; reject-band ignored / poor-band low-confidence accepted / good-band 0.7; outlier holds once then accepts real movement, good-accuracy jumps exempt; degraded-streak pause-contract signal with threshold and instant clear.
- FLIPPED (expected, per plan item 4) single-tick pause fixtures to sustained degradation: state_machine pause-overlay test (both variants, incl. seeding an accepted fix indoors), journey pause segment, navigation_ui PAUSED status test, session_identity cooldown test.

## 6. Tests Executed
| Command | Result |
|---|---|
| `flutter test test/gps_quality_test.dart` | 4/4 pass |
| `flutter analyze --no-pub` | **30 issues = baseline parity** |
| `flutter test --reporter compact` (full) | **237/237 pass** |

## 7. Acceptance Criteria
- [x] Stale/outlier/invalid fixtures provably never reach `currentFix` (gps_quality tests 1–3). PASS
- [x] Update rate unchanged — gate is per-fix acceptance only; no timers/throttling introduced; 500 ms interval stream untouched. PASS
- [x] Indoor pipeline byte-for-byte: arbitration suite green (gate runs at GPS intake; indoor evidence path untouched). PASS

## 8. Architectural Rules / Invariants
INV-8 inputs exist outdoors now (machine-readable quality on every fix); INV-11 preserved (raw kept, acceptance-only filtering). Arbiter internals untouched (§18 protected).

## 9. Regression Verification
Full 237-test suite green; arbitration/lifecycle suites unchanged and passing; exit-dwell flows using non-confirming accuracies still behave identically (raw path feeds exit checks as before).

## 10. Problems Encountered
- Rejected (>50 m) fixes leave NO canonical position when none existed before → tick pipeline saw null location and the old indoor-variant/journey pause fixtures silently stopped ticking. Fixed by seeding one accepted fix before degrading those fixtures.
- Analyzer flagged unused `_lastRawGps` → surfaced via `lastRawGpsForDiagnostics` getter (contract made explicit rather than deleting preservation).

## 11. Problems Resolved
Both above.

## 12. Problems Remaining
NONE

## 13. Deviations From Plan
- Added `gpsPausePoorTicks=3`: plan says "recent fixes are all in poor/invalid band for stabilityWindowSeconds" without a concrete tick count; a fixed count keeps behavior deterministic in fake-async tests while preserving hysteresis intent.
- Confidence values for the poor band chosen (0.25) where plan left the mapping extension unspecified beyond "flagged low-confidence".
- Sub-meter distanceFilter mapped to 1 m (plan-prescribed); noted that this is a behavioral change from the previous disabled(0) gate.

## 14. Final Phase Status
**COMPLETE**
