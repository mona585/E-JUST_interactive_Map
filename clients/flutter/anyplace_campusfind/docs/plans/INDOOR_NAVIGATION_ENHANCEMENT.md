# Indoor Navigation Enhancement — Complete Plan

## 1. Overview

Two-mode navigation system: **Route Preview** (frame the full route) → **Active Navigation** (follow mode with floor transitions). Handles outdoor→indoor transitions with automatic building/floor detection.

---

## 2. State Machine

```
IDLE
  ↓ user taps "Route Here"
ROUTE_PREVIEW
  ↓ camera frames full route, "Start Directions" shown
  ↓ user taps "Start Directions"
ACTIVE_NAVIGATION
  ↓ follow mode ON, bottom sheet collapsed
  ↓ user taps "End Navigation"
IDLE
```

**Sub-states within ACTIVE_NAVIGATION:**

```
OUTDOOR_FOLLOW → approaching building
  ↓ GPS near entrance
INDOOR_FOLLOW → navigating on current floor
  ↓ approaching connector, pre-load next floor
TRANSITIONING → positioning blackout in stairwell/elevator
  ↓ positioning confirms new floor
INDOOR_FOLLOW → continued on new floor
  ↓ user exits building (combined signals)
OUTDOOR_FOLLOW → back outside
```

---

## 3. Key Components to Build/Modify

### 3.1 Navigation Controller (NEW)

**File:** `lib/state/navigation_controller.dart`

A new `ChangeNotifier` that orchestrates the entire navigation lifecycle:

- Holds navigation state (idle, preview, active)
- Manages outdoor/indoor/transitioning sub-states
- Owns the active route, current floor, destination
- Coordinates between `SpaceProvider`, `LocationProvider`, and map camera
- Handles rerouting logic, deviation detection, cooldowns
- Manages floor transition detection and pre-loading

### 3.2 Route Preview Mode

**Trigger:** User taps "Route Here" → `requestRouteToSelectedPoi()`

**Camera framing:**

- After route loads, compute bounding box of all `polylinePoints`
- Use `LatLngBounds` to fit camera with padding
- Animate camera to show entire route on floorplan
- Implementation: new `_fitRouteBounds()` method in `MapScreen`

**Bottom sheet:**

- `PoiDetailCard` shows "Route ready on floor X"
- "Start Directions" button appears below route status
- "Clear" button still available

### 3.3 Active Navigation Mode

**Trigger:** User taps "Start Directions"

**Camera follow:**

- User position pinned to **lower third** of screen (not dead center)
- Camera follows `LocationProvider.currentLocation` updates
- Fixed zoom level (configurable, default 19.0 for indoor, 17.0 for outdoor)
- North-up orientation (no heading lock)
- Smooth animation between position updates (lerp, not instant jump)

**Follow mode logic:**

- Active by default when navigation starts
- Temporarily disabled when user pans/zooms
- Re-enabled when user taps re-center/My Location button
- Re-center also re-collapses bottom sheet

**Rerouting:**

- Check deviation every GPS update (after cooldown)
- Deviation = perpendicular distance from user position to nearest route segment
- Threshold: 15m (configurable)
- Cooldown: 15s after last reroute
- Suppress during floor transition (until positioning stable)
- Auto-reroute from current position to same destination
- Retry up to 3 times on network failure, keep old route if all fail

### 3.4 Outdoor → Indoor Transition (Two-Stage)

**Stage 1 — Early Preparation:**

- While navigating outdoors, check GPS distance to destination building center
- When distance < 100m (configurable): start pre-loading
  - Building floors list
  - Ground floor floorplan
  - Ground floor POIs (to find entrance POIs)
  - Ground floor radiomap
- Camera stays in outdoor follow mode
- Bottom sheet shows: "Approaching [Building Name]"

**Stage 2 — Indoor Transition:**

- After ground floor POIs loaded, find **nearest entrance POI** to GPS position (Haversine)
- When GPS distance to entrance < 25m (configurable):
  - Auto-select building + ground floor
  - Request indoor route from server
  - Switch to indoor floorplan view
  - Start indoor follow mode
- **Fallback (no entrance POIs):** Use building center proximity with tighter threshold

**Hysteresis:**

- Entry threshold ≠ exit threshold (prevents flickering)
- After indoor transition fires, suppress re-checking for 30s or until positioning stable
- Preparation stage: start at 100m, cancel only if >150m away

### 3.5 Floor Transition Detection

**Route-segment progress (primary trigger):**

- Track which route segment user is on (nearest point on polyline)
- When user reaches segment just before floor-change point → pre-load next floor

**Distance fallback:**

- If user deviates from route but is near a connector POI → pre-load

**Floor switch trigger (position-driven):**

- DO NOT switch floor based on route data alone
- Switch ONLY when positioning confirms new floor:
  - 3 consecutive valid indoor estimates on new floor
  - Each within 5s of previous
  - Position delta < 15m between estimates
  - `matchedAps >= 2` (minimum confidence)
- Pre-load next floor's floorplan + radiomap BEFORE user reaches connector

**Positioning blackout:**

- Hold last known floor and position
- Show "Moving to Floor X..." status
- Do NOT switch to next floor until positioning confirms

### 3.6 Building Exit Detection

**Combined signals (ALL must be true):**

1. Indoor positioning lost (source changed `indoorWifi` → `gps`)
2. GPS available (`_gpsLocation != null`)
3. GPS accuracy < 15m (outdoor-quality signal)
4. GPS position outside `FloorplanModel.bounds` (primary) OR distance from building center > 80m (fallback)

**Debounce:** 3 consecutive GPS updates meeting all conditions

**On exit:**

- Clear indoor floor selection
- Clear floorplan overlay
- Switch to outdoor follow mode
- Continue showing building highlight + distance

### 3.7 Positioning Stability Tracker (NEW)

**File:** Add to `LocationProvider` or new `PositioningStability` class

- Rolling window of last 3-5 indoor estimates
- Expose `PositioningStability` enum: `unavailable`, `acquiring`, `stable`
- Criteria for `stable`: 3+ consecutive valid estimates within 5s window, position delta < 15m, `matchedAps >= 2`
- Notify listeners on state change
- Used by: floor transition detection, reroute suppression, building exit debounce

### 3.8 Server Fix

**File:** `server/app/controllers/NavigationController.scala`

- In `navigateSameBuilding()` (line 270-277): add `pois_type` to `NavResultPoint`
- One-line fix: `p.pois_type = poi.get(SCHEMA.fPoisType)`
- Enables client to identify connector types (Stair/Elevator) from route response
- Floor-change detection works as fallback even without this fix

### 3.9 UI Changes

**PoiDetailCard:**

- Add "Start Directions" button (visible after route loads)
- Add "End Navigation" state (visible during active navigation)
- Route status message updates for each state

**MapBottomSheet:**

- Collapsed state during navigation: floor indicator + positioning status + end button
- Positioning status in user-friendly language: "Indoor location" / "Updating location..." / "GPS active"
- Expandable to show additional context

**MapControls:**

- Re-center button resumes follow mode during navigation
- "My Location" icon changes state based on follow mode active/inactive

**MapScreen:**

- New `_fitRouteBounds()` for route preview camera framing
- Follow mode camera logic (lower-third positioning, smooth animation)
- Route polyline rendering (already exists, no change)

### 3.10 Data Model Additions

**NavigationRouteModel:**

- Add `floorTransitions` getter: identifies points where `floorNumber` changes between consecutive points
- Add `segmentsByFloor` getter: groups route points by floor number
- Add `connectorPoints` getter: points where floor changes (using `pois_type` if available, floor-change as fallback)

**NavigationState (NEW enum):**

```dart
enum NavigationPhase { idle, preview, active }
enum NavigationSubState { outdoor, indoor, transitioning }
```

---

## 4. Configurable Constants

| Constant | Default | Purpose |
|---|---|---|
| `buildingPrepThreshold` | 100m | GPS distance to start pre-loading building data |
| `buildingPrepCancelThreshold` | 150m | Cancel pre-loading if user moves away |
| `entranceTransitionThreshold` | 25m | GPS distance to entrance POI for indoor switch |
| `exitAccuracyThreshold` | 15m | GPS accuracy for building exit detection |
| `exitDistanceThreshold` | 80m | Fallback distance from building center for exit |
| `deviationThreshold` | 15m | Route deviation before auto-reroute |
| `rerouteCooldown` | 15s | Minimum time between reroutes |
| `stabilityWindowDuration` | 5s | Rolling window for positioning stability |
| `stabilityMinEstimates` | 3 | Consecutive estimates needed for stable |
| `stabilityMaxDelta` | 15m | Max position jump between consecutive estimates |
| `stabilityMinMatchedAps` | 2 | Minimum WiFi APs matched for valid estimate |
| `indoorFollowZoom` | 19.0 | Camera zoom during indoor navigation |
| `outdoorFollowZoom` | 17.0 | Camera zoom during outdoor navigation |
| `transitionBlackoutMessage` | "Moving to Floor X..." | Status during floor transition |
| `rerouteMaxRetries` | 3 | Network retry attempts for rerouting |

---

## 5. File Change Summary

| File | Action | Purpose |
|---|---|---|
| `lib/state/navigation_controller.dart` | **NEW** | Navigation lifecycle orchestrator |
| `lib/state/space_provider.dart` | MODIFY | Expose floor transitions, connector detection |
| `lib/state/location_provider.dart` | MODIFY | Add positioning stability tracker |
| `lib/data/models/navigation_route_model.dart` | MODIFY | Add floorTransitions, segmentsByFloor, connectorPoints |
| `lib/ui/screens/map_screen.dart` | MODIFY | Add _fitRouteBounds, follow mode camera, outdoor/indoor transitions |
| `lib/ui/widgets/poi_detail_card.dart` | MODIFY | Add Start Directions / End Navigation buttons |
| `lib/ui/widgets/map_bottom_sheet.dart` | MODIFY | Collapsed navigation state, positioning status |
| `lib/ui/widgets/map_controls.dart` | MODIFY | Re-center resumes follow mode |
| `lib/config/map_config.dart` | MODIFY | Add navigation zoom constants |
| `lib/config/navigation_config.dart` | **NEW** | All configurable thresholds |
| `server/app/controllers/NavigationController.scala` | MODIFY | Add pois_type to navigateSameBuilding response |

---

## 6. Implementation Order

### Phase 1 — Foundation (no visual changes)

1. Create `NavigationController` with state machine
2. Create `NavigationConfig` with all constants
3. Add positioning stability tracker to `LocationProvider`
4. Add floor transition helpers to `NavigationRouteModel`
5. Fix server `pois_type` in `navigateSameBuilding`

### Phase 2 — Route Preview

6. Implement camera framing (`_fitRouteBounds`) in `MapScreen`
7. Add "Start Directions" button to `PoiDetailCard`
8. Wire Route Preview state to NavigationController

### Phase 3 — Active Navigation (indoor)

9. Implement follow-mode camera (lower-third, smooth animation)
10. Implement deviation detection and auto-reroute
11. Implement floor transition detection and pre-loading
12. Implement positioning blackout handling
13. Update collapsed bottom sheet for navigation state

### Phase 4 — Outdoor ↔ Indoor Transitions

14. Implement Stage 1 (building proximity → pre-load)
15. Implement Stage 2 (entrance proximity → indoor switch)
16. Implement building exit detection (combined signals)
17. Implement hysteresis for both transitions

### Phase 5 — Polish

18. Add re-center → resume follow mode
19. Add map tap → exit follow mode
20. Add app backgrounding continuity
21. Add "Still navigating" banner on resume
22. End Navigation flow

---

## 7. What's OUT of Scope (Future Enhancements)

- Turn-by-turn verbal/text directions
- Distance-to-destination in collapsed sheet
- Compass/heading lock (map rotation to match device heading)
- Dynamic zoom based on distance to next turn
- Cross-building routing (backend limitation)
- Manual floor override during Active Navigation
- Floating "Start" button on map
- Outdoor turn-by-turn routing
- Route summary/preview before starting
- Saved/favorite routes
