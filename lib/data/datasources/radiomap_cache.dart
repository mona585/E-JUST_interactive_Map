import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/api_config.dart';

/// Local disk cache manager for Anyplace RadioMap files.
///
/// Directory structure:
/// `<baseDir>/radiomaps/<buid>/<floor>/indoor-radiomap-mean.txt`
class RadioMapCache {
  final Directory? customBaseDir;

  RadioMapCache({this.customBaseDir});

  /// Resolves the base root directory for radiomaps.
  Future<Directory> _getRootDir() async {
    if (customBaseDir != null) {
      return Directory('${customBaseDir!.path}/radiomaps');
    }
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/radiomaps');
  }

  /// Resolves the file handle for a specific building and floor radiomap.
  Future<File> getFile(
    String buid,
    String floor, {
    String filename = ApiConfig.defaultRadiomapMeanFilename,
  }) async {
    final root = await _getRootDir();
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    final cleanFilename = filename.trim();
    return File('${root.path}/$cleanBuid/$cleanFloor/$cleanFilename');
  }

  /// Checks whether a valid non-empty cached radiomap exists for the specified buid and floor.
  Future<bool> hasRadioMap(
    String buid,
    String floor, {
    String filename = ApiConfig.defaultRadiomapMeanFilename,
  }) async {
    final file = await getFile(buid, floor, filename: filename);
    final exists = await file.exists();
    if (!exists) return false;
    try {
      final length = await file.length();
      if (length == 0) return false;
      final content = await file.readAsString();
      return content.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Reads and returns cached RadioMap plaintext, or null on cache miss.
  Future<String?> getRadioMap(
    String buid,
    String floor, {
    String filename = ApiConfig.defaultRadiomapMeanFilename,
  }) async {
    final file = await getFile(buid, floor, filename: filename);
    if (!await file.exists()) {
      debugPrint('[RadioMapCache] Cache MISS for buid=$buid, floor=$floor');
      return null;
    }

    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        debugPrint(
          '[RadioMapCache] Cache file exists but is empty for buid=$buid, floor=$floor',
        );
        return null;
      }
      debugPrint(
        '[RadioMapCache] Cache HIT for buid=$buid, floor=$floor (${content.length} chars)',
      );
      return content;
    } catch (e) {
      debugPrint('[RadioMapCache] Error reading cached radiomap: $e');
      return null;
    }
  }

  /// Writes RadioMap plaintext to persistent disk cache.
  Future<File> saveRadioMap(
    String buid,
    String floor,
    String content, {
    String filename = ApiConfig.defaultRadiomapMeanFilename,
  }) async {
    final file = await getFile(buid, floor, filename: filename);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final writtenFile = await file.writeAsString(content, flush: true);
    debugPrint(
      '[RadioMapCache] Saved radiomap to cache: ${writtenFile.path} (${content.length} chars)',
    );
    return writtenFile;
  }

  /// Clears the cached radiomap for a specific floor.
  Future<bool> clearRadioMap(String buid, String floor) async {
    final file = await getFile(buid, floor);
    if (await file.parent.exists()) {
      await file.parent.delete(recursive: true);
      debugPrint(
        '[RadioMapCache] Cleared radiomap cache for buid=$buid, floor=$floor',
      );
      return true;
    }
    return false;
  }

  /// Purges the entire radiomaps cache directory.
  Future<void> clearAll() async {
    final root = await _getRootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
      debugPrint('[RadioMapCache] Cleared entire radiomaps cache directory');
    }
  }
}
