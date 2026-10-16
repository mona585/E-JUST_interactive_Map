import 'package:flutter/foundation.dart';

import '../models/position_fix.dart';
import '../models/space_model.dart';

/// CANONICAL ROUTE LIFECYCLE (MASTER PLAN PHASE 4).
///
/// REQUESTED → GENERATED(cascade) → COMMITTED(preview seed) → PREVIEW
///   → ACTIVE(startActiveNavigation) ⇄ REROUTING(overlay)
///   → SEGMENT_ADVANCED* → ARRIVED → TERMINATED(endNavigation /
///   terminateNavigation)
///
/// Invalidations:
///  * End anywhere terminates immediately.
///  * `retargetDestination` replaces the SESSION WHOLESALE (new sessionId,
///    revision 0) BEFORE any content moves; the old run's in-flight work
///    fails its identity fence and is discarded.
///  * A candidate that fails post-await validation is discarded and never
///    touches the store; the previously committed route persists.
///
/// Destination changes are transactions: identity first, content second,
/// and no old-session artifact may interleave (INV-3 extended to the
/// destination dimension).
///
/// I→O EXIT RELEASE MATRIX (MASTER PLAN PHASE 10, INV-9):
///  * RELEASED on confirmed exit: floorplan overlay browsing state, POI
///    selection (see `releaseIndoorContextForNavigation`).
///  * PRESERVED FOR MAP CONTEXT: selected building + last floor selection.
///  * RADIOMAP residency follows the Phase 11 scoped policy — targeted,
///    never a global native wipe from selection/exit paths.
///  * PRESERVED ALWAYS: route store, destination identity, session id and
///    revision; navigating-floor bookkeeping becomes stale-but-harmless and
///    is recomputed on reroute or the next indoor leg. Custom-route progress
///    switches source automatically through the existing state gate.

/// Legacy sub-state during active navigation.
///
/// Retained for compatibility with existing consumers; derived from the
/// canonical [NavigationState] machine via the navigator's `subState`.
enum NavigationSubState { outdoor, indoor, transitioning }

/// Canonical navigation state (ORIGINAL PHASE 2 — Navigation State Machine).
///
/// One explicit state replaces the fragmented
/// `NavigationPhase` + `NavigationSubState` + scattered-booleans
/// representation. The state describes where the user is *in relation to the
/// planned route*; it never fabricates physical location — physical position
/// and building/floor identity always come exclusively from [PositionFix].
enum NavigationState {
  /// No navigation session.
  idle,

  /// A route is rendered but directions have not started.
  routePreview,

  /// Actively navigating; positioning believes the user is outdoors.
  activeOutdoor,

  /// A building-entry flow is in progress, awaiting positioning
  /// corroboration (Wi-Fi engagement). Entered from entrance-proximity or
  /// from Wi-Fi belief while outdoors; never from destination selection.
  enteringBuilding,

  /// Actively navigating; positioning believes the user is indoors.
  activeIndoor,

  /// A floor change is in progress (connector approached or floor evidence
  /// diverging), awaiting confirmation of the new floor.
  floorTransition,

  /// A building-exit flow is in progress: GPS is believed and accumulating
  /// outside-building confirmation.
  exitingBuilding,

  /// Destination reached with arrival evidence.
  ///
  /// Structurally present in this phase; reachable only via an explicit
  /// arrival-evidence hook (ORIGINAL PHASE 6 wires the producer).
  arrived,

  /// Navigation temporarily halted (e.g. GPS loss). Resumes to
  /// [NavigationSnapshot.previousActiveState].
  paused,

  /// Recomputing the route. Returns to
  /// [NavigationSnapshot.previousActiveState] on success or failure.
  rerouting,
}

extension NavigationStateX on NavigationState {
  /// The five states representing an ongoing movement situation.
  bool get isActivity {
    switch (this) {
      case NavigationState.activeOutdoor:
      case NavigationState.enteringBuilding:
      case NavigationState.activeIndoor:
      case NavigationState.floorTransition:
      case NavigationState.exitingBuilding:
        return true;
      default:
        return false;
    }
  }

  /// Everything a running session covers (activities + overlays + arrival).
  bool get isSessionLive {
    return this != NavigationState.idle && this != NavigationState.routePreview;
  }
}

/// Immutable observable of the navigation machine.
///
/// Two kinds of scope live side by side and must never be conflated:
///  - [NavigationSnapshot.fix].buildingId / .floor — physical identity,
///    populated only by positioning evidence.
///  - [navigatingBuildingId] / [navigatingFloor] — route-context bookkeeping
///    ("which leg of the plan are we on"), derived from the planned route.
@immutable
class NavigationSnapshot {
  final NavigationState state;

  /// The activity to restore after [NavigationState.paused],
  /// [NavigationState.rerouting] or [NavigationState.arrived].
  final NavigationState? previousActiveState;

  /// Pass-through of the canonical physical position. Never edited here.
  final PositionFix? fix;

  /// Route-context bookkeeping (planned leg), NOT a physical claim.
  final String? navigatingBuildingId;
  final String? navigatingFloor;

  /// Floor the route expects next while in [NavigationState.floorTransition].
  final String? expectedNextFloor;

  /// Human-readable reason while in [NavigationState.paused].
  final String? pauseReason;

  final int segmentIndex;
  final DateTime timestamp;

  const NavigationSnapshot({
    required this.state,
    this.previousActiveState,
    this.fix,
    this.navigatingBuildingId,
    this.navigatingFloor,
    this.expectedNextFloor,
    this.pauseReason,
    this.segmentIndex = 0,
    required this.timestamp,
  });
}

/// Static allowed-transition table for the navigation machine.
///
/// Dynamic edges handled by the controller in addition to this table:
///  - paused/rerouting -> [NavigationSnapshot.previousActiveState]
///  - user-initiated End -> idle (valid from every state)
const Map<NavigationState, Set<NavigationState>> kAllowedNavigationTransitions =
    {
      NavigationState.idle: {NavigationState.routePreview},
      NavigationState.routePreview: {
        NavigationState.idle,
        NavigationState.activeOutdoor,
        NavigationState.activeIndoor,
      },
      NavigationState.activeOutdoor: {
        NavigationState.idle,
        NavigationState.enteringBuilding,
        NavigationState.rerouting,
        NavigationState.paused,
        NavigationState.arrived,
      },
      NavigationState.enteringBuilding: {
        NavigationState.idle,
        NavigationState.activeIndoor,
        NavigationState.activeOutdoor,
        NavigationState.rerouting,
      },
      NavigationState.activeIndoor: {
        NavigationState.idle,
        NavigationState.floorTransition,
        NavigationState.exitingBuilding,
        NavigationState.rerouting,
        NavigationState.paused,
        NavigationState.arrived,
      },
      NavigationState.floorTransition: {
        NavigationState.idle,
        NavigationState.activeIndoor,
        NavigationState.exitingBuilding,
      },
      NavigationState.exitingBuilding: {
        NavigationState.idle,
        NavigationState.activeOutdoor,
        NavigationState.activeIndoor,
      },
      NavigationState.arrived: {NavigationState.idle},
      NavigationState.paused: {NavigationState.idle},
      NavigationState.rerouting: {NavigationState.idle},
    };

/// Whether [to] is reachable from [from] purely by the static table.
bool isAllowedNavigationTransition(NavigationState from, NavigationState to) {
  if (to == NavigationState.idle) return true; // user End / cancel anywhere
  return kAllowedNavigationTransitions[from]?.contains(to) ?? false;
}

/// Identity of exactly one navigation run (MASTER PLAN PHASE 1).
///
/// Created when a preview is seeded, carried through the whole session, and
/// destroyed by termination. Retargeting (Phase 4) replaces the instance
/// wholesale, producing a fresh [sessionId]. Every async continuation that
/// intends to mutate navigation state captures `(sessionId, routeRevision)`
/// at launch and must observe both unchanged at commit time.
class NavigationSession {
  NavigationSession({
    String? sessionId,
    this.destinationPuid,
    this.destinationSpace,
    this.destinationFloorNumber,
    this.routeRevision = 0,
  }) : sessionId = sessionId ?? (++_counter).toString();

  /// Monotonic per-process counter; uniqueness is the entire contract.
  static int _counter = 0;

  final String sessionId;
  String? destinationPuid;
  SpaceModel? destinationSpace;
  String? destinationFloorNumber;

  /// Bumped on preview seed and on every committed route replacement, so a
  /// superseded async route computation can never commit over newer state.
  int routeRevision;
}