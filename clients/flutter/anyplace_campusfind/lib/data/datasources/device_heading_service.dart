import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Abstract source of live device-orientation heading (azimuth degrees,
/// clockwise, [0, 360)).
///
/// Deliberately independent from the location streams (GPS / Wi-Fi): the
/// heading must update while the user is stationary and must not wait for
/// position events.
abstract class DeviceHeadingService {
  /// Continuous heading updates in degrees.
  Stream<double> get headingStream;
}

/// EventChannel implementation backed by the native
/// `TYPE_ROTATION_VECTOR` sensor via `DeviceHeadingBridge` (Android).
class MethodChannelDeviceHeadingService implements DeviceHeadingService {
  static const String _channelName =
      'eg.edu.ejust.anyplace_campusfind/heading_stream';

  final EventChannel _eventChannel;

  Stream<double>? _stream;

  MethodChannelDeviceHeadingService({
    EventChannel? eventChannel,
  }) : _eventChannel = eventChannel ??
            const EventChannel(_channelName);

  @override
  Stream<double> get headingStream {
    _stream ??= _eventChannel
        .receiveBroadcastStream()
        .where((event) => event is Map && event['heading'] != null)
        .map((event) {
      final value = (event as Map)['heading'];
      final deg = value is num
          ? value.toDouble()
          : double.tryParse(value.toString()) ?? 0.0;
      return (deg % 360.0 + 360.0) % 360.0;
    }).handleError((error) {
      debugPrint('[DeviceHeadingService] Stream error: $error');
    });
    return _stream!;
  }
}
