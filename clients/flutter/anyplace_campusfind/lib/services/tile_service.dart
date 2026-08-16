import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/floor.dart';
import 'api_service.dart';

/// Downloads, extracts and caches floorplan tile archives.
///
/// The backend serves a zip (via `POST /api/floortiles/zip/:buid/:floor`)
/// whose structure is:
///   `static_tiles/<zoom>/z<zoom>x<x>y<y>.png`
///   `static_tiles/bounds.txt`
///
/// Extraction mirrors that layout under
/// `<appSupport>/floorplan_tiles/<buid>_<floorNumber>/static_tiles/` so a
/// custom [TileProvider] (Phase 3 map screen) can serve local files.
class TileService {
  TileService(this._api);

  final ApiService _api;

  /// Directory containing extracted tiles for a building/floor, or null when
  /// not yet downloaded.
  Future<Directory?> tileDirFor(Floor floor) async {
    final base = await _tilesRoot();
    final floorDir = Directory(
      p.join(base.path, '${floor.buid}_${floor.floorNumber}'),
    );
    return _resolveTilesDir(floorDir);
  }

  /// Returns the extracted tiles directory for a floor, downloading and
  /// extracting it on first use. Previously downloaded floors are served
  /// straight from disk (Phase 7.4 tile caching) so the floorplan still
  /// renders offline (Phase 7.2).
  Future<Directory> ensureTiles(Floor floor) async {
    final existing = await tileDirFor(floor);
    if (existing != null) return existing;
    return downloadAndExtract(floor);
  }

  /// Downloads the tiles zip for a floor and extracts it to the cache,
  /// returning the extracted tiles directory.
  Future<Directory> downloadAndExtract(Floor floor) async {
    debugPrint(
      '[tiles] downloading zip ${floor.buid} floor ${floor.floorNumber}',
    );
    final bytes = await _api.fetchFloorTilesZip(floor.buid, floor.floorNumber);
    debugPrint('[tiles] zip bytes: ${bytes.length}');
    final root = await _tilesRoot();
    final floorDir = Directory(
      p.join(root.path, '${floor.buid}_${floor.floorNumber}'),
    );
    if (await floorDir.exists()) {
      await floorDir.delete(recursive: true);
    }
    await floorDir.create(recursive: true);

    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final dest = File(p.join(floorDir.path, file.name));
      await dest.parent.create(recursive: true);
      await dest.writeAsBytes(file.content as List<int>, flush: true);
    }

    final tilesDir = await _resolveTilesDir(floorDir);
    if (tilesDir == null) {
      throw ApiException(
        'Tile archive for ${floor.buid}/${floor.floorNumber} '
        'has no floorplan tiles',
      );
    }
    return tilesDir;
  }

  /// The tiles directory inside [floorDir], regardless of archive layout.
  ///
  /// Two layouts exist in the wild:
  ///  * classic: `static_tiles/<zoom>/z<zoom>x<x>y<y>.png` (older deployments,
  ///    used by the unit tests);
  ///  * flat:    `<zoom>/z<zoom>x<x>y<y>.png` at the archive root (the public
  ///    UCY Anyplace server), with `bounds.txt` and no `static_tiles` bucket.
  /// Both are served by [LocalFloorplanTileProvider]; only the root directory
  /// that contains the tile files differs.
  Future<Directory?> _resolveTilesDir(Directory floorDir) async {
    if (!await floorDir.exists()) return null;

    final staticTiles = Directory(p.join(floorDir.path, 'static_tiles'));
    if (await staticTiles.exists()) return staticTiles;

    // Flat layout: the floor directory itself contains `<zoom>/…png` files.
    try {
      await for (final entity
          in floorDir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.png')) return floorDir;
      }
    } catch (_) {
      // Unreadable directory — treat as not downloaded.
    }
    return null;
  }

  Future<Directory> _tilesRoot() async {
    final appSupport = await getApplicationSupportDirectory();
    final root = Directory(p.join(appSupport.path, 'floorplan_tiles'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }
}
