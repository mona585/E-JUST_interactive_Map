import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/floor_model.dart';
import '../models/floorplan_model.dart';

/// Local disk cache manager for Anyplace geographic floorplan images.
///
/// Directory structure:
/// `<baseDir>/floorplans/<buid>/<floor>/floorplan.png`
/// `<baseDir>/floorplans/<buid>/<floor>/metadata.json`
class FloorplanCache {
  final Directory? customBaseDir;

  FloorplanCache({this.customBaseDir});

  Future<Directory> _getRootDir() async {
    if (customBaseDir != null) {
      return Directory('${customBaseDir!.path}/floorplans');
    }
    final appSupport = await getApplicationSupportDirectory();
    return Directory('${appSupport.path}/floorplans');
  }

  /// Resolves the directory where the floorplan image is stored for a building/floor.
  Future<Directory> getFloorDir(String buid, String floor) async {
    final root = await _getRootDir();
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    return Directory('${root.path}/$cleanBuid/$cleanFloor');
  }

  /// Checks if a valid cached floorplan image exists for the given building and floor.
  Future<bool> hasFloorplan(String buid, String floor) async {
    final dir = await getFloorDir(buid, floor);
    final imageFile = File('${dir.path}/floorplan.png');
    return await imageFile.exists() && await imageFile.length() > 0;
  }

  /// Retrieves the cached [FloorplanModel] if available, otherwise null.
  Future<FloorplanModel?> getFloorplan(
    String buid,
    String floor,
    FloorModel floorMetadata,
  ) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();

    if (!await hasFloorplan(cleanBuid, cleanFloor)) {
      debugPrint(
        '[FloorplanCache] Cache MISS for floorplan buid=$cleanBuid, floor=$cleanFloor',
      );
      return null;
    }

    final dir = await getFloorDir(cleanBuid, cleanFloor);
    final imageFile = File('${dir.path}/floorplan.png');
    final fileSize = await imageFile.length();

    // Read cached bounds if metadata.json exists, otherwise use FloorModel bounds
    double swLat = floorMetadata.bottomLeftLat ?? 0.0;
    double swLng = floorMetadata.bottomLeftLng ?? 0.0;
    double neLat = floorMetadata.topRightLat ?? 0.0;
    double neLng = floorMetadata.topRightLng ?? 0.0;

    final metaFile = File('${dir.path}/metadata.json');
    if (await metaFile.exists()) {
      try {
        final content = await metaFile.readAsString();
        final dynamic json = jsonDecode(content);
        if (json is Map<String, dynamic>) {
          swLat = (json['bottom_left_lat'] as num?)?.toDouble() ?? swLat;
          swLng = (json['bottom_left_lng'] as num?)?.toDouble() ?? swLng;
          neLat = (json['top_right_lat'] as num?)?.toDouble() ?? neLat;
          neLng = (json['top_right_lng'] as num?)?.toDouble() ?? neLng;
        }
      } catch (e) {
        debugPrint('[FloorplanCache] Error reading metadata.json: $e');
      }
    }

    debugPrint(
      '[FloorplanCache] Cache HIT for floorplan buid=$cleanBuid, floor=$cleanFloor ($fileSize bytes)',
    );

    return FloorplanModel(
      buid: cleanBuid,
      floorNumber: cleanFloor,
      imagePath: imageFile.path,
      bottomLeftLat: swLat,
      bottomLeftLng: swLng,
      topRightLat: neLat,
      topRightLng: neLng,
      isCached: true,
      imageSizeBytes: fileSize,
    );
  }

  /// Saves the decoded PNG image bytes to disk atomically and returns the resulting [FloorplanModel].
  Future<FloorplanModel> saveFloorplan(
    String buid,
    String floor,
    Uint8List imageBytes,
    FloorModel floorMetadata,
  ) async {
    final cleanBuid = buid.trim();
    final cleanFloor = floor.trim();
    final dir = await getFloorDir(cleanBuid, cleanFloor);
    await dir.create(recursive: true);

    final targetFile = File('${dir.path}/floorplan.png');
    final tempFile = File('${dir.path}/floorplan.png.tmp');

    // 1. Atomic write to temporary file
    await tempFile.writeAsBytes(imageBytes, flush: true);

    // 2. Atomic rename (replaces target file safely)
    if (await tempFile.exists()) {
      await tempFile.rename(targetFile.path);
    }

    // 3. Write metadata.json
    final metaFile = File('${dir.path}/metadata.json');
    final swLat = floorMetadata.bottomLeftLat ?? 0.0;
    final swLng = floorMetadata.bottomLeftLng ?? 0.0;
    final neLat = floorMetadata.topRightLat ?? 0.0;
    final neLng = floorMetadata.topRightLng ?? 0.0;

    final metaJson = jsonEncode({
      'buid': cleanBuid,
      'floor_number': cleanFloor,
      'bottom_left_lat': swLat,
      'bottom_left_lng': swLng,
      'top_right_lat': neLat,
      'top_right_lng': neLng,
      'size_bytes': imageBytes.length,
      'saved_at': DateTime.now().toIso8601String(),
    });
    await metaFile.writeAsString(metaJson, flush: true);

    debugPrint(
      '[FloorplanCache] Saved ${imageBytes.length} bytes to ${targetFile.path}',
    );

    return FloorplanModel(
      buid: cleanBuid,
      floorNumber: cleanFloor,
      imagePath: targetFile.path,
      imageBytes: imageBytes,
      bottomLeftLat: swLat,
      bottomLeftLng: swLng,
      topRightLat: neLat,
      topRightLng: neLng,
      isCached: true,
      imageSizeBytes: imageBytes.length,
    );
  }

  /// Clears the floorplan cache for a specific building and floor.
  Future<bool> clearFloorplan(String buid, String floor) async {
    final dir = await getFloorDir(buid, floor);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      debugPrint(
        '[FloorplanCache] Cleared floorplan cache for buid=$buid, floor=$floor',
      );
      return true;
    }
    return false;
  }

  /// Purges the entire floorplans cache directory.
  Future<void> clearAll() async {
    final root = await _getRootDir();
    if (await root.exists()) {
      await root.delete(recursive: true);
      debugPrint('[FloorplanCache] Cleared all floorplans');
    }
  }
}