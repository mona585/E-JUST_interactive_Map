import 'package:flutter/material.dart';

import '../providers/search_provider.dart';
import '../utils/category_deriver.dart';

IconData _iconFor(EntityCategory category) {
  switch (category) {
    case EntityCategory.professor:
      return Icons.person;
    case EntityCategory.cafeteria:
      return Icons.restaurant;
    case EntityCategory.library:
      return Icons.local_library;
    case EntityCategory.lab:
      return Icons.science;
    case EntityCategory.building:
      return Icons.apartment;
    case EntityCategory.other:
      return Icons.place;
  }
}

/// List tile for a cross-entity search result with a category badge.
class SearchResultCard extends StatelessWidget {
  const SearchResultCard({
    super.key,
    required this.result,
    required this.onTap,
  });

  final SearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Icon(_iconFor(result.category),
              color: scheme.onSecondaryContainer),
        ),
        title: Text(result.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(result.subtitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Badge(
          label: Text(result.category.label),
        ),
        onTap: onTap,
      ),
    );
  }
}
