import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi_model.dart';
import '../models/space_model.dart';
import '../viewmodels/space_view_model.dart';

/// A selectable trip endpoint for the From/To search bar
/// (UI/UX REDESIGN PHASE 2).
class TripEndpoint {
  const TripEndpoint.myLocation()
    : poi = null,
      space = null,
      isMyLocation = true;

  const TripEndpoint.poi(PoiModel this.poi)
    : space = null,
      isMyLocation = false;

  const TripEndpoint.space(SpaceModel this.space)
    : poi = null,
      isMyLocation = false;

  final PoiModel? poi;
  final SpaceModel? space;
  final bool isMyLocation;

  bool get isPoi => poi != null;
  bool get isSpace => space != null;

  String get label =>
      isMyLocation ? 'My Location' : (poi?.name ?? space?.name ?? '');
}

/// The chosen origin. Defaults to My Location (spec: "From defaults to My
/// Location"). The user may instead pick a whole building as a custom start
/// point; its verified coordinates are then used as the actual outdoor routing
/// origin. Switching back to My Location restores the current-location origin.
final directionOriginProvider = StateProvider<TripEndpoint>(
  (ref) => const TripEndpoint.myLocation(),
);

/// The chosen destination (`To`). Null until the user picks a result.
final directionDestinationProvider = StateProvider<TripEndpoint?>(
  (ref) => null,
);

/// Executes the Directions action using ONLY existing routing features.
///
/// Deliberately takes plain collaborators (not BuildContext) so callers can
/// pop the search overlay before awaiting network work.
Future<void> executeDirections({
  required SpaceViewModel spaceProvider,
  required TripEndpoint origin,
  required TripEndpoint destination,
  void Function(String message)? notice,
}) async {
  // The origin is either My Location (the default) or a whole building the
  // user picked as a custom start point via the From field. When a building is
  // selected its VERIFIED coordinates become the actual routing origin — the
  // chosen origin is never silently replaced by the device GPS position.
  final originOverride = origin.space?.latLng;

  // ── Destination is a whole building ──
  if (destination.space != null) {
    await spaceProvider.requestRouteToBuilding(
      destination.space!,
      originOverride: originOverride,
    );
    return;
  }

  // ── Destination is a POI ──
  final dest = destination.poi!;
  await spaceProvider.navigateToPoi(dest);
  await spaceProvider.requestRouteToSelectedPoi(
    originOverride: originOverride,
  );
}
