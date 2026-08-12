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
class CacheService {
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

  void setCampuses(List<Campus> campuses) => _campuses = campuses;

  void setSpaces(List<Space> spaces) => _spaces = spaces;

  void setFloors(String buid, List<Floor> floors) =>
      _floorsByBuid[buid] = floors;

  void setPois(String buid, List<Poi> pois) => _poisByBuid[buid] = pois;

  List<Floor> floorsOf(String buid) => _floorsByBuid[buid] ?? const [];

  List<Poi> poisOf(String buid) => _poisByBuid[buid] ?? const [];

  Space? spaceByBuid(String buid) {
    for (final s in _spaces) {
      if (s.buid == buid) return s;
    }
    return null;
  }

  bool get hasData => _spaces.isNotEmpty;

  void clearData() {
    _campuses = [];
    _spaces = [];
    _floorsByBuid.clear();
    _poisByBuid.clear();
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
