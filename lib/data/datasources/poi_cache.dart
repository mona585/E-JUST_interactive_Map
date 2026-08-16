import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/poi_model.dart';

/// Local disk cache manager for Anyplace Points of Interest (POIs).
///
/// Directory structure:
/// `<baseDir>/pois/<buid>/<floor>/pois.json`
class PoiCache {
  final Directory? customBaseDir;

  PoiCache({this.customBaseDir});

  Future<Directory> _getRootDir() async {
    if (customBaseDir != null) {
      return Directory('${customBaseDir!.path}/pois');
    }
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/pois');
  }

  /// Resolves the directory where POIs are stored for a building/floor.
  Future<Directory> getFloorDir(String buid, String floor) async {
    final root = await _getRootDir();
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    return Directory('${root.path}/$cleanBuid/$cleanFloor');
  }

  /// Checks if a valid cached POI list exists for the given building and floor.
  Future<bool> hasPois(String buid, String floor) async {
    final dir = await getFloorDir(buid, floor);
    final file = File('${dir.path}/pois.json');
    return await file.exists() && await file.length() > 0;
  }

  /// Retrieves the cached list of [PoiModel]s if available, otherwise null.
  Future<List<PoiModel>?> getPois(String buid, String floor) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();

    if (!await hasPois(cleanBuid, cleanFloor)) {
      debugPrint(
        '[PoiCache] Cache MISS for buid=$cleanBuid, floor=$cleanFloor',
      );
      return null;
    }

    final dir = await getFloorDir(cleanBuid, cleanFloor);
    final file = File('${dir.path}/pois.json');

    try {
      final content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is List) {
        final list = decoded
            .whereType<Map<String, dynamic>>()
            .map((e) => PoiModel.fromJson(e))
            .toList();

        debugPrint(
          '[PoiCache] Cache HIT for buid=$cleanBuid, floor=$cleanFloor (${list.length} POIs)',
        );
        return list;
      }
    } catch (e) {
      debugPrint('[PoiCache] Error reading cached pois.json: $e');
    }

    return null;
  }

  /// Saves the list of [PoiModel]s to disk atomically.
  Future<void> savePois(
    String buid,
    String floor,
    List<PoiModel> pois,
  ) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    final dir = await getFloorDir(cleanBuid, cleanFloor);
    await dir.create(recursive: true);

    final targetFile = File('${dir.path}/pois.json');
    final tempFile = File('${dir.path}/pois.json.tmp');

    final jsonList = pois.map((p) => p.toJson()).toList();
    final jsonText = jsonEncode(jsonList);

    // 1. Write to temporary file
    await tempFile.writeAsString(jsonText, flush: true);

    // 2. Atomic rename
    if (await tempFile.exists()) {
      await tempFile.rename(targetFile.path);
    }

    debugPrint(
      '[PoiCache] Saved ${pois.length} POIs for buid=$cleanBuid, floor=$cleanFloor to ${targetFile.path}',
    );
  }

  /// Clears cached POIs for a specific building and floor.
  Future<bool> clearPois(String buid, String floor) async {
    final dir = await getFloorDir(buid, floor);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint('[PoiCache] Cleared POI cache for buid=$buid, floor=$floor');
      return true;
    }
    return false;
  }

  /// Purges all cached POIs.
  Future<void> clearAll() async {
    final root = await _getRootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
      debugPrint('[PoiCache] Cleared all POIs cache');
    }
  }
}
