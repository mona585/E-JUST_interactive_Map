import 'package:flutter/material.dart';

import '../utils/category_deriver.dart';

/// Horizontal scrollable category chips. `null` selection = "All".
class FilterChips extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<EntityCategory> categories;
  final EntityCategory? selected;
  final ValueChanged<EntityCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category.label),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}
