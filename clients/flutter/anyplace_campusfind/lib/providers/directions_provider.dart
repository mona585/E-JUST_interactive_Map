import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/poi_model.dart';
import '../data/models/space_model.dart';
import '../state/space_provider.dart';

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
/// Location"); changing it stores a resolved POI or resets back to My
/// Location. Custom origins are functionally supported between two POIs via
/// `SpaceProvider.requestRouteBetweenPois`; any other combination falls back
/// to My Location with a visible notice.
final directionOriginProvider =
    StateProvider<TripEndpoint>((ref) => const TripEndpoint.myLocation());

/// The chosen destination (`To`). Null until the user picks a result.
final directionDestinationProvider = StateProvider<TripEndpoint?>((ref) => null);

/// Executes the Directions action using ONLY existing routing features.
///
/// Deliberately takes plain collaborators (not BuildContext) so callers can
/// pop the search overlay before awaiting network work.
Future<void> executeDirections({
  required SpaceProvider spaceProvider,
  required TripEndpoint origin,
  required TripEndpoint destination,
  void Function(String message)? notice,
}) async {
  // ── Destination is a whole building ──
  if (destination.space != null) {
    if (!origin.isMyLocation) {
      notice?.call(
          'Custom origin needs two specific places — using your location.');
    }
    await spaceProvider.requestRouteToBuilding(destination.space!);
    return;
  }

  // ── Destination is a POI ──
  final dest = destination.poi!;
  await spaceProvider.navigateToPoi(dest);

  if (!origin.isMyLocation && origin.poi != null) {
    final ok = await spaceProvider.requestRouteBetweenPois(origin.poi!, dest);
    if (ok) return;
    notice?.call('Place-to-place route unavailable — using your location.');
  }
  await spaceProvider.requestRouteToSelectedPoi();
}
