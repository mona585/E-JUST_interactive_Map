# Complete Navigation System — Full Problem Resolution & Implementation Plan

**Target:** `clients/flutter/anyplace_campusfind`

**Baseline:** Current implementation documented at commit `2856a4b7` on `campusfind-migration`.

**Purpose:** This document is an **implementation plan**, not an analysis. The agent must execute it **phase by phase**, verify each phase before continuing, and preserve all working Indoor/Wi-Fi functionality while fixing Outdoor Navigation, My Map integration, routing, handoffs, rerouting, lifecycle, state synchronization, and reliability.

---

# 0. Non-Negotiable Rules

Before making any change:

1. **Inspect the current source first.**
2. Do not assume the documentation is the desired architecture; it is only the baseline of what currently exists.
3. Do not remove working Wi-Fi fingerprinting.
4. Do not replace indoor positioning with GPS.
5. Do not replace My Map with another map implementation.
6. Google Maps remains the **renderer**, not the positioning source.
7. `LocationProvider.currentFix` remains the canonical location input to navigation.
8. Navigation must support:

   * Outdoor GPS
   * Indoor Wi-Fi fingerprinting
   * Outdoor → Indoor
   * Indoor → Outdoor
   * Multi-floor navigation
   * Cross-building navigation
   * My Map rendering
   * Rerouting
   * Arrival
   * Navigation termination
9. Do not introduce a second independent navigation engine.
10. Do not silently retarget an active navigation session.
11. Do not allow floor/building selection APIs to accidentally destroy an active navigation route.
12. Every asynchronous navigation operation must be associated with the **current navigation session/request identity**.
13. Do not consider a phase complete until its acceptance tests pass.
14. Do not make unrelated UI changes.
15. Do not modify backend behavior unless the source inspection proves it is required and the change is explicitly justified.

---

# 1. Phase 0 — Create a New Baseline Before Editing

First inspect the actual repository again.

Verify:

```text
lib/main.dart
lib/state/location_provider.dart
lib/state/navigation_controller.dart
lib/state/navigation_state_model.dart
lib/state/space_provider.dart

lib/data/models/
lib/data/repositories/
lib/data/datasources/

lib/ui/screens/map_screen.dart
lib/ui/widgets/

lib/screens/main_shell.dart

android/.../sensing/

server/.../NavigationController.scala
server/.../Dijkstra.scala

test/
```

Also inspect all current references to:

```text
_activeNavigationRoute
_activeRoute
_navigationDestinationPuid
_selectedPoi
_selectedSpace
_selectedFloor
selectSpace()
selectFloor()
clearSelection()
clearFloorSelection()
clearSelectedPoi()
clearNavigationRoute()
endNavigation()
requestRouteToSelectedPoi()
_triggerReroute()
loadRadioMapForSelectedFloor()
clearRadioMap()
currentFix
currentLocation
_followMode
```

### Required output

Before modifying code, produce a short implementation report:

```text
Current implementation
↓
Files involved
↓
Current data ownership
↓
Current route lifecycle
↓
Current navigation lifecycle
↓
Current My Map rendering lifecycle
↓
Planned changes
```

Do not start implementation until this baseline is understood.

---

# 2. Phase 1 — Establish One Authoritative Navigation Session

## Problem

The current system has two route copies:

```text
SpaceProvider._activeNavigationRoute
NavigationController._activeRoute
```

The Map renders the first.

Navigation calculations use the second.

This creates:

* invisible navigation
* stale polylines
* silent route replacement
* route disappearance during floor transitions
* route disappearance after building exit
* destination mismatch
* inconsistent rerouting

## Required architecture

Create a clear ownership contract:

```text
Navigation Session
        │
        ├── destination
        ├── active route
        ├── route revision
        ├── current segment
        ├── current floor
        ├── current building
        └── navigation state
```

There must be **one authoritative navigation route for the active session**.

The Map and controller must consume the same logical route.

### Preferred design

`NavigationController` owns the active navigation session and route.

`SpaceProvider` remains responsible for:

* selected space
* selected floor
* selected POI
* floorplan data
* POIs
* radiomap lifecycle

But those browsing/selection operations must not independently destroy the active navigation session.

If the implementation chooses to keep the route physically stored in `SpaceProvider`, then establish a strict synchronization contract where:

```text
active navigation route
=
route being evaluated
=
route being rendered
```

There must never be a state where:

```text
controller route != rendered route
```

unless the route is explicitly in a controlled replacement transaction.

---

# 3. Phase 2 — Introduce Navigation Session Identity

Every navigation run must have a unique session ID.

Example concept:

```text
NavigationSession
    sessionId
    destinationPuid
    destinationBuilding
    destinationFloor
    route
    routeRevision
    state
```

Every async operation must capture:

```text
sessionId
routeRequestId
```

and validate them before committing.

This applies to:

* initial route calculation
* rerouting
* floor loading
* radiomap loading
* POI loading
* building preload
* entrance preparation
* cross-building route composition
* OSRM requests
* backend route requests

---

# 4. Phase 3 — Fix Destination Changes

## Current problem

User can be navigating to:

```text
Room A
```

then select:

```text
Room B
```

The active controller can still target Room A.

A delayed reroute can even reinstall Room A's route.

## Required behavior

When destination changes during an active session:

### Option A — safest

Explicitly terminate the old navigation session and require:

```text
Calculate Route
→ Preview
→ Start Directions
```

for the new destination.

### Option B

Perform an explicit controlled destination replacement:

```text
old session
↓
invalidate old async work
↓
clear old route
↓
create new route
↓
confirm new destination
↓
continue only if explicitly allowed
```

Do **not** silently retarget an active session.

### Acceptance

Impossible:

```text
Navigation to A
→ select B
→ delayed A route appears
```

---

# 5. Phase 4 — Separate Browsing Selection From Navigation Selection

This is one of the major architectural problems.

Current APIs such as:

```text
selectSpace()
selectFloor()
selectPoi()
clearSelection()
```

can destroy navigation state.

That must stop.

## New rule

Browsing state and navigation state are different concepts.

For example:

```text
Selected floor for browsing
        ≠
Current navigating floor
```

and:

```text
Selected POI
        ≠
Navigation destination
```

unless the user explicitly starts/replaces navigation.

---

# 6. Phase 5 — Fix `selectFloor()` During Active Navigation

## Current bug

Automatic floor transitions call:

```text
selectFloor()
```

which calls:

```text
_resetNavigationRouteState()
```

and destroys the visible route.

## Required behavior

When navigation is active:

```text
selectFloor(F2)
```

must:

1. Load Floor 2.
2. Load Floor 2 radiomap.
3. Load Floor 2 POIs.
4. Update selected floor.
5. Update current navigating floor.
6. Preserve the active navigation route.
7. Preserve route destination.
8. Preserve route segments for other floors.
9. Keep the route available to the Map.
10. Only change which floor's geometry is emphasized/active.

Never clear the entire navigation route merely because the floor changed.

---

# 7. Phase 6 — Fix Route Rendering in My Map

The Map is a critical part of navigation.

Current problem:

```text
MapScreen → SpaceProvider route
Controller → private route
```

This must become:

```text
Navigation Session
       ↓
Authoritative Route
       ↓
My Map / MapScreen
```

## Required rendering rules

My Map must correctly render:

### Outdoor segment

Visible on outdoor map.

### Indoor segment

Visible when its floor is active.

### Entrance transition

Visible as the transition between outdoor and indoor.

### Floor transition

Visible/represented correctly between floors.

### Future floor

Must not incorrectly appear as active navigation geometry on the current floor.

### Current floor

Must always show the route relevant to that floor.

### Route after reroute

Must immediately replace the old rendered route.

### Route after building exit

Must remain visible.

### Route after floor change

Must remain available.

---

# 8. Phase 7 — Correct Route Segment Metadata

## Current problem

Hybrid outdoor waypoints can be stamped with:

```text
destination building
destination floor
```

even though they are outdoor.

This breaks floor-filtered deviation checks.

## Required model rule

Every route point/segment must have correct semantic metadata.

Outdoor points:

```text
isOutdoor = true
floor = null
building = null
```

Indoor points:

```text
isOutdoor = false
building = actual building
floor = actual floor
```

Transition points:

```text
explicit transition metadata
```

Do not use destination metadata as a shortcut for unrelated route points.

---

# 9. Phase 8 — Define Correct Route Geometry Semantics

Create a single function/concept equivalent to:

```text
getActiveRouteGeometry(currentLocationContext)
```

It must determine:

```text
Outdoor:
    outdoor route geometry

Indoor:
    current building + current floor geometry

Transition:
    transition geometry

Cross-floor:
    connector/transition geometry
```

This must be used consistently by:

* deviation detection
* route progress
* rendering
* arrival anchor resolution
* segment advancement
* rerouting context

Do not have different components independently reconstruct route geometry.

---

# 10. Phase 9 — Fix Outdoor GPS Quality Pipeline

The current GPS is essentially raw pass-through.

That is insufficient for reliable outdoor navigation.

Implement a dedicated GPS quality layer **without replacing the raw GPS source**.

Required checks:

### 10.1 Accuracy

Reject or mark unreliable fixes when accuracy is clearly unusable.

Do not rely only on:

```text
accuracy >100m → paused
```

Navigation should distinguish:

```text
good
usable
poor
invalid
```

---

### 10.2 Staleness

Each GPS fix must be checked against timestamp.

Reject stale fixes.

Do not allow:

```text
old GPS
↓
treated as current location
```

---

### 10.3 Outlier detection

Detect impossible jumps using:

* distance
* timestamp delta
* implied speed
* accuracy

Do not blindly reject legitimate high-speed movement.

Use a physically reasonable threshold.

---

### 10.4 Smoothing

Apply lightweight smoothing only to presentation/navigation position where appropriate.

Do not destroy the raw sensor value.

Maintain:

```text
raw GPS
filtered navigation GPS
```

so debugging remains possible.

---

# 11. Phase 10 — Preserve GPS Responsiveness

The target is responsive navigation.

Do not introduce heavy smoothing that causes visible lag.

The system should process incoming fixes immediately.

Target:

```text
up to ~2 updates/second or better when Android provides them
```

Do not artificially throttle useful location updates to 3+ seconds.

---

# 12. Phase 11 — Make Accuracy Affect Navigation Decisions Correctly

Current thresholds are fixed:

```text
15m arrival
15m deviation
30m KMZ off-route
100m pause
```

They should not blindly ignore location quality.

Introduce a clear policy:

```text
high-quality GPS
    → normal thresholds

medium-quality GPS
    → require stronger confirmation

poor GPS
    → pause/avoid reroute decisions

invalid GPS
    → ignore fix
```

Do not allow one bad GPS fix to trigger:

* reroute
* arrival
* building exit
* building entry
* major route transition

---

# 13. Phase 12 — Fix Outdoor Route Progress

KMZ progress currently exists only in one branch.

Create consistent route progress behavior.

For outdoor navigation:

```text
GPS position
↓
project/snap to active outdoor route
↓
progress
↓
distance from route
↓
off-route decision
```

This must work for:

* pure KMZ routes
* hybrid routes
* rerouted KMZ routes
* cross-building routes

Do not silently disable deviation because metadata filtering returned no points.

---

# 14. Phase 13 — Fix Off-Route Detection

Use two complementary mechanisms:

### Outdoor

```text
route projection / snap distance
+
polyline deviation
```

### Indoor

```text
floor-filtered route geometry
+
building/floor identity
```

### Transition

Do not reroute while the user is legitimately changing floors/buildings.

---

# 15. Phase 14 — Prevent False Reroutes

A single noisy GPS fix should not automatically produce a route recalculation.

Require:

```text
persistent deviation
OR
strong KMZ off-route evidence
```

while respecting the cooldown.

Recommended conceptual flow:

```text
bad fix
    ↓
quality check
    ↓
possible deviation
    ↓
confirmation
    ↓
reroute
```

---

# 16. Phase 15 — Redesign Rerouting Transaction

Rerouting must be atomic from the user's perspective.

Current:

```text
old route
↓
new route written to scope
↓
controller adopts
```

Replace with:

```text
Current Session
       ↓
capture sessionId + destination + routeRevision
       ↓
calculate candidate route
       ↓
validate candidate
       ↓
validate session still active
       ↓
validate destination unchanged
       ↓
validate floor/building context
       ↓
commit new route atomically
```

Until commit:

> old route remains active and visible.

---

# 17. Phase 16 — Rerouting Failure Policy

If reroute fails:

```text
new route rejected
old route remains
navigation remains alive
```

But expose a clear state:

```text
reroute failed
```

rather than silently pretending the route is current.

Allow a later retry after cooldown.

---

# 18. Phase 17 — Fix Rerouting Floor Context

Current outdoor rerouting can use:

```text
_currentNavigatingFloor ?? '0'
```

even when the user is outdoors.

Fix this.

Outdoor rerouting must not send stale indoor floor information.

Routing context should explicitly be:

```text
outdoor
OR
indoor(building, floor)
```

not inferred from a nullable floor string.

---

# 19. Phase 18 — Improve Routing Cascade

Preserve the existing fallback strategy but make its semantics explicit:

```text
Cross-building
    ↓
KMZ
    ↓
OSRM
    ↓
Backend coordinate route
    ↓
Backend POI route
    ↓
Hybrid
    ↓
straight-line fallback
```

Every result must carry:

```text
complete / partial
source
segment type
confidence/quality
```

Do not silently accept a partial route as if it were complete.

---

# 20. Phase 19 — Fix Cross-Building Route Composition

Cross-building routing must correctly produce:

```text
Outdoor
→ entrance
→ indoor
→ floor transition
→ indoor
→ exit
→ outdoor
```

depending on the journey.

Do not hard-cap a valid journey at 6 segments without explicit handling.

If the cap remains:

```text
detect truncation
mark route incomplete
surface warning
```

Prefer removing the arbitrary cap if safe.

---

# 21. Phase 20 — Fix Outdoor → Indoor Handoff

The desired behavior:

```text
Outdoor GPS
     ↓
100m building preparation
     ↓
load building context
     ↓
25m entrance proximity
     ↓
enteringBuilding
     ↓
load destination floor + radiomap
     ↓
Wi-Fi corroboration
     ↓
activeIndoor
```

Important:

Wi-Fi appearing early must not blindly force indoor mode.

Require:

```text
Wi-Fi quality
+
building identity
+
reasonable spatial relationship
```

before committing.

---

# 22. Phase 21 — Fix Indoor → Outdoor Handoff

Desired:

```text
Wi-Fi loss
↓
GPS recovery
↓
GPS quality validation
↓
outside-building evidence
↓
exit confirmation
↓
activeOutdoor
```

Do NOT clear:

* active route
* destination
* navigation session
* remaining route
* necessary routing metadata

just because indoor positioning is no longer needed.

Only clear the **indoor positioning context**.

---

# 23. Phase 22 — Separate Radiomap Lifecycle From Navigation Route Lifecycle

This is critical.

Current:

```text
clearSelection()
↓
clear radiomap
+
clear route
```

These must be independent.

Correct:

```text
Leaving Building C
    ↓
clear C radiomap
    ↓
preserve navigation session
    ↓
preserve route
    ↓
continue outdoor GPS
```

When approaching Building D:

```text
preload D
↓
select destination floor
↓
load D radiomap
```

---

# 24. Phase 23 — Fix Floor Transition Lifecycle

Correct:

```text
activeIndoor F1
↓
connector detected
↓
begin transition
↓
freeze visual position temporarily
↓
preserve route
↓
load F2 floorplan
↓
load F2 radiomap
↓
wait for F2 identity confirmation
↓
activeIndoor F2
↓
resume marker
↓
resume route evaluation
```

There must be:

* timeout
* recovery
* wrong-floor handling
* no permanent blackout
* preserved route

If confirmation never arrives:

```text
do not remain indefinitely frozen
```

Provide a controlled recovery path.

---

# 25. Phase 24 — Fix Radiomap Async Races

Keep request IDs, but tie them to:

```text
navigation session
building
floor
radiomap request
```

A late radiomap response must never activate the wrong floor/building.

---

# 26. Phase 25 — Fix Navigation Termination

Create one canonical method:

```text
terminateNavigationSession()
```

It must safely perform the required cleanup.

No caller should have to remember:

```text
endNavigation()
+
clearNavigationRoute()
```

as two unrelated operations.

Termination must:

* invalidate session
* cancel/ignore async work
* clear navigation route
* clear destination
* clear controller state
* clear transition state
* reset rerouting
* release held position
* stop navigation-specific timers/listeners
* restore idle UI

Whether GPS/Wi-Fi background tracking remains active for general My Map functionality should be a **separate sensing lifecycle decision**, not an accidental navigation side effect.

---

# 27. Phase 26 — Separate Navigation Tracking From General Location Tracking

Do not stop the global location provider merely because navigation ended if My Map needs live positioning.

Instead:

```text
Location tracking
        │
        ├── Map browsing
        │
        └── Navigation session
```

Navigation subscribes/unsubscribes to the stream logically.

This prevents:

> End Navigation = accidentally kill location needed by My Map.

---

# 28. Phase 27 — Fix Arrival Detection

Arrival must use the authoritative route/session.

### Outdoor

Require:

```text
valid GPS
+
destination proximity
+
route/context consistency
+
2 consecutive confirmations
```

### Indoor

Require:

```text
Wi-Fi
+
correct building
+
correct floor
+
destination proximity
+
2 consecutive confirmations
```

Do not arrive because of a stale GPS fix.

Do not arrive because of a point from another floor.

---

# 29. Phase 28 — Fix Arrival Anchor Lifecycle

The destination anchor must survive:

* floor changes
* building exit
* radiomap clearing
* POI list reload

Do not depend exclusively on currently loaded POIs.

Store stable destination information:

```text
destinationPuid
destination coordinates
destination building
destination floor
```

and resolve the live POI object only when available.

---

# 30. Phase 29 — Camera Behavior

My Map should behave consistently.

### Start navigation

Fit route once.

### Active navigation

Follow user.

### Manual pan

Exit follow mode.

### Re-center

Resume follow.

### Reroute

Do not blindly reset camera.

Optionally refit only when explicitly needed.

### Indoor

Zoom appropriate to floor navigation.

### Outdoor

Zoom appropriate to walking navigation.

### Transition

Do not jump unpredictably.

---

# 31. Phase 30 — Marker and Heading

Keep:

```text
Position = LocationProvider
Heading = DeviceHeadingBridge
```

Heading remains presentation-only.

Marker:

```text
blue dot
+
direction arrow
```

must rotate smoothly.

Heading must never alter:

* GPS position
* Wi-Fi position
* route
* deviation
* arrival
* building detection

---

# 32. Phase 31 — My Map Integration Contract

Define explicitly:

### My Map owns

* map rendering
* marker rendering
* route rendering
* camera
* user interaction
* follow mode

### LocationProvider owns

* location data

### NavigationController owns

* navigation session
* state
* destination
* route progress
* transitions
* rerouting
* arrival

### SpaceProvider owns

* map content
* buildings
* floors
* POIs
* radiomap loading
* browsing selection

No component may silently mutate another component's navigation lifecycle.

---

# 33. Phase 32 — Remove Comment/Behavior Drift

Fix or remove comments claiming behavior that does not exist, including:

* deferred indoor route refresh
* KMZ overlay restrictions
* other misleading navigation comments

Documentation must describe actual behavior.

---

# 34. Phase 33 — Fix State Machine Semantics

Keep the 10-state machine, but make state ownership strict.

Every automatic transition must have:

```text
source
trigger
evidence
timeout
recovery
side effects
```

No direct state mutation except controlled termination/recovery paths.

`rerouting` should remain an overlay/session state or be modeled explicitly without corrupting the underlying active mode.

---

# 35. Phase 34 — Timer Consistency

Use one injectable clock abstraction.

Do not mix:

```text
DateTime.now()
```

with:

```text
_now()
```

This makes transition/reroute tests deterministic.

---

# 36. Phase 35 — Async Cancellation/Invalidation

There may not be true HTTP cancellation.

That is acceptable if every async operation has:

```text
sessionId
requestId
destination
building
floor
routeRevision
```

and validates them before commit.

The important rule is:

> A completed old operation may never modify current navigation state.

---

# 37. Phase 36 — Failure Recovery

Implement explicit recovery for:

### GPS unavailable

Remain in appropriate non-navigation state.

### GPS poor

Pause safely.

### GPS stale

Ignore stale fix.

### Wi-Fi unavailable indoors

Do not fabricate indoor position.

### Wrong building

Do not enter activeIndoor.

### Wrong floor

Do not confirm floor.

### Radiomap failure

Allow controlled retry.

### Backend failure

Use fallback engines.

### OSRM failure

Use local/fallback routing.

### Reroute failure

Keep valid old route.

### Route invalid

Never activate it.

### Async stale result

Discard.

---

# 38. Phase 37 — Testing Must Be Scenario-Based

Do not only run unit tests.

Test the complete system.

## Test 1 — Outdoor only

```text
Parking
→ Building C
```

Verify:

* GPS follows smoothly
* route visible
* marker follows
* camera follows
* off-route detection works
* rerouting works
* arrival works

---

## Test 2 — Outdoor → Indoor

```text
Parking
→ Building C
→ Room 104
```

Verify:

* preload
* entrance detection
* Wi-Fi handoff
* floor loading
* route remains visible
* marker switches GPS → Wi-Fi
* arrival works

---

## Test 3 — Wi-Fi appears too early

Verify no false indoor transition.

---

## Test 4 — Wrong building Wi-Fi

Verify:

```text
enteringBuilding
→ timeout
→ activeOutdoor
```

without destroying route.

---

## Test 5 — Indoor floor transition

```text
Floor 1
→ Floor 2
```

Verify:

* route remains visible
* floor 1 geometry transitions correctly
* floor 2 geometry becomes active
* radiomap switches
* marker is not permanently frozen

---

## Test 6 — Indoor → Outdoor

Verify:

* GPS recovery
* exit confirmation
* route remains visible
* radiomap clears only when appropriate
* outdoor navigation continues

---

## Test 7 — Destination change

```text
Room A
→ Room B
```

Verify no delayed Room A route returns.

---

## Test 8 — Reroute + destination change race

Start reroute for A.

Change to B.

Verify A's result is discarded.

---

## Test 9 — End during API request

Verify no stale route appears after End.

---

## Test 10 — Poor GPS

Inject poor accuracy.

Verify:

```text
navigation pauses
```

without route corruption.

---

## Test 11 — GPS jump

Inject an impossible jump.

Verify marker/navigation does not teleport or trigger false arrival/reroute.

---

## Test 12 — Stale GPS

Inject an old timestamp.

Verify it is rejected.

---

## Test 13 — My Map browsing after End

Verify location tracking still behaves according to the intended map-browsing lifecycle.

---

## Test 14 — Route replacement

Reroute must replace:

```text
rendered route
+
evaluation route
```

atomically.

---

# 39. Phase 38 — Automated Tests

Add tests for:

### Route ownership

```text
renderedRoute == evaluationRoute
```

### Destination identity

Old destination cannot overwrite new destination.

### Floor changes

`selectFloor()` cannot destroy active navigation route.

### Exit

`clearIndoorContext()` cannot destroy navigation route.

### Rerouting

Old route remains until new route is validated.

### Async

Old request cannot commit.

### GPS

Stale/outlier/poor fixes handled correctly.

### Arrival

Requires valid evidence.

### State machine

All transitions legal.

---

# 40. Phase 39 — Logging / Debug Instrumentation

Add structured logs for:

```text
SESSION_START
SESSION_END

GPS_ACCEPTED
GPS_REJECTED
GPS_STALE
GPS_OUTLIER

WIFI_BELIEF_ENTER
WIFI_BELIEF_EXIT

BUILDING_PRELOAD
ENTRANCE_DWELL_START
INDOOR_CONFIRMED
EXIT_DWELL_START
OUTDOOR_CONFIRMED

FLOOR_TRANSITION_START
FLOOR_CONFIRMED

ROUTE_REQUEST_START
ROUTE_REQUEST_SUCCESS
ROUTE_REQUEST_DISCARDED
REROUTE_START
REROUTE_SUCCESS
REROUTE_DISCARDED
REROUTE_FAILED

ARRIVAL
```

Every navigation event should include:

```text
sessionId
destination
source
building
floor
routeRevision
```

when available.

---

# 41. Phase 40 — Final Acceptance Architecture

The final system should behave conceptually as:

```text
                         ┌──────────────────┐
                         │      My Map      │
                         │ Renderer / UI    │
                         └────────┬─────────┘
                                  │
                                  ↓
                       ┌─────────────────────┐
                       │ Navigation Session  │
                       │ SINGLE SOURCE       │
                       │ OF NAVIGATION TRUTH │
                       └──────────┬──────────┘
                                  │
              ┌───────────────────┼──────────────────┐
              ↓                   ↓                  ↓
          Route state         State machine      Destination
              │                   │                  │
              ↓                   ↓                  ↓
       Route progress       O/I transitions     Arrival
              │                   │                  │
              └───────────────────┼──────────────────┘
                                  ↓
                           Rerouting engine
                                  ↓
                       validated route commit
                                  │
                                  ↓
                       LocationProvider
                                  │
                    ┌─────────────┴─────────────┐
                    ↓                           ↓
                  GPS                         Wi-Fi
                    │                           │
             quality pipeline             radiomap
                    │                           │
                    └─────────────┬─────────────┘
                                  ↓
                         canonical PositionFix
```

---

# 42. Implementation Order — MUST FOLLOW THIS ORDER

The agent should **not randomly fix bugs**.

Execute exactly in this order:

### Phase A — Architecture

1. Baseline inspection
2. Navigation session identity
3. Single route ownership
4. Destination ownership
5. Browsing vs navigation selection separation

### Phase B — Route correctness

6. Fix route metadata
7. Fix route geometry selection
8. Fix My Map rendering
9. Fix floor transitions
10. Fix building exit route preservation

### Phase C — Outdoor positioning

11. GPS timestamp/staleness
12. GPS quality classification
13. GPS outlier detection
14. lightweight filtering
15. responsive update pipeline

### Phase D — Navigation decisions

16. deviation detection
17. route progress
18. arrival
19. building approach
20. entrance/exit confirmation

### Phase E — Rerouting

21. session-aware rerouting
22. destination validation
23. floor/building context validation
24. atomic route replacement
25. reroute failure recovery

### Phase F — Indoor/Outdoor integration

26. Outdoor → Indoor
27. Indoor → Outdoor
28. radiomap lifecycle separation
29. floor transition lifecycle
30. Wi-Fi/GPS arbitration integration

### Phase G — Lifecycle

31. unified navigation termination
32. async invalidation
33. timer abstraction
34. sensing vs navigation lifecycle

### Phase H — My Map/UI

35. camera behavior
36. marker behavior
37. route rendering
38. follow mode
39. status/transition UI

### Phase I — Verification

40. unit tests
41. integration tests
42. race-condition tests
43. real-device testing
44. full campus walking scenarios
45. final architecture audit

---

# 43. Definition of Done

The implementation is **NOT complete** until all of the following are true.

### Route

* [ ] One authoritative navigation route.
* [ ] Map and controller never silently diverge.
* [ ] Route survives floor changes.
* [ ] Route survives building exit.
* [ ] Route replacement is atomic.
* [ ] Old destinations cannot overwrite new destinations.
* [ ] Correct building/floor metadata exists.
* [ ] Partial routes are explicitly marked.

### Outdoor

* [ ] GPS stale fixes rejected.
* [ ] GPS impossible jumps handled.
* [ ] GPS quality affects navigation decisions.
* [ ] Navigation remains responsive.
* [ ] Off-route detection works reliably.
* [ ] Rerouting works.
* [ ] Failed reroute preserves valid route.

### Indoor

* [ ] Wi-Fi fingerprinting remains functional.
* [ ] Radiomap loading remains functional.
* [ ] Floor transitions preserve navigation.
* [ ] Wrong-floor evidence does not falsely confirm.
* [ ] Indoor arrival requires correct identity.

### Handoff

* [ ] Outdoor → Indoor works.
* [ ] Indoor → Outdoor works.
* [ ] Early Wi-Fi does not cause false entry.
* [ ] Wrong-building Wi-Fi safely reverts.
* [ ] Exit does not destroy navigation.

### My Map

* [ ] Marker always represents canonical position.
* [ ] Route displayed is the route being evaluated.
* [ ] Outdoor route visible.
* [ ] Indoor route visible.
* [ ] Transition route visible.
* [ ] Floor-specific rendering works.
* [ ] Camera follow works.
* [ ] Manual pan exits follow.
* [ ] Re-center restores follow.

### Lifecycle

* [ ] End invalidates the navigation session.
* [ ] Old async results cannot modify current navigation.
* [ ] Navigation cleanup is centralized.
* [ ] Map browsing location behavior is independent from navigation.
* [ ] No ghost route after End.
* [ ] No invisible navigation after route deletion.

### Testing

* [ ] Outdoor-only test passes.
* [ ] Outdoor → Indoor passes.
* [ ] Indoor → Outdoor passes.
* [ ] Multi-floor passes.
* [ ] Cross-building passes.
* [ ] Reroute passes.
* [ ] Destination-change race passes.
* [ ] End-during-request passes.
* [ ] GPS jump test passes.
* [ ] GPS stale test passes.
* [ ] Poor GPS test passes.
* [ ] My Map browsing remains functional.

---

# 44. Final Instruction to the Implementing Agent

**Do not treat this as a list of independent bug fixes.**

The problems are connected.

The correct dependency chain is:

```text
Route ownership
      ↓
Navigation session identity
      ↓
Selection/navigation separation
      ↓
Route lifecycle
      ↓
My Map rendering
      ↓
Floor/building transitions
      ↓
GPS quality
      ↓
Deviation
      ↓
Rerouting
      ↓
Arrival
      ↓
Termination
```

Therefore:

> **Implement one phase at a time. After each phase, run the relevant tests, inspect the diff, verify that existing Indoor Wi-Fi functionality still works, and only then proceed to the next phase.**

Do not declare success because the app builds.

The final acceptance criterion is **behavioral correctness across the complete journey**:

```text
My Map
  ↓
Outdoor GPS
  ↓
Route
  ↓
Building approach
  ↓
Entrance
  ↓
Wi-Fi fingerprint positioning
  ↓
Indoor route
  ↓
Floor transition
  ↓
Indoor destination
  ↓
Building exit
  ↓
GPS recovery
  ↓
Outdoor continuation
  ↓
Rerouting when necessary
  ↓
Arrival
  ↓
Clean termination
```

**The objective is not merely to make individual bugs disappear. The objective is to make Outdoor, Indoor, Routing, My Map, Positioning, Handoffs, Rerouting, and Lifecycle behave as one coherent navigation system.**
