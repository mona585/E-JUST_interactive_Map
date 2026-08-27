import 'dart:async';
import 'dart:math' show cos, pi, sin, atan2, log, ln2, max, min, pow;
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/painting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../config/navigation_config.dart';
import '../../config/theme.dart';
import '../../data/datasources/device_heading_service.dart';
import '../../data/models/custom_route_model.dart';
import '../../data/models/space_model.dart';
import '../../data/models/user_location.dart';
import '../../providers/panel_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/service_query.dart';
import '../../state/location_provider.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../../utils/category_deriver.dart';
import '../utils/navigation_display.dart';
import '../utils/floorplan_overlay_cache.dart';
import '../widgets/map_controls.dart';

/// E-JUST campus boundary (ADDITIONAL REQUIREMENT): geographic bounds used
/// ONLY to fit the initial/campus-overview camera viewport. Never drawn.
/// Corners (DMS → decimal):
///   30°51'45.2"N 29°33'41.8"E   30°51'26.4"N 29°33'40.9"E
///   30°51'37.2"N 29°34'03.8"E   30°51'19.7"N 29°33'59.1"E
final LatLngBounds ejustCampusBounds = LatLngBounds(
  southwest: LatLng(30.8554722, 29.5613611),
  northeast: LatLng(30.8625556, 29.5677222),
);

LatLng _ejustCampusCenter() => LatLng(
      (ejustCampusBounds.southwest.latitude +
              ejustCampusBounds.northeast.latitude) /
          2,
      (ejustCampusBounds.southwest.longitude +
              ejustCampusBounds.northeast.longitude) /
          2,
    );

/// Main Map Screen displaying Anyplace buildings, indoor floorplans, indoor POIs, and device GPS on Google Maps.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key, DeviceHeadingService? deviceHeadingService})
      : _deviceHeadingService = deviceHeadingService;

  final DeviceHeadingService? _deviceHeadingService;

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _lastCenteredFloorKey;
  String? _lastFocusedSpaceBuid;
  String? _lastFloorFallbackKey;
  bool _lastFollowMode = false;
  bool _hasInitialCentering = false;
  bool _hasCenteredOnCustomRoutes = false;

  // Prepared floorplan overlays. The bitmap for the active floor is decoded
  // and encoded exactly once (bounded LRU across recently used floors) and
  // the resulting GroundOverlay instance is reused verbatim on every
  // GoogleMap rebuild, so heading/GPS/provider churn never re-uploads the
  // floorplan image to the native renderer.
  static const int _floorplanCacheCapacity = 3;
  final FloorplanOverlayCache _floorplanOverlayCache =
      FloorplanOverlayCache(capacity: _floorplanCacheCapacity);
  PreparedFloorplanOverlay? _activeFloorplanOverlay;
  String? _preparingFloorplanKey;
  int _floorplanGeneration = 0;

  // Marker icon caches (generated once from widget screenshots)
  // CORRECTION PASS: modern pin-style markers — buildings render as rounded
  // SQUARE badges (apartment glyph, primary/amber), POIs as CIRCLE badges
  // with their EntityCategory iconography; selected states invert the fill.
  BitmapDescriptor? _buildingIcon;
  BitmapDescriptor? _buildingSelectedIcon;
  final Map<EntityCategory, BitmapDescriptor> _poiCategoryIcons = {};
  BitmapDescriptor? _poiSelectedIcon;
  bool _markerIconsReady = false;

  // ADDITIONAL REQUIREMENT: initial E-JUST campus viewport.
  // One-shot fit of [ejustCampusBounds] whenever the app ENTERS the campus
  // overview (no building/floor/POI selected, no navigation). Re-armed on
  // exit so returning to campus overview re-fits. While active, the legacy
  // one-time GPS camera animation is suppressed (positioning pipeline
  // itself untouched — My Location still recenters on demand).
  bool _campusFitPending = true;
  bool _isCampusOverviewNow = true;

  // Navigation-style user location icons (blue dot + heading cone).
  // Two variants: directional (cone visible) and dot-only, used when the
  // heading is unavailable so we never imply a false direction.
  BitmapDescriptor? _userDotIcon;
  BitmapDescriptor? _userDirectionalIcon;

  // Device-orientation heading stream (independent of GPS / Wi-Fi position).
  // Drives the marker's direction arrow; updates while standing still.
  late final DeviceHeadingService _deviceHeadingService =
      widget._deviceHeadingService ?? MethodChannelDeviceHeadingService();
  StreamSubscription<double>? _headingSubscription;
  double? _deviceHeading;
  final ValueNotifier<double?> _markerHeadingNotifier = ValueNotifier(null);

  // Cached non-user markers so heading-only updates don't rebuild everything.
  Set<Marker> _baseMarkersCache = <Marker>{};
  String? _baseMarkersSignature;

  // Heading tracking for Google Maps-style camera rotation
  double _currentHeading = 0.0;      // Smoothed heading applied to camera + marker
  LatLng? _lastPositionForBearing;   // Previous position for movement-derived bearing
  DateTime _lastBearingUpdateTime = DateTime.now();
  DateTime _lastMovingTime = DateTime.now();

  // Camera follow state (coalescing: never queue overlapping animations)
  bool _cameraAnimating = false;
  LatLng? _lastAppliedCameraTarget;
  double _lastAppliedCameraBearing = 0.0;
  LatLng? _pendingCameraTarget;
  double? _pendingCameraZoom;
  double? _pendingCameraBearing;
  bool _isProgrammaticMove = false;
  /// BUG-11: stays true after a programmatic animation completes until the
  /// camera settles (onCameraIdle), so inertia cannot exit follow mode.
  bool _programmaticTailPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Register the route-bounds fitter so the dynamic content panel can ask
    // the map layer to frame the active route (Phase 4 bridge), plus the
    // generic focus requester used by service results (Phase 6).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(routeBoundsFitterProvider.notifier).state = _fitRouteBounds;
      ref.read(mapFocusRequesterProvider.notifier).state =
          _mapFocusRequesterImpl;
    });

    // Generate marker icons from widgets
    _generateMarkerIcons();

    // Device-orientation heading stream: rotates the direction arrow
    // independently of position updates (works while standing still).
    _headingSubscription = _deviceHeadingService.headingStream.listen((deg) {
      _deviceHeading = deg;
      debugPrint('[MapScreen] device heading: ${deg.toStringAsFixed(1)}°');
      // Notifier drives only the map subtree rebuild — not the whole screen.
      _markerHeadingNotifier.value = deg;
    });

    // Trigger initial loading of spaces and bind location provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final spaceProvider = context.read<SpaceProvider>();
      final locationProvider = context.read<LocationProvider>();
      spaceProvider.setLocationProvider(locationProvider);

      // Start GPS tracking and auto-center on first valid location.
      // requestAndCenter handles permission request + initial fix + starts tracking.
      locationProvider.addListener(_checkInitialCentering);
      locationProvider.requestAndCenter();

      // Spaces are loaded by MainShell. Listen for when they arrive.
      if (spaceProvider.spaces.isEmpty) {
        void listener() {
          if (spaceProvider.spaces.isNotEmpty) {
            spaceProvider.removeListener(listener);
            if (mounted) setState(() {});
          }
        }
        spaceProvider.addListener(listener);
      }

      // Listen for NavigationController changes to follow user position
      final navController = context.read<NavigationController>();
      navController.addListener(_onNavigationChanged);
    });
  }

  Future<void> _generateMarkerIcons() async {
    // CORRECTION PASS: modern pin badges for buildings & POIs.
    try {
      _buildingIcon = await _pinDescriptor(
          icon: Icons.apartment,
          accent: AppTheme.primary,
          filled: false,
          square: true,
          width: 24);
      _buildingSelectedIcon = await _pinDescriptor(
          icon: Icons.apartment,
          accent: AppTheme.markerSelected,
          filled: true,
          square: true,
          width: 26);
      _poiSelectedIcon = await _pinDescriptor(
          icon: Icons.place,
          accent: AppTheme.primary,
          filled: true,
          width: 22);
      for (final category in EntityCategory.values) {
        _poiCategoryIcons[category] = await _pinDescriptor(
            icon: category.icon,
            accent: category.color,
            filled: false,
            width: 20);
      }
      if (!mounted) return;
      setState(() => _markerIconsReady = true);
    } catch (e) {
      debugPrint('[MapScreen] Failed to render marker icons: $e');
    }
    // User location indicator: navigation-style (blue dot + heading cone).
    // Rendered once as PNG bitmaps; the cone points north at rotation = 0 so
    // the Google Maps `rotation` parameter aligns it with the heading.
    try {
      final results = await Future.wait([
        _renderUserLocationIcon(withHeadingCone: false),
        _renderUserLocationIcon(withHeadingCone: true),
      ]);
      if (!mounted) return;
      setState(() {
        _userDotIcon = BitmapDescriptor.bytes(results[0]);
        _userDirectionalIcon = BitmapDescriptor.bytes(results[1]);
      });
    } catch (e) {
      debugPrint('[MapScreen] Failed to render user location icons: $e');
    }
  }

  /// Renders a modern map-pin badge: rounded body (square for buildings,
  /// circle for POIs) with a small tail, white fill + colored ring, and an
  /// icon glyph. Filled variant inverts to an accent-colored body with a
  /// white glyph (selected states).
  /// Renders a modern map-pin badge at HIGH resolution ([quality]× the
  /// logical size) so it stays sharp on high-density screens; callers pass
  /// `BitmapDescriptor.bytes(bytes, width:, height:)` with the LOGICAL dims
  /// to display it small and crisp.
  ///
  /// Geometry (logical units): body width = [logicalWidth], body height =
  /// width × 1.12, tail = width × 0.30 below, total ≈ width × 1.42.
  static Future<Uint8List> _renderPinIcon({
    required IconData icon,
    required Color accent,
    required bool filled,
    bool square = false,
    double logicalWidth = 24,
    int quality = 4,
  }) async {
    final q = quality.toDouble();
    final W = logicalWidth * q; // body width px
    final tailH = W * 0.30;
    final bodyH = W * 1.12;
    final H = bodyH + tailH; // canvas height px
    final left = 0.0;
    final top = 0.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, W, bodyH),
        Radius.circular(square ? W * 0.20 : W / 2));

    final bodyPaint = ui.Paint()
      ..color = filled ? accent : Colors.white;
    final borderPaint = ui.Paint()
      ..color = accent
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = W * 0.085;

    canvas.drawRRect(rrect, bodyPaint);
    canvas.drawRRect(rrect, borderPaint);

    // Tail triangle.
    final cx = W / 2;
    final path = Path()
      ..moveTo(cx - W * 0.16, top + bodyH - W * 0.06)
      ..lineTo(cx + W * 0.16, top + bodyH - W * 0.06)
      ..lineTo(cx, top + H - 1)
      ..close();
    canvas.drawPath(path, bodyPaint);
    canvas.drawPath(path, borderPaint);
    // Re-fill body over the seam so the join looks clean.
    canvas.drawRRect(rrect, bodyPaint);

    final glyphColor = filled ? Colors.white : accent;
    _paintIconGlyph(canvas, icon, Offset(cx, top + bodyH / 2), glyphColor,
        W * (square ? 0.50 : 0.46));

    final picture = recorder.endRecording();
    final image = await picture.toImage(W.toInt(), H.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  /// Convenience: renders a pin and wraps it as a BitmapDescriptor displayed
  /// at its small LOGICAL size (sharp on any density).
  static Future<BitmapDescriptor> _pinDescriptor({
    required IconData icon,
    required Color accent,
    required bool filled,
    bool square = false,
    double width = 24,
  }) async {
    final bytes = await _renderPinIcon(
      icon: icon,
      accent: accent,
      filled: filled,
      square: square,
      logicalWidth: width,
    );
    return BitmapDescriptor.bytes(
      bytes,
      width: width,
      height: (width * 1.42).round().toDouble(),
    );
  }

  /// Draws a MaterialIcons glyph centered at [center] using [TextPainter]
  /// (the icons font ships with the app via uses-material-design).
  static void _paintIconGlyph(
    Canvas canvas,
    IconData icon,
    Offset center,
    Color color,
    double fontSize,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: fontSize,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  /// Renders the user-location indicator bitmap.
  ///
  /// Design: a solid blue position dot with a white ring, optionally topped by
  /// a translucent heading cone sweeping [headingConeHalfAngleDegrees] to each
  /// side of "north". Everything is centered in the canvas so the marker
  /// anchor (0.5, 0.5) sits exactly on the geographic position; rotating the
  /// flat marker spins the cone around that fixed point.
  static Future<Uint8List> _renderUserLocationIcon({
    required bool withHeadingCone,
  }) async {
    // 170px bitmap renders as a compact navigation dot (the previous 240px
    // canvas displayed as an oversized marker on device).
    const canvasSize = 170.0;
    final dotColor = AppTheme.primary; // App red accent
    final coneColor = dotColor.withValues(alpha: 0.20);
    const headingConeHalfAngleDegrees = 26.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(canvasSize / 2, canvasSize / 2);

    if (withHeadingCone) {
      final sweep = headingConeHalfAngleDegrees * 2 * pi / 180.0;
      final radius = canvasSize * 0.46;
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawArc(
        rect,
        -pi / 2 - sweep / 2,
        sweep,
        true,
        ui.Paint()..color = coneColor,
      );
    }

    // Small modern navigation dot.
    final dotRadius = canvasSize * 0.085;
    final ringRadius = dotRadius + canvasSize * 0.016;

    // White ring around the dot for contrast on any map style.
    canvas.drawCircle(center, ringRadius, ui.Paint()..color = Colors.white);
    canvas.drawCircle(center, dotRadius, ui.Paint()..color = dotColor);

    final picture = recorder.endRecording();
    final image =
        await picture.toImage(canvasSize.toInt(), canvasSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    return byteData!.buffer.asUint8List();
  }

  /// Connector POIs (elevators, stairs, or `pois_type == "None"`) are hidden
  /// from the map but remain in the data/navigation layers for floor-transition
  /// detection and routing.
  static bool _isConnectorPoi(String poisType, String name) {
    final t = poisType.toLowerCase();
    return t == 'none' || t.contains('elevator') ||
        t.contains('stairs') || t.contains('staircase');
  }

  /// One-time listener that centers the map on the user's first valid location.
  void _checkInitialCentering() {
    if (_hasInitialCentering) return;
    // ADDITIONAL REQUIREMENT: while the campus overview owns the camera
    // (E-JUST bounds fit), skip this legacy one-shot GPS camera move. GPS
    // tracking itself is unaffected; My Location still recenters on demand.
    if (_isCampusOverviewNow) {
      debugPrint('[MapScreen] Skipping GPS initial camera — campus overview fit active');
      return;
    }
    final location = context.read<LocationProvider>().currentLocation;
    if (location != null && _mapController != null) {
      debugPrint('[MapScreen] GPS location: ${location.latitude},${location.longitude}');
      _hasInitialCentering = true;
      context.read<LocationProvider>().removeListener(_checkInitialCentering);
      if (!_hasCenteredOnCustomRoutes) {
        debugPrint('[MapScreen] Auto-centering on GPS ${location.latitude},${location.longitude}');
        _animatedMapMove(location.latLng, MapConfig.defaultZoom);
      } else {
        debugPrint('[MapScreen] Skipping GPS centering — already centered on custom routes');
      }
    }
  }

  /// Centers the map on the custom route bounds if no GPS fix has been acquired.
  /// Called after custom routes finish loading.
  void _centerOnCustomRoutesIfNeeded() {
    if (_hasInitialCentering) return;
    if (_hasCenteredOnCustomRoutes) return;
    if (_mapController == null) return;

    final spaceProvider = context.read<SpaceProvider>();
    if (!spaceProvider.customRouteRepository.isLoaded) return;

    final allPoints = <LatLng>[];
    for (final route in spaceProvider.customRouteRepository.routes) {
      allPoints.addAll(route.vertices);
    }
    if (allPoints.isEmpty) return;

    _hasCenteredOnCustomRoutes = true;

    // Compute bounds
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;
    for (final pt in allPoints) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLng) minLng = pt.longitude;
      if (pt.longitude > maxLng) maxLng = pt.longitude;
    }

    final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    debugPrint('[MapScreen] Centering on custom routes: $center');
    _animatedMapMove(center, 17.0);
  }

  @override
  void dispose() {
    // Release the fitter bridge if we still own it.
    try {
      if (ref.read(routeBoundsFitterProvider.notifier).state ==
          _fitRouteBounds) {
        ref.read(routeBoundsFitterProvider.notifier).state = null;
      }
      final focus = ref.read(mapFocusRequesterProvider.notifier);
      if (focus.state != null &&
          identical(focus.state, _mapFocusRequesterImpl)) {
        focus.state = null;
      }
    } catch (_) {}

    // Invalidate any in-flight floorplan preparation before teardown so a
    // late async completion can never call setState on this State.
    _floorplanGeneration++;
    _activeFloorplanOverlay = null;
    _preparingFloorplanKey = null;
    _floorplanOverlayCache.clear();
    _headingSubscription?.cancel();
    _markerHeadingNotifier.dispose();
    _mapController?.dispose();
    _mapController = null;
    WidgetsBinding.instance.removeObserver(this);
    try {
      context.read<LocationProvider>().removeListener(_checkInitialCentering);
    } catch (_) {}
    try {
      final navController = context.read<NavigationController>();
      navController.removeListener(_onNavigationChanged);
    } catch (_) {}
    _currentHeading = 0.0;
    _lastPositionForBearing = null;
    _lastAppliedCameraTarget = null;
    _pendingCameraTarget = null;
    _pendingCameraZoom = null;
    _pendingCameraBearing = null;
    _programmaticTailPending = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nav = context.read<NavigationController>();
    if (!nav.isActive) return;

    if (state == AppLifecycleState.paused) {
      debugPrint('[MapScreen] App paused ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â navigation continues');
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('[MapScreen] App resumed \u2014 still navigating');
      // Re-center camera on user position after resume
      final location = context.read<LocationProvider>().currentLocation;
      if (location != null && nav.followMode) {
        final display = displayLocationFor(
          holdFloorTransition: nav.isTransitioningFloors,
          heldPosition: nav.heldPositionDuringTransition,
          currentLocation: location,
        );
        _followUserPosition(display?.latLng ?? location.latLng, nav.subState,
            bearing: _currentHeading);
      }
    }
  }

  void _onNavigationChanged() {
    if (!mounted) return;
    final nav = context.read<NavigationController>();
    final locationProvider = context.read<LocationProvider>();
    final location = locationProvider.currentLocation;
    final now = DateTime.now();

    if (!nav.isActive) {
      _currentHeading = 0.0;
      _lastPositionForBearing = null;
      _lastFollowMode = false;
      return;
    }

    if (nav.followMode) {
      // ORIGINAL PHASE 7: follow the held position during floor
      // transitions. PHASE 12 / BUG-16b: the heading EMA consumes the SAME
      // displayed (held) position, so the arrow cannot swing while the dot
      // is pinned.
      final display = displayLocationFor(
        holdFloorTransition: nav.isTransitioningFloors,
        heldPosition: nav.heldPositionDuringTransition,
        currentLocation: location,
      );
      if (display != null) {
        final headingSource = location ?? display;
        final heading = _updateHeading(headingSource, now);
        _followUserPosition(display.latLng, nav.subState, bearing: heading);
      }
    }

    // Detect follow mode turning on (e.g. re-center tap)
    if (nav.followMode && !_lastFollowMode) {
      final display = displayLocationFor(
        holdFloorTransition: nav.isTransitioningFloors,
        heldPosition: nav.heldPositionDuringTransition,
        currentLocation: location,
      );
      if (display != null) {
        final heading = location != null
            ? _updateHeading(location, now)
            : _currentHeading;
        _followUserPosition(display.latLng, nav.subState, bearing: heading);
      }
    }
    _lastFollowMode = nav.followMode;
  }

  double _computeBearing(LatLng from, LatLng to) {
    final dLon = (to.longitude - from.longitude) * pi / 180;
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  double _smoothHeading(double raw, double current) {
    double diff = raw - current;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    return (current + NavigationConfig.bearingSmoothingFactor * diff + 360) % 360;
  }

  /// Updates the effective user heading.
  ///
  /// PHASE 12 / BUG-16: the dead compass-from-location branch is removed —
  /// [UserLocation.heading] is always 0 in this pipeline, so it can never
  /// seed a usable direction. Heading derives from (a) the device-orientation
  /// sensor stream handled separately ([_deviceHeading]) and (b) the
  /// movement-bearing EMA below.
  double _updateHeading(UserLocation location, DateTime now) {
    final currentPos = location.latLng;

    if (_lastPositionForBearing == null) {
      _lastPositionForBearing = currentPos;
      _lastMovingTime = now;
      return _currentHeading;
    }

    // Rate-limit heading recomputation.
    final elapsed = now.difference(_lastBearingUpdateTime).inMilliseconds;
    if (elapsed < NavigationConfig.bearingUpdateIntervalMs) {
      return _currentHeading;
    }

    final distance = Geolocator.distanceBetween(
      _lastPositionForBearing!.latitude,
      _lastPositionForBearing!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    final speed = location.speed;
    final isMoving = speed > NavigationConfig.bearingSpeedThreshold &&
        distance > NavigationConfig.bearingMinMovementMeters;

    if (isMoving) {
      final rawBearing =
          _computeBearing(_lastPositionForBearing!, currentPos);
      _currentHeading = _smoothHeading(rawBearing, _currentHeading);
      _lastMovingTime = now;
    } else {
      // Stationary: hold last heading briefly, then ease back to north.
      final stationaryMs = now.difference(_lastMovingTime).inMilliseconds;
      if (stationaryMs > NavigationConfig.bearingHoldDurationMs) {
        _currentHeading = _smoothHeading(0.0, _currentHeading);
      }
    }

    _lastPositionForBearing = currentPos;
    _lastBearingUpdateTime = now;
    return _currentHeading;
  }

  void _followUserPosition(LatLng userPosition, NavigationSubState subState,
      {double bearing = 0.0}) {
    if (!mounted || _mapController == null) return;
    final targetZoom = subState == NavigationSubState.indoor
        ? NavigationConfig.indoorFollowZoom
        : NavigationConfig.outdoorFollowZoom;

    // Lower-third positioning
    final screenHeight = MediaQuery.of(context).size.height;
    final latOffset =
        (screenHeight * (1.0 - NavigationConfig.followLowerThirdFraction)) *
            0.000008;

    _animateFollowCamera(
      LatLng(userPosition.latitude - latOffset, userPosition.longitude),
      targetZoom,
      bearing: bearing,
    );
  }

  /// Follow-mode camera update with change-gating and animation coalescing.
  ///
  /// A new follow animation is only issued when the user moved at least
  /// [NavigationConfig.cameraMoveThresholdMeters] or the heading changed by at
  /// least [NavigationConfig.cameraBearingThresholdDegrees] since the last
  /// applied camera. If an animation is still in flight, the latest target is
  /// coalesced and applied once the current animation settles — never queued
  /// as overlapping animations.
  void _animateFollowCamera(LatLng target, double zoom,
      {required double bearing}) {
    final lastTarget = _lastAppliedCameraTarget;
    if (lastTarget != null) {
      final moved = Geolocator.distanceBetween(
        lastTarget.latitude,
        lastTarget.longitude,
        target.latitude,
        target.longitude,
      );
      var bearingDelta = (bearing - _lastAppliedCameraBearing).abs();
      if (bearingDelta > 180) bearingDelta = 360 - bearingDelta;
      if (moved < NavigationConfig.cameraMoveThresholdMeters &&
          bearingDelta < NavigationConfig.cameraBearingThresholdDegrees) {
        return; // Not a meaningful change — skip.
      }
    }

    if (_cameraAnimating) {
      // Coalesce: remember the newest target; it replaces anything pending.
      _pendingCameraTarget = target;
      _pendingCameraZoom = zoom;
      _pendingCameraBearing = bearing;
      return;
    }

    _cameraAnimating = true;
    _lastAppliedCameraTarget = target;
    _lastAppliedCameraBearing = bearing;

    _isProgrammaticMove = true;
    _mapController!
        .animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: zoom, bearing: bearing),
          ),
        )
        .whenComplete(() {
      if (!mounted) {
        _cameraAnimating = false;
        _pendingCameraTarget = null;
        return;
      }
      _cameraAnimating = false;
      // BUG-11: keep the programmatic guard until the camera settles so
      // scroll inertia cannot be misread as a user pan.
      _programmaticTailPending = true;

      // Apply the most recent coalesced target, if any.
      final pendingTarget = _pendingCameraTarget;
      if (pendingTarget != null) {
        final pendingZoom = _pendingCameraZoom ?? zoom;
        final pendingBearing = _pendingCameraBearing ?? bearing;
        _pendingCameraTarget = null;
        _pendingCameraZoom = null;
        _pendingCameraBearing = null;
        _lastAppliedCameraTarget = null; // Force re-apply regardless of gate.
        _animateFollowCamera(pendingTarget, pendingZoom,
            bearing: pendingBearing);
      }
    });
  }

  void _onBuildingTapped(SpaceModel space) {
    final provider = context.read<SpaceProvider>();
    provider.selectSpace(space);
    _animatedMapMove(space.latLng, 16.5);
  }

  void _animatedMapMove(LatLng destLocation, double destZoom, {double bearing = 0.0}) {
    if (_mapController == null) return;
    _isProgrammaticMove = true;
    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: destLocation,
          zoom: destZoom,
          bearing: bearing,
        ),
      ),
    ).then((_) {
      _isProgrammaticMove = false;
    });
  }

  void _zoomIn() {
    _mapController?.animateCamera(CameraUpdate.zoomIn());
  }

  void _zoomOut() {
    _mapController?.animateCamera(CameraUpdate.zoomOut());
  }

  Future<void> _onMyLocationTapped() async {
    final locationProvider = context.read<LocationProvider>();
    final spaceProvider = context.read<SpaceProvider>();

    final userLoc = await locationProvider.requestAndCenter();

    if (!mounted) return;

    if (userLoc != null) {
      _animatedMapMove(userLoc.latLng, MapConfig.focusedZoom);
    } else {
      // Show feedback if permission denied or GPS disabled
      final message = locationProvider.errorMessage;
      if (message != null && message.isNotEmpty) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.location_off, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(message)),
              ],
            ),
            backgroundColor: AppTheme.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppTheme.cardBorder),
            ),
          ),
        );
      }

      // Fallback: center on selected space or default center
      if (spaceProvider.selectedSpace != null) {
        _animatedMapMove(spaceProvider.selectedSpace!.latLng, 16.5);
      } else if (spaceProvider.spaces.isNotEmpty) {
        _animatedMapMove(spaceProvider.spaces.first.latLng, 15.0);
      } else {
        _animatedMapMove(SpaceProvider.defaultCenter, MapConfig.defaultZoom);
      }
    }
  }

  void _checkFloorplanCameraCenter(SpaceProvider spaceProvider) {
    if (spaceProvider.hasActiveFloorplan &&
        spaceProvider.selectedSpace != null &&
        spaceProvider.selectedFloor != null) {
      final key =
          '${spaceProvider.selectedSpace!.buid}_${spaceProvider.selectedFloor!.floorNumber}';
      if (_lastCenteredFloorKey != key) {
        _lastCenteredFloorKey = key;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _mapController != null) {
            final floorplan = spaceProvider.activeFloorplan;
            // Only center on floorplan if it has valid geographic bounds;
            // otherwise fall back to the selected space location so the
            // building remains visible when the backend does not provide
            // floorplan bounds.
            final center =
                floorplan?.hasValidBounds == true
                    ? floorplan!.center
                    : spaceProvider.selectedSpace!.latLng;
            _animatedMapMove(
              center,
              MapConfig.indoorFloorplanZoom,
            );
          }
        });
      }
    } else if (spaceProvider.selectedFloor == null) {
      _lastCenteredFloorKey = null;
    }
  }

  /// Fits the camera so the ENTIRE calculated route is visible and visually
  /// centered in the AVAILABLE map area (top search bar and bottom dynamic
  /// panel excluded), with padding around the geometry.
  ///
  /// Refinement ("Route Here"): replaces the span-proportional estimate with
  /// a true viewport fit — the zoom is derived from both the width AND height
  /// of the padded bounds against available pixels (no fixed zoom), and the
  /// camera target is biased upward-equivalently (south shift) so the route
  /// centers between the top UI and the bottom panel instead of the screen.
  void _fitRouteBounds(dynamic spaceProviderArg) {
    final spaceProvider = spaceProviderArg as SpaceProvider;
    final route = spaceProvider.activeNavigationRoute;
    if (route == null || route.polylinePoints.isEmpty) return;
    if (_mapController == null) return;

    // ── 1. Padded geographic bounds from the actual polyline ──
    double minLat = route.polylinePoints.first.latitude;
    double maxLat = route.polylinePoints.first.latitude;
    double minLng = route.polylinePoints.first.longitude;
    double maxLng = route.polylinePoints.first.longitude;
    for (final point in route.polylinePoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    final centerLat = (minLat + maxLat) / 2.0;

    const padMeters = NavigationConfig.routeFramePadding;
    final latPad = padMeters / 111320.0;
    final lngPad =
        padMeters / (111320.0 * cos(centerLat * pi / 180));
    final boundsLatSpan = (maxLat + latPad) - (minLat - latPad);
    final boundsLngSpan = (maxLng + lngPad) - (minLng - lngPad);

    // ── 2. Available viewport (exclude top bar + bottom panel chrome) ──
    final size = MediaQuery.of(context).size;
    const horizontalChrome = 32.0; // side breathing room
    const topChromeFraction = 0.14; // search/status bar zone
    const bottomChromeFraction = 0.40; // expanded destination panel zone
    final availW =
        (size.width - horizontalChrome).clamp(120.0, size.width).toDouble();
    final availH = (size.height * (1 - topChromeFraction - bottomChromeFraction))
        .clamp(160.0, size.height)
        .toDouble();

    // ── 3+4. Pure fit computation (unit-tested) ──
    final cam = computeRouteCamera(
      centerLat: centerLat,
      boundsLatSpanDeg: boundsLatSpan,
      boundsLngSpanDeg: boundsLngSpan,
      availW: availW,
      availH: availH,
    );
    final zoom = cam.zoom;
    final shiftedCenter = LatLng(cam.targetLat, (minLng + maxLng) / 2.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animatedMapMove(shiftedCenter, zoom);
    });
  }

  /// ADDITIONAL REQUIREMENT: fit the camera to the E-JUST campus bounds.
  /// Runs once per campus-overview entry; never during selection/navigation
  /// states. Padding keeps the whole area comfortably visible.
  void _fitCampusOverview() {
    if (_mapController == null) return;
    final sw = ejustCampusBounds.southwest;
    final ne = ejustCampusBounds.northeast;
    final centerLat = (sw.latitude + ne.latitude) / 2;
    final centerLng = (sw.longitude + ne.longitude) / 2;

    const padMeters = 40.0;
    final latPad = padMeters / 111320.0;
    final lngPad =
        padMeters / (111320.0 * cos(centerLat * pi / 180));
    final latSpan = (ne.latitude - sw.latitude) + 2 * latPad;
    final lngSpan = (ne.longitude - sw.longitude) + 2 * lngPad;

    final size = MediaQuery.of(context).size;
    const topF = 0.12, bottomF = 0.18; // top bar + collapsed panel zone
    final availW = (size.width - 24).clamp(120.0, size.width).toDouble();
    final availH =
        (size.height * (1 - topF - bottomF)).clamp(160.0, size.height).toDouble();

    final cosLat = cos(centerLat * pi / 180);
    final mpp0 = 156543.03392 * cosLat;
    final zw = log((availW * mpp0) /
            (lngSpan * 111320.0 * cosLat)) /
        ln2;
    final zh = log((availH * mpp0) / (latSpan * 111320.0)) / ln2;
    final zoom = min(zw, zh).clamp(13.0, 17.0).toDouble();

    _animatedMapMove(LatLng(centerLat, centerLng), zoom);
  }

  /// Centralized camera response to building selection.
  ///
  /// With the dynamic content panel (and search flows) selecting spaces
  /// outside the map widget, the map itself now owns the "zoom to selected
  /// building" behavior so every selection path animates identically. Fires
  /// once per buid; deferred until the controller exists.
  /// Stable reference used for the focus bridge ownership check in dispose.
  void _mapFocusRequesterImpl(dynamic target, double zoom) =>
      _animatedMapMove(target as LatLng, zoom);

  void _focusSelectedBuilding(SpaceProvider spaceProvider) {    final selected = spaceProvider.selectedSpace;
    if (selected == null) return;
    if (_lastFocusedSpaceBuid == selected.buid) return;
    if (_mapController == null) return;

    _lastFocusedSpaceBuid = selected.buid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _mapController != null) {
        // CORRECTION PASS (#3): 17.0 keeps the selected building clearly
        // prominent instead of a campus-wide framing.
        _animatedMapMove(selected.latLng, 17.0);
      }
    });
  }

  /// CORRECTION PASS (#4): when a floor is selected but no floorplan image
  /// exists/loaded yet, still move the camera to the building at floor-level
  /// zoom so the selection becomes the visual focus. When the floorplan IS
  /// available, the existing `_checkFloorplanCameraCenter` refines to its
  /// exact bounds — the two are complementary, never fighting.
  void _focusFloorFallback(SpaceProvider spaceProvider) {
    final floor = spaceProvider.selectedFloor;
    final space = spaceProvider.selectedSpace;
    if (floor == null || space == null) {
      _lastFloorFallbackKey = null;
      return;
    }
    final key = '${space.buid}_${floor.floorNumber}';
    if (_lastFloorFallbackKey == key) return;
    if (_mapController == null) return;
    if (spaceProvider.hasActiveFloorplan) return; // existing logic owns it

    _lastFloorFallbackKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _mapController != null &&
          !spaceProvider.hasActiveFloorplan) {
        _animatedMapMove(space.latLng, MapConfig.focusedZoom);
      }
    });
  }

  /// Build the non-user markers (buildings + POIs).
  ///
  /// Cached by a lightweight state signature so heading-stream updates can
  /// rebuild only the user marker without recomputing everything.
  ///
  /// PHASE 7: while a service is active, POI markers show the CURRENT SCOPE
  /// results of that service (category-filtered over the same index the
  /// panel uses) instead of every loaded floor POI; the selected result is
  /// visually distinguished. Deactivating the service restores the normal
  /// set because the filter derives purely from provider state.
  Set<Marker> _buildBaseMarkers(
      SpaceProvider spaceProvider, SpaceModel? selectedSpace) {
    final activeService = ref.watch(activeServiceProvider);

    var visiblePois = spaceProvider.hasPois ? spaceProvider.pois : const [];
    if (activeService != null) {
      visiblePois = queryScopedServices(
        category: activeService,
        campusIndexPois: ref.read(searchServiceProvider).allIndexedPois(),
        buildingBuid: spaceProvider.selectedSpace?.buid,
        floorNumber: spaceProvider.selectedFloor?.floorNumber,
      );
    }

    final signature =
        '${spaceProvider.spaces.length}|${selectedSpace?.buid ?? ''}|'
        '${visiblePois.length}|${activeService?.name ?? ''}|'
        '${spaceProvider.selectedPoi?.puid ?? ''}|'
        '$_markerIconsReady';
    if (_baseMarkersSignature == signature) {
      return _baseMarkersCache;
    }

    final markers = <Marker>{};

    // Building markers
    for (final space in spaceProvider.spaces) {
      final isSelected = selectedSpace?.buid == space.buid;
      markers.add(Marker(
        markerId: MarkerId(space.buid),
        position: space.latLng,
        icon: isSelected
            ? (_buildingSelectedIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueYellow))
            : (_buildingIcon ??
                BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed)),
        anchor: _markerIconsReady ? const Offset(0.5, 0.95) : Offset(0.5, 0.5),
        infoWindow: InfoWindow(
          title: space.name,
          snippet: space.spaceType,
          onTap: () => _onBuildingTapped(space),
        ),
        onTap: () => _onBuildingTapped(space),
      ));
    }

    // Indoor POI markers (connectors hidden — see _isConnectorPoi)
    if (visiblePois.isNotEmpty) {
      final selectedPuid = spaceProvider.selectedPoi?.puid;
      for (final poi in visiblePois) {
        if (_isConnectorPoi(poi.poisType, poi.name)) continue;
        final isSelected = poi.puid == selectedPuid;
        final categoryIcon =
            _poiCategoryIcons[CategoryDeriver.fromPoiType(poi.poisType)];
        markers.add(Marker(
          markerId: MarkerId(poi.puid),
          position: poi.latLng,
          icon: isSelected
              ? (_poiSelectedIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueOrange))
              : (categoryIcon ??
                  BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueViolet)),
          anchor: _markerIconsReady && categoryIcon != null
              ? const Offset(0.5, 0.95)
              : Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: poi.name,
            snippet: poi.poisType,
          ),
          onTap: () {
            spaceProvider.selectPoi(poi);
            _animatedMapMove(poi.latLng, _mapController != null ? 18.0 : MapConfig.defaultZoom);
          },
        ));
      }
    }

    _baseMarkersSignature = signature;
    _baseMarkersCache = markers;
    return markers;
  }

  /// The user-location indicator: small dot + directional cone.
  ///
  /// Heading source priority:
  ///   1. Device-orientation sensor stream ([_deviceHeading]) — updates
  ///      instantly, even while standing still, independent of GPS/Wi-Fi.
  ///   2. Movement-derived heading ([_currentHeading]) as fallback when the
  ///      sensor is unavailable.
  /// When neither has a real direction (> 0.5°), the dot-only icon is used so
  /// a false due-north orientation is never implied.
  Marker? _buildUserMarker(UserLocation? location) {
    if (location == null) return null;

    final deviceHeading = _deviceHeading;
    final double? effectiveHeading = (deviceHeading != null && deviceHeading > 0.5)
        ? deviceHeading
        : (_currentHeading > 0.5 ? _currentHeading : null);

    final fallbackAzure =
        BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);
    return Marker(
      markerId: const MarkerId('user_location'),
      position: location.latLng,
      icon: effectiveHeading == null
          ? (_userDotIcon ?? fallbackAzure)
          : (_userDirectionalIcon ?? fallbackAzure),
      rotation: effectiveHeading ?? 0.0,
      flat: true,
      anchor: const Offset(0.5, 0.5),
    );
  }

  /// Build polylines for navigation routes and custom KMZ routes.
  ///
  /// PHASE 12: rendering is a pure projection of (route store, display
  /// context) — nothing here mutates navigation state. The active-route
  /// projection itself lives in [routePolylineSpecs] so the representation →
  /// style mapping stays testable; this method only layers the campus KMZ
  /// polylines underneath and materializes the specs as Google Polylines.
  Set<Polyline> _buildPolylines(
      SpaceProvider spaceProvider, NavigationController? nav) {
    final polylines = <Polyline>{};

    final route = spaceProvider.activeNavigationRoute;
    final sessionLive = nav?.isActive ?? false;
    final indoorEmphasis =
        nav != null && nav.isActive && nav.subState == NavigationSubState.indoor;
    final displayedFloor = spaceProvider.selectedFloor?.floorNumber;

    // Custom KMZ routes (BUG-9b closure): hidden during a live session by
    // default — see [showCampusRoutes] and the config flag.
    if (showCampusRoutes(
      sessionLive: sessionLive,
      routeHasOutdoorCoverage: route?.hasOutdoorSegment ?? false,
      flagEnabled: NavigationConfig.showCampusRoutesDuringNavigation,
    )) {
      if (spaceProvider.customRouteRepository.isLoaded) {
        final customRoutes = spaceProvider.customRouteRepository.routes
            .where((r) => r.hasPoints)
            .toList(growable: false);
        for (var i = 0; i < customRoutes.length; i++) {
          final campusRoute = customRoutes[i];
          final routePoints = campusRoute.vertices;
          if (routePoints.length >= 2) {
            // Exact color/width come from the source My Maps feature
            // (<LineStyle> resolved at parse time). The KML-spec defaults
            // apply only when the feature defines no style of its own.
            final declaredWidth =
                (campusRoute.lineWidth ?? CustomRoute.kDefaultLineWidth)
                    .round();
            polylines.add(Polyline(
              polylineId: PolylineId('custom_route_$i'),
              points: routePoints,
              width: max(1, declaredWidth),
              color: Color(campusRoute.lineColorArgb ??
                  CustomRoute.kDefaultLineColorArgb),
            ));
          }
        }
      }
    }

    for (final spec in routePolylineSpecs(
      route: route,
      displayedFloor: displayedFloor,
      indoorEmphasis: indoorEmphasis,
    )) {
      polylines.add(Polyline(
        polylineId: PolylineId(spec.id),
        points: spec.points,
        width: spec.width,
        color: spec.color,
        patterns: spec.patterns ?? [],
      ));
    }

    return polylines;
  }

  /// Keeps [_activeFloorplanOverlay] in sync with the selected floorplan.
  ///
  /// Runs on every provider-driven rebuild but performs no I/O and allocates
  /// no bitmaps: it either reuses an already-prepared overlay, keeps waiting
  /// on an in-flight preparation, or kicks off preparation exactly once per
  /// floor identity. A selection that supersedes an in-flight preparation
  /// bumps the generation token so the stale result is discarded.
  void _syncFloorplanOverlay(SpaceProvider spaceProvider) {
    final floorplan = spaceProvider.activeFloorplan;
    final imagePath = spaceProvider.activeFloorplanImagePath;

    String? desiredKey;
    FloorplanOverlayRequest? request;
    if (spaceProvider.hasActiveFloorplan && floorplan != null &&
        imagePath != null) {
      request = FloorplanOverlayRequest(
        buid: floorplan.buid,
        floorNumber: floorplan.floorNumber,
        imagePath: imagePath,
        bounds: floorplan.bounds,
      );
      desiredKey = request.key;
    }

    // A newer selection (or a cleared one) invalidates any in-flight work.
    if (_preparingFloorplanKey != null && _preparingFloorplanKey != desiredKey) {
      _floorplanGeneration++;
      _preparingFloorplanKey = null;
    }

    if (desiredKey == null) {
      _activeFloorplanOverlay = null;
      return;
    }

    final cached = _floorplanOverlayCache.get(desiredKey);
    if (cached != null) {
      _preparingFloorplanKey = null;
      _activeFloorplanOverlay = cached;
      return;
    }
    if (_activeFloorplanOverlay?.key == desiredKey ||
        _preparingFloorplanKey == desiredKey) {
      return; // already prepared / already preparing — nothing to do
    }

    _activeFloorplanOverlay = null;
    final generation = ++_floorplanGeneration;
    _preparingFloorplanKey = desiredKey;
    FloorplanOverlayCache.prepare(request!).then((prepared) {
      if (!mounted || generation != _floorplanGeneration || prepared == null) {
        return; // disposed or superseded by a newer floor selection
      }
      _floorplanOverlayCache.put(prepared);
      if (_preparingFloorplanKey == desiredKey) {
        _preparingFloorplanKey = null;
      }
      setState(() {
        if (_activeFloorplanOverlay?.key != desiredKey) {
          _activeFloorplanOverlay = prepared;
        }
      });
    });
  }

  /// Returns the stable overlay set shown on the map.
  ///
  /// The same [GroundOverlay] instance is returned until the floorplan
  /// actually changes; google_maps_flutter diffs objects by equality, so an
  /// identical instance produces zero platform-channel traffic regardless of
  /// how often this widget rebuilds.
  Set<GroundOverlay> _buildGroundOverlays() {
    final active = _activeFloorplanOverlay;
    if (active == null) {
      return const <GroundOverlay>{};
    }
    return <GroundOverlay>{active.overlay};
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SpaceProvider, LocationProvider>(
      builder: (context, spaceProvider, locationProvider, _) {
        final selectedSpace = spaceProvider.selectedSpace;
        final userLocation = locationProvider.currentLocation;

        _checkFloorplanCameraCenter(spaceProvider);
        _syncFloorplanOverlay(spaceProvider);
        _focusSelectedBuilding(spaceProvider);
        _focusFloorFallback(spaceProvider);

        // ADDITIONAL REQUIREMENT: campus-overview detection + one-shot fit.
        final navActive = context.select<NavigationController, bool>(
          (nav) => nav.isActive,
        );
        final isCampusOverview = selectedSpace == null &&
            spaceProvider.selectedFloor == null &&
            spaceProvider.selectedPoi == null &&
            !navActive;
        if (isCampusOverview != _isCampusOverviewNow) {
          // Entering the overview re-arms the fit; leaving disarms it.
          _campusFitPending = isCampusOverview;
          _isCampusOverviewNow = isCampusOverview;
        }
        if (isCampusOverview &&
            _campusFitPending &&
            _mapController != null) {
          _campusFitPending = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _fitCampusOverview();
          });
        }

        // If no GPS and no building selected, try to center on custom routes
        if (!_hasInitialCentering && !_hasCenteredOnCustomRoutes) {
          _centerOnCustomRoutesIfNeeded();
        }

        // Initial camera position: campus bounds center when in overview,
        // otherwise the existing per-selection target.
        final initialTarget = isCampusOverview
            ? _ejustCampusCenter()
            : (selectedSpace?.latLng ??
                userLocation?.latLng ??
                SpaceProvider.defaultCenter);

        // ORIGINAL PHASE 7: during a floor transition the Phase 5 held
        // position replaces the raw fix so the marker does not jump floors.
        final displayLocation = displayLocationFor(
          holdFloorTransition: context.read<NavigationController>().isTransitioningFloors,
          heldPosition:
              context.read<NavigationController>().heldPositionDuringTransition,
          currentLocation: userLocation,
        );

        return Scaffold(
          body: Stack(
            children: [
              // 1. Google Map.
              //
              // Wrapped in a ValueListenableBuilder on the device-heading
              // stream so the direction arrow updates at sensor rate without
              // rebuilding the rest of the screen. Base markers are cached
              // (_buildBaseMarkers) so heading-only rebuilds stay cheap.
              ValueListenableBuilder<double?>(
                valueListenable: _markerHeadingNotifier,
                builder: (context, heading, _) {
                  return GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: initialTarget,
                      zoom: isCampusOverview ? 14.5 : MapConfig.defaultZoom,
                    ),
                    mapType: MapConfig.mapType,
                    onMapCreated: (controller) {
                      _mapController = controller;
                      // If location was already acquired before map creation, center now
                      _checkInitialCentering();
                      _centerOnCustomRoutesIfNeeded();
                    },
                    onTap: (LatLng latLng) {
                      if (spaceProvider.selectedPoi != null) {
                        spaceProvider.clearSelectedPoi();
                      } else if (selectedSpace != null) {
                        spaceProvider.clearSelection();
                      }
                    },
                    onCameraMove: (CameraPosition position) {
                      final nav = context.read<NavigationController>();
                      if (nav.isActive &&
                          nav.followMode &&
                          !_isProgrammaticMove &&
                          !_programmaticTailPending) {
                        // User is manually panning — exit follow mode
                        nav.exitFollowMode();
                      }
                    },
                    onCameraIdle: () {
                      _programmaticTailPending = false;
                    },
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    compassEnabled: false,
                    mapToolbarEnabled: false,
                    markers: {
                      ..._buildBaseMarkers(spaceProvider, selectedSpace),
                      if (_buildUserMarker(displayLocation)
                          case final Marker userMarker)
                        userMarker,
                    },
                    polylines: _buildPolylines(
                        spaceProvider, context.read<NavigationController>()),
                    groundOverlays: _buildGroundOverlays(),
                  );
                },
              ),

              // 3. Map Action Controls (Search, My Location, Zoom In, Zoom Out, Reload)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: MapControls(
                      onRecenter: () {
                        final nav = context.read<NavigationController>();
                        if (nav.isActive) {
                          nav.resumeFollowMode();
                        }
                        _programmaticTailPending = false;
                        _onMyLocationTapped();
                      },
                      onZoomIn: _zoomIn,
                      onZoomOut: _zoomOut,
                      onReload: () =>
                          spaceProvider.loadSpaces(forceReload: true),
                      isLoading: spaceProvider.isLoading,
                      isTrackingLocation: locationProvider.isTracking,
                    ),
                  ),
                ),
              ),

              // 4. Former detail bottom sheet, navigation status bar /
              //    arrival banner, and error banner were relocated in
              //    Phase 1: the dynamic content panel and nav overlays now
              //    live in MainShell; spaces status/retry moved to MapTopBar.
              ],
            ),
         );
       },
     );
   }
}

/// Pure route-preview camera math (CORRECTION PASS #5/#13, unit-tested).
///
/// Computes the zoom that fits BOTH padded spans inside the available
/// viewport pixels (meters-per-pixel model), clamped to a sensible campus
/// range `[14, 19]`, plus the south-shifted target latitude that visually
/// centers the route between the top UI and the bottom panel.
({double zoom, double targetLat}) computeRouteCamera({
  required double centerLat,
  required double boundsLatSpanDeg,
  required double boundsLngSpanDeg,
  required double availW,
  required double availH,
}) {
  const minZoom = 14.0;
  const maxZoom = 19.0;
  const topChromeFraction = 0.14;
  const bottomChromeFraction = 0.40;

    final cosLat = cos(centerLat * pi / 180);
    final mppAtZoom0 = 156543.03392 * cosLat;
    final widthMeters = boundsLngSpanDeg * 111320.0 * cosLat;
    final heightMeters = boundsLatSpanDeg * 111320.0;
    // Largest zoom where the span still fits its axis:
    //   span_m <= availPx * mppAtZoom0 / 2^z   ⇒   z = log2(availPx*mpp0/span)
    final zoomForWidth = log((availW * mppAtZoom0) / widthMeters) / ln2;
    final zoomForHeight = log((availH * mppAtZoom0) / heightMeters) / ln2;
  final zoom =
      min(zoomForWidth, zoomForHeight).clamp(minZoom, maxZoom).toDouble();

  // Bias: shift target SOUTH so the route centers in the region ABOVE the
  // bottom panel (visible midpoint sits above screen center).
  final bottomChromePx = bottomChromeFraction; // caller-normalized below
  // Caller passes pixel fractions via availH already; bias uses the same
  // fractional model against a nominal 800dp height for determinism.
  const nominalHeight = 800.0;
  final offsetPx =
      (nominalHeight * (bottomChromePx - topChromeFraction)) / 2.0;
  final degPerPixel = 360.0 / (256.0 * pow(2, zoom));
  return (
    zoom: zoom,
    targetLat: centerLat - offsetPx * degPerPixel,
  );
}
