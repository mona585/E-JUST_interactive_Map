import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/ui/utils/floorplan_overlay_cache.dart';

final LatLngBounds _bounds = LatLngBounds(
  southwest: LatLng(30.0, 32.0),
  northeast: LatLng(30.01, 32.02),
);

Future<Uint8List> _renderPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF3366AA),
  );
  final image = await recorder.endRecording().toImage(width, height);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
  } finally {
    image.dispose();
  }
}

FloorplanOverlayRequest _request(
  String imagePath, {
  String buid = 'buid-a',
  String floorNumber = '2',
}) =>
    FloorplanOverlayRequest(
      buid: buid,
      floorNumber: floorNumber,
      imagePath: imagePath,
      bounds: _bounds,
    );

Future<PreparedFloorplanOverlay> _prepareOrFail(
  FloorplanOverlayRequest request,
) async {
  final prepared = await FloorplanOverlayCache.prepare(request);
  if (prepared == null) {
    fail('FloorplanOverlayCache.prepare unexpectedly returned null');
  }
  return prepared;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('floorplan_overlay_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeImage(String fileName) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(await _renderPng(64, 48));
    return file.path;
  }

  group('FloorplanOverlayCache.prepare', () {
    test('builds the ground overlay with the expected id and bounds',
        () async {
      final path = await writeImage('floor_a.png');
      final request = _request(path);

      final prepared = await FloorplanOverlayCache.prepare(request);

      expect(prepared, isNotNull);
      expect(prepared!.key, request.key);
      expect(prepared.overlay.groundOverlayId.value, 'floorplan_buid-a_2');
      expect(
        prepared.overlay.bounds!.southwest,
        _bounds.southwest,
      );
      expect(
        prepared.overlay.bounds!.northeast,
        _bounds.northeast,
      );
    });

    test('returns null when the image file does not exist', () async {
      final missing = '${tempDir.path}${Platform.pathSeparator}missing.png';
      expect(await FloorplanOverlayCache.prepare(_request(missing)), isNull);
    });

    test('returns null when the image file is empty', () async {
      final empty = File('${tempDir.path}${Platform.pathSeparator}empty.png');
      await empty.writeAsBytes(const <int>[]);

      expect(
        await FloorplanOverlayCache.prepare(_request(empty.path)),
        isNull,
      );
    });

    test('distinct floors produce distinct overlays', () async {
      final pathA = await writeImage('floor_2.png');
      final pathB = await writeImage('floor_3.png');

      final floor2 =
          await FloorplanOverlayCache.prepare(_request(pathA, floorNumber: '2'));
      final floor3 =
          await FloorplanOverlayCache.prepare(_request(pathB, floorNumber: '3'));

      expect(floor2, isNotNull);
      expect(floor3, isNotNull);
      expect(identical(floor2!.overlay, floor3!.overlay), isFalse);
      expect(floor2.overlay.groundOverlayId.value, 'floorplan_buid-a_2');
      expect(floor3.overlay.groundOverlayId.value, 'floorplan_buid-a_3');
    });
  });

  group('FloorplanOverlayCache rebuild stability', () {
    test('identical floorplan state returns the same instance on every build',
        () async {
      final path = await writeImage('stable.png');
      final request = _request(path);
      final prepared = await _prepareOrFail(request);

      final cache = FloorplanOverlayCache(capacity: 2)..put(prepared);

      // Simulate the burst of provider/GPS/heading-driven rebuilds: every
      // lookup must yield the exact same GroundOverlay instance so the maps
      // plugin diffs it as unchanged.
      for (var i = 0; i < 50; i++) {
        expect(identical(cache.get(request.key), prepared), isTrue,
            reason: 'rebuild $i produced a different overlay instance');
      }
    });

    test('heading-style churn between two lookups keeps the entry resident',
        () async {
      final path = await writeImage('churn.png');
      final request = _request(path);
      final prepared = await _prepareOrFail(request);

      final cache = FloorplanOverlayCache(capacity: 2)..put(prepared);

      for (var i = 0; i < 10; i++) {
        cache.get('unrelated|$i'); // unrelated churn must not evict
        expect(identical(cache.get(request.key), prepared), isTrue);
      }
    });
  });

  group('FloorplanOverlayCache floor switching', () {
    test('switching back to a recent floor reuses the prepared overlay',
        () async {
      final pathA = await writeImage('a.png');
      final pathB = await writeImage('b.png');
      final requestA = _request(pathA);
      final requestB = _request(pathB, floorNumber: '3');

      final cache = FloorplanOverlayCache(capacity: 3);

      final preparedA = await _prepareOrFail(requestA);
      cache.put(preparedA);
      final preparedB = await _prepareOrFail(requestB);
      cache.put(preparedB);

      // Floor B selected: A is replaced by B.
      expect(identical(cache.get(requestB.key), preparedB), isTrue);
      // Back to floor A: reused without re-preparation.
      expect(identical(cache.get(requestA.key), preparedA), isTrue);
      // And back to B again.
      expect(identical(cache.get(requestB.key), preparedB), isTrue);
    });

    test('evicts least-recently-used entries beyond its bounded capacity',
        () async {
      final paths = <String>[
        for (var i = 1; i <= 4; i++) await writeImage('f$i.png'),
      ];
      final requests = [
        for (var i = 0; i < paths.length; i++)
          _request(paths[i], floorNumber: '${i + 1}'),
      ];

      final cache = FloorplanOverlayCache(capacity: 2);
      for (final request in requests) {
        cache.put(await _prepareOrFail(request));
      }

      // Only the two most recent floors remain cached.
      expect(cache.contains(requests[0].key), isFalse);
      expect(cache.contains(requests[1].key), isFalse);
      expect(cache.contains(requests[2].key), isTrue);
      expect(cache.contains(requests[3].key), isTrue);

      // An evicted floor is simply prepared again (fresh instance, same id).
      final rePrepared =
          await FloorplanOverlayCache.prepare(requests[0]);
      expect(rePrepared, isNotNull);
      expect(rePrepared!.overlay.groundOverlayId.value,
          'floorplan_buid-a_1');
    });
  });
}
