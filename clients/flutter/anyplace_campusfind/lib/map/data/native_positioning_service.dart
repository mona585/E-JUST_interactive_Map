import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Abstract interface communicating with the native Kotlin positioning engine.
abstract class NativePositioningService {
  /// Loads and validates a RadioMap plaintext into the native positioning engine.
  Future<bool> loadRadioMap(String text, String buid, String floor);

  /// Clears the active RadioMap from the native engine.
  Future<bool> clearRadioMap();

  /// Retrieves metadata about the currently active RadioMap in the native engine.
  Future<Map<String, dynamic>?> getActiveRadioMapInfo();
}

/// MethodChannel implementation of [NativePositioningService].
class MethodChannelNativePositioningService implements NativePositioningService {
  static const String channelName =
      'eg.edu.ejust.anyplace_campusfind/positioning';

  final MethodChannel _channel;

  MethodChannelNativePositioningService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  @override
  Future<bool> loadRadioMap(String text, String buid, String floor) async {
    try {
      final dynamic result = await _channel.invokeMethod<bool>('loadRadioMap', {
        'text': text,
        'buid': buid,
        'floor': floor,
      });
      final bool success = result == true;
      debugPrint(
        '[NativePositioningService] loadRadioMap for buid=$buid, floor=$floor -> success=$success',
      );
      return success;
    } on MissingPluginException {
      debugPrint(
        '[NativePositioningService] Platform channel not available on this host platform',
      );
      return false;
    } on PlatformException catch (e) {
      debugPrint(
        '[NativePositioningService] PlatformException in loadRadioMap: ${e.message}',
      );
      return false;
    } catch (e) {
      debugPrint(
        '[NativePositioningService] Unexpected error in loadRadioMap: $e',
      );
      return false;
    }
  }

  @override
  Future<bool> clearRadioMap() async {
    try {
      final dynamic result =
          await _channel.invokeMethod<bool>('clearRadioMap');
      debugPrint('[NativePositioningService] clearRadioMap -> $result');
      return result == true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      debugPrint(
        '[NativePositioningService] Error clearing native radiomap: $e',
      );
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getActiveRadioMapInfo() async {
    try {
      final dynamic result =
          await _channel.invokeMethod<dynamic>('getRadioMapInfo');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
      return null;
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[NativePositioningService] Error getting radiomap info: $e');
      return null;
    }
  }
}