import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../config/map_config.dart';
import '../../config/theme.dart';
import '../../data/models/navigation_route_model.dart';
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
      // Journey-overview context (preview / no indoor emphasis yet): the
      // full indoor geometry stays visible so a user still outdoors can see
      // where the journey leads — the same rationale as the boundary rule
      // below. Once indoors, only the displayed floor's slice renders.
      if (!indoorEmphasis) return (visible: true, dimmed: false);
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

// ────────────────────────────────────────────────────────────────
// Route rendering projection (extracted verbatim from MapScreen so the
// representation → style mapping is testable and stays a pure function).
// ────────────────────────────────────────────────────────────────

/// One drawable active-route polyline exactly as the map should draw it.
class RoutePolylineSpec {
  final String id;
  final List<LatLng> points;
  final int width;
  final Color color;

  /// Null = solid line (no dash/dot pattern).
  final List<PatternItem>? patterns;

  const RoutePolylineSpec({
    required this.id,
    required this.points,
    required this.width,
    required this.color,
    this.patterns,
  });
}

class _SegmentStyle {
  final Color color;
  final int width;
  final List<PatternItem>? patterns;

  const _SegmentStyle({
    required this.color,
    required this.width,
    this.patterns,
  });
}

/// Segment type → polyline style mapping (colors unchanged since the
/// feature's original definition; see CROSS_BUILDING_NAVIGATION_PLAN.md).
final Map<RouteSegmentType, _SegmentStyle> _kSegmentStyles = {
  RouteSegmentType.outdoorWalking: _SegmentStyle(
    color: const Color(0xFF1E88E5),
    width: 5,
    patterns: [PatternItem.dot, PatternItem.gap(10)],
  ),
  RouteSegmentType.indoorRouting: _SegmentStyle(
    color: AppTheme.primary,
    width: 6,
  ),
  RouteSegmentType.exitTransition: _SegmentStyle(
    color: const Color(0xFFFF9800),
    width: 5,
    patterns: [PatternItem.dash(20), PatternItem.gap(10)],
  ),
  RouteSegmentType.entranceTransition: _SegmentStyle(
    color: const Color(0xFF4CAF50),
    width: 5,
    patterns: [PatternItem.dash(20), PatternItem.gap(10)],
  ),
  RouteSegmentType.floorTransition: _SegmentStyle(
    color: const Color(0xFF9C27B0),
    width: 4,
    patterns: [PatternItem.dot, PatternItem.gap(8)],
  ),
};

Color _styleColor(_SegmentStyle style, {required bool dimmed}) {
  return dimmed
      ? style.color.withValues(alpha: 0.30)
      : style.color.withValues(alpha: _styleBaseAlphaOf(style));
}

double _styleBaseAlphaOf(_SegmentStyle style) {
  // The original call sites baked these alphas in per branch; they live here
  // now so every caller shares one source of truth.
  if (identical(style, _kSegmentStyles[RouteSegmentType.outdoorWalking])) {
    return 0.9;
  }
  return 0.85;
}

/// Pure projection of the SINGLE route store onto drawable polylines.
///
/// Representation-aware:
///  * SEGMENTED routes render one spec per visible segment styled by type —
///    indoorRouting geometry always uses the intended indoor navigation style
///    regardless of which producer created it (cross-building composer or the
///    same-building wrap).
///  * LEGACY routes (no segment metadata) keep their dedicated branch:
///    outdoor-flagged points dotted blue ('route_outdoor'), indoor points
///    solid red ('route_indoor'). Genuine legacy routes still render.
///  * RouteModelStatus is deliberately NOT consulted — validity lives in the
///    status/warning channel, never in color.
List<RoutePolylineSpec> routePolylineSpecs({
  required NavigationRouteModel? route,
  required String? displayedFloor,
  required bool indoorEmphasis,
}) {
  if (route == null) return const [];
  final specs = <RoutePolylineSpec>[];

  // Segment-based rendering (cross-building + unified same-building), floor-scoped.
  if (route.hasSegments) {
    for (var i = 0; i < route.segments.length; i++) {
      final seg = route.segments[i];
      if (seg.isEmpty) continue;

      final style = _kSegmentStyles[seg.type];
      if (style == null) continue;

      var points = seg.points;
      // Truthful per-point floors refine multi-floor indoor legs into the
      // displayed floor's slice. Without aligned point floors the whole leg
      // shows/hides via the visibility rule below, exactly as before.
      final hasAlignedFloors = seg.pointFloors.length == seg.points.length;
      final isIndoorLeg = seg.type == RouteSegmentType.indoorRouting ||
          seg.type == RouteSegmentType.floorTransition;
      if (isIndoorLeg &&
          displayedFloor != null &&
          hasAlignedFloors &&
          seg.pointFloors.any((f) => f == displayedFloor)) {
        points = [
          for (var j = 0; j < seg.points.length; j++)
            if (seg.pointFloors[j] == displayedFloor) seg.points[j],
        ];
        if (points.length < 2) continue;
      }

      final vis = segmentVisibility(
        type: seg.type,
        floorNumber: seg.floorNumber,
        displayedFloor: displayedFloor,
        indoorEmphasis: indoorEmphasis,
      );
      if (!vis.visible) continue;

      specs.add(RoutePolylineSpec(
        id: 'route_segment_$i',
        points: points,
        width: vis.dimmed ? (style.width - 1).clamp(1, 12) : style.width,
        color: _styleColor(style, dimmed: vis.dimmed),
        patterns: style.patterns ?? [],
      ));
    }
    return specs;
  }

  // Legacy rendering (non-segment routes), floor-aware for the indoor
  // portion thanks to truthful metadata (Phase 7).
  if (route.hasOutdoorSegment) {
    final vis = segmentVisibility(
      type: RouteSegmentType.outdoorWalking,
      floorNumber: null,
      displayedFloor: displayedFloor,
      indoorEmphasis: indoorEmphasis,
    );
    specs.add(RoutePolylineSpec(
      id: 'route_outdoor',
      points: route.outdoorPolylinePoints,
      width: vis.dimmed ? 4 : 5,
      color: const Color(0xFF1E88E5)
          .withValues(alpha: vis.dimmed ? 0.32 : 0.9),
      patterns: [PatternItem.dot, PatternItem.gap(10)],
    ));
  }

  if (route.hasIndoorSegment) {
    final indoorPoints = displayedFloor != null
        ? route.polylinePointsForFloor(displayedFloor)
        : route.indoorPolylinePoints;
    if (indoorPoints.length >= 2) {
      specs.add(RoutePolylineSpec(
        id: 'route_indoor',
        points: indoorPoints,
        width: 6,
        color: AppTheme.primary.withValues(alpha: 0.85),
      ));
    }
  }

  return specs;
}
