import 'dart:io';

import 'package:archive/archive.dart';
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
    final dir = Directory(
      p.join(base.path, '${floor.buid}_${floor.floorNumber}', 'static_tiles'),
    );
    if (await dir.exists()) return dir;
    return null;
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
  /// returning the extracted `static_tiles` directory.
  Future<Directory> downloadAndExtract(Floor floor) async {
    final bytes = await _api.fetchFloorTilesZip(floor.buid, floor.floorNumber);
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

    final tilesDir = Directory(p.join(floorDir.path, 'static_tiles'));
    if (!await tilesDir.exists()) {
      throw ApiException(
        'Tile archive for ${floor.buid}/${floor.floorNumber} '
        'has no static_tiles directory',
      );
    }
    return tilesDir;
  }

  Future<Directory> _tilesRoot() async {
    final appSupport = await getApplicationSupportDirectory();
    final root = Directory(p.join(appSupport.path, 'floorplan_tiles'));
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }
}
