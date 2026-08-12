// Phase 7.4/7.2 — TileService caches floorplan tiles and serves them offline.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:anyplace_campusfind/models/floor.dart';
import 'package:anyplace_campusfind/services/api_service.dart';
import 'package:anyplace_campusfind/services/tile_service.dart';

/// Test double so `getApplicationSupportDirectory` works without a device.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final Directory temp;

  _FakePathProvider(this.temp);

  @override
  Future<String?> getApplicationSupportPath() async => temp.path;
}

/// ApiService stub that counts calls and returns a canned zip archive.
class _FakeApiService extends ApiService {
  int zipCalls = 0;

  final List<int> archiveBytes;

  _FakeApiService(this.archiveBytes);

  @override
  Future<Uint8List> fetchFloorTilesZip(String buid, String floorNumber) async {
    zipCalls++;
    return Uint8List.fromList(archiveBytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('tile_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final floor = Floor(
    fuid: 'b1_2',
    buid: 'b1',
    floorNumber: '2',
    floorName: 'Second Floor',
    description: null,
  );

  // A valid zip containing a single static_tiles/19/z19x0y0.png entry.
  List<int> makeZip() {
    return ZipEncoder().encode(Archive()
      ..addFile(ArchiveFile(
        'static_tiles/19/z19x0y0.png',
        10,
        List<int>.filled(10, 1),
      )));
  }

  test('downloadAndExtract writes static_tiles and returns its directory', () async {
    final service = TileService(_FakeApiService(makeZip()));
    final dir = await service.downloadAndExtract(floor);

    expect(dir.existsSync(), isTrue);
    expect(
      File('${dir.path}${Platform.pathSeparator}19'
          '${Platform.pathSeparator}z19x0y0.png').existsSync(),
      isTrue,
    );
  });

  test('ensureTiles returns cached directory without a second download', () async {
    final api = _FakeApiService(makeZip());
    final service = TileService(api);

    final first = await service.ensureTiles(floor);
    expect(api.zipCalls, 1);

    final second = await service.ensureTiles(floor);
    expect(second.path, first.path);
    expect(api.zipCalls, 1, reason: 'cached tiles must not be re-downloaded');
  });

  test('tileDirFor returns null before any download', () async {
    final service = TileService(_FakeApiService(makeZip()));
    expect(await service.tileDirFor(floor), isNull);
  });

  test('downloadAndExtract throws ApiException on a broken archive', () async {
    final service = TileService(_FakeApiService(const [1, 2, 3]));
    await expectLater(
      service.downloadAndExtract(floor),
      throwsA(isA<ApiException>()),
    );
  });
}
