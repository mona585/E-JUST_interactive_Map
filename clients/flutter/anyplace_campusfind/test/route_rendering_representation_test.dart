import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:anyplace_campusfind/config/theme.dart';
import 'package:anyplace_campusfind/data/models/navigation_route_model.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';

// ---------------------------------------------------------------------------
// PHASE-R — Route REPRESENTATION → rendering semantics.
//
// These tests pin the projection contract extracted into
// routePolylineSpecs(): the style a route receives is a function of its
// REPRESENTATION (segment types / legacy shape), never of validity status,
// and genuine indoor geometry always renders with the SAME intended indoor
// navigation style regardless of which producer created it.
// ---------------------------------------------------------------------------

const _lng = 29.5828;

LatLng _p(double lat) => LatLng(lat, _lng);

String _patternKey(PatternItem item) => item.toString();

List<String> _patternKeys(List<PatternItem>? patterns) =>
    (patterns ?? const <PatternItem>[]).map(_patternKey).toList();

/// Fully structural snapshot (records compare List fields by identity, so
/// lists are flattened into comparable strings here).
({
  String id,
  int width,
  int colorValue,
  String patterns,
  String points,
}) _snap(RoutePolylineSpec s) => (
      id: s.id,
      width: s.width,
      colorValue: s.color.toARGB32(),
      patterns: _patternKeys(s.patterns).join('|'),
      points: s.points.map((p) => '${p.latitude},${p.longitude}').join(';'),
    );

/// Cross-building composed journey: outdoorWalking + destination-building
/// indoorRouting leg spanning floors 0 → 2 (per-point truthful floors).
NavigationRouteModel _composed() => NavigationRouteModel.fromSegments(
      segments: [
        RouteSegment.outdoor(
          points: [_p(30.900), _p(30.870)],
          buildingId: 'b1',
        ),
        RouteSegment.indoor(
          points: [_p(30.865), _p(30.8645), _p(30.840)],
          buildingId: 'b1',
          floorNumber: '0',
          pointFloors: const ['0', '0', '2'],
          instruction: 'Enter Building One',
        ),
      ],
      status: RouteModelStatus.ready,
    );

void main() {
  group('A. cross-building composed route', () {
    test('outdoor leg renders dotted blue; indoor leg renders the intended '
        'indoor navigation style (never a boundary style)', () {
      final specs =
          routePolylineSpecs(route: _composed(), displayedFloor: null, indoorEmphasis: false);

      expect(specs.length, 2);

      final outdoor = specs[0];
      expect(outdoor.id, 'route_segment_0');
      expect(outdoor.color, const Color(0xFF1E88E5).withValues(alpha: 0.9));
      expect(outdoor.width, 5);
      expect(_patternKeys(outdoor.patterns),
          [_patternKey(PatternItem.dot), _patternKey(PatternItem.gap(10))]);

      final indoor = specs[1];
      expect(indoor.id, 'route_segment_1');
      // THE unified indoor style — identical to the same-building case below.
      expect(indoor.color, AppTheme.primary.withValues(alpha: 0.85));
      expect(indoor.width, 6);
      expect(indoor.patterns ?? const [], isEmpty,
          reason: 'real indoor geometry is solid indoorRouting, not a dashed '
              'boundary marker');
      expect(indoor.points, [_p(30.865), _p(30.8645), _p(30.840)]);
    });

    test('multi-floor indoor leg slices truthfully per displayed floor', () {
      final floor0 = routePolylineSpecs(
          route: _composed(), displayedFloor: '0', indoorEmphasis: true);
      expect(floor0.map((s) => s.id), contains('route_segment_1'));
      expect(
          floor0.firstWhere((s) => s.id == 'route_segment_1').points,
          [_p(30.865), _p(30.8645)]);

      // Floor 2 slice holds a single point → nothing drawable from it; the
      // dimmed outdoor outline remains as orientation context.
      final floor2 = routePolylineSpecs(
          route: _composed(), displayedFloor: '2', indoorEmphasis: true);
      expect(floor2.map((s) => s.id), ['route_segment_0']);
      expect(floor2.single.color, const Color(0xFF1E88E5).withValues(alpha: 0.30));
      expect(floor2.single.width, 4);
    });
  });

  group('B. same-building indoor route representation parity', () {
    test('toSegmentedIndoor wraps a legacy indoor route into the SAME '
        'representation/style as the composed indoor leg', () {
      final legacy = NavigationRouteModel(points: [
        NavigationRoutePoint(
            latitude: 30.860,
            longitude: _lng,
            puid: 'conn_9',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'None'),
        NavigationRoutePoint(
            latitude: 30.840,
            longitude: _lng,
            puid: 'room-1',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'room'),
      ]);

      final wrapped = legacy.toSegmentedIndoor(
        fallbackBuildingId: 'b1',
        instruction: 'Head to Room 104',
      );

      expect(wrapped.hasSegments, isTrue);
      expect(wrapped.segments.single.type, RouteSegmentType.indoorRouting);
      expect(wrapped.segments.single.buildingId, 'b1');
      expect(wrapped.segments.single.instruction, 'Head to Room 104');
      // Geometry carried verbatim.
      expect(wrapped.polylinePoints, legacy.polylinePoints);
      // Per-point floors preserved through the wrap.
      expect(wrapped.points.map((p) => p.floorNumber).toList(),
          legacy.points.map((p) => p.floorNumber).toList());

      // Style parity with the composed cross-building indoor leg.
      final reference = NavigationRouteModel.fromSegments(
        segments: [
          RouteSegment.indoor(
            points: [_p(30.865), _p(30.8645), _p(30.840)],
            buildingId: 'b1',
            floorNumber: '0',
          ),
        ],
        status: RouteModelStatus.ready,
      );
      final wrappedSpec = _snap(routePolylineSpecs(
          route: wrapped, displayedFloor: '0', indoorEmphasis: true).single);
      final referenceSpec = _snap(routePolylineSpecs(
              route: reference, displayedFloor: '0', indoorEmphasis: true)
          .single
          .copyWithPoints(reference.polylinePoints));
      expect(wrappedSpec.id, referenceSpec.id);
      expect(wrappedSpec.colorValue, referenceSpec.colorValue);
      expect(wrappedSpec.width, referenceSpec.width);
      expect(wrappedSpec.patterns, referenceSpec.patterns);
    });

    test('non-applicable inputs are returned unchanged', () {
      final segmented = _composed();
      expect(identical(segmented.toSegmentedIndoor(), segmented), isTrue);

      final hybrid = NavigationRouteModel(points: [
        NavigationRoutePoint.outdoor(latitude: 30.90, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.87, longitude: _lng),
        NavigationRoutePoint(
            latitude: 30.86,
            longitude: _lng,
            puid: 'room-1',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'room'),
      ]);
      expect(identical(hybrid.toSegmentedIndoor(), hybrid), isTrue,
          reason: 'hybrid routes keep their dedicated legacy rendering path');

      final singlePoint = NavigationRouteModel(points: [
        NavigationRoutePoint(
            latitude: 30.86,
            longitude: _lng,
            puid: 'room-1',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'room'),
      ]);
      expect(singlePoint.hasRenderablePath, isFalse);
      expect(identical(singlePoint.toSegmentedIndoor(), singlePoint), isTrue);
    });
  });

  group('D. genuine legacy routes still render', () {
    test('hybrid legacy route keeps route_outdoor + route_indoor styling',
        () {
      final hybrid = NavigationRouteModel(points: [
        NavigationRoutePoint.outdoor(latitude: 30.90, longitude: _lng),
        NavigationRoutePoint.outdoor(latitude: 30.87, longitude: _lng),
        NavigationRoutePoint(
            latitude: 30.86,
            longitude: _lng,
            puid: 'room-1',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'room'),
        NavigationRoutePoint(
            latitude: 30.85,
            longitude: _lng,
            puid: 'room-2',
            buid: 'b1',
            floorNumber: '0',
            poisType: 'room'),
      ]);

      final outdoors = routePolylineSpecs(
          route: hybrid, displayedFloor: null, indoorEmphasis: false);
      expect(outdoors.map((s) => s.id).toSet(), {'route_outdoor', 'route_indoor'});
      expect(
          outdoors.firstWhere((s) => s.id == 'route_outdoor').color,
          const Color(0xFF1E88E5).withValues(alpha: 0.9));
      expect(outdoors.firstWhere((s) => s.id == 'route_indoor').color,
          AppTheme.primary.withValues(alpha: 0.85));

      // Floor filtering parity: a floor with no indoor points hides only the
      // indoor polyline.
      final otherFloor = routePolylineSpecs(
          route: hybrid, displayedFloor: '7', indoorEmphasis: true);
      expect(otherFloor.map((s) => s.id), ['route_outdoor']);
    });
  });

  group('E. RouteModelStatus never changes rendering', () {
    test('ready and partial render identically; warning travels with a wrap',
        () {
      final ready = _composed();
      final partial = NavigationRouteModel.fromSegments(
        segments: ready.segments,
        status: RouteModelStatus.partial,
        partialRouteWarning: 'Route incomplete — could not generate outdoor '
            'walking route.',
      );

      final readySpecs = routePolylineSpecs(
          route: ready, displayedFloor: null, indoorEmphasis: false);
      final partialSpecs = routePolylineSpecs(
          route: partial, displayedFloor: null, indoorEmphasis: false);
      expect(partialSpecs.map(_snap).toList(), readySpecs.map(_snap).toList(),
          reason: 'validity lives in status/warning channels, never color');

      // Status/warning pass through the representation wrap untouched.
      final legacyPartial = NavigationRouteModel(
        points: [
          NavigationRoutePoint(
              latitude: 30.86,
              longitude: _lng,
              puid: 'a',
              buid: 'b1',
              floorNumber: '0',
              poisType: 'None'),
          NavigationRoutePoint(
              latitude: 30.85,
              longitude: _lng,
              puid: 'b',
              buid: 'b1',
              floorNumber: '0',
              poisType: 'None'),
        ],
        status: RouteModelStatus.partial,
        partialRouteWarning: 'missing leg',
      );
      final wrapped = legacyPartial.toSegmentedIndoor();
      expect(wrapped.isPartial, isTrue);
      expect(wrapped.partialRouteWarning, 'missing leg');
    });
  });

  group('PHASE 3 boundary semantics', () {
    test('a TRUE unknown-boundary fallback keeps the entranceTransition '
        '(green dashed, incomplete-flagged) style', () {
      final route = NavigationRouteModel.fromSegments(
        segments: [
          RouteSegment.outdoor(points: [_p(30.90), _p(30.87)], buildingId: 'b1'),
          RouteSegment.fallback(
            type: RouteSegmentType.entranceTransition,
            points: [_p(30.865), _p(30.860)],
            buildingId: 'b1',
            isIncomplete: true,
          ),
        ],
        status: RouteModelStatus.partial,
      );

      final specs =
          routePolylineSpecs(route: route, displayedFloor: null, indoorEmphasis: false);
      final boundary = specs[1];
      expect(boundary.color, const Color(0xFF4CAF50).withValues(alpha: 0.85));
      expect(boundary.width, 5);
      expect(_patternKeys(boundary.patterns),
          [_patternKey(PatternItem.dash(20)), _patternKey(PatternItem.gap(10))]);
    });
  });
}

extension on RoutePolylineSpec {
  /// Test helper: override points so two differently-shaped routes can be
  /// compared style-for-style.
  RoutePolylineSpec copyWithPoints(List<LatLng> pts) => RoutePolylineSpec(
        id: id,
        points: pts,
        width: width,
        color: color,
        patterns: patterns,
      );
}
