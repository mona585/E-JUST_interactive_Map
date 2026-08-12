import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../providers/map_view_provider.dart';
import '../services/positioning_service.dart';
import 'providers.dart';
import 'route_provider.dart';

/// Which source produced the current best position.
enum PositioningMode { off, gps, wifi }

/// Snapshot of the combined GPS + Wi-Fi position.
class PositionState {
  const PositionState({
    this.gps,
    this.wifi,
    this.mode = PositioningMode.off,
    this.error,
    this.isActive = false,
  });

  /// Last known GPS fix.
  final LatLng? gps;

  /// Last Wi-Fi fingerprint estimate.
  final LatLng? wifi;

  /// The source backing [position].
  final PositioningMode mode;

  final String? error;
  final bool isActive;

  /// The best known position (Wi-Fi preferred when indoors).
  LatLng? get position => mode == PositioningMode.wifi ? wifi : gps;

  PositionState copyWith({
    LatLng? gps,
    bool clearGps = false,
    LatLng? wifi,
    bool clearWifi = false,
    PositioningMode? mode,
    String? error,
    bool clearError = false,
    bool? isActive,
  }) {
    return PositionState(
      gps: clearGps ? null : gps ?? this.gps,
      wifi: clearWifi ? null : wifi ?? this.wifi,
      mode: mode ?? this.mode,
      error: clearError ? null : error ?? this.error,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Tracks GPS continuously and periodically runs Wi-Fi fingerprint
/// positioning while a building + floor are selected.
class PositionNotifier extends StateNotifier<PositionState> {
  PositionNotifier({
    required PositioningService service,
    required MapViewState Function() currentMapState,
    required void Function(LatLng? position) onUserPosition,
    Duration wifiInterval = const Duration(seconds: 7),
  })  : _service = service,
        _currentMapState = currentMapState,
        _onUserPosition = onUserPosition,
        _wifiInterval = wifiInterval,
        super(const PositionState());

  final PositioningService _service;
  final MapViewState Function() _currentMapState;
  final void Function(LatLng?) _onUserPosition;
  final Duration _wifiInterval;

  StreamSubscription<LatLng>? _gpsSub;
  Timer? _wifiTimer;
  bool _started = false;

  /// Starts GPS tracking and the periodic Wi-Fi positioning loop.
  ///
  /// Safe to call repeatedly (e.g. on tab rebuilds) — the first call starts
  /// the tracking, subsequent calls until [stop] are no-ops.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    if (state.isActive) return;

    final granted = await _service.requestGpsPermission();
    if (!granted) {
      state = state.copyWith(
        error: 'Location permission denied',
        isActive: false,
      );
      return;
    }

    state = state.copyWith(isActive: true, clearError: true);
    _gpsSub = _service.gpsStream().listen(
          (pos) => _applyGps(pos),
          onError: (Object e) {
            state = state.copyWith(error: 'GPS error: $e');
          },
          cancelOnError: false,
        );
    _wifiTimer = Timer.periodic(_wifiInterval, (_) => _wifiEstimate());
    await _wifiEstimate();
  }

  void _applyGps(LatLng pos) {
    state = state.copyWith(
      gps: pos,
      mode: state.wifi == null ? PositioningMode.gps : state.mode,
    );
    _onUserPosition(state.position);
  }

  /// Runs one Wi-Fi scan + server estimate when a building and floor are
  /// selected. Falls back silently to GPS when unavailable.
  Future<void> _wifiEstimate() async {
    final mapState = _currentMapState();
    final space = mapState.selectedSpace;
    final floor = mapState.selectedFloor;
    if (space == null || floor == null) return;

    try {
      final accessPoints = await _service.scanAccessPoints();
      if (accessPoints.isEmpty) return;

      final estimate = await _service.estimatePosition(
        buid: space.buid,
        floor: floor.floorNumber,
        accessPoints: accessPoints,
      );
      if (estimate == null) return; // no radiomap data → keep GPS

      final wifi = LatLng(estimate.lat, estimate.long);
      state = state.copyWith(wifi: wifi, mode: PositioningMode.wifi);
      _onUserPosition(state.position);
    } catch (_) {
      // Graceful fallback: stay on GPS.
    }
  }

  /// Stops tracking (GPS subscription + Wi-Fi timer).
  void stop() {
    _started = false;
    _gpsSub?.cancel();
    _gpsSub = null;
    _wifiTimer?.cancel();
    _wifiTimer = null;
    state = state.copyWith(isActive: false);
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

final positioningServiceProvider =
    Provider<PositioningService>((ref) {
  return PositioningService(api: ref.watch(apiServiceProvider));
});

final positionStateProvider =
    StateNotifierProvider<PositionNotifier, PositionState>((ref) {
  return PositionNotifier(
    service: ref.watch(positioningServiceProvider),
    currentMapState: () => ref.read(mapViewStateProvider),
    onUserPosition: (position) =>
        ref.read(userLocationProvider.notifier).state = position,
  );
});
