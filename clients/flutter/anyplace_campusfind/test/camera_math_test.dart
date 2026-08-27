import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/ui/screens/map_screen.dart';

void main() {
  group('computeRouteCamera (Route Here fit math)', () {
    const centerLat = 30.859877; // E-JUST centroid

    test('tiny route zooms to the maximum clamp', () {
      final cam = computeRouteCamera(
        centerLat: centerLat,
        boundsLatSpanDeg: 0.0004,
        boundsLngSpanDeg: 0.0004,
        availW: 360,
        availH: 400,
      );
      expect(cam.zoom, 19.0);
      // Bias shifts target SOUTH of the geometric center.
      expect(cam.targetLat, lessThan(centerLat));
    });

    test('campus-scale route (~800 m) lands mid-range', () {
      // ~800 m ≈ 0.0072° latitude span.
      final cam = computeRouteCamera(
        centerLat: centerLat,
        boundsLatSpanDeg: 0.0080,
        boundsLngSpanDeg: 0.0080,
        availW: 340,
        availH: 380,
      );
      expect(cam.zoom, greaterThan(15.5));
      expect(cam.zoom, lessThan(18.5));
    });

    test('very long route clamps to the minimum (never over-zoomed)', () {
      final cam = computeRouteCamera(
        centerLat: centerLat,
        boundsLatSpanDeg: 0.20, // ~22 km
        boundsLngSpanDeg: 0.20,
        availW: 340,
        availH: 380,
      );
      expect(cam.zoom, 14.0);
    });

    test('width-limited vs height-limited routes pick the tighter axis', () {
      final wideFlat = computeRouteCamera(
        centerLat: centerLat,
        boundsLatSpanDeg: 0.002,
        boundsLngSpanDeg: 0.010,
        availW: 340,
        availH: 380,
      );
      final tallNarrow = computeRouteCamera(
        centerLat: centerLat,
        boundsLatSpanDeg: 0.010,
        boundsLngSpanDeg: 0.002,
        availW: 340,
        availH: 380,
      );
      expect(wideFlat.zoom, closeTo(tallNarrow.zoom, 0.35));
    });

    test('bias always points south regardless of zoom', () {
      for (final span in [0.0006, 0.008, 0.15]) {
        final cam = computeRouteCamera(
          centerLat: centerLat,
          boundsLatSpanDeg: span,
          boundsLngSpanDeg: span,
          availW: 340,
          availH: 380,
        );
        expect(cam.targetLat, lessThan(centerLat),
            reason: 'span=$span');
      }
    });
  });
}
