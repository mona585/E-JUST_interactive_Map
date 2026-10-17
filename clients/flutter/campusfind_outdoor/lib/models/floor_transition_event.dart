/// First-class record of a floor-transition lifecycle step
/// (ORIGINAL PHASE 5 — Floor Transitions).
///
/// The navigation half distinguishes four stages: EXPECTED (the route says a
/// floor change is coming), DETECTED (positioning evidence first diverges),
/// CONFIRMED (evidence-gated acceptance), and ABORTED (dwell timed out).
/// Events are observations of machine activity — they never drive it.
///
/// Invariant reminder: a loaded RadioMap (selection/residency) is candidacy
/// only. Only [FloorTransitionStage.confirmed] represents physical-floor
/// proof backed by positioning evidence.
enum FloorTransitionStage {
  /// Route context expects a move to another floor (connector approached).
  expected,

  /// Positioning evidence first diverged from the navigating floor within
  /// the current accumulation run.
  detected,

  /// Enough consecutive consistent evidence accumulated — the switch is
  /// accepted and route-context bookkeeping updated.
  confirmed,

  /// The transition dwell exceeded its timeout and was aborted; evidence
  /// re-evaluates on subsequent ticks.
  aborted,
}

/// What caused a [FloorTransitionEvent].
enum FloorTransitionTrigger {
  /// Proximity to a route connector point (floor-change point).
  connectorProximity,

  /// Divergent positioning evidence (organic drift or post-abort redetection).
  evidence,

  /// The transition dwell exceeded its timeout.
  timeout,
}

class FloorTransitionEvent {
  const FloorTransitionEvent({
    required this.stage,
    required this.trigger,
    required this.timestamp,
    this.fromFloor,
    this.toFloor,
  });

  /// Lifecycle step this event records.
  final FloorTransitionStage stage;

  /// Cause of the recorded step.
  final FloorTransitionTrigger trigger;

  /// Route-context floor before the step, when meaningful.
  final String? fromFloor;

  /// Floor the step points at (expected/detected target, confirmed new
  /// floor). Null when not applicable.
  final String? toFloor;

  /// When the step was recorded (controller clock).
  final DateTime timestamp;

  @override
  String toString() => 'FloorTransitionEvent('
      'stage: ${stage.name}, trigger: ${trigger.name}, '
      'from: $fromFloor, to: $toFloor)';
}
