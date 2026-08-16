import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
import '../models/poi.dart';
import '../models/space.dart';
import '../utils/category_deriver.dart';

/// Map-view state: selected building, selected floor, active POI category.
class MapViewState {
  const MapViewState({
    this.selectedSpace,
    this.selectedFloor,
    this.poiCategory,
  });

  final Space? selectedSpace;
  final Floor? selectedFloor;
  final EntityCategory? poiCategory;

  MapViewState copyWith({
    Space? selectedSpace,
    bool clearSpace = false,
    Floor? selectedFloor,
    bool clearFloor = false,
    EntityCategory? poiCategory,
    bool clearCategory = false,
  }) {
    return MapViewState(
      selectedSpace: clearSpace ? null : selectedSpace ?? this.selectedSpace,
      selectedFloor: clearFloor ? null : selectedFloor ?? this.selectedFloor,
      poiCategory: clearCategory ? null : poiCategory ?? this.poiCategory,
    );
  }
}

final mapViewStateProvider =
    StateNotifierProvider<MapViewNotifier, MapViewState>(
  (ref) => MapViewNotifier(),
);

/// A request to focus the map on a building (and optionally a floor/POI).
/// Set by the Search feature; consumed (and cleared) by MapScreen.
class MapFocusRequest {
  const MapFocusRequest({required this.buid, this.floorNumber, this.poi});

  final String buid;
  final String? floorNumber;
  final Poi? poi;
}

/// Pending map-focus request from outside the map tab (e.g. search results).
/// Non-null until MapScreen applies it.
final mapFocusRequestProvider = StateProvider<MapFocusRequest?>((ref) => null);

/// Test seam: when overridden, `MapScreen` swaps its `GoogleMap` surface for
/// the provided widget. The Maps SDK plugin is not available in widget tests,
/// so shell-level tests override this with a placeholder instead of stubbing
/// the platform channel.
final mapSurfaceBuilderProvider = Provider<Widget Function()?>(
  (ref) => null,
);

class MapViewNotifier extends StateNotifier<MapViewState> {
  MapViewNotifier() : super(const MapViewState());

  void selectSpace(Space? space) {
    state = state.copyWith(
      selectedSpace: space,
      clearFloor: true,
      clearCategory: true,
    );
  }

  void selectFloor(Floor? floor) {
    state = state.copyWith(selectedFloor: floor);
  }

  void setCategory(EntityCategory? category) {
    state = state.copyWith(
      poiCategory: category,
      clearCategory: false,
    );
  }

  void clearSelection() {
    state = const MapViewState();
  }
}
