import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/floor.dart';
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
