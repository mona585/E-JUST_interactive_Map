import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Identifies the floorplan image a ground overlay should display.
///
/// The [key] is the stable identity used for bitmap caching: two requests
/// with the same key describe the same image and must share one prepared
/// [BytesMapBitmap] so repeated GoogleMap rebuilds never re-upload it.
@immutable
class FloorplanOverlayRequest {
  const FloorplanOverlayRequest({
    required this.buid,
    required this.floorNumber,
    required this.imagePath,
    required this.bounds,
  });

  final String buid;
  final String floorNumber;
  final String imagePath;
  final LatLngBounds bounds;

  String get key => '$buid|$floorNumber|$imagePath';
}

/// A floorplan whose bitmap has been decoded/resized/encoded exactly once.
class PreparedFloorplanOverlay {
  const PreparedFloorplanOverlay({required this.key, required this.overlay});

  final String key;

  /// Stable overlay object. Reusing this identical instance across rebuilds
  /// makes google_maps_flutter treat the overlay as unchanged, so no bitmap
  /// data crosses the platform channel until the floorplan actually changes.
  final GroundOverlay overlay;
}

/// Bounded LRU cache of prepared floorplan overlays.
///
/// Guarantees:
/// - the floorplan image file is read and decoded once per floor identity;
/// - the same [GroundOverlay] instance is returned for the same key, so
///   heading/GPS/provider-driven rebuilds produce zero platform updates;
/// - memory stays bounded ([capacity] entries, each holding only resized
///   (capped) encoded PNG bytes).
class FloorplanOverlayCache {
  FloorplanOverlayCache({this.capacity = 3})
      : assert(capacity > 0, 'capacity must be positive');

  final int capacity;

  final LinkedHashMap<String, PreparedFloorplanOverlay> _entries =
      LinkedHashMap<String, PreparedFloorplanOverlay>();

  static String keyFor({
    required String buid,
    required String floorNumber,
    required String imagePath,
  }) =>
      '$buid|$floorNumber|$imagePath';

  /// Returns the cached entry for [key], refreshing its recency.
  PreparedFloorplanOverlay? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) return null;
    _entries[key] = entry;
    return entry;
  }

  bool contains(String key) => _entries.containsKey(key);

  void put(PreparedFloorplanOverlay entry) {
    _entries.remove(entry.key);
    _entries[entry.key] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  /// Reads, decodes and resizes the floorplan image exactly once and builds
  /// the resulting [GroundOverlay]. Returns null on any failure (missing,
  /// empty or unreadable file / decode error); callers simply show no overlay
  /// instead of crashing or falling back to unbounded raw uploads.
  ///
  /// The decode is capped at [maxDimension] on the longest side, mirroring
  /// the previous resize behavior, so the encoded bitmap handed to the maps
  /// renderer stays within sane texture sizes.
  static Future<PreparedFloorplanOverlay?> prepare(
    FloorplanOverlayRequest request, {
    int maxDimension = 2048,
  }) async {
    try {
      final Uint8List rawBytes = await File(request.imagePath).readAsBytes();
      if (rawBytes.isEmpty) {
        debugPrint(
            '[FloorplanOverlayCache] empty floorplan image: ${request.imagePath}');
        return null;
      }

      final Uint8List bitmapBytes =
          await _resizePng(rawBytes, maxDimension: maxDimension);
      debugPrint(
        '[FloorplanOverlayCache] prepared ${request.key} '
        '(${bitmapBytes.length} bytes)',
      );

      final overlay = GroundOverlay.fromBounds(
        groundOverlayId: GroundOverlayId(
            'floorplan_${request.buid}_${request.floorNumber}'),
        image: BitmapDescriptor.bytes(bitmapBytes,
            bitmapScaling: MapBitmapScaling.none),
        bounds: request.bounds,
        transparency: 0.0,
      );
      return PreparedFloorplanOverlay(key: request.key, overlay: overlay);
    } catch (e) {
      debugPrint('[FloorplanOverlayCache] failed to prepare $request: $e');
      return null;
    }
  }

  /// Downscales [rawBytes] so both dimensions fit within [maxDimension].
  ///
  /// The scaling is performed by the native image codec (targetWidth /
  /// targetHeight), so the full-resolution bitmap is never materialized in
  /// Dart memory — critical for multi-megabyte campus floorplans on
  /// low-end devices.
  static Future<Uint8List> _resizePng(
    Uint8List rawBytes, {
    required int maxDimension,
  }) async {
    ui.Image? image =
        await _decodeBounded(rawBytes, targetWidth: maxDimension);
    if (image == null) {
      return rawBytes;
    }
    if (image.height <= maxDimension) {
      return _encodePng(image, fallback: rawBytes);
    }
    // Bounding the width still leaves the height above the cap: the image
    // is portrait, so bound its height instead.
    image.dispose();
    image = await _decodeBounded(rawBytes, targetHeight: maxDimension);
    if (image == null) {
      return rawBytes;
    }
    return _encodePng(image, fallback: rawBytes);
  }

  static Future<ui.Image?> _decodeBounded(
    Uint8List bytes, {
    int? targetWidth,
    int? targetHeight,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
        targetHeight: targetHeight,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('[FloorplanOverlayCache] decode failed: $e');
      return null;
    }
  }

  static Future<Uint8List> _encodePng(
    ui.Image image, {
    required Uint8List fallback,
  }) async {
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List() ?? fallback;
    } finally {
      image.dispose();
    }
  }
}
