import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

/// Serves floorplan tiles from a locally-extracted `static_tiles/` directory.
///
/// Tile files follow the Anyplace convention:
///   `static_tiles/<zoom>/z<zoom>x<x>y<y>.png`
/// (see `server/anyplace_tiler/fix-tile-structure.sh`).
class LocalFloorplanTileProvider extends TileProvider {
  LocalFloorplanTileProvider(this._tilesDir, {super.headers});

  final Directory _tilesDir;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final file = File(
      '${_tilesDir.path}${Platform.pathSeparator}${coordinates.z}'
      '${Platform.pathSeparator}z${coordinates.z}x${coordinates.x}'
      'y${coordinates.y}.png',
    );
    return FileImage(file);
  }
}
