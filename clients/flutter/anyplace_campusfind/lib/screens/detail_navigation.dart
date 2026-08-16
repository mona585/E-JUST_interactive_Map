import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi.dart';
import '../models/space.dart';
import '../providers/map_view_provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../utils/category_deriver.dart';
import 'building_detail_screen.dart';
import 'professor_profile_screen.dart';

/// Routes a search result tap to the map, focusing the correct building
/// (and floor / POI when the result carries one).
void openSearchResult(
  BuildContext context,
  WidgetRef ref,
  SearchResult result,
) {
  final space = result.space;
  final poi = result.poi;
  final floor = result.floor;
  if (space == null && poi == null) return;

  final buid = space?.buid ?? poi!.buid;
  final floorNumber = floor?.floorNumber ?? poi?.floorNumber;

  debugPrint('[search] result tapped: ${result.name} '
      '(buid=$buid floor=$floorNumber poi=${poi?.name})');

  // Switch to the Map tab and ask MapScreen to focus the target.
  ref.read(shellTabProvider.notifier).state = 1;
  ref.read(mapFocusRequestProvider.notifier).state = MapFocusRequest(
    buid: buid,
    floorNumber: floorNumber,
    poi: poi,
  );
}

/// Opens the correct detail screen for a POI (professor → profile, otherwise
/// the building the POI belongs to).
void openPoi(
  BuildContext context,
  WidgetRef ref,
  Poi poi, {
  Space? space,
}) {
  _openPoi(context, ref, poi, space: space ?? ref.read(cacheServiceProvider).spaceByBuid(poi.buid));
}

void _openPoi(
  BuildContext context,
  WidgetRef ref,
  Poi poi, {
  Space? space,
}) {
  final category = CategoryDeriver.derivePoi(poi);
  if (category == EntityCategory.professor) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProfessorProfileScreen(poi: poi, space: space),
      ),
    );
    return;
  }
  if (space == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${poi.name} (${poi.floorNumber})')),
    );
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BuildingDetailScreen(space: space),
    ),
  );
}