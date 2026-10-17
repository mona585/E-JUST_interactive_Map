import 'package:flutter/services.dart';
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

/// Google Maps platform fake that ACTUALLY creates the platform view (so
/// `GoogleMap.onMapCreated` fires and the production camera code runs) and
/// RECORDS every camera move.
///
/// Unlike [FakeGoogleMapsPlatform] (which never fires `onMapCreated`, leaving
/// all camera work behind its null-controller guards), this fake lets widget
/// tests observe the real camera command sequence — including later camera
/// updates that may override an earlier one.
class RecordingGoogleMapsPlatform extends MethodChannelGoogleMapsFlutter {
  RecordingGoogleMapsPlatform({this.autoCreateView = true});

  /// When true, the platform view is "created" on the next frame, firing
  /// `GoogleMap.onMapCreated`. Set false to reproduce the never-created case.
  final bool autoCreateView;

  /// Every camera update applied to the map, in order.
  final List<CameraUpdate> cameraUpdates = <CameraUpdate>[];

  /// The camera the widget requested at MAP CREATION
  /// (`GoogleMap.initialCameraPosition`, delivered via
  /// `MapWidgetConfiguration`). This is NOT routed through `animateCamera`, so
  /// it never appears in [cameraUpdates]; it is the first frame's camera.
  CameraPosition? initialCameraPosition;

  /// Whether the platform view has been handed to the widget.
  bool created = false;

  bool _viewCreated = false;

  @override
  Future<void> init(int mapId) async {
    // Register the map-id channel (so later platform calls such as
    // `tileOverlays#update` resolve instead of throwing `UnknownMapIDError`)
    // and swallow every method call: this test double never talks to a real
    // native renderer.
    ensureChannelInitialized(mapId).setMethodCallHandler(
      (MethodCall call) async => null,
    );
  }

  @override
  void dispose({required int mapId}) {}

  @override
  Future<void> updateGroundOverlays(
    GroundOverlayUpdates groundOverlayUpdates, {
    required int mapId,
  }) async {}

  @override
  Widget buildViewWithConfiguration(
    int creationId,
    PlatformViewCreatedCallback onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) {
    // Capture the creation-time camera (idempotent: the first build wins).
    initialCameraPosition ??= widgetConfiguration.initialCameraPosition;
    if (autoCreateView && !_viewCreated) {
      _viewCreated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (created) return;
        created = true;
        onPlatformViewCreated(creationId);
      });
    }
    return const SizedBox.expand();
  }

  @override
  Future<void> animateCamera(
    CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    cameraUpdates.add(cameraUpdate);
  }

  @override
  Future<void> moveCamera(
    CameraUpdate cameraUpdate, {
    required int mapId,
  }) async {
    cameraUpdates.add(cameraUpdate);
  }

  /// The target of the LAST `CameraUpdate.newCameraPosition` applied, or null.
  CameraPosition? get lastCameraPosition {
    for (final update in cameraUpdates.reversed) {
      if (update is CameraUpdateNewCameraPosition) {
        return update.cameraPosition;
      }
    }
    return null;
  }

  /// Installs this fake for the current test and returns it.
  static RecordingGoogleMapsPlatform install({bool autoCreateView = true}) {
    final platform = RecordingGoogleMapsPlatform(
      autoCreateView: autoCreateView,
    );
    GoogleMapsFlutterPlatform.instance = platform;
    return platform;
  }
}
