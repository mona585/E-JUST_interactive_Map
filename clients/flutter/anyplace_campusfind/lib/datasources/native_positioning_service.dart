import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/position_estimate.dart';

/// Abstract interface communicating with the native Kotlin positioning engine.
abstract class NativePositioningService {
  /// Loads and validates a RadioMap plaintext into the native positioning engine.
  ///
  /// [onFailureDetail], when provided, receives a human-readable reason for a
  /// `false` return (e.g. platform channel unavailable vs. rejected format).
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  });

  /// Clears the active RadioMap from the native engine.
  Future<bool> clearRadioMap();

  /// Removes a single resident RadioMap ("buid|floor") from the native engine
  /// without touching any other resident map.
  ///
  /// Returns true when the map was present and removed. Native scanning stops
  /// only when this removes the last resident map; [clearRadioMap] remains the
  /// explicit global reset.
  Future<bool> removeRadioMap(String buid, String floor);

  /// Retrieves metadata about the currently active RadioMap in the native engine.
  Future<Map<String, dynamic>?> getActiveRadioMapInfo();

  /// Real-time stream of native indoor position estimates emitted by Kotlin engine.
  Stream<PositionEstimate> get positionStream;
}

/// MethodChannel and EventChannel implementation of [NativePositioningService].
class MethodChannelNativePositioningService implements NativePositioningService {
  static const String methodChannelName =
      'eg.edu.ejust.anyplace_campusfind/positioning';
  static const String eventChannelName =
      'eg.edu.ejust.anyplace_campusfind/position_stream';

  final MethodChannel _channel;
  final EventChannel _eventChannel;
  Stream<PositionEstimate>? _positionStream;

  MethodChannelNativePositioningService({
    MethodChannel? channel,
    EventChannel? eventChannel,
  })  : _channel = channel ?? const MethodChannel(methodChannelName),
        _eventChannel = eventChannel ?? const EventChannel(eventChannelName);

  @override
  Stream<PositionEstimate> get positionStream {
    _positionStream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => PositionEstimate.fromMap(Map<dynamic, dynamic>.from(event as Map)))
        .handleError((error) {
      debugPrint('[NativePositioningService] Stream error: $error');
    });
    return _positionStream!;
  }

  @override
  Future<bool> loadRadioMap(
    String text,
    String buid,
    String floor, {
    void Function(String detail)? onFailureDetail,
  }) async {
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
      onFailureDetail?.call(
          'Indoor positioning engine is unavailable on this device build.');
      return false;
    } on PlatformException catch (e) {
      debugPrint(
        '[NativePositioningService] PlatformException in loadRadioMap: ${e.message}',
      );
      onFailureDetail?.call('Native engine error: ${e.message}');
      return false;
    } catch (e) {
      debugPrint(
        '[NativePositioningService] Unexpected error in loadRadioMap: $e',
      );
      onFailureDetail?.call('Unexpected native engine error: $e');
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
  Future<bool> removeRadioMap(String buid, String floor) async {
    try {
      final dynamic result =
          await _channel.invokeMethod<bool>('removeRadioMap', {
        'buid': buid,
        'floor': floor,
      });
      debugPrint(
        '[NativePositioningService] removeRadioMap buid=$buid, floor=$floor -> removed=${result == true}',
      );
      return result == true;
    } on MissingPluginException {
      return true;
    } catch (e) {
      debugPrint(
        '[NativePositioningService] Error removing native radiomap: $e',
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
