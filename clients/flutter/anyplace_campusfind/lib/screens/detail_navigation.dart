import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../data/models/quick_access_item.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../state/space_provider.dart';

/// Navigates to a search result by switching to the Map tab and selecting the entity.
void openSearchResult(BuildContext context, WidgetRef ref, SearchResult result) async {
  ref.read(shellTabProvider.notifier).state = 1; // Switch to Map tab

  final spaceProvider = provider.Provider.of<SpaceProvider>(context, listen: false);

  if (result.space != null) {
    // Building: select it on the map
    spaceProvider.selectSpace(result.space!);
  } else if (result.floor != null) {
    // Floor: find parent space, select it, then select the floor
    final floor = result.floor!;
    final space = spaceProvider.spaces.firstWhere(
      (s) => s.buid == floor.buid,
      orElse: () => throw StateError('Space ${floor.buid} not found'),
    );
    spaceProvider.selectSpace(space);
    await spaceProvider.loadFloorsForSelectedSpace();
    final matchingFloor = spaceProvider.floors.firstWhere(
      (f) => f.floorNumber == floor.floorNumber,
      orElse: () => floor,
    );
    spaceProvider.selectFloor(matchingFloor);
  } else if (result.poi != null) {
    // POI: full navigation (space → floor → poi)
    await spaceProvider.navigateToPoi(result.poi!);
  }
}

/// Navigates to a Quick Access item by switching to the Map tab and resolving
/// its stored building/POI identifiers, regardless of the current selection.
void openQuickAccessItem(
  BuildContext context,
  WidgetRef ref,
  QuickAccessItem item,
) async {
  ref.read(shellTabProvider.notifier).state = 1; // Switch to Map tab

  final spaceProvider = provider.Provider.of<SpaceProvider>(context, listen: false);
  final searchService = ref.read(searchServiceProvider);
  final ok = await spaceProvider.navigateToQuickAccessItem(
    item,
    searchService: searchService,
  );
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This location could not be opened.')),
    );
  }
}
