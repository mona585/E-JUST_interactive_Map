import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anyplace_campusfind/data/datasources/native_positioning_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MethodChannelNativePositioningService', () {
    const channelName = 'eg.edu.ejust.anyplace_campusfind/positioning';

    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName),
              (MethodCall call) async {
        methodCalls.add(call);
        if (call.method == 'loadRadioMap') {
          final args = call.arguments as Map;
          if (args['text'] == 'VALID_TEXT') return true;
          return false;
        } else if (call.method == 'clearRadioMap') {
          return true;
        } else if (call.method == 'getRadioMapInfo') {
          return {
            'buid': 'buid_1',
            'floor': '0',
            'apCount': 10,
          };
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null);
    });

    test('loadRadioMap invokes MethodChannel with text, buid, floor', () async {
      final service = MethodChannelNativePositioningService();
      final success = await service.loadRadioMap('VALID_TEXT', 'buid_1', '0');

      expect(success, isTrue);
      expect(methodCalls.length, equals(1));
      expect(methodCalls[0].method, 'loadRadioMap');
      expect(methodCalls[0].arguments['buid'], 'buid_1');
    });

    test('clearRadioMap invokes MethodChannel clearRadioMap', () async {
      final service = MethodChannelNativePositioningService();
      final success = await service.clearRadioMap();

      expect(success, isTrue);
      expect(methodCalls.last.method, 'clearRadioMap');
    });

    test('getActiveRadioMapInfo returns map metadata', () async {
      final service = MethodChannelNativePositioningService();
      final info = await service.getActiveRadioMapInfo();

      expect(info, isNotNull);
      expect(info!['buid'], 'buid_1');
      expect(info['apCount'], 10);
    });
  });
}
