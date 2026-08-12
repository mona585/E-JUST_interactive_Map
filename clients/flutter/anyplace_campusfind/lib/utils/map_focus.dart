import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../providers/map_view_provider.dart';
import '../providers/providers.dart';
import '../providers/route_provider.dart';

/// Returns to the Map tab with the given building (and optionally floor)
/// selected, without starting a route.
void showBuildingOnMap(
  BuildContext context,
  WidgetRef ref,
  Space space, {
  Floor? floor,
}) {
  _focusBuilding(context, ref, space, floor: floor);
}

/// Focuses the building on the Map tab and starts a combined route to the
/// given POI (outdoor leg from current position when available).
void navigateToPoiOnMap(
  BuildContext context,
  WidgetRef ref,
  Poi poi,
) {
  _focusBuilding(context, ref, ref.read(cacheServiceProvider).spaceByBuid(poi.buid),
      floor: _floorForPoi(ref, poi));
  ref.read(routeStateProvider.notifier).navigateToPoi(
        poi,
        from: ref.read(userLocationProvider),
      );
}

/// Focuses the building on the Map tab and starts an outdoor route to the
/// building (used by the Building Detail "Navigate to Building" button).
void navigateToBuildingOnMap(
  BuildContext context,
  WidgetRef ref,
  Space space,
) {
  _focusBuilding(context, ref, space);
  ref.read(routeStateProvider.notifier).navigateToBuilding(
        space,
        from: ref.read(userLocationProvider),
      );
}

Floor? _floorForPoi(WidgetRef ref, Poi poi) {
  final cache = ref.read(cacheServiceProvider);
  for (final f in cache.floorsOf(poi.buid)) {
    if (f.floorNumber == poi.floorNumber) return f;
  }
  return null;
}

void _focusBuilding(
  BuildContext context,
  WidgetRef ref,
  Space? space, {
  Floor? floor,
}) {
  if (space == null) return;
  final notifier = ref.read(mapViewStateProvider.notifier);
  notifier.selectSpace(space);
  if (floor != null) notifier.selectFloor(floor);
  ref.read(shellTabProvider.notifier).state = 1;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
