import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
import '../services/api_service.dart';
import '../services/tile_service.dart';
import 'providers.dart';

/// Lifecycle of the locally-extracted floorplan tiles for one building+floor.
enum FloorplanStatus { idle, loading, ready, unavailable, error }

/// Snapshot of the tile acquisition state for a single floor.
class FloorplanState {
  const FloorplanState({
    required this.status,
    this.tilesDir,
    this.error,
  });

  final FloorplanStatus status;
  final Directory? tilesDir;
  final String? error;

  bool get isReady => status == FloorplanStatus.ready && tilesDir != null;
}

/// Identifies one (building, floor) tile set.
class FloorplanKey {
  const FloorplanKey(this.buid, this.floorNumber);

  final String buid;
  final String floorNumber;

  @override
  bool operator ==(Object other) =>
      other is FloorplanKey &&
      other.buid == buid &&
      other.floorNumber == floorNumber;

  @override
  int get hashCode => Object.hash(buid, floorNumber);

  /// The [Floor] this key maps to, used by [TileService].
  Floor toFloor() => Floor(
        buid: buid,
        floorNumber: floorNumber,
        fuid: '${buid}_$floorNumber',
      );
}

/// Downloads and caches floorplan tiles for one building+floor exactly once;
/// subsequent requests reuse the cached [FloorplanState].
class FloorplanTilesNotifier extends StateNotifier<FloorplanState> {
  FloorplanTilesNotifier(this._tiles, this._key)
      : super(const FloorplanState(status: FloorplanStatus.idle));

  final TileService _tiles;
  final FloorplanKey _key;
  bool _requested = false;

  /// Kicks off the (idempotent) download. Safe to call from every build.
  Future<void> ensure() async {
    if (_requested) return;
    _requested = true;
    state = const FloorplanState(status: FloorplanStatus.loading);
    debugPrint('[floorplan] ${_key.buid} floor ${_key.floorNumber} loading');
    try {
      final tilesDir = await _tiles.ensureTiles(_key.toFloor());
      state = FloorplanState(status: FloorplanStatus.ready, tilesDir: tilesDir);
      debugPrint('[floorplan] ${_key.buid} floor ${_key.floorNumber} ready');
    } on ApiException catch (e) {
      // The public UCY deployment has no floor/all, so a missing floor is the
      // common case here — degrade it into a graceful "unavailable" state.
      final msg = e.message.toLowerCase();
      final notFound = e.statusCode == 404 ||
          e.statusCode == 400 ||
          msg.contains('no floorplan tiles') ||
          msg.contains('404');
      state = FloorplanState(
        status: notFound ? FloorplanStatus.unavailable : FloorplanStatus.error,
        error: e.message,
      );
    } catch (e) {
      state = FloorplanState(status: FloorplanStatus.error, error: e.toString());
    }
  }
}

final floorplanTilesProvider =
    StateNotifierProvider.family<FloorplanTilesNotifier, FloorplanState,
            FloorplanKey>(
        (ref, key) => FloorplanTilesNotifier(ref.watch(tileServiceProvider), key));