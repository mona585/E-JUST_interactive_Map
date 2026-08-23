import '../../data/models/user_location.dart';
import '../../state/navigation_controller.dart';
import '../../state/navigation_state_model.dart';

/// UI projection helpers for the canonical navigation machine
/// (ORIGINAL PHASE 7 — UI exposure).
///
/// Pure mapping only: every value surfaced is read from the existing
/// Phase 1–6 public APIs. Nothing here computes navigation behavior.

/// Human-readable status label for the current canonical navigation state.
///
/// ARRIVED / PAUSED / ENTERING_BUILDING / EXITING_BUILDING get dedicated
/// labels; every other state falls through to
/// [NavigationController.positioningStatus], which already covers the
/// positioning-source line and the ORIGINAL PHASE 5 floor-transition
/// blackout text ("Moving to Floor N…"). The blackout wording and the
/// held-position semantics are consumed as-is, never altered here.
String navigationStatusLabel(NavigationController nav) {
  switch (nav.navigationState) {
    case NavigationState.arrived:
      return 'Arrived at ${nav.destinationSpace?.name ?? 'destination'}';
    case NavigationState.paused:
      return nav.pauseMessage ?? 'Paused \u2022 weak signal';
    case NavigationState.enteringBuilding:
      return 'Entering building\u2026';
    case NavigationState.exitingBuilding:
      return 'Leaving building\u2026';
    default:
      // PHASE 6: a failed recalculation is visible while the valid old
      // route keeps guiding; the flag clears on the next success or End.
      if (nav.rerouteFailed && nav.isActive) {
        return 'Recalculation failed \u2014 retrying soon';
      }
      // PHASE 8: indoor guidance could not be fetched after the handoff —
      // the general path keeps guiding until a floor confirmation retries.
      if (nav.indoorGuidanceUnavailable && nav.isActive) {
        return 'Indoor route unavailable \u2014 following general path';
      }
      return nav.positioningStatus;
  }
}

/// The position the UI should render for the user right now.
///
/// While a floor transition is in progress, the Phase 5 held-position cache
/// is exposed so the marker/camera do not jump across floors mid-blackout;
/// any other time the live location passes through unchanged.
UserLocation? displayLocationFor({
  required bool holdFloorTransition,
  required UserLocation? heldPosition,
  required UserLocation? currentLocation,
}) {
  if (holdFloorTransition && heldPosition != null) return heldPosition;
  return currentLocation;
}
