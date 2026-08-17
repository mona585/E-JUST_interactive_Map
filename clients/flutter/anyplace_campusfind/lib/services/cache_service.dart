import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';

/// Lightweight local settings (campus selection, recent waypoints).
class CacheService {
  VoidCallback? onDataChanged;

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

  // ---- Saved POIs (favorites) ----
  Future<List<String>> getSavedPois() async {
    final prefs = await _ensurePrefs();
    return prefs.getStringList(AppConstants.prefSavedPois) ?? const [];
  }

  Future<void> toggleSavedPoi(String puid) async {
    final list = (await getSavedPois()).toList();
    if (list.contains(puid)) {
      list.remove(puid);
    } else {
      list.insert(0, puid);
    }
    await _setStringList(AppConstants.prefSavedPois, list);
    onDataChanged?.call();
  }

  Future<bool> isPoiSaved(String puid) async {
    final list = await getSavedPois();
    return list.contains(puid);
  }
}
