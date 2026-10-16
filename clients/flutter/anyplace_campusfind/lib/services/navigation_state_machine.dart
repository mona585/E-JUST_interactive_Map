import 'package:flutter/foundation.dart';

import '../models/navigation_state.dart';
import 'navigation_engine.dart';
import 'navigation_event_log.dart';

/// Canonical navigation state machine core.
///
/// Extracted from [NavigationPilot]: owns the state, the allowed-edge
/// enforcement, the activity-restore bookkeeping and the dwell
/// (corroboration-window) arm/disarm that is coupled to transitions into
/// ENTERING/EXITING_BUILDING. Every engine component transitions through
/// [transition] so illegal edges stay rejected once, with a debug print —
/// never thrown — so a bad detection heuristic cannot crash a live session.
class NavigationStateMachine {
  NavigationStateMachine({
    required DateTime Function() now,
    required NavigationEventLog navEvent,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _now = now,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent;

  final DateTime Function() _now;
  final NavigationEventLog _navEvent;

  NavigationState _state = NavigationState.idle;
  NavigationState? _previousActiveState;

  /// Dwell (entry/exit corroboration) bookkeeping: armed on transitions into
  /// the two dwell states, cleared by every other transition. Read by the
  /// building-context handler through [dwellStart].
  DateTime? _dwellStart;

  /// Current canonical navigation state.
  NavigationState get state => _state;

  /// The activity to restore after a paused/rerouting/arrived overlay.
  NavigationState? get previousActiveState => _previousActiveState;

  /// Start of the current building-entry/exit dwell window, if any.
  DateTime? get dwellStart => _dwellStart;

  NavigationSubState get subState =>
      NavigationEngine.projectSubState(_state, _previousActiveState);

  /// A live session covers activities and overlays but not preview/idle —
  /// identical semantics to the legacy "phase == active" check.
  bool get isActive => _state.isSessionLive;
  bool get isPreview => _state == NavigationState.routePreview;
  bool get isTransitioningFloors => _state == NavigationState.floorTransition;
  bool get isRerouting => _state == NavigationState.rerouting;
  bool get isArrived => _state == NavigationState.arrived;
  bool get isPaused => _state == NavigationState.paused;

  /// Enforces the allowed-edge table and records overlay bookkeeping.
  ///
  /// Illegal edges are rejected — never thrown. Returns whether the
  /// transition happened.
  bool transition(NavigationState to) {
    final from = _state;
    if (from == to) return false;

    final dynamicRestore =
        (from == NavigationState.paused || from == NavigationState.rerouting) &&
        to == _previousActiveState;
    if (!dynamicRestore && !isAllowedNavigationTransition(from, to)) {
      debugPrint('[NavigationViewModel] Rejected transition $from -> $to');
      return false;
    }

    _state = to;
    _navEvent.navEvent('STATE', detail: '$from->$to');

    switch (to) {
      case NavigationState.paused:
      case NavigationState.rerouting:
      case NavigationState.arrived:
        if (from.isActivity) _previousActiveState = from;
        break;
      default:
        _previousActiveState = null;
    }

    if (to == NavigationState.enteringBuilding ||
        to == NavigationState.exitingBuilding) {
      _dwellStart = _now();
    } else {
      _dwellStart = null;
    }
    return true;
  }

  /// Hard teardown: back to idle, dropping restore bookkeeping. Used by
  /// user-initiated session end (bypasses the allowed-edge table).
  void reset() {
    _state = NavigationState.idle;
    _previousActiveState = null;
    _dwellStart = null;
  }

  /// Fault-path teardown: forces the state to idle WITHOUT touching restore
  /// or dwell bookkeeping (identical semantics to the original catch path of
  /// canonical termination).
  void forceIdle() {
    _state = NavigationState.idle;
  }
}
