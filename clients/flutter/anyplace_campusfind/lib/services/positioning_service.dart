import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../models/position.dart';
import 'api_service.dart';

typedef GpsStreamBuilder = Stream<LatLng> Function();
typedef WifiScanBuilder = Future<List<WiFiAccessPoint>> Function();
typedef PermissionRequest = Future<bool> Function();

/// Wraps GPS (`geolocator`), Wi-Fi scanning (`wifi_scan`) and the backend
/// fingerprint positioning endpoint, with injectable builders so tests can
/// substitute fakes for the platform plugins.
class PositioningService {
  PositioningService({
    required ApiService api,
    GpsStreamBuilder? gpsStreamBuilder,
    WifiScanBuilder? wifiScanBuilder,
    PermissionRequest? permissionRequest,
  })  : _api = api,
        _gpsStreamBuilder = gpsStreamBuilder ?? _defaultGpsStream,
        _wifiScanBuilder = wifiScanBuilder ?? _defaultWifiScan,
        _permissionRequest = permissionRequest ?? _defaultPermissionRequest;

  final ApiService _api;
  final GpsStreamBuilder _gpsStreamBuilder;
  final WifiScanBuilder _wifiScanBuilder;
  final PermissionRequest _permissionRequest;

  /// Requests location permission if needed and reports whether the app may
  /// read the device position.
  Future<bool> requestGpsPermission() => _permissionRequest();

  /// Continuous GPS position updates.
  Stream<LatLng> gpsStream() => _gpsStreamBuilder();

  /// Scans nearby access points and returns them as `{bssid, rss}` maps.
  Future<List<Map<String, dynamic>>> scanAccessPoints() async {
    final results = await _wifiScanBuilder();
    return results
        .map((ap) => {'bssid': ap.bssid, 'rss': ap.level})
        .toList();
  }

  /// Server-side fingerprint positioning. Returns null when the backend has no
  /// usable fix (radiomap data absent) or the request fails.
  Future<PositionEstimate?> estimatePosition({
    required String buid,
    required String floor,
    required List<Map<String, dynamic>> accessPoints,
  }) async {
    try {
      final estimate = await _api.estimatePosition(
        buid: buid,
        floor: floor,
        accessPoints: accessPoints,
      );
      return estimate.hasFix ? estimate : null;
    } on ApiException {
      return null;
    }
  }

  static Stream<LatLng> _defaultGpsStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).map((p) => LatLng(p.latitude, p.longitude));
  }

  static Future<List<WiFiAccessPoint>> _defaultWifiScan() async {
    final can = await WiFiScan.instance.canGetScannedResults(
      askPermissions: true,
    );
    if (can != CanGetScannedResults.yes) return const [];
    await WiFiScan.instance.startScan();
    return WiFiScan.instance.getScannedResults();
  }

  static Future<bool> _defaultPermissionRequest() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}
