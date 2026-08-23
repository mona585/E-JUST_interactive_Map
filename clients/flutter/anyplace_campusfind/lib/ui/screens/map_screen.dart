import 'dart:async';
import 'dart:math' show cos, pi, sin, atan2;
import 'dart:typed_data';
import 'package:geolocator/geolocator.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../config/map_config.dart';
import '../../config/navigation_config.dart';
import '../../config/theme.dart';
import '../../data/datasources/device_heading_service.dart';
import '../../data/models/route_segment.dart';
import '../../data/models/space_model.dart';
import '../../data/models/user_location.dart';
import '../../state/location_provider.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../widgets/building_search_sheet.dart';
import '../widgets/arrival_banner.dart';
import '../widgets/map_bottom_sheet.dart';
import '../widgets/map_controls.dart';
import '../widgets/navigation_status_bar.dart';
import '../utils/navigation_display.dart';
import '../utils/floorplan_overlay_cache.dart';

/// Main Map Screen displaying Anyplace buildings, indoor floorplans, indoor POIs, and device GPS on Google Maps.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key, DeviceHeadingService? deviceHeadingService})
      : _deviceHeadingService = deviceHeadingService;

  final DeviceHeadingService? _deviceHeadingService;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  GoogleMapController? _mapController;
  String? _lastCenteredFloorKey;
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
  BitmapDescriptor? _buildingIcon;
  BitmapDescriptor? _buildingSelectedIcon;

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
    // Building markers: default Google Maps marker with custom hue.
    _buildingIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    _buildingSelectedIcon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);

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

  void _openSearchSheet() {
    final provider = context.read<SpaceProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BuildingSearchSheet(
        spaces: provider.spaces,
        selectedSpace: provider.selectedSpace,
        onSelect: (space) {
          provider.selectSpace(space);
          _animatedMapMove(space.latLng, 16.5);
        },
      ),
    );
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

  /// Fits the camera to frame the full active navigation route with padding.
  void _fitRouteBounds(SpaceProvider spaceProvider) {
    final route = spaceProvider.activeNavigationRoute;
    if (route == null || route.polylinePoints.isEmpty) return;

    // Compute bounds from polyline points
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

    // Apply padding to the bounds
    final paddingMeters = NavigationConfig.routeFramePadding;
    final latPad = paddingMeters / 111320.0;
    final centerLat = (minLat + maxLat) / 2.0;
    final lngPad = paddingMeters / (111320.0 * cos(centerLat * pi / 180));

    final paddedBounds = LatLngBounds(
      southwest: LatLng(minLat - latPad, minLng - lngPad),
      northeast: LatLng(maxLat + latPad, maxLng + lngPad),
    );

    final center = LatLng(
      (paddedBounds.southwest.latitude + paddedBounds.northeast.latitude) / 2.0,
      (paddedBounds.southwest.longitude + paddedBounds.northeast.longitude) / 2.0,
    );
    final latSpan = paddedBounds.northeast.latitude - paddedBounds.southwest.latitude;
    final lngSpan = paddedBounds.northeast.longitude - paddedBounds.southwest.longitude;

    final maxSpan = latSpan > lngSpan ? latSpan : lngSpan;
    // PHASE 12 / BUG-10: span-proportional zoom (meters), replacing the
    // pinned 19.0 clamp that framed long outdoor routes absurdly close.
    final maxSpanMeters =
        maxSpan * 111320.0 * cos(centerLat * pi / 180);
    final estimatedZoom =
        routeFitZoomForSpan(maxSpanMeters).clamp(MapConfig.indoorFloorplanZoom, 19.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _animatedMapMove(center, estimatedZoom);
    });
  }

  /// Build the non-user markers (buildings + POIs).
  ///
  /// Cached by a lightweight state signature so heading-stream updates can
  /// rebuild only the user marker without recomputing everything.
  Set<Marker> _buildBaseMarkers(
      SpaceProvider spaceProvider, SpaceModel? selectedSpace) {
    final signature =
        '${spaceProvider.spaces.length}|${selectedSpace?.buid ?? ''}|'
        '${(spaceProvider.hasPois ? spaceProvider.pois.length : 0)}|'
        '${spaceProvider.selectedPoi?.puid ?? ''}';
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
        icon: isSelected ? (_buildingSelectedIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow)) : (_buildingIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)),
        infoWindow: InfoWindow(
          title: space.name,
          snippet: space.spaceType,
          onTap: () => _onBuildingTapped(space),
        ),
        onTap: () => _onBuildingTapped(space),
      ));
    }

    // Indoor POI markers (connectors hidden — see _isConnectorPoi)
    if (spaceProvider.hasPois) {
      for (final poi in spaceProvider.pois) {
        if (_isConnectorPoi(poi.poisType, poi.name)) continue;
        markers.add(Marker(
          markerId: MarkerId(poi.puid),
          position: poi.latLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
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

  /// Build polylines for navigation routes and custom KMZ routes
  ///
  /// PHASE 12: rendering is a pure projection of (route store, display
  /// context) — nothing here mutates navigation state.
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
        final customRoutes =
            spaceProvider.customRouteRepository.getAllRoutePolylinePoints();
        for (var i = 0; i < customRoutes.length; i++) {
          final routePoints = customRoutes[i];
          if (routePoints.length >= 2) {
            // White outline (wider, behind)
            polylines.add(Polyline(
              polylineId: PolylineId('custom_route_${i}_outline'),
              points: routePoints,
              width: 12,
              color: Colors.white,
            ));
            // Gray fill (narrower, on top) — Google Maps road style
            polylines.add(Polyline(
              polylineId: PolylineId('custom_route_$i'),
              points: routePoints,
              width: 6,
              color: const Color(0xFF9E9E9E),
            ));
          }
        }
      }
    }

    if (route == null) return polylines;

    // Segment-based rendering (cross-building navigation), floor-scoped.
    if (route.hasSegments) {
      for (var i = 0; i < route.segments.length; i++) {
        final seg = route.segments[i];
        if (seg.isEmpty) continue;

        final style = _segmentStyles[seg.type];
        if (style == null) continue;

        final vis = segmentVisibility(
          type: seg.type,
          floorNumber: seg.floorNumber,
          displayedFloor: displayedFloor,
          indoorEmphasis: indoorEmphasis,
        );
        if (!vis.visible) continue;

        polylines.add(Polyline(
          polylineId: PolylineId('route_segment_$i'),
          points: seg.points,
          width: vis.dimmed ? (style.width - 1).clamp(1, 12) : style.width,
          color: vis.dimmed ? style.color.withValues(alpha: 0.30) : style.color,
          patterns: style.patterns ?? [],
        ));
      }
      return polylines;
    }

    // Legacy rendering (non-segment routes), now floor-aware for the indoor
    // portion thanks to truthful metadata (Phase 7).
    if (route.hasOutdoorSegment) {
      final vis = segmentVisibility(
        type: RouteSegmentType.outdoorWalking,
        floorNumber: null,
        displayedFloor: displayedFloor,
        indoorEmphasis: indoorEmphasis,
      );
      polylines.add(Polyline(
        polylineId: const PolylineId('route_outdoor'),
        points: route.outdoorPolylinePoints,
        width: vis.dimmed ? 4 : 5,
        color: const Color(0xFF1E88E5)
            .withValues(alpha: vis.dimmed ? 0.32 : 0.9),
        patterns: [PatternItem.dot, PatternItem.gap(10)],
      ));
    }

    if (route.hasIndoorSegment) {
      final indoorPoints = displayedFloor != null
          ? route.polylinePointsForFloor(displayedFloor)
          : route.indoorPolylinePoints;
      if (indoorPoints.length >= 2) {
        polylines.add(Polyline(
          polylineId: const PolylineId('route_indoor'),
          points: indoorPoints,
          width: 6,
          color: AppTheme.primary.withValues(alpha: 0.85),
        ));
      }
    }

    return polylines;
  }

  /// Segment type → polyline style mapping.
  static final Map<RouteSegmentType, _SegmentStyle> _segmentStyles = {
    RouteSegmentType.outdoorWalking: _SegmentStyle(
      color: Color(0xFF1E88E5).withValues(alpha: 0.9),
      width: 5,
      patterns: [PatternItem.dot, PatternItem.gap(10)],
    ),
    RouteSegmentType.indoorRouting: _SegmentStyle(
      color: AppTheme.primary.withValues(alpha: 0.85),
      width: 6,
    ),
    RouteSegmentType.exitTransition: _SegmentStyle(
      color: Color(0xFFFF9800).withValues(alpha: 0.85),
      width: 5,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    ),
    RouteSegmentType.entranceTransition: _SegmentStyle(
      color: Color(0xFF4CAF50).withValues(alpha: 0.85),
      width: 5,
      patterns: [PatternItem.dash(20), PatternItem.gap(10)],
    ),
    RouteSegmentType.floorTransition: _SegmentStyle(
      color: Color(0xFF9C27B0).withValues(alpha: 0.85),
      width: 4,
      patterns: [PatternItem.dot, PatternItem.gap(8)],
    ),
  };

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

        // If no GPS and no building selected, try to center on custom routes
        if (!_hasInitialCentering && !_hasCenteredOnCustomRoutes) {
          _centerOnCustomRoutesIfNeeded();
        }

        // Initial camera position
        final initialTarget = selectedSpace?.latLng ??
            userLocation?.latLng ??
            SpaceProvider.defaultCenter;

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
                      zoom: MapConfig.defaultZoom,
                    ),
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

              // 2. Top Header Bar
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.apartment,
                            color: AppTheme.primary,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Anyplace',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              GestureDetector(
                                onTap: spaceProvider.errorMessage != null &&
                                        spaceProvider.spaces.isEmpty &&
                                        !spaceProvider.isLoading
                                    ? () => spaceProvider.loadSpaces(forceReload: true)
                                    : null,
                                child: Text(
                                  spaceProvider.isLoading
                                      ? 'Loading campus spaces...'
                                      : spaceProvider.errorMessage != null &&
                                              spaceProvider.spaces.isEmpty
                                          ? 'No connection ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â tap to retry'
                                          : '${spaceProvider.spaces.length} spaces mapped',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: spaceProvider.errorMessage != null &&
                                            spaceProvider.spaces.isEmpty
                                        ? const Color(0xFFDC2626)
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (locationProvider.isIndoorWifiActive) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFF0D9488).withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.wifi,
                                    size: 12,
                                    color: Color(0xFF0D9488),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Indoor Wi-Fi (${locationProvider.latestIndoorEstimate?.matchedAps ?? 0} APs)',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0D9488),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (spaceProvider.isLoading) ...[
                            const SizedBox(width: 12),
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
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
                      onSearch: _openSearchSheet,
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

              // 4. Draggable Bottom Sheet for Building/POI details
              if (spaceProvider.selectedSpace != null ||
                  spaceProvider.selectedPoi != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: MapBottomSheet(
                    key: ValueKey(
                      'sheet_${spaceProvider.selectedSpace?.buid}_${spaceProvider.selectedPoi?.puid}',
                    ),
                    onFitRouteBounds: _fitRouteBounds,
                  ),
                ),

              // 5. Navigation Status Bar (during active navigation) +
              //    Arrival Banner (ORIGINAL PHASE 7 exposure).
              if (context.select<NavigationController, bool>(
                (nav) => nav.isActive,
              ))
                Positioned(
                  left: 16,
                  right: 76,
                  bottom: 24,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ArrivalBanner(
                        onDone: () {
                          context.read<NavigationController>().endNavigation();
                          spaceProvider.clearNavigationRoute();
                        },
                      ),
                      const NavigationStatusBar(),
                    ],
                  ),
                ),

              // 6. Error Banner (if any)
              if (spaceProvider.hasError && selectedSpace == null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              spaceProvider.errorMessage!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => spaceProvider.loadSpaces(),
                            child: const Text(
                              'Retry',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Polyline style for a route segment.
class _SegmentStyle {
  final Color color;
  final int width;
  final List<PatternItem>? patterns;

  const _SegmentStyle({
    required this.color,
    required this.width,
    this.patterns,
  });
}