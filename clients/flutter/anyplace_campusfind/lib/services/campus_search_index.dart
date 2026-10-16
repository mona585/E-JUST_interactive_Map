import 'package:flutter/foundation.dart';

import '../models/floor_model.dart';
import '../models/space_model.dart';
import '../repositories/poi_repository.dart';
import '../repositories/space_repository.dart';
import 'search_service.dart';

/// Progressive background sync of floors + POIs for every campus building
/// into a [SearchService] index.
///
/// Extracted from [SpaceViewModel]. Uses batched concurrency to avoid
/// flooding the network or blocking the main thread, and honors the
/// user-action pause flag between every batch/building.
class CampusSearchIndex {
  CampusSearchIndex({
    required SpaceRepository repository,
    required PoiRepository poiRepository,
    required List<SpaceModel> Function() spaces,
    required bool Function() isPaused,
    required void Function(String buid, List<FloorModel> floors)
        onFloorsIndexed,
  }) :
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _repository = repository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _poiRepository = poiRepository,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _spaces = spaces,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _isPaused = isPaused,
       // ignore: prefer_initializing_formals (private named formals are not allowed)
       _onFloorsIndexed = onFloorsIndexed;

  final SpaceRepository _repository;
  final PoiRepository _poiRepository;
  final List<SpaceModel> Function() _spaces;
  final bool Function() _isPaused;
  final void Function(String buid, List<FloorModel> floors) _onFloorsIndexed;

  /// Progressive background sync: fetches floors + POIs for all buildings
  /// and indexes them into [searchService]. Uses batched concurrency to avoid
  /// flooding the network or blocking the main thread.
  Future<void> loadAllFloorsAndPois(SearchService searchService) async {
    searchService.markSyncStarted(_spaces().length);

    const int batchSize = 3;
    int processed = 0;

    final spaces = _spaces();
    for (int i = 0; i < spaces.length; i += batchSize) {
      // Respect user-action pause
      while (_isPaused()) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final batch = spaces.sublist(
        i,
        (i + batchSize > spaces.length) ? spaces.length : i + batchSize,
      );

      // Fetch floors for all buildings in this batch concurrently
      final floorResults = await Future.wait(
        batch.map((space) async {
          try {
            final floors = await _repository.getFloorsByBuid(space.buid);
            return _FloorFetchResult(space.buid, floors, null);
          } catch (e) {
            return _FloorFetchResult(space.buid, const [], e);
          }
        }),
        eagerError: false,
      );

      // Process floor results and fetch POIs per building SEQUENTIALLY
      for (final result in floorResults) {
        // Check pause between each building
        while (_isPaused()) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (result.error == null && result.floors.isNotEmpty) {
          searchService.addFloors(result.buid, result.floors);
          _onFloorsIndexed(result.buid, result.floors);

          // Fetch POIs for each floor sequentially (not all at once)
          for (final floor in result.floors) {
            try {
              final pois = await _poiRepository.getPoisByFloor(
                result.buid,
                floor.floorNumber,
              );
              searchService.addPois(result.buid, floor.floorNumber, pois);
            } catch (e) {
              debugPrint(
                '[SpaceViewModel] loadAllFloorsAndPois: POI fetch failed for '
                '${result.buid}/F${floor.floorNumber}: $e',
              );
            }
          }
        }

        processed++;
        searchService.markSyncProgress(processed);
      }

      // Yield to event loop between batches (200ms to avoid server overload)
      await Future.delayed(const Duration(milliseconds: 200));
    }

    searchService.markSyncComplete();
  }
}

class _FloorFetchResult {
  final String buid;
  final List<FloorModel> floors;
  final Object? error;
  _FloorFetchResult(this.buid, this.floors, this.error);
}