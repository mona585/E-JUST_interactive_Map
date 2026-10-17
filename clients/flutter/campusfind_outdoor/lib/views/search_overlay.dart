import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../config/theme.dart';
import '../models/poi_model.dart';
import '../providers/directions_provider.dart';
import '../providers/providers.dart';
import '../providers/search_provider.dart';
import '../viewmodels/space_view_model.dart';
import '../utils/category_deriver.dart';
import '../viewmodels/search_overlay_view_model.dart';
import '../widgets/search_result_card.dart';

/// Full-screen From/To search overlay (UI/UX REDESIGN PHASE 2).
///
/// Independent from the bottom dynamic content area: opening, typing, or
/// dismissing this route never mutates panel state. Selecting a `To` result
/// closes the overlay first and only then resolves the destination chain via
/// the existing SpaceViewModel features.
class SearchOverlay extends ConsumerStatefulWidget {
  const SearchOverlay({super.key});

  @override
  ConsumerState<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends ConsumerState<SearchOverlay> {
  final _controller = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final SearchOverlayViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = SearchOverlayViewModel(
      searchService: ref.read(searchServiceProvider),
    )..addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    _searchFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onViewModelChanged() {
    if (mounted) setState(() {});
  }

  /// Opens the origin picker AND focuses the shared search field.
  ///
  /// BUG 1: this is the missing piece of the tap path. The origin picker and
  /// the destination search share ONE text field; while picking an origin the
  /// field used to be disabled (`enabled: !pickingFrom`), so the picker opened
  /// with no way to type — "no usable search field". The field is now always
  /// enabled and is focused on entry (after the frame that re-enables it).
  void _beginPickingOrigin() {
    _viewModel.beginPickingOrigin();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _viewModel.pickingFrom) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _clearSearch() {
    _controller.clear();
    _viewModel.clearQuery();
  }

  Future<void> _chooseDestination(SearchResult result) async {
    TripEndpoint? endpoint;
    if (result.poi != null) {
      endpoint = TripEndpoint.poi(result.poi!);
    } else if (result.space != null) {
      endpoint = TripEndpoint.space(result.space!);
    } else if (result.floor != null) {
      // A floor cannot be routed to directly — resolve to its building.
      final space = provider.Provider.of<SpaceViewModel>(
        context,
        listen: false,
      ).spaces.where((s) => s.buid == result.floor!.buid).firstOrNull;
      if (space != null) endpoint = TripEndpoint.space(space);
    }
    if (endpoint == null) return;

    ref.read(directionDestinationProvider.notifier).state = endpoint;

    final spaceProvider = provider.Provider.of<SpaceViewModel>(
      context,
      listen: false,
    );
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Close the overlay FIRST; all remaining work uses captured collaborators.
    navigator.pop();

    await executeDirections(
      spaceProvider: spaceProvider,
      origin: ref.read(directionOriginProvider),
      destination: endpoint,
      notice: (message) => messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message))),
    );
  }

  void _chooseOrigin(TripEndpoint endpoint) {
    ref.read(directionOriginProvider.notifier).state = endpoint;
    _viewModel.endPickingOrigin();
  }

  void _swapEndpoints() {
    final origin = ref.read(directionOriginProvider);
    final destination = ref.read(directionDestinationProvider);
    if (!origin.isPoi || destination == null) return;
    ref.read(directionOriginProvider.notifier).state = destination;
    ref.read(directionDestinationProvider.notifier).state = origin;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    final query = vm.query;
    final origin = ref.watch(directionOriginProvider);

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (vm.pickingFrom) {
              vm.endPickingOrigin();
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          vm.pickingFrom ? 'Choose origin' : 'Where to?',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            tooltip: 'Swap From and To',
            onPressed: _swapEndpoints,
            icon: Icon(
              Icons.swap_vert,
              color:
                  origin.isPoi &&
                      ref.watch(directionDestinationProvider) != null
                  ? AppTheme.primary
                  : AppTheme.textTertiary,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── From row ──
          InkWell(
            onTap: _beginPickingOrigin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: vm.pickingFrom
                    ? AppTheme.primary.withValues(alpha: 0.05)
                    : Colors.transparent,
                border: Border(bottom: BorderSide(color: AppTheme.cardBorder)),
              ),
              child: Row(
                children: [
                  Icon(
                    origin.isMyLocation ? Icons.my_location : Icons.place,
                    size: 20,
                    color: origin.isMyLocation
                        ? AppTheme.textSecondary
                        : AppTheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'From',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                        Text(
                          origin.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: origin.isMyLocation
                                ? AppTheme.textPrimary
                                : AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (vm.pickingFrom)
                    TextButton(
                      onPressed: vm.endPickingOrigin,
                      child: const Text('Cancel'),
                    ),
                ],
              ),
            ),
          ),

          // ── Shared search field ──
          // One field drives BOTH the destination search and the origin
          // picker (the results area switches on `pickingFrom`). It must stay
          // ENABLED in origin mode — a disabled field left the origin picker
          // with no way to search for a building.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: TextField(
              controller: _controller,
              focusNode: _searchFocusNode,
              onChanged: vm.setQuery,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: vm.pickingFrom
                    ? 'Search buildings for origin…'
                    : 'Search buildings…',
                prefixIcon: const Icon(
                  Icons.search,
                  size: 22,
                  color: AppTheme.textTertiary,
                ),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 20,
                          color: AppTheme.textTertiary,
                        ),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
            ),
          ),

          Expanded(child: _buildResults(origin)),
        ],
      ),
    );
  }

  Widget _buildResults(TripEndpoint origin) {
    final vm = _viewModel;
    if (vm.pickingFrom) return _buildOriginPicker();

    final results = vm.destinationResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: AppTheme.textTertiary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              vm.query.isNotEmpty
                  ? 'No results match your search'
                  : vm.searchService.isSyncing
                  ? 'Loading places…'
                  : 'Type a place or pick a suggestion',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (vm.query.isEmpty) {
      // OPTIONAL recommendations — plain typing always works without them.
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          _RecentSection(onPick: _chooseDestination),
          const SizedBox(height: 16),
          Text(
            'Suggestions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          for (final r in results.take(SearchOverlayViewModel.suggestionLimit))
            SearchResultCard(result: r, onTap: () => _chooseDestination(r)),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      itemCount: results.length,
      itemBuilder: (context, i) => SearchResultCard(
        result: results[i],
        onTap: () => _chooseDestination(results[i]),
      ),
    );
  }

  Widget _buildOriginPicker() {
    final vm = _viewModel;
    final results = vm.originResults;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _EndpointTile(
          icon: Icons.my_location,
          title: 'My Location',
          subtitle: 'Use current device location',
          onTap: () => _chooseOrigin(const TripEndpoint.myLocation()),
        ),
        const SizedBox(height: 8),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              vm.query.isEmpty
                  ? vm.searchService.isSyncing
                        ? 'Loading buildings…'
                        : 'Type a building name to use as your start point'
                  : 'No matching building found',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 13,
              ),
            ),
          )
        else
          for (final r in results)
            if (r.space != null)
              _EndpointTile(
                icon: Icons.apartment,
                title: r.name,
                subtitle: r.subtitle,
                onTap: () => _chooseOrigin(TripEndpoint.space(r.space!)),
              ),
      ],
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection({required this.onPick});

  final void Function(SearchResult) onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    ref.watch(cacheVersionProvider);
    final spaceProvider = provider.Provider.of<SpaceViewModel>(context);

    return FutureBuilder<List<String>>(
      future: cache.getRecentWaypoints(),
      builder: (context, snapshot) {
        final puids = snapshot.data ?? const <String>[];
        final recents = puids
            .map(
              (p) =>
                  spaceProvider.pois.where((poi) => poi.puid == p).firstOrNull,
            )
            .whereType<PoiModel>()
            .take(5)
            .toList();
        if (recents.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recents',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            for (final poi in recents)
              SearchResultCard(
                result: SearchResult(
                  name: poi.name,
                  subtitle: poi.poisType,
                  category: CategoryDeriver.fromPoiType(poi.poisType),
                  score: 100,
                  entityType: 'poi',
                  poi: poi,
                ),
                onTap: () {
                  final space = spaceProvider.spaces
                      .where((s) => s.buid == poi.buid)
                      .firstOrNull;
                  if (space != null && !spaceProvider.isLoading) {
                    onPick(
                      SearchResult(
                        name: poi.name,
                        subtitle: poi.poisType,
                        category: CategoryDeriver.fromPoiType(poi.poisType),
                        score: 100,
                        entityType: 'poi',
                        poi: poi,
                        space: space,
                      ),
                    );
                  } else {
                    onPick(
                      SearchResult(
                        name: poi.name,
                        subtitle: poi.poisType,
                        category: CategoryDeriver.fromPoiType(poi.poisType),
                        score: 100,
                        entityType: 'poi',
                        poi: poi,
                      ),
                    );
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

class _EndpointTile extends StatelessWidget {
  const _EndpointTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppTheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppTheme.cardBorder),
        ),
        child: ListTile(
          leading: Icon(icon, size: 20, color: AppTheme.primary),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            size: 18,
            color: AppTheme.textTertiary,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}
