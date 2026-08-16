import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:anyplace_campusfind/core/config/api_config.dart';
import 'package:anyplace_campusfind/data/datasources/anyplace_api_client.dart';
import 'package:anyplace_campusfind/data/datasources/radiomap_cache.dart';
import 'package:anyplace_campusfind/data/repositories/radiomap_repository.dart';

void main() {
  group('Live Anyplace RadioMap & Wi-Fi Localization Integration Test', () {
    late AnyplaceApiClient apiClient;
    late RadioMapCache cache;
    late AnyplaceRadioMapRepository repository;
    late Directory tempDir;

    // Building B7 (Floor 0)
    const b7Buid = 'building_b8f4e123-d58f-45b7-9942-4492b198c9e4_1786536183663';
    const b7FloorNum = '0';

    setUp(() async {
      final httpClient = HttpClient()
        ..badCertificateCallback =
            ((X509Certificate cert, String host, int port) => true);
      final ioClient = IOClient(httpClient);

      apiClient = AnyplaceApiClient(client: ioClient, baseUrl: ApiConfig.baseUrl);
      tempDir = await Directory.systemTemp.createTemp('live_wifi_pos_test_');
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
        'fetches live RadioMap plaintext for B7 Floor 0 and validates format structure',
        () async {
      final text = await repository.getRadioMap(b7Buid, b7FloorNum);

      expect(text, isNotEmpty);
      expect(text, contains('# NaN'));
      expect(text.lines.length, greaterThan(10));

      final lines = text.split('\n');
      expect(lines[0], startsWith('# NaN'));
      expect(lines[1], startsWith('# X'));

      // Extract BSSID list from line 2
      final line2 = lines[1].replaceAll(',', ' ').trim();
      final tokens = line2.split(RegExp(r'\s+'));
      final macs = tokens.sublist(4);

      expect(macs, isNotEmpty);
      expect(macs.length, greaterThanOrEqualTo(5));

      // Verify BSSID format (6 pairs of hex)
      for (final mac in macs) {
        expect(mac.contains(':'), isTrue);
      }
    });
  });
}

extension on String {
  List<String> get lines => split('\n');
}
