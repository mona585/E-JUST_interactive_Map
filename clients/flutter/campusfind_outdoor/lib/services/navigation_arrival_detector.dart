import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../config/navigation_config.dart';
import '../models/navigation_state.dart';
import '../models/poi_model.dart';
import '../models/position_fix.dart';
import '../models/user_location.dart';
import 'navigation_event_log.dart';
import 'navigation_pilot_port.dart';
import 'navigation_route_scope.dart';
import 'navigation_state_machine.dart';

/// Destination point the arrival detector measures against.
///
/// Resolved once per session from the destination POI when available, else
/// from the route's final point. Identity fields gate indoor arrival:
/// proximity only confirms when confirmed positioning identity matches.
class ArrivalAnchor {
  const ArrivalAnchor({
    required this.latitude,
    required this.longitude,
    this.buid,
    this.floorNumber,
  });

  final double latitude;
  final double longitude;
  final String? buid;
  final String? floorNumber;
}

/// Arrival detection (ORIGINAL PHASE 6) extracted from [NavigationPilot].
///
/// Owns the session-stable [ArrivalAnchor] (per sessionId+routeRevision) and
/// the evidence-gated confirmation counter; arrival is evidence, never
/// coincidence.
class NavigationArrivalDetector {
  NavigationArrivalDetector({
    required NavigationRouteScope scope,
    required NavigationPilotPort port,
    required NavigationStateMachine machine,
    required NavigationEventLog navEvent,
    required NavigationSession? Function() session,
  // ignore: prefer_initializing_formals (private named formals are not allowed)
  }) : _scope = scope,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _port = port,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _machine = machine,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _navEvent = navEvent,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _session = session;

  final NavigationRouteScope _scope;
  final NavigationPilotPort _port;
  final NavigationStateMachine _machine;
  final NavigationEventLog _navEvent;
  final NavigationSession? Function() _session;

  ArrivalAnchor? _arrivalAnchor;
  int _arrivalConfirmationCounter = 0;
  String? _anchorSessionId;
  int _anchorRevision = -1;

  /// Test-only identity view of the resolved arrival anchor.
  Object? get arrivalAnchorForTest => _arrivalAnchor;

  /// The resolved arrival anchor for the live session, or null.
  ArrivalAnchor? get anchor => _arrivalAnchor;

  /// Resolves the arrival anchor for the current session: the destination
  /// POI when resolvable in the scope, otherwise the route's final point
  /// (always present and data-driven).
  void resolveAnchor() {
    // PHASE 13: the anchor is stable per (sessionId, revision). Unrelated
    // POI-list churn cannot move it; only committed replacements re-resolve.
    final session = _session();
    if (session == null) {
      _arrivalAnchor = null;
      return;
    }
    if (_anchorSessionId == session.sessionId &&
        _anchorRevision == session.routeRevision &&
        _arrivalAnchor != null) {
      return;
    }

    final poi = _scope.pois
        .where((p) => p.puid == session.destinationPuid)
        .firstOrNull;
    if (poi != null) {
      _arrivalAnchor = ArrivalAnchor(
        latitude: poi.latitude,
        longitude: poi.longitude,
        buid: poi.buid,
        floorNumber: poi.floorNumber,
      );
    } else {
      final route = _scope.activeNavigationRoute;
      final last = route?.hasPoints == true ? route!.points.last : null;
      if (last != null) {
        _arrivalAnchor = ArrivalAnchor(
          latitude: last.latitude,
          longitude: last.longitude,
          buid: last.buid.isEmpty ? null : last.buid,
          floorNumber: last.floorNumber.isEmpty ? null : last.floorNumber,
        );
      } else {
        _arrivalAnchor = null;
      }
    }
    _anchorSessionId = session.sessionId;
    _anchorRevision = session.routeRevision;
  }

  /// PHASE 13 / INV-8: arrival is evidence, never coincidence.
  void checkArrival(UserLocation location) {
    if (_machine.state != NavigationState.activeOutdoor &&
        _machine.state != NavigationState.activeIndoor) {
      return;
    }
    final anchor = _arrivalAnchor;
    if (anchor == null) return;

    if (_machine.state == NavigationState.activeIndoor) {
      final fix = _port.currentFix;
      final identityMatches =
          fix != null &&
          fix.hasScope &&
          fix.buildingId == anchor.buid &&
          fix.floor == anchor.floorNumber;
      if (!identityMatches) {
        _arrivalConfirmationCounter = 0;
        return;
      }
    } else {
      // Outdoor evidence-quality gate (Phase 5 flags).
      final fix = _port.currentFix;
      final qualifies =
          fix != null &&
          fix.source == PositionSource.gps &&
          fix.status == PositionFixStatus.fresh &&
          fix.accuracy <= NavigationConfig.gpsGoodAccuracyMeters;
      if (!qualifies) {
        _arrivalConfirmationCounter = 0;
        return;
      }
    }

    final dist = Geolocator.distanceBetween(
      location.latitude,
      location.longitude,
      anchor.latitude,
      anchor.longitude,
    );
    if (dist >= NavigationConfig.arrivalProximityThresholdMeters) {
      _arrivalConfirmationCounter = 0;
      return;
    }

    _arrivalConfirmationCounter++;
    if (_arrivalConfirmationCounter >=
        NavigationConfig.arrivalConfirmationCount) {
      debugPrint('[NavigationViewModel] Arrival confirmed at destination');
      arrive();
    }
  }

  /// Shared arrival path for the evidence producer and the manual hook.
  void arrive() {
    if (!_machine.state.isActivity) return;
    _navEvent.navEvent('ARRIVAL', detail: 'anchor resolved', force: true);
    _machine.transition(NavigationState.arrived);
    _port.notifyChanged();
  }

  /// Manual arrival hook kept test-visible; [checkArrival] drives it in
  /// production through the same [arrive] path.
  void markArrived() => arrive();

  /// Degraded-but-honest anchor: pins the anchor directly on the requested
  /// POI when no route committed for it (retarget fallback).
  void anchorOn(PoiModel poi) {
    _arrivalAnchor = ArrivalAnchor(
      latitude: poi.latitude,
      longitude: poi.longitude,
      buid: poi.buid,
      floorNumber: poi.floorNumber,
    );
  }

  /// Test-only anchor suppression (Phase 9).
  void clearAnchorForTest() {
    _arrivalAnchor = null;
  }

  void resetForPreviewSeed() {
    _arrivalConfirmationCounter = 0;
  }

  void resetForStartActive() {
    _arrivalConfirmationCounter = 0;
  }

  void resetForEnd() {
    _arrivalAnchor = null;
    _arrivalConfirmationCounter = 0;
  }

  void resetForRetarget() {
    _arrivalConfirmationCounter = 0;
    _arrivalAnchor = null;
  }
}
