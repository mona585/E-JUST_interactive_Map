import 'package:flutter/material.dart';

import '../config/map_theme.dart';
import '../models/space_model.dart';

/// Modal bottom sheet allowing users to search and jump to any building.
class BuildingSearchSheet extends StatefulWidget {
  final List<SpaceModel> spaces;
  final SpaceModel? selectedSpace;
  final ValueChanged<SpaceModel> onSelect;

  const BuildingSearchSheet({
    super.key,
    required this.spaces,
    this.selectedSpace,
    required this.onSelect,
  });

  @override
  State<BuildingSearchSheet> createState() => _BuildingSearchSheetState();
}

class _BuildingSearchSheetState extends State<BuildingSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<SpaceModel> _filteredSpaces = [];

  @override
  void initState() {
    super.initState();
    _filteredSpaces = widget.spaces;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSpaces = widget.spaces;
      } else {
        _filteredSpaces = widget.spaces.where((space) {
          final nameMatch = space.name.toLowerCase().contains(query);
          final buidMatch = space.buid.toLowerCase().contains(query);
          final bucodeMatch =
              space.bucode != null && space.bucode!.toLowerCase().contains(query);
          final descMatch = space.description != null &&
              space.description!.toLowerCase().contains(query);
          return nameMatch || buidMatch || bucodeMatch || descMatch;
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MapTheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.business, color: MapTheme.primaryLight),
                const SizedBox(width: 10),
                Text(
                  'Anyplace Buildings (${widget.spaces.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: MapTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: MapTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: MapTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by name, bucode, or buid...',
                hintStyle: const TextStyle(color: MapTheme.textSecondary),
                prefixIcon: const Icon(Icons.search, color: MapTheme.textSecondary),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: MapTheme.primaryLight),
                ),
              ),
            ),
          ),

          // Buildings List
          Expanded(
            child: _filteredSpaces.isEmpty
                ? const Center(
                    child: Text(
                      'No matching buildings found',
                      style: TextStyle(color: MapTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _filteredSpaces.length,
                    separatorBuilder: (_, _) => const Divider(
                      color: Color(0x11FFFFFF),
                      height: 1,
                    ),
                    itemBuilder: (context, index) {
                      final space = _filteredSpaces[index];
                      final isSelected = widget.selectedSpace?.buid == space.buid;

                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tileColor: isSelected
                            ? MapTheme.primaryLight.withValues(alpha: 0.15)
                            : null,
                        leading: CircleAvatar(
                          backgroundColor: isSelected
                              ? MapTheme.markerSelected
                              : MapTheme.surfaceLight,
                          child: Icon(
                            space.spaceType.toLowerCase() == 'vessel'
                                ? Icons.directions_boat
                                : Icons.apartment,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          space.name,
                          style: TextStyle(
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected
                                ? MapTheme.markerSelected
                                : MapTheme.textPrimary,
                          ),
                        ),
                        subtitle: Text(
                          '${space.bucode != null ? '[${space.bucode}] ' : ''}${space.latitude.toStringAsFixed(4)}, ${space.longitude.toStringAsFixed(4)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MapTheme.textSecondary,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: MapTheme.textSecondary,
                          size: 18,
                        ),
                        onTap: () {
                          widget.onSelect(space);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
}