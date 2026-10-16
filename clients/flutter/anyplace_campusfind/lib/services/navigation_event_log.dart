import 'package:flutter/foundation.dart';

import '../models/navigation_state.dart';
import '../models/position_fix.dart';
import '../utils/navigation_log.dart';
import 'navigation_pilot_port.dart';

/// Single canonical `[NAV] EVENT=…` writer for the navigation engine.
///
/// Extracted from [NavigationPilot] so every extracted engine component
/// reports through one choke point with the identical line format. Verbose
/// events are dropped in profile/release ([kDebugMode]); force=true keeps
/// SESSION/TERMINATE/ARRIVAL-class lines always on.
class NavigationEventLog {
  NavigationEventLog({
    required NavigationPilotPort port,
    required NavigationSession? Function() session,
    required String? Function() currentFloor,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _session = session,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _currentFloor = currentFloor;

  final NavigationPilotPort _port;
  final NavigationSession? Function() _session;
  final String? Function() _currentFloor;

  void navEvent(String name, {String detail = '', bool force = false}) {
    if (!force && !kDebugMode) return;
    final s = _session();
    final fix = _port.currentFix;
    final src = fix == null
        ? '-'
        : (fix.source == PositionSource.wifi ? 'wifi' : 'gps');
    navigationLog(
      '[NAV] EVENT=$name'
      ' sid=${s?.sessionId ?? '-'}'
      ' rev=${s?.routeRevision ?? '-'}'
      ' dst=${s?.destinationPuid ?? '-'}'
      ' bldg=${s?.destinationSpace?.buid ?? '-'}'
      ' flr=${_currentFloor() ?? '-'}'
      ' src=$src'
      '${detail.isEmpty ? '' : ' detail=$detail'}',
    );
  }
}
