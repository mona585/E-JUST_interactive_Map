import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../models/campus.dart';
import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';

/// In-memory cache of backend data plus SharedPreferences persistence for
/// lightweight local settings (campus selection, recent waypoints).
///
/// POIs/floors are keyed by `buid` so screens can look them up without
/// refetching after the initial bulk load. SharedPreferences is initialised
/// lazily so the cache can be constructed synchronously.
///
/// The bulk dataset (spaces + floors + POIs) is additionally snapshotted to a
/// JSON file under the app support directory so the app can show cached data
/// offline (Phase 7.2).
class CacheService {
  /// Fired whenever in-memory dataset mutates. Providers should increment a
  /// counter on this callback so dependent providers (e.g. search) rebuild.
  VoidCallback? onDataChanged;

  void _notify() => onDataChanged?.call();

  Future<SharedPreferences>? _prefsFuture;

  Future<SharedPreferences> _ensurePrefs() {
    return _prefsFuture ??= SharedPreferences.getInstance();
  }
  Future<void> _setString(String key, String? value) async {
    final prefs = await _ensurePrefs();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _setStringList(String key, List<String> value) async {
    final prefs = await _ensurePrefs();
    await prefs.setStringList(key, value);
  }

  // ---- Campus selection ----
  Future<String?> getSelectedCampusId() async {
    final prefs = await _ensurePrefs();
    return prefs.getString(AppConstants.prefCampusId);
  }

  Future<void> setSelectedCampusId(String? cuid) async {
    await _setString(AppConstants.prefCampusId, cuid);
  }

  // ---- In-memory dataset ----
  List<Campus> _campuses = [];
  List<Space> _spaces = [];
  final Map<String, List<Floor>> _floorsByBuid = {};
  final Map<String, List<Poi>> _poisByBuid = {};

  List<Campus> get campuses => _campuses;
  List<Space> get spaces => _spaces;

  void setCampuses(List<Campus> campuses) {
    _campuses = campuses;
    _notify();
  }

  void setSpaces(List<Space> spaces) {
    _spaces = spaces;
    _notify();
  }

  void setFloors(String buid, List<Floor> floors) {
    _floorsByBuid[buid] = floors;
    _notify();
  }

  void setPois(String buid, List<Poi> pois) {
    _poisByBuid[buid] = pois;
    _notify();
  }

  List<Floor> floorsOf(String buid) => _floorsByBuid[buid] ?? const [];

  List<Poi> poisOf(String buid) => _poisByBuid[buid] ?? const [];

  Space? spaceByBuid(String buid) {
    for (final s in _spaces) {
      if (s.buid == buid) return s;
    }
    return null;
  }

  bool get hasData => _spaces.isNotEmpty;

  /// True when the current dataset came from the local offline snapshot
  /// rather than a live fetch (Phase 7.2).
  bool _fromOfflineSnapshot = false;
  bool get fromOfflineSnapshot => _fromOfflineSnapshot;

  void clearData() {
    _campuses = [];
    _spaces = [];
    _floorsByBuid.clear();
    _poisByBuid.clear();
    _fromOfflineSnapshot = false;
    _notify();
  }

  // ---- Offline snapshot (Phase 7.2) ----
  Future<File> _snapshotFile() async {
    final appSupport = await getApplicationSupportDirectory();
    return File(p.join(appSupport.path, 'campus_data_snapshot.json'));
  }

  /// Writes the current in-memory dataset to a JSON file for offline use.
  ///
  /// The dataset can be large (every space, floor and POI on campus), so the
  /// JSON encoding runs on a background isolate to avoid blocking the UI
  /// thread (ANR / dropped frames) right after the bulk load.
  Future<void> saveOfflineSnapshot() async {
    final file = await _snapshotFile();
    final data = _SnapshotData(
      spaces: _spaces,
      floors: Map.of(_floorsByBuid),
      pois: Map.of(_poisByBuid),
    );
    final json = await compute(_encodeSnapshot, data);
    await file.writeAsString(json, flush: true);
  }

  /// Loads the offline snapshot into memory. Returns true when data was
  /// restored (used by the bulk loader as a fallback when the network fails).
  ///
  /// Decoding and model construction run on a background isolate; only the
  /// (cheap) in-memory assignment happens on the UI thread.
  Future<bool> loadOfflineSnapshot() async {
    final file = await _snapshotFile();
    if (!await file.exists()) return false;
    try {
      final json = await file.readAsString();
      final data = await compute(_decodeSnapshot, json);
      _spaces = data.spaces;
      _floorsByBuid
        ..clear()
        ..addAll(data.floors);
      _poisByBuid
        ..clear()
        ..addAll(data.pois);
      _fromOfflineSnapshot = _spaces.isNotEmpty;
      return _fromOfflineSnapshot;
    } catch (_) {
      return false;
    }
  }

  // ---- Recent waypoints (persisted) ----
  Future<List<String>> getRecentWaypoints() async {
    final prefs = await _ensurePrefs();
    return prefs.getStringList(AppConstants.prefRecentWaypoints) ?? const [];
  }

  Future<void> addRecentWaypoint(String puid) async {
    final list = (await getRecentWaypoints()).toList()
      ..remove(puid)
      ..insert(0, puid);
    await _setStringList(
      AppConstants.prefRecentWaypoints,
      list.take(10).toList(),
    );
  }
}

/// The part of the dataset written to / restored from the offline snapshot.
/// Plain fields of simple model objects so instances are sendable between
/// isolates (used with [compute]).
class _SnapshotData {
  const _SnapshotData({
    required this.spaces,
    required this.floors,
    required this.pois,
  });

  final List<Space> spaces;
  final Map<String, List<Floor>> floors;
  final Map<String, List<Poi>> pois;
}

/// Runs on a background isolate: serialises the snapshot to a JSON string.
String _encodeSnapshot(_SnapshotData data) {
  return jsonEncode({
    'spaces': data.spaces.map((s) => s.toJson()).toList(),
    'floors': {
      for (final e in data.floors.entries)
        e.key: e.value.map((f) => f.toJson()).toList(),
    },
    'pois': {
      for (final e in data.pois.entries)
        e.key: e.value.map((poi) => poi.toJson()).toList(),
    },
  });
}

/// Runs on a background isolate: decodes the snapshot JSON and rebuilds the
/// model objects.
_SnapshotData _decodeSnapshot(String json) {
  final map = jsonDecode(json) as Map<String, dynamic>;
  final spaces = ((map['spaces'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>())
      .map(Space.fromJson)
      .toList();
  final floors = <String, List<Floor>>{};
  final rawFloors = map['floors'] as Map<String, dynamic>? ?? const {};
  rawFloors.forEach((buid, list) {
    floors[buid] =
        ((list as List<dynamic>).cast<Map<String, dynamic>>()).map(Floor.fromJson).toList();
  });
  final pois = <String, List<Poi>>{};
  final rawPois = map['pois'] as Map<String, dynamic>? ?? const {};
  rawPois.forEach((buid, list) {
    pois[buid] =
        ((list as List<dynamic>).cast<Map<String, dynamic>>()).map(Poi.fromJson).toList();
  });
  return _SnapshotData(spaces: spaces, floors: floors, pois: pois);
}
