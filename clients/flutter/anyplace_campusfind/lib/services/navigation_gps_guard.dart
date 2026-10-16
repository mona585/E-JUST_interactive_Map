import 'package:flutter/foundation.dart';

import '../config/navigation_config.dart';
import '../models/navigation_state.dart';
import '../models/user_location.dart';
import 'navigation_pilot_port.dart';
import 'navigation_state_machine.dart';

/// GPS loss/recovery and pause/resume ownership extracted from
/// [NavigationPilot].
///
/// Owns the pause reason and the degraded-GPS hysteresis policy: PAUSED is
/// entered once the degraded streak reaches its threshold (a single bad tick
/// can never pause — INV-8 hysteresis); recovery returns to the interrupted
/// activity through the machine's dynamic restore edge.
class NavigationGpsGuard {
  NavigationGpsGuard({
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine;

  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;

  String? _pauseReason;

  bool get isPaused => _machine.state == NavigationState.paused;
  String? get pauseMessage => _pauseReason;

  /// PHASE 5: GPS quality is judged by the LocationViewModel ingestion gate.
  /// PAUSED is entered once the degraded streak (poor/invalid/held fixes)
  /// reaches [NavigationConfig.gpsPausePoorTicks]; a single bad tick can
  /// never pause (INV-8 hysteresis).
  void checkGpsLoss(UserLocation location) {
    if (!_machine.state.isActivity) return;
    if (_port.gpsDegraded) {
      _pauseNavigation('GPS signal weak — waiting for better signal');
    }
  }

  /// Resumes from PAUSED once good-band GPS returns and the degraded streak
  /// has cleared.
  void checkGpsRecovery(UserLocation location) {
    if (_machine.state != NavigationState.paused) return;
    if (!_port.gpsDegraded &&
        location.accuracy <= NavigationConfig.gpsGoodAccuracyMeters) {
      _resumeFromPause();
    }
  }

  /// Pauses navigation (e.g., during GPS loss). Valid from any activity.
  void _pauseNavigation(String message) {
    if (_machine.state == NavigationState.paused) return;
    _pauseReason = message;
    debugPrint('[NavigationViewModel] Paused: $message');
    _machine.transition(NavigationState.paused);
    _port.notifyChanged();
  }

  /// Resumes navigation after GPS restore, returning to the interrupted
  /// activity.
  void _resumeFromPause() {
    if (_machine.state != NavigationState.paused) return;
    final target = _machine.previousActiveState;
    _pauseReason = null;
    debugPrint('[NavigationViewModel] Resumed');
    if (target != null) {
      _machine.transition(target);
    } else {
      _machine.transition(NavigationState.idle);
    }
    _port.notifyChanged();
  }

  void resetForEnd() {
    _pauseReason = null;
  }
}
