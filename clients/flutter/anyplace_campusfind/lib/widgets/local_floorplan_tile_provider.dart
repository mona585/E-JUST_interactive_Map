import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Serves floorplan tiles from a locally-extracted tiles directory.
///
/// Tile files follow the Anyplace convention:
///   `<zoom>/z<zoom>x<x>y<y>.png`
/// (see `server/anyplace_tiler/fix-tile-structure.sh`). The same layout is
/// produced by both the `static_tiles/` and the flat zip layouts handled by
/// [TileService].
class LocalFloorplanTileProvider extends TileProvider {
  LocalFloorplanTileProvider(this._tilesDir, {super.headers});

  final Directory _tilesDir;

  /// 1x1 transparent PNG, returned for tile coordinates that were not part of
  /// the downloaded archive (tiles outside the floorplan's geographic extent).
  /// FlutterMap keeps asking for the visible grid even above/below the tiled
  /// zooms, so missing files must not surface as image-load errors.
  static final Uint8List _emptyTile = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = File(
      '${_tilesDir.path}${Platform.pathSeparator}${coordinates.z}'
      '${Platform.pathSeparator}z${coordinates.z}x${coordinates.x}'
      'y${coordinates.y}.png',
    );
    if (file.existsSync()) return FileImage(file);
    return MemoryImage(_emptyTile);
  }
}