import 'package:flutter_test/flutter_test.dart';

import 'package:anyplace_campusfind/config/navigation_config.dart';
import 'package:anyplace_campusfind/data/models/route_segment.dart';
import 'package:anyplace_campusfind/ui/utils/navigation_display.dart';

// ---------------------------------------------------------------------------
// PHASE 12 — Rendering & Camera Consistency (BUG-9, BUG-10; pure rules)
// ---------------------------------------------------------------------------

void main() {
  group('segmentVisibility (floor-scoped rendering rules)', () {
    test('outdoor legs visible outdoors, dimmed outline while indoors', () {
      final out = segmentVisibility(
        type: RouteSegmentType.outdoorWalking,
        floorNumber: null,
        displayedFloor: null,
        indoorEmphasis: false,
      );
      expect(out.visible, isTrue);
      expect(out.dimmed, isFalse);

      final indoors = segmentVisibility(
        type: RouteSegmentType.outdoorWalking,
        floorNumber: null,
        displayedFloor: '2',
        indoorEmphasis: true,
      );
      expect(indoors.visible, isTrue,
          reason: 'dimmed orientation outline stays');
      expect(indoors.dimmed, isTrue);
    });

    test('indoor legs render only their own displayed floor', () {
      for (final type in [
        RouteSegmentType.indoorRouting,
        RouteSegmentType.floorTransition,
      ]) {
        final onFloor = segmentVisibility(
          type: type,
          floorNumber: '1',
          displayedFloor: '1',
          indoorEmphasis: true,
        );
        expect(onFloor.visible, isTrue);

        final otherFloor = segmentVisibility(
          type: type,
          floorNumber: '1',
          displayedFloor: '2',
          indoorEmphasis: true,
        );
        expect(otherFloor.visible, isFalse);
      }
    });

    test('entrance/exit boundaries follow the displayed context', () {
      final outdoors = segmentVisibility(
        type: RouteSegmentType.entranceTransition,
        floorNumber: null,
        displayedFloor: null,
        indoorEmphasis: false,
      );
      expect(outdoors.visible, isTrue);

      final withFloorShown = segmentVisibility(
        type: RouteSegmentType.exitTransition,
        floorNumber: '0',
        displayedFloor: '0',
        indoorEmphasis: true,
      );
      expect(withFloorShown.visible, isTrue);
    });
  });

  group('showCampusRoutes (KMZ layer gating, BUG-9b)', () {
    test('visible when idle', () {
      expect(
        showCampusRoutes(sessionLive: false, routeHasOutdoorCoverage: true),
        isTrue,
      );
    });

    test('hidden during a live session with outdoor coverage', () {
      expect(
        showCampusRoutes(sessionLive: true, routeHasOutdoorCoverage: true),
        isFalse,
      );
    });

    test('flag forces visibility during a session', () {
      expect(
        showCampusRoutes(
          sessionLive: true,
          routeHasOutdoorCoverage: true,
          flagEnabled: NavigationConfig.showCampusRoutesDuringNavigation,
        ),
        NavigationConfig.showCampusRoutesDuringNavigation,
      );
    });

    test('kept when the route lacks its own outdoor coverage', () {
      expect(
        showCampusRoutes(sessionLive: true, routeHasOutdoorCoverage: false),
        isTrue,
      );
    });
  });

  group('routeFitZoomForSpan (BUG-10)', () {
    test('span table matches the plan mapping', () {
      expect(routeFitZoomForSpan(3000), 14.0);
      expect(routeFitZoomForSpan(1000), 15.5);
      expect(routeFitZoomForSpan(400), 17.0);
      expect(routeFitZoomForSpan(120), greaterThanOrEqualTo(17.0));
    });

    test('long outdoor routes are no longer pinned to 19', () {
      expect(routeFitZoomForSpan(5000), lessThan(17.0));
    });
  });
}
