import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/radiomap_cache.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';

void main() {
  group('Live Anyplace RadioMap Integration Test', () {
    late AnyplaceApiClient apiClient;
    late RadioMapCache cache;
    late AnyplaceRadioMapRepository repository;
    late Directory tempDir;

    // Building known to have real RadioMaps in Anyplace public backend
    const testBuid = 'building_d7687dfe-d904-41b1-8378-374dbdec35e0_1504342475011'; // Langvann
    const testFloor = '1';

    setUp(() async {
      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);
      final ioClient = IOClient(httpClient);

      apiClient = AnyplaceApiClient(client: ioClient, baseUrl: ApiConfig.baseUrl);
      tempDir = await Directory.systemTemp.createTemp('live_radiomap_test_');
      cache = RadioMapCache(customBaseDir: tempDir);
      repository = AnyplaceRadioMapRepository(apiClient: apiClient, cache: cache);
    });

    tearDown(() async {
      apiClient.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
        'fetches real RadioMap for Langvann (Floor 1), verifies WGS84 coordinates and AP list',
        () async {
      // 1. Fetch via repository (performs live HTTP download)
      final radiomapText = await repository.getRadioMap(testBuid, testFloor);

      expect(radiomapText, isNotEmpty);
      expect(radiomapText, startsWith('# NaN'));

      final lines = radiomapText.split('\n').where((l) => l.trim().isNotEmpty).toList();
      expect(lines.length, greaterThan(5));

      // 2. Verify header line with MAC addresses
      final headerLine = lines[1];
      expect(headerLine, contains('HEADING'));
      expect(headerLine, contains(':')); // MAC addresses contain colons

      // 3. Verify fingerprint data line (WGS84 lat, lon, heading, rssi...)
      final firstDataLine = lines[2];
      final tokens = firstDataLine.split(',').map((t) => t.trim()).toList();
      expect(tokens.length, greaterThanOrEqualTo(4));

      final lat = double.parse(tokens[0]);
      final lon = double.parse(tokens[1]);
      final heading = double.parse(tokens[2]);

      // Coordinates for Langvann are roughly ~66.33° N, ~14.14° E
      expect(lat, inInclusiveRange(66.0, 67.0));
      expect(lon, inInclusiveRange(14.0, 15.0));
      expect(heading, inInclusiveRange(0.0, 360.0));

      // 4. Verify disk cache persistence
      expect(await cache.hasRadioMap(testBuid, testFloor), isTrue);
      final cachedText = await cache.getRadioMap(testBuid, testFloor);
      expect(cachedText, equals(radiomapText));

      // 5. Subsequent call returns from disk cache
      final secondFetch = await repository.getRadioMap(testBuid, testFloor);
      expect(secondFetch, equals(radiomapText));
    });
  });
}
