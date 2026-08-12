import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
import '../models/space.dart';
import '../providers/map_view_provider.dart';
import '../providers/providers.dart';

/// Returns to the Map tab with the given building (and optionally floor)
/// selected. Route drawing itself lands in Phase 5; this is the pre-route
/// "focus this building" behavior.
void showBuildingOnMap(
  BuildContext context,
  WidgetRef ref,
  Space space, {
  Floor? floor,
}) {
  final notifier = ref.read(mapViewStateProvider.notifier);
  notifier.selectSpace(space);
  if (floor != null) notifier.selectFloor(floor);
  ref.read(shellTabProvider.notifier).state = 1;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
