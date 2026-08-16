import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Serves floorplan tiles from a locally-extracted tiles directory to the
/// Google Maps SDK.
///
/// Tile files follow the Anyplace convention:
///   `<zoom>/z<zoom>x<x>y<y>.png`
/// (see `server/anyplace_tiler/fix-tile-structure.sh`). The same layout is
/// produced by both the `static_tiles/` and the flat zip layouts handled by
/// [TileService], so the Web-Mercator x/y/z coordinates requested by Google
/// Maps map directly onto the downloaded files.
class GoogleFloorplanTileProvider extends TileProvider {
  GoogleFloorplanTileProvider(this._tilesDir);

  final Directory _tilesDir;

  /// 1x1 transparent PNG, returned for tile coordinates that were not part of
  /// the downloaded archive (tiles outside the floorplan's geographic extent).
  /// Google Maps keeps requesting tiles for the whole visible grid, so missing
  /// files must not surface as image-load errors.
  static final Uint8List _emptyTile = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  );

  @override
  Future<Tile> getTile(int x, int y, int? zoom) async {
    final z = zoom ?? 0;
    final file = File(
      '${_tilesDir.path}${Platform.pathSeparator}$z'
      '${Platform.pathSeparator}z${z}x$x'
      'y$y.png',
    );
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      return Tile(256, 256, bytes);
    }
    return Tile(256, 256, _emptyTile);
  }
}