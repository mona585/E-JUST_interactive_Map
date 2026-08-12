import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/poi.dart';
import '../models/space.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../utils/category_deriver.dart';
import 'building_detail_screen.dart';
import 'professor_profile_screen.dart';

/// Routes a search result tap to the right detail screen:
/// - professors → Professor Profile
/// - buildings → Building Detail
/// - other POIs (cafe/library/lab) → their Building Detail
void openSearchResult(
  BuildContext context,
  WidgetRef ref,
  SearchResult result,
) {
  final poi = result.poi;
  if (poi != null) {
    _openPoi(context, ref, poi);
    return;
  }
  final space = result.space;
  if (space != null) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BuildingDetailScreen(space: space),
      ),
    );
  }
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
