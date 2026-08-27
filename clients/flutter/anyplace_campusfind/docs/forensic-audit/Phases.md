**# PHASE-01 — DATA INTEGRITY**

**## Scope**

Entire deployment dataset reachable on the authoritative backend (\`[https://ap.cs.ucy.ac.cy:44](https://ap.cs.ucy.ac.cy:44)\`):

buildings, floors, POIs, \`pois\_type\`, \`is\_building\_entrance\`, \`is\_door\`, connectors,

coordinates, associations, radiomap coverage, navigation-graph health.

**## Inputs inspected**

\- Live API: \`/api/mapping/space/public\`, \`/api/mapping/floor/all\`,

  \`/api/mapping/pois/floor/all\`, \`/api/radiomap/space\`, \`/api/navigation/route\`

  (queried via Dart using the app's own HTTP stack; curl rejected by the front

  controller while Dart 200s — see API-006).

\- Local: \`poi\_model.dart\`, \`lib/utils/poi\_classification.dart\`, \`MongodbDatasource.scala\`,

  \`NavigationController.scala\`, \`MapPoiController.scala\`, migration docs.

\- Prior captured runtime: \`[TEMP-DIAG][CHECK1]\` segment dumps, \`[ENTRANCE\_DEBUG]\` chain.

**## Data inspected**

\- 3,554 public spaces scanned; **\*\*11 buildings in this deployment's import batch\*\***

  (\`buid\` timestamp ≥ 2026-06) enumerated fully: test, **\*\*B7\*\***, Silent Infotech, mona,

  Library, National Bank branch, Blue hall Cafeteria, Stationery shop, Food court,

  Student Affairs, B3.

\- B7 floor 0: 24 POIs pre-fix / re-verified post-fix. Floor 1: 6 POIs. All dumped.

**## Runtime checks executed**

\- Full per-building/per-floor sweep via Dart (POST contracts identical to app).

\- Navigation graph probes: \`POST /api/navigation/route {pois\_from,pois\_to}\`.

\- Radiomap coverage probe: \`POST /api/radiomap/space {buid,floor}\`.

**## Findings**

\| ID | Sev | Type | Finding | Evidence |

\|---|---|---|---|---|

\| DATA-001 | P1 | DATA | G13 (Room) had \`is\_building\_entrance=true\`; real "Entrance" had \`false\` → wrong-door selection | Live records pre-fix; \`[ENTRANCE\_DEBUG] Step4\`; fixed by user mid-audit |

\| DATA-001b | P1 | DATA | **\*\*FIXED & VERIFIED LIVE\*\***: floor 0 now has exactly one entrance-class record \`Entrance\`(flag=true); G13=\`Room/false\` | Re-query this audit |

\| DATA-002 | P2 | DATA | **\*\*B7 floor 1 has no radiomap\*\*** ("Can't create radiomap on-the-fly.") ⇒ no indoor positioning upstairs; F1-24 unreachable by guidance | radiomap/space probe |

\| DATA-003 | P2 | DATA | 6 of 11 batch buildings (Library, National Bank, Blue hall, Stationery, Food court, Student Affairs) return **\*\*zero floors\*\*** ⇒ Quick-Access defaults point at entities with no indoor data | floor/all empty for each |

\| DATA-004 | P2 | DATA | B3 has floor 0 with **\*\*0 POIs\*\***; Silent Infotech floor 6 with 0 POIs; mona 3 POIs w/o entrance record | pois probes |

\| DATA-005 | P3 | DATA | \`is\_door=false\` on every record incl. doors ⇒ field unused in this dataset | census |

\| DATA-006 | P3 | DATA | Booleans stored as strings; V1 Boolean migration documented but unapplied (version skew vs migration doc) | CHANGES.COLLECTIONS.md:199; live values |

\| DATA-007 | P3 | DATA | 17 connectors all named "Connector" — display ambiguity only | TEMP\_POIS.json dump |

\| DATA-008 | P3 | DESIGN/DATA | \`contains('door')\` substring also matches "indoor/outdoor" — latent misclassification hazard, not triggered today | poi\_classification.dart:78 |

\## Proven-correct

B7 floor-0 classification post-fix; floor↔building associations (all POIs' buid match);

floor strings consistent between floor list and POIs; coordinates present on all 30 B7

POIs and parse as valid doubles; no duplicate puids anywhere in batch.

\## Verdict: \*\*PARTIAL\*\*

B7 clean after user's fix (DATA-001b), but deployment-wide gaps (DATA-002/003/004)

directly break indoor features outside B7-floor-0, and fleet-wide flag hygiene is

unproven beyond the 11-building batch.
**# PHASE-02 — POSITIONING**

**## Scope**

GPS pipeline, ingestion gates, Wi-Fi scan→WKNN→engine→bridge→arbiter→\`currentFix\`,

source switching, O/I transitions, consumers.

**## Inputs / code paths**

\`GpsLocationService\` (geolocator 500 ms interval; distanceFilter floor 1 m),

\`LocationProvider.\_ingestGps\` (:505–591) + protected arbiter core (:245–591),

Kotlin \`WifiScanner\`(120)/\`KnnLocalizer\`(145)/\`PositioningEngine\`(233)/\`PositioningBridge\`(116)/\`RadioMap\`(79)/\`DeviceHeadingBridge\`(152), \`NavigationController\` consumers.

**## Runtime checks executed**

Live logcat during deploy: engine \`Scan:\` lines streaming (0 matched APs outdoors — correct no-claim behavior).

**## Proven-correct behavior (static+test)**

\- Ingestion gates: stale>10 s → demote-stale; acc>50 reject; implied-speed outlier hold-then-accept; good/poor bands; degraded-streak≥3 (\`gps\_quality\_test.dart\` ×4).

\- Native LRU≤4 upsert/evict atomicity; parse-failure leaves residency intact (Engine:80–103).

\- Winner selection measurement-only: max matchedAps, tie min bestDistance (Engine:179–190); selection-independent by construction.

\- no-match ⇒ \`status="no\_match"\`, null coords/empty ids ⇒ Dart \`isValid=false\` ⇒ never becomes belief.

\- Arbiter: qualification/hysteresis(3)/scope-confirm/outlier-hold/stale-timer — 19-test suite green throughout implementation.

\- Listener-replacement race guarded via identity-checked clear (Engine:63–69).

\- Scanner event-driven + fallback re-scan honoring \~4/2 min platform throttle.

**## Confirmed defects**

\- **\*\*POS-001 (P2, DESIGN)\*\*** Handoff confirmation can land while the user is still at/outside the doorway (Wi-Fi bleed satisfies confirmed-scope corroboration). Downstream effect neutralized for B7 post-DATA-fix, but semantics remain "confirmed ≠ physically inside".

\- **\*\*POS-002 (P3)\*\*** Hard GPS outage shorter than 3 degraded ticks shows stale dot with no PAUSED hint (INV-8 tradeoff).

**## Data defects affecting positioning**

\- **\*\*DATA-002\*\***: B7 floor 1 radiomap absent ⇒ Wi-Fi positioning impossible upstairs (engine returns no-match; arbiter exits indoor).

\- **\*\*DATA-003/004\*\***: buildings without floors/POIs can never produce estimates (no radiomaps loadable).

**## Unknowns requiring field validation**

Real scan cadence under platform throttle on CPH2185; WKNN accuracy vs true position per floor; elevator/vertical behavior; multi-map winner stability near B7/F0↔F1 boundary.

Procedure: walk B7 F0 perimeter + stair run to F1 while capturing \`[LocationProvider]\` and \`Scan:\` logcat lines.

**## Verdict: \*\*PASS\*\* (algorithms/thresholds proven; accuracy calibration = PENDING FIELD VALIDATION).**
**# PHASE-08 — MAP RENDERING / CAMERA**

**## Scope**

Projection fidelity from store→polylines/markers/camera; visibility rules; heading; follow mode.

**## PROVEN CORRECT**

\- Rendering is a pure projection: \`\_buildPolylines(spaceProvider, nav)\` reads store + display context and calls pure rules (\`segmentVisibility\`, \`showCampusRoutes\`, \`routeFitZoomForSpan\` in navigation\_display.dart) — no navigation mutation anywhere in M (verified by read + rule unit tests ×9).

\- Store==rendered identity proven at commit points (route\_store \`same()\` pins) and by live capture (76-pt preview matched composer output exactly).

\- Floor-scoped visibility: indoor/floorTransition segments only on displayed floor; outdoor dimmed-outline while indoors; boundaries follow context.

\- KMZ overlay hidden during sessions unless flag/coverage rule says otherwise.

\- Camera: coalesced follow animations; programmatic-tail prevents inertia follow-exits; resume recenter; fit-zoom span table replaces pinned-19 (BUG-10).

\- Heading: dead compass branch removed; EMA consumes displayed (held) position so arrow matches pinned dot during transitions (BUG-16).

**## CONFIRMED DEFECTS**

None at rendering layer. All visual wrongness traced upstream (composer/guidance/data).

**## DESIGN NOTES**

Visibility depends on *\*browsing\** selectedFloor — correct post-Phase-10 (context retained), but INDOOR-001 tap-wipe still hides indoor legs mid-session (upstream defect counted there, not here).

**## Verdict: \*\*PASS\*\***
**# PHASE-09 — API / BACKEND INTEGRATION**

**## Scope**

All 8 REST contracts + native platform channels + server-side handlers (Scala) compared against Flutter expectations. Evidence includes live Dart-stack probes (curl rejected by front controller; Dart 200s — API-006).

**## Contracts verified live**

\| Endpoint | Req fields | Notes |

\|---|---|---|

\| POST /mapping/space/public | {} | 3554 spaces; string bools; B7 included |

\| POST /mapping/floor/all | buid | floors[] w/ floor\_number strings |

\| POST /mapping/pois/floor/all | buid, floor\_number | pois[]; \`is\_building\_entrance/is\_door\` as STRINGS; coords as strings |

\| POST /radiomap/space | **\*\*buid, floor\*\*** (field name = \`floor\`, not floor\_number) | map\_url\_mean present ⇒ coverage YES; error\_messages "Can't create radiomap on-the-fly." ⇒ NO |

\| POST /navigation/route | **\*\*pois\_from, pois\_to\*\*** | Dijkstra over ALL floor POIs + connections; isolated node ⇒ OK with num\_of\_pois=0 |

\| POST /navigation/route-coordinates | **\*\*coordinates\_lat/lon, floor\_number, pois\_to all REQUIRED\*\*** (Scala:167–173) | anchors at argmin-nearest floor POI ≤5 km (:194–208); Phase-6 client omits floor outdoors ⇒ deterministic 400 ⇒ soft-fail by design |

\| POST /mapping/pois/add/update | OAuth2 + field whitelist | flag persisted verbatim (scala:103–107) |

Native channels: position estimates (\`NativePositionEstimate\` map), radio load/clear/info, heading stream — boundary suite covers late/disposed delivery.

**## PROVEN CORRECT**

Field names/null-handling match on all consumed paths; gzip transparently decoded by Dart HTTP; per-point FormatException skip keeps partial data usable; ApiException taxonomy carries statusCode.

**## CONFIRMED DEFECTS**

\- **\*\*API-001 (P1→by-design)\*\*** Outdoor reroutes cannot use coordinate endpoint post-Phase-6 (missing floor ⇒ 400). Documented behavior change; reroute falls to KMZ-only outdoors.

\- **\*\*API-002 (P3)\*\*** \`num\_of\_pois\` ignored by client.

\- **\*\*API-003 (P3)\*\*** String booleans + planned V1 Boolean migration = future parser dependency (parseBool leniency currently saves it).

\- **\*\*API-004 (P2)\*\*** Error classification by message substring ("not supported"/"no route") — brittle against server copy changes.

\- **\*\*API-005 (P3)\*\*** Server stores booleans as strings while migration doc targets Boolean — version-skew trap for future clients.

**## Verdict: \*\*PASS\*\* (all consumed contracts verified live; seams documented).**
**# PHASE-10 — STABILITY / CRASH AUDIT**

**## Scope**

Exceptions, races, disposal, lifecycle, stress — audited only after correctness phases.

**## PROVEN SAFE**

\- Async fencing: every NC await site identity-gated (5 sites); late/ended/superseded results inert (session\_identity, race\_battery).

\- Teardown never-throw incl. fault-injected scope explosion (termination\_test).

\- Native↔Dart listener replacement race guarded by identity-checked clear; late events after dispose fully inert (boundary suite ×12).

\- Stress ×50 preview→active→End cycles: unique sids, zero residue, post-stress responsiveness.

\- RadioMap parse failures leave residency intact; LRU eviction bounded.

\- Timer hygiene: LP stale timer generation-guarded; floor-transition timeout uses injectable clock.

**## CONFIRMED ISSUES**

\- **\*\*STABILITY-001 (P2)\*\*** \`SpaceProvider.\_navigateToIdentifier\` throws \`StateError('Space $buid not found')\` (firstWhere orElse throw) when a quick-access/search target's building isn't in \`\_spaces\` (e.g., offline/partial load). Propagates unawaited through UI closures → zone error, silent no-op. Expected: typed failure result.

\- **\*\*STABILITY-002 (P3)\*\*** \`M.\_animatedMapMove(...).then(...)\` lacks \`mounted\` guard (follow path has one).

\- **\*\*STABILITY-003 (P3)\*\*** Global mutable \`navigationLog\` hook unsynchronized (test-only hazard).

**## Ruled out**

Route-store double-ownership (Phase-2 grep + getter); ghost routes (teardown clears store); reroute resurrection (fences); pending-timer leaks in navigation suites.

**## Verdict: \*\*PASS\*\* (no P0 crash path in exercised production flows; P2 error-propagation gap open).**
**# PHASE-11 — LOGGER / DATA COLLECTION**

**## Scope determination**

Question: is Logger part of this Flutter product?

**\*\*Answer: NO — by evidence.\*\***

\- Zero files in \`lib/\` matching log/fingerprint/rssi/scan-collection semantics.

\- No endpoint in \`ApiConfig\` for RSSI/fingerprint ingestion.

\- The repository's own history (\`NAVIGATION\_IMPLEMENTATION\_HISTORY.md\`) and AGENTS.md describe data collection as the separate legacy Android app (\`clients/android-new/logger\`, package \`eg.edu.ejust.anyplace.logger\`) outside this project's launch scope.

\- Server-side ingestion exists and is healthy (\`Mapping.scala\` addRssLogs family; \`RadiomapController\` frozen-map creation) — it is fed by the external logger, not by CampusFind.

**## Consequences audited (not defects of this client)**

\- Radiomap freshness for B7 (and any building) depends entirely on the external logger app + upload pipeline. Verified live: B7 F0 has a working radiomap (positioning suite green); **\*\*F1 has none\*\*** (DATA-002) — someone must run the logger on floor 1 before indoor positioning works upstairs.

\- \`PositioningController.scala\` realtime endpoint exists but this client intentionally uses native on-device KNN instead.

**## Missing functionality (scoped)**

\- No in-app "radiomap health" indicator despite client knowing per-floor coverage via metadata errors (would have surfaced DATA-002 to users).

**## Verdict: \*\*BLOCKED / OUT OF SCOPE\*\* for this Flutter product. Absence is intentional architecture, not a defect. Field radiomap collection remains a dependency tracked under DATA-002.**
**# PHASE-12 — CROSS-FEATURE INTEGRATION**

**## Boundary audit results**

\| Boundary | Finding |

\|---|---|

\| DATA → POSITIONING | DATA-002 (no F1 radiomap) makes upper-floor positioning impossible — clean client code, pure data gap. |

\| DATA → NAVIGATION | DATA-001 (G13 flag) previously poisoned entrance pool; post-fix verified healthy (\`Entrance→G01 OK path=5\`). Remaining risk: same mislabel pattern in other buildings unaudited. |

\| POSITIONING → NAVIGATION | POS-001 premature-confirm window: guidance can fire while user is at the doorway. Post-fix anchor lands on a *\*clean\** POI, but "confirmed indoors ≠ inside" semantics remain. |

\| POSITIONING → MAP | Faithful; hold-projection + heading freeze keep marker/arrow coherent (Phase-8 PASS). |

\| ROUTE HERE → ACTIVE NAV | Preview route is exactly what Start Directions adopts (identity pins); no preview→active divergence exists post-Phase-2. |

\| Floor selection → Route visibility | INDOOR-001: in-session browsing wipe hides indoor legs AND disables exit fallback geometry (the compounding AUD-01 cluster). |

\| API → Models | String booleans rely on lenient parser (API-003); coordinate-endpoint floor cliff (API-001) intentionally converts reroute-api to outdoor-only. |

\| Lifecycle → Navigation | Tab-leave terminates by design; dispose races inert; stress-proven. |

\| Entrance semantics → Routing | Anyplace's dual encoding (flag XOR type) + OR-classifier = role ambiguity; scorer resolves ambiguities geometrically (NAV-001). Fixed for B7 by data; structural ambiguity remains for future buildings. |

\| Radiomap → Positioning | Coverage gaps (F1, 6 buildings) silently degrade to GPS-only with no user-facing signal beyond status line. |

**## Compensation patterns detected**

1\. Phase-8 guidance historically masked composition-tail defects by rewriting routes after entry (removed as masking now that both are correct).

2\. INV-4 guards prevent route destruction on the INDOOR-001 tap, but cannot preserve exit-detection context — partial compensation only.

3\. Server argmin projection would have masked an empty-entrance-pool scenario by inventing a start node — currently unreachable outdoors due to Phase-6 floor omission.

**## Cross-feature verdict**

All boundaries verified with explicit owner per semantic; remaining risks are the three open P1/P2 code items plus data-gaps, not boundary confusion.