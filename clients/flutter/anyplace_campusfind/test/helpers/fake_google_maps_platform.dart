import 'package:flutter/widgets.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

/// Not exported by the platform-interface barrel; identical structural type.
typedef PlatformViewCreatedCallback = void Function(int viewId);

/// Minimal Google Maps platform fake for widget tests.
///
/// The map-first shell mounts [MapScreen] (which embeds a real `GoogleMap`)
/// on every launch, so shell tests need a platform implementation that does
/// not require the native renderer. This fake short-circuits view creation
/// and leaves every other platform call untouched: `onMapCreated` never
/// fires, so all camera work in production code stays behind its existing
/// null-controller guards.
class FakeGoogleMapsPlatform extends MethodChannelGoogleMapsFlutter {
  @override
  Future<void> init(int mapId) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    return const SizedBox.expand();
  }
}

/// Installs [FakeGoogleMapsPlatform] for the current test.
void installFakeGoogleMapsPlatform() {
  GoogleMapsFlutterPlatform.instance = FakeGoogleMapsPlatform();
}
