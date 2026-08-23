import '../../config/map_config.dart';
import '../../data/models/route_segment.dart';
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

/// PHASE 12 — floor-scoped segment visibility (pure projection rule).
///
/// [displayedFloor] is the BROWSING-selected floor (null = none). Rules:
///  * outdoor legs: visible unless a live indoor emphasis exists — while
///    indoors they stay as a dimmed orientation outline ([returnsDimmed]).
///  * indoor/transition legs with a real floor: only that floor's geometry.
///  * entrance/exit boundaries (empty floor): follow their indoor side —
///    shown when any floor is displayed or when outdoors.
({bool visible, bool dimmed}) segmentVisibility({
  required RouteSegmentType type,
  required String? floorNumber,
  required String? displayedFloor,
  required bool indoorEmphasis,
}) {
  final floor = (floorNumber == null || floorNumber.isEmpty) ? null : floorNumber;
  switch (type) {
    case RouteSegmentType.outdoorWalking:
      if (!indoorEmphasis) return (visible: true, dimmed: false);
      return (visible: true, dimmed: true);
    case RouteSegmentType.indoorRouting:
    case RouteSegmentType.floorTransition:
      return (visible: floor == null || floor == displayedFloor, dimmed: false);
    case RouteSegmentType.exitTransition:
    case RouteSegmentType.entranceTransition:
      // Boundaries belong to their indoor side; keep them when any floor is
      // displayed or when the user is outdoors.
      return (visible: displayedFloor != null || !indoorEmphasis,
          dimmed: false);
  }
}

/// Whether campus KMZ polylines should render right now.
///
/// Hidden during a live session unless the flag is enabled explicitly or
/// the active route carries no outdoor coverage of its own.
bool showCampusRoutes({
  required bool sessionLive,
  required bool routeHasOutdoorCoverage,
  bool flagEnabled = false,
}) {
  if (!sessionLive) return true;
  if (flagEnabled) return true;
  return !routeHasOutdoorCoverage;
}

/// PHASE 12 / BUG-10: span→zoom mapping for route framing.
///
/// [maxSpanMeters] is the padded bounds' larger axis in meters. Long outdoor
/// frames zoom OUT (≤17); tight frames keep the indoor-scale close-up.
double routeFitZoomForSpan(double maxSpanMeters) {
  final double base;
  if (maxSpanMeters > 2000) {
    base = 14.0;
  } else if (maxSpanMeters > 800) {
    base = 15.5;
  } else if (maxSpanMeters > 300) {
    base = 17.0;
  } else {
    base = MapConfig.indoorFloorplanZoom.toDouble();
  }
  return base;
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
