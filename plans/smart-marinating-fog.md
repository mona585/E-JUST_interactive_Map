# Plan: Google Maps-style Navigation Camera (Follow + Rotate)

## Context
The map camera currently follows the user's position during active navigation but **never rotates** — bearing is always 0. The user wants Google Maps-style behavior: the map rotates so the direction of movement faces the top of the screen, with smooth transitions, manual gesture handling, and a re-center button.

## Current State (key findings)
- `map_screen.dart:196-210` `_followUserPosition()` sets `CameraPosition(target:, zoom:)` — **no bearing**
- `map_screen.dart:218-228` `_animatedMapMove()` also uses `CameraPosition(target:, zoom:)` — no bearing parameter
- `UserLocation.heading` exists (compass heading from GPS) but is **0.0 for indoor** positions
- `NavigationController` has `_followMode` toggle but no bearing state
- `onCameraMove` (line 649-653) has a comment "Don't exit follow mode during programmatic moves" but **no actual logic** — manual gestures don't exit follow mode
- Re-center button (line 806-811) already calls `resumeFollowMode()` + `_onMyLocationTapped()`
- `_animatedMapMove` is called from ~10 places — all need bearing support

## Implementation Plan

### Step 1: Add bearing constants to `NavigationConfig`
**File:** `lib/config/navigation_config.dart`

Add:
```dart
// -- Camera bearing --
/// Minimum speed (m/s) to compute movement bearing (filters stationary GPS noise).
static const double bearingSpeedThreshold = 0.5;

/// Exponential moving average factor for bearing smoothing (0..1). Lower = smoother.
static const double bearingSmoothingFactor = 0.25;

/// Minimum time (ms) between bearing-driven camera updates (prevents jitter at high GPS rates).
static const int bearingUpdateIntervalMs = 300;

/// When standing still, hold the last bearing for this duration (ms) before resetting to 0.
static const int bearingHoldDurationMs = 3000;
```

### Step 2: Add bearing computation + smoothing to `_MapScreenState`
**File:** `lib/ui/screens/map_screen.dart`

Add fields:
```dart
double _currentBearing = 0.0;    // Smoothed bearing applied to camera
double _lastBearing = 0.0;       // Raw bearing from last position delta
LatLng? _lastPositionForBearing; // Previous position for bearing computation
DateTime _lastBearingUpdateTime = DateTime.zero;
DateTime _lastMovingTime = DateTime.zero;
bool _isUserGesture = false;     // True when user is manually panning
```

Add utility methods:
```dart
/// Compute bearing from point A to point B (degrees, 0=north, clockwise).
double _computeBearing(LatLng from, LatLng to) {
  final dLon = (to.longitude - from.longitude) * pi / 180;
  final lat1 = from.latitude * pi / 180;
  final lat2 = to.latitude * pi / 180;
  final y = sin(dLon) * cos(lat2);
  final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

/// Smooth bearing using exponential moving average, handling 360°→0° wraparound.
double _smoothBearing(double raw, double current) {
  double diff = raw - current;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  return (current + NavigationConfig.bearingSmoothingFactor * diff + 360) % 360;
}
```

### Step 3: Modify `_followUserPosition()` to include bearing
**File:** `lib/ui/screens/map_screen.dart`

Change signature to accept optional bearing:
```dart
void _followUserPosition(LatLng userPosition, NavigationSubState subState, {double bearing = 0.0})
```

Update `CameraPosition` to include `bearing`:
```dart
_animatedMapMove(
  LatLng(userPosition.latitude - latOffset, userPosition.longitude),
  targetZoom,
  bearing: bearing,
);
```

### Step 4: Modify `_animatedMapMove()` to accept bearing
**File:** `lib/ui/screens/map_screen.dart`

Add `bearing` parameter (default 0.0):
```dart
void _animatedMapMove(LatLng destLocation, double destZoom, {double bearing = 0.0}) {
  if (_mapController == null) return;
  _mapController!.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(
        target: destLocation,
        zoom: destZoom,
        bearing: bearing,
      ),
    ),
  );
}
```

### Step 5: Compute bearing from position deltas in `_onNavigationChanged()`
**File:** `lib/ui/screens/map_screen.dart`

Update `_onNavigationChanged()`:
```dart
void _onNavigationChanged() {
  if (!mounted || _isUserGesture) return;
  final nav = context.read<NavigationController>();
  final locationProvider = context.read<LocationProvider>();
  final location = locationProvider.currentLocation;

  if (nav.isActive && nav.followMode && location != null) {
    final now = DateTime.now();
    final bearing = _updateBearing(location, now);
    _lastBearingUpdateTime = now;
    _followUserPosition(location.latLng, nav.subState, bearing: bearing);
  }

  // Detect follow mode turning on (e.g. re-center tap)
  if (nav.followMode && !_lastFollowMode && location != null) {
    final now = DateTime.now();
    final bearing = _updateBearing(location, now);
    _followUserPosition(location.latLng, nav.subState, bearing: bearing);
  }
  _lastFollowMode = nav.followMode;
}
```

Add `_updateBearing()`:
```dart
double _updateBearing(UserLocation location, DateTime now) {
  final currentPos = location.latLng;

  if (_lastPositionForBearing == null) {
    _lastPositionForBearing = currentPos;
    _currentBearing = 0.0;
    return _currentBearing;
  }

  // Check update interval
  final elapsed = now.difference(_lastBearingUpdateTime).inMilliseconds;
  if (elapsed < NavigationConfig.bearingUpdateIntervalMs) {
    return _currentBearing;
  }

  final distance = Geolocator.distanceBetween(
    _lastPositionForBearing!.latitude, _lastPositionForBearing!.longitude,
    currentPos.latitude, currentPos.longitude,
  );

  final speed = location.speed; // m/s from GPS

  // Only update bearing if moving above threshold
  if (speed > NavigationConfig.bearingSpeedThreshold && distance > 0.5) {
    _lastBearing = _computeBearing(_lastPositionForBearing!, currentPos);
    _currentBearing = _smoothBearing(_lastBearing, _currentBearing);
    _lastMovingTime = now;
  } else {
    // Standing still — hold last bearing briefly, then fade to 0
    final stationaryMs = now.difference(_lastMovingTime).inMilliseconds;
    if (stationaryMs > NavigationConfig.bearingHoldDurationMs) {
      // Gradually reset bearing to 0 (map faces north when stopped)
      _currentBearing = _smoothBearing(0.0, _currentBearing);
    }
    // else: hold current bearing
  }

  _lastPositionForBearing = currentPos;
  return _currentBearing;
}
```

### Step 6: Detect manual gestures to disable follow mode
**File:** `lib/ui/screens/map_screen.dart`

Update `onCameraMove` in `GoogleMap` widget (line 649-653):
```dart
onCameraMove: (CameraPosition position) {
  final nav = context.read<NavigationController>();
  if (nav.isActive && nav.followMode && !_isProgrammaticMove) {
    // User is manually panning — exit follow mode
    _isUserGesture = true;
    nav.exitFollowMode();
  }
},
```

Add `_isProgrammaticMove` flag:
```dart
bool _isProgrammaticMove = false;
```

Wrap `_animatedMapMove` to set the flag:
```dart
void _animatedMapMove(LatLng destLocation, double destZoom, {double bearing = 0.0}) {
  if (_mapController == null) return;
  _isProgrammaticMove = true;
  _mapController!.animateCamera(
    CameraUpdate.newCameraPosition(
      CameraPosition(target: destLocation, zoom: destZoom, bearing: bearing),
    ),
  ).then((_) {
    _isProgrammaticMove = false;
  });
}
```

### Step 7: Enhance re-center button to restore bearing
**File:** `lib/ui/screens/map_screen.dart`

Update re-center handler (line 806-811):
```dart
onRecenter: () {
  final nav = context.read<NavigationController>();
  if (nav.isActive) {
    nav.resumeFollowMode();
  }
  _isUserGesture = false;
  _onMyLocationTapped();
},
```

### Step 8: Reset bearing state on navigation end
**File:** `lib/ui/screens/map_screen.dart`

In `dispose()`, add cleanup:
```dart
_currentBearing = 0.0;
_lastPositionForBearing = null;
_isUserGesture = false;
```

Also reset when navigation controller becomes inactive — in `_onNavigationChanged()`:
```dart
if (!nav.isActive) {
  _currentBearing = 0.0;
  _lastPositionForBearing = null;
  _lastFollowMode = false;
  return;
}
```

### Step 9: Handle `didChangeAppLifecycleState` resume
**File:** `lib/ui/screens/map_screen.dart`

In the `resumed` branch (line 172-176), pass bearing:
```dart
if (location != null && nav.followMode) {
  final bearing = _updateBearing(location, DateTime.now());
  _followUserPosition(location.latLng, nav.subState, bearing: bearing);
}
```

## Files Modified
1. `lib/config/navigation_config.dart` — new bearing constants
2. `lib/ui/screens/map_screen.dart` — bearing computation, smoothing, gesture detection, `_animatedMapMove` bearing parameter

## Testing
1. `flutter analyze` — no errors
2. Run existing 58 tests: `flutter test` — all must pass
3. Build APK: `flutter build apk --debug`
4. Manual testing on device:
   - Start navigation → map should rotate to face movement direction
   - Walk straight → camera follows with bearing locked
   - Turn left/right → camera smoothly rotates
   - Stop walking → camera holds bearing briefly, then resets to north
   - Pan map manually → follow mode exits, camera stops rotating
   - Tap re-center → follow mode restores, camera re-acquires bearing
   - Switch tabs → navigation lifecycle handled (existing tab-change fix)
   - Indoor navigation → bearing computed from position deltas (no compass needed)
   - Floor switch → bearing resets appropriately
