import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/constants.dart';
import '../data/models/quick_access_item.dart';

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

  // ---- Quick Access (unified saved locations) ----

  /// Whether the Quick Access preference key has ever been written.
  ///
  /// Used as the one-time gate for first-run seeding/migration. An existing
  /// (possibly empty) key is a valid user state and must never be re-seeded.
  Future<bool> hasQuickAccessKey() async {
    final prefs = await _ensurePrefs();
    return prefs.containsKey(AppConstants.prefQuickAccess);
  }

  Future<List<QuickAccessItem>> getQuickAccessItems() async {
    final prefs = await _ensurePrefs();
    final raw = prefs.getString(AppConstants.prefQuickAccess);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(QuickAccessItem.fromJson)
            .toList();
      }
    } catch (e) {
      debugPrint('[CacheService] Error decoding quick access items: $e');
    }
    return const [];
  }

  Future<void> setQuickAccessItems(List<QuickAccessItem> items) async {
    final prefs = await _ensurePrefs();
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await prefs.setString(AppConstants.prefQuickAccess, encoded);
    onDataChanged?.call();
  }

  Future<bool> isQuickAccessItem(String type, String id) async {
    final items = await getQuickAccessItems();
    return items.any((i) => i.type == type && i.id == id);
  }

  /// Adds [item] if absent, or removes the existing entry if present.
  /// Deduplicated by `type + id`. New items are appended at the end.
  Future<void> toggleQuickAccessItem(QuickAccessItem item) async {
    final items = (await getQuickAccessItems()).toList();
    final existingIndex =
        items.indexWhere((i) => i.type == item.type && i.id == item.id);
    if (existingIndex >= 0) {
      items.removeAt(existingIndex);
    } else {
      items.add(item);
    }
    await setQuickAccessItems(items);
  }

  /// Removes every Quick Access item. The preference key persists so that
  /// first-run default seeding is not triggered again.
  Future<void> clearQuickAccessItems() async {
    await setQuickAccessItems(const []);
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
    onDataChanged?.call();
  }

  // ---- Legacy Saved POIs (migration source, read-only) ----
  Future<List<String>> getSavedPois() async {
    final prefs = await _ensurePrefs();
    return prefs.getStringList(AppConstants.prefSavedPois) ?? const [];
  }

  /// Removes the legacy `saved_pois` key after a successful one-time migration.
  Future<void> removeSavedPoisKey() async {
    final prefs = await _ensurePrefs();
    await prefs.remove(AppConstants.prefSavedPois);
  }
}
