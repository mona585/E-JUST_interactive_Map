import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/config/api_config.dart';

void main() {
  group('ApiConfig', () {
    test('server URL defaults to the intended E-JUST backend', () {
      expect(ApiConfig.serverUrl, equals('https://map.beout.ai'));
    });

    test('OSRM base URL defaults to HTTPS (no cleartext)', () {
      expect(ApiConfig.osrmBaseUrl, startsWith('https://'));
      expect(ApiConfig.osrmBaseUrl, isNot(startsWith('http://')));
      expect(ApiConfig.osrmFootUrl, endsWith('/route/v1/foot'));
    });
  });
}
