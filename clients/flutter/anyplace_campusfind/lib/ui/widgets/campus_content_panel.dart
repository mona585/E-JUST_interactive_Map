import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;

import '../../config/theme.dart';
import '../../data/models/poi_model.dart';
import '../../data/models/quick_access_item.dart';
import '../../data/models/space_model.dart';
import '../../providers/panel_provider.dart';
import '../../providers/search_provider.dart';
import '../../services/service_query.dart';
import '../../state/navigation_controller.dart';
import '../../state/space_provider.dart';
import '../../utils/category_deriver.dart';
import '../../utils/poi_classification.dart';
import 'gate_detail_card.dart';
import 'poi_detail_card.dart';

/// The single always-present bottom dynamic content area of the map-first
/// shell.
///
/// Context ladder (Phase 4):
///   Campus (Buildings | Services)
///     → Building (floors chips)
///       → Floor (POI cards)
///         → Destination (PoiDetailCard; Directions via EXISTING flows)
///   Gate (map marker) → Gate detail card (same bottom-panel pattern)
///
/// Campus/Building contexts use explicit panel state ([panelContextProvider]);
/// Floor, Gate and Destination derive directly from `SpaceProvider` selection
/// state so loading pipelines remain the single source of truth. Back
/// affordances walk the ladder one step at a time; clearing selection returns
/// to Campus.
class CampusContentPanel extends ConsumerStatefulWidget {
  const CampusContentPanel({super.key});

  @override
  ConsumerState<CampusContentPanel> createState() => _CampusContentPanelState();
}

enum _PanelView { campus, building, floor, destination, gate, service }

class _CampusContentPanelState extends ConsumerState<CampusContentPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<double>? _animation;

  static const _collapsedFraction = 0.14;
  static const _expandedFraction = 0.45;

  double _currentFraction = _collapsedFraction;
  double _dragStartY = 0;
  double _dragStartFraction = 0;

  SpaceProvider? _subscribedSpaceProvider;
  String? _lastAutoContextBuid;

  // Service results (Phase 6).
  final PageController _pageController = PageController(viewportFraction: 0.88);
  int _carouselPage = 0;
  String? _lastAutoSelectedServiceKey;
  bool _userIsSwipingCarousel = false;

  @override
  void initState() {
    super.initState();
    // CORRECTION #2: single source of truth for the visible carousel index —
    // the PageController itself. A listener (not onPageChanged) keeps arrows
    // synchronized with swipes AND programmatic jumps/arrows alike.
    _pageController.addListener(_onCarouselPageTick);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() {
        if (_animation != null) {
          setState(() {
            _currentFraction = _animation!.value;
          });
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    if (!identical(spaceProvider, _subscribedSpaceProvider)) {
      _subscribedSpaceProvider?.removeListener(_onSpaceChanged);
      _subscribedSpaceProvider = spaceProvider;
      spaceProvider.addListener(_onSpaceChanged);
    }
  }

  void _onCarouselPageTick() {
    if (!mounted || !_pageController.hasClients) return;
    final p = _pageController.page?.round() ?? 0;
    if (p != _carouselPage && mounted) {
      setState(() => _carouselPage = p);
    }
  }

  void _goToCarouselPage(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _subscribedSpaceProvider?.removeListener(_onSpaceChanged);
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  /// Keeps [panelContextProvider] in step with selection changes:
  /// cleared selection → Campus; a NEWLY selected building → Building.
  /// Back-driven campus context is never overridden for the SAME buid.
  void _onSpaceChanged() {
    if (!mounted) return;
    final spaceProvider = _subscribedSpaceProvider!;
    final selected = spaceProvider.selectedSpace;
    final contextNow = ref.read(panelContextProvider);

    if (selected == null) {
      _lastAutoContextBuid = null;
      if (contextNow != PanelContext.campus) {
        ref.read(panelContextProvider.notifier).state = PanelContext.campus;
      }
      setState(() {});
      return;
    }

    // While a service is active on the Services tab, selection changes only
    // re-scope the service — they do NOT yank the user into Building context.
    // (debug listener prints removed)
    final serviceActive =
        ref.read(activeServiceProvider) != null &&
            ref.read(campusPanelTabProvider) == CampusPanelTab.services;
    if (!serviceActive &&
        selected.buid != _lastAutoContextBuid &&
        contextNow == PanelContext.campus) {
      _lastAutoContextBuid = selected.buid;
      ref.read(panelContextProvider.notifier).state = PanelContext.building;
    }
    setState(() {});
  }

  // ────────────────────────── snap mechanics ──────────────────────────

  void _snapTo(double target) {
    _animation = Tween<double>(
      begin: _currentFraction,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController
      ..reset()
      ..forward();
  }

  double _snapForPosition(double fraction) {
    final distances = [
      (_collapsedFraction - fraction).abs(),
      (_expandedFraction - fraction).abs(),
    ];
    final minDist = distances.reduce((a, b) => a < b ? a : b);
    final idx = distances.indexOf(minDist);
    return [_collapsedFraction, _expandedFraction][idx];
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _dragStartFraction = _currentFraction;
  }

  void _onDragUpdate(DragUpdateDetails details, double screenHeight) {
    final dy = _dragStartY - details.globalPosition.dy;
    final dfraction = dy / screenHeight;
    final newFraction =
        (_dragStartFraction + dfraction).clamp(_collapsedFraction, _expandedFraction);
    setState(() {
      _currentFraction = newFraction;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    _snapTo(_snapForPosition(_currentFraction));
  }

  void _onHandleTap() {
    if (_currentFraction <= _collapsedFraction + 0.05) {
      _snapTo(_expandedFraction);
    } else {
      _snapTo(_collapsedFraction);
    }
  }

  // ─────────────────────────────── build ───────────────────────────────

  _PanelView _resolveView(SpaceProvider spaceProvider) {
    // A selected campus gate is its own destination-level panel that takes
    // priority over the indoor pipeline (a gate is campus-scoped and can be
    // selected alongside a building/floor); clearing it returns to the
    // underlying context.
    if (spaceProvider.selectedGate != null) return _PanelView.gate;
    if (spaceProvider.selectedPoi != null &&
        spaceProvider.selectedFloor != null) {
      return _PanelView.destination;
    }
    if (spaceProvider.selectedFloor != null) return _PanelView.floor;
    final panelContext = ref.read(panelContextProvider);
    if (panelContext == PanelContext.building &&
        spaceProvider.selectedSpace != null) {
      return _PanelView.building;
    }
    if (panelContext == PanelContext.campus &&
        ref.watch(campusPanelTabProvider) == CampusPanelTab.services &&
        ref.watch(activeServiceProvider) != null) {
      return _PanelView.service;
    }
    return _PanelView.campus;
  }

  @override
  Widget build(BuildContext context) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final tab = ref.watch(campusPanelTabProvider);
    ref.watch(panelContextProvider); // rebuild on explicit context flips
    final view = _resolveView(spaceProvider);
    final screenHeight = MediaQuery.of(context).size.height;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 0),
      height: screenHeight * _currentFraction,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: (d) => _onDragUpdate(d, screenHeight),
            onVerticalDragEnd: _onDragEnd,
            onTap: _onHandleTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.cardBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildTitleBar(view, tab),
                ],
              ),
            ),
          ),

          Container(height: 1, color: AppTheme.cardBorder.withValues(alpha: 0.5)),

          Expanded(child: _buildBody(view, tab)),
        ],
      ),
    );
  }

  Widget _buildBody(_PanelView view, CampusPanelTab tab) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    switch (view) {
      case _PanelView.destination:
        return _buildDestination(spaceProvider);
      case _PanelView.floor:
        return _buildFloorContext(spaceProvider);
      case _PanelView.gate:
        return _buildGateContext(spaceProvider);
      case _PanelView.building:
        return _buildBuildingContext(spaceProvider.selectedSpace!);
      case _PanelView.service:
        return _buildServiceContext(spaceProvider);
      case _PanelView.campus:
        return _buildCampusContext(tab, spaceProvider);
    }
  }

  // ─────────────────────────── title bar ───────────────────────────

  VoidCallback? _backActionFor(_PanelView view) {
    final spaceProvider =
        provider.Provider.of<SpaceProvider>(context, listen: false);
    switch (view) {
      case _PanelView.destination:
        return () {
          final nav = provider.Provider.of<NavigationController>(context,
              listen: false);
          // BUG-8 closure semantics preserved: ending a preview tears down
          // through terminateNavigation which clears the single store.
          if (nav.isPreview) nav.terminateNavigation();
          spaceProvider.clearSelectedPoi();
        };
      case _PanelView.gate:
        return () => spaceProvider.clearSelectedGate();
      case _PanelView.floor:
        return () => spaceProvider.clearFloorSelection();
      case _PanelView.service:
        return () =>
            ref.read(activeServiceProvider.notifier).state = null;
      case _PanelView.building:
        return () =>
            ref.read(panelContextProvider.notifier).state = PanelContext.campus;
      case _PanelView.campus:
        return null;
    }
  }

  Widget _buildTitleBar(_PanelView view, CampusPanelTab tab) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final back = _backActionFor(view);
    // NAVIGATION REFINEMENT: while navigation is active and the user has
    // re-expanded the panel, offer a one-tap way back to the compact bar.
    final navActive =
        provider.Provider.of<NavigationController>(context).isActive;

    String title;
    String subtitle;
    IconData icon;

    switch (view) {
      case _PanelView.destination:
        final poi = spaceProvider.selectedPoi!;
        title = poi.name;
        subtitle = poi.poisType;
        icon = Icons.place;
      case _PanelView.gate:
        final gate = spaceProvider.selectedGate!;
        title = gate.name;
        subtitle = 'Campus Gate';
        icon = Icons.meeting_room_outlined;
      case _PanelView.service:
        final service = ref.watch(activeServiceProvider)!;
        title = service.label;
        subtitle = _currentScope(sp: spaceProvider).label;
        icon = service.icon;
      case _PanelView.floor:
        final floor = spaceProvider.selectedFloor!;
        title = spaceProvider.selectedSpace?.name ?? 'Building';
        subtitle = 'Floor ${floor.displayName}';
        icon = Icons.layers;
      case _PanelView.building:
        final b = spaceProvider.selectedSpace!;
        title = b.name;
        subtitle = b.bucode?.isNotEmpty == true
            ? '${b.bucode} · ${b.spaceType}'
            : b.spaceType;
        icon = Icons.location_city;
      case _PanelView.campus:
        title = tab == CampusPanelTab.services ? 'Services' : 'Buildings';
        subtitle = _campusSubtitle();
        icon = tab == CampusPanelTab.services
            ? Icons.grid_view
            : Icons.location_city;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (back != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back,
                  size: 20, color: AppTheme.textSecondary),
              onPressed: back,
            )
          else
            Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.textPrimary)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          if (navActive)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Back to navigation bar',
              icon: const Icon(Icons.picture_in_picture_alt,
                  size: 20, color: Color(0xFF059669)),
              onPressed: () =>
                  ref.read(navPanelOpenProvider.notifier).state = false,
            ),
          Icon(
            _currentFraction >= _expandedFraction
                ? Icons.keyboard_arrow_down
                : Icons.keyboard_arrow_up,
            size: 22,
            color: AppTheme.textTertiary,
          ),
        ],
      ),
    );
  }

  String _campusSubtitle() {
    final spaceProvider = _subscribedSpaceProvider;
    if (spaceProvider == null) return '';
    if (spaceProvider.isLoading) return 'Loading campus…';
    return '${spaceProvider.spaces.length} buildings mapped';
  }

  /// Current service scope triple: label + building/floor identifiers.
  ({String label, String? buid, String? floorNumber}) _currentScope(
      {required SpaceProvider sp}) {
    final building = sp.selectedSpace;
    final floor = sp.selectedFloor;
    return (
      label: serviceScopeLabel(
        buildingName: building?.name,
        floorDisplayName: floor?.displayName,
      ),
      buid: building?.buid,
      floorNumber: floor?.floorNumber,
    );
  }

  // ─────────────────────── CAMPUS CONTEXT ───────────────────────

  Widget _buildCampusContext(CampusPanelTab tab, SpaceProvider spaceProvider) {
    final List<Widget> content;
    if (spaceProvider.isLoading) {
      content = const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (tab == CampusPanelTab.services) {
      content = [_buildServiceTypeGrid(spaceProvider)];
    } else {
      content = [
        // NAVIGATION/CAMPUS REFINEMENT: buildings render as a responsive
        // card grid (2 columns on phones) directly beneath the switch; the
        // former duplicate count text under the section title was removed.
        _buildBuildingsGrid(spaceProvider),
        if (spaceProvider.spaces.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              spaceProvider.hasError
                  ? 'Could not load buildings — retry from the top bar.'
                  : 'No buildings available yet.',
              style:
                  const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
            ),
          ),
        // CORRECTION PASS: Quick Access / Recent Waypoints sections removed
        // from the redesigned UI entirely. Their destinations remain
        // reachable through Services → "Places" (real server entities).
        const SizedBox(height: 16),
      ];
    }

    return ListView(
      padding: EdgeInsets.zero,
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: _SegmentedSwitch(),
        ),
        ...content,
      ],
    );
  }

  // ─────────────────────── BUILDING CONTEXT ───────────────────────

  // ─────────────────────── BUILDINGS CARD GRID ───────────────────────

  /// Responsive card grid (CORRECTION #1: **4 cards per row** on phone
  /// widths; 5 on tablets/wide). Compact map-directory style — no clipping,
  /// no horizontal scroll. Presentation only; tap behavior unchanged.
  Widget _buildBuildingsGrid(SpaceProvider spaceProvider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // USER DECISION: 3 building cards per row (was 4).
        final columns = w >= 620 ? 5 : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.74,
          ),
          itemCount: spaceProvider.spaces.length,
          itemBuilder: (context, i) {
            final space = spaceProvider.spaces[i];
            return _BuildingCard(
              space: space,
              isSelected:
                  spaceProvider.selectedSpace?.buid == space.buid,
              onTap: () {
                // Same semantics as before: selectSpace() no-ops when the
                // SAME buid is already selected; re-entering that building's
                // context is still expected UX.
                if (spaceProvider.selectedSpace?.buid == space.buid) {
                  _lastAutoContextBuid = space.buid;
                  ref.read(panelContextProvider.notifier).state =
                      PanelContext.building;
                  setState(() {});
                  return;
                }
                spaceProvider.selectSpace(space);
              },
            );
          },
        );
      },
    );
  }


  /// Service-type grid derived from the progressive campus index. Counts are
  /// computed for the CURRENT scope; zero-result types render disabled.
  Widget _buildServiceTypeGrid(SpaceProvider spaceProvider) {
    final searchService = ref.read(searchServiceProvider);
    final categories = searchService.discoverCategoriesFromIndex();
    final indexPois = searchService.allIndexedPois();
    final scope = _currentScope(sp: spaceProvider);

    // CORRECTION PASS (#2): "Places" — the former Quick Access destinations
    // (Library, Blue Hall, Food court, Bank, B7, Admin Building) are real
    // E-JUST BUILDINGS from the server; expose them as a service type whose
    // results are those buildings. No fake entities.
    final hasPlaces = spaceProvider.spaces.isNotEmpty;
    final placesCount = scope.buid == null
        ? spaceProvider.spaces.length
        : spaceProvider.spaces.where((s) => s.buid == scope.buid).length;

    if (categories.isEmpty && !hasPlaces) {
      return const _InfoRow(
        icon: Icons.grid_view,
        text:
            'No service types discovered yet — data may still be loading.',
      );
    }

    final tiles = <Widget>[
      if (hasPlaces)
        _ServiceTile(
          category: EntityCategory.building,
          label: 'Places',
          count: placesCount,
          onTap: placesCount == 0
              ? null
              : () =>
                  ref.read(activeServiceProvider.notifier).state =
                      EntityCategory.building,
        ),
    ];
    for (final category in categories) {
      if (category == EntityCategory.building) continue;
      final results = queryScopedServices(
        category: category,
        campusIndexPois: indexPois,
        buildingBuid: scope.buid,
        floorNumber: scope.floorNumber,
      );
      tiles.add(_ServiceTile(
        category: category,
        count: results.length,
        onTap: results.isEmpty
            ? null
            : () => ref.read(activeServiceProvider.notifier).state = category,
      ));
    }

    // Responsive: 4 columns on normal phones (compact tiles), 3 on very
    // narrow screens, 5+ on wide surfaces.
        final vw = MediaQuery.of(context).size.width;
        final cols = vw >= 620 ? 5 : (vw >= 430 ? 4 : 3);

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.95,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => tiles[i],
    );
  }

  /// Chosen-service RESULTS view (Phase 6).
  ///
  /// * 0 results → scope-aware empty state.
  /// * 1 result  → single result card; selecting it focuses the map.
  /// * ≥2        → horizontal carousel; FIRST result auto-selected and
  ///   focused once per service/scope entry. Carousel → map and map →
  ///   carousel synchronization live here via [SpaceProvider.selectPoi] and
  ///   the [mapFocusRequesterProvider] bridge.
  /// Dispatcher for the Services context: "Places" (buildings) vs POI
  /// category results.
  Widget _buildServiceContext(SpaceProvider spaceProvider) {
    final category = ref.watch(activeServiceProvider)!;
    if (category == EntityCategory.building) {
      return _buildPlacesResults(spaceProvider);
    }
    return _buildPoiServiceResults(category, spaceProvider);
  }

  /// "Places" results — the E-JUST buildings themselves (real server
  /// entities). Selecting one performs the normal building selection;
  /// Directions uses the EXISTING building-route cascade (#8).
  Widget _buildPlacesResults(SpaceProvider spaceProvider) {
    final scope = _currentScope(sp: spaceProvider);
    final buildings = scope.buid == null
        ? spaceProvider.spaces
        : spaceProvider.spaces.where((s) => s.buid == scope.buid).toList();

    // Auto-select/focus first place once per entry (same rule as POI results).
    final key = 'places|${scope.buid ?? ''}|${scope.floorNumber ?? ''}';
    if (_lastAutoSelectedServiceKey != key && buildings.isNotEmpty) {
      _lastAutoSelectedServiceKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _selectPlace(spaceProvider, buildings.first);
      });
    }
    final selectedIndex = buildings
        .indexWhere((s) => s.buid == spaceProvider.selectedSpace?.buid);
    if (_pageController.hasClients &&
        selectedIndex >= 0 &&
        _pageController.page?.round() != selectedIndex &&
        !_userIsSwipingCarousel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.animateToPage(
            selectedIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ServiceScopeLine(label: scope.label),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 148,
          child: _CarouselArrows(
            page: _carouselPage,
            count: buildings.length,
            onPrev: () => _goToCarouselPage(_carouselPage - 1),
            onNext: () => _goToCarouselPage(_carouselPage + 1),
            child: PageView.builder(
              controller: _pageController,
              itemCount: buildings.length,
              onPageChanged: (index) {
                _userIsSwipingCarousel = true;
                _selectPlace(spaceProvider, buildings[index]);
                _userIsSwipingCarousel = false;
              },
              itemBuilder: (context, i) {
                final b = buildings[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _BuildingResultCard(
                    name: b.name,
                    subtitle:
                        b.bucode?.isNotEmpty == true ? b.bucode! : b.spaceType,
                    selected: spaceProvider.selectedSpace?.buid == b.buid,
                    onTap: () =>
                        _selectPlace(spaceProvider, b, explicitTap: true),
                    onDirections: () => spaceProvider.requestRouteToBuilding(b),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _selectPlace(SpaceProvider spaceProvider, SpaceModel space,
      {bool explicitTap = false}) {
    final alreadySelected = spaceProvider.selectedSpace?.buid == space.buid;
    if (!alreadySelected) {
      spaceProvider.selectSpace(space);
    } else if (explicitTap) {
      // Explicit tap on an ALREADY-selected place re-opens its Building
      // context; the automatic first-result selection must NOT.
      _lastAutoContextBuid = space.buid;
      ref.read(panelContextProvider.notifier).state = PanelContext.building;
    }
    // ignore: avoid_print
    final focus = ref.read(mapFocusRequesterProvider);
    focus?.call(space.latLng, 17.0);
  }

  Widget _buildPoiServiceResults(
      EntityCategory category, SpaceProvider spaceProvider) {
    final scope = _currentScope(sp: spaceProvider);
    final results = queryScopedServices(
      category: category,
      campusIndexPois: ref.read(searchServiceProvider).allIndexedPois(),
      buildingBuid: scope.buid,
      floorNumber: scope.floorNumber,
    );

    if (results.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        children: [
          _ServiceScopeLine(label: scope.label),
          const SizedBox(height: 8),
          const _InfoRow(
            icon: Icons.search_off,
            text: 'Nothing matches in this scope yet.',
          ),
        ],
      );
    }

    // Auto-select + focus the FIRST result exactly once per service+scope.
    final key = '${category.name}|${scope.buid ?? ''}|${scope.floorNumber ?? ''}';
    if (_lastAutoSelectedServiceKey != key) {
      _lastAutoSelectedServiceKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (spaceProvider.selectedPoi?.puid != results.first.puid) {
          spaceProvider.selectPoi(results.first);
        }
        _focusPoiIfAvailable(results.first);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }

    // Keep carousel page in sync with external selection (marker taps —
    // Phase 7 covers markers; search/destination flows already select POIs).
    final selectedIndex =
        results.indexWhere((p) => p.puid == spaceProvider.selectedPoi?.puid);
    if (_pageController.hasClients &&
        selectedIndex >= 0 &&
        _pageController.page?.round() != selectedIndex &&
        !_userIsSwipingCarousel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.animateToPage(
            selectedIndex,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }

    final body = results.length == 1
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              height: 148,
              child: _ServiceResultCard(
                poi: results.first,
                buildingName:
                    _buildingNameFor(spaceProvider, results.first.buid),
                selected: true,
                onTap: () =>
                    _selectAndFocusResult(spaceProvider, results.first),
                onDirections:
                    () => _startDirectionsForPoi(spaceProvider, results.first),
              ),
            ),
          )
        : SizedBox(
            height: 148,
            child: _CarouselArrows(
              page: _carouselPage,
              count: results.length,
              onPrev: () => _goToCarouselPage(_carouselPage - 1),
              onNext: () => _goToCarouselPage(_carouselPage + 1),
              child: PageView.builder(
                controller: _pageController,
                itemCount: results.length,
                onPageChanged: (index) {
                  _userIsSwipingCarousel = true;
                  final poi = results[index];
                  if (spaceProvider.selectedPoi?.puid != poi.puid) {
                    spaceProvider.selectPoi(poi);
                  }
                  _focusPoiIfAvailable(poi);
                  _userIsSwipingCarousel = false;
                },
                itemBuilder: (context, i) {
                  final poi = results[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: _ServiceResultCard(
                      poi: poi,
                      buildingName:
                          _buildingNameFor(spaceProvider, poi.buid),
                      selected: spaceProvider.selectedPoi?.puid == poi.puid,
                      onTap: () => _selectAndFocusResult(spaceProvider, poi),
                      onDirections: () =>
                          _startDirectionsForPoi(spaceProvider, poi),
                    ),
                  );
                },
              ),
            ),
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _ServiceScopeLine(label: scope.label),
        ),
        const SizedBox(height: 10),
        body,
        const SizedBox(height: 8),
      ],
    );
  }

  String? _buildingNameFor(SpaceProvider spaceProvider, String buid) =>
      spaceProvider.spaces.where((s) => s.buid == buid).firstOrNull?.name;

  /// CORRECTION PASS (#9): tapping a service result now establishes the
  /// FULL destination chain (building → floor → POI) via the existing
  /// `navigateToPoi`, so the destination state (PoiDetailCard with working
  /// Directions) appears — not just a bare selection. During an ACTIVE
  /// session we only select + focus, so navigation is never torn down.
  Future<void> _selectAndFocusResult(
      SpaceProvider spaceProvider, PoiModel poi) async {
    final nav =
        provider.Provider.of<NavigationController>(context, listen: false);
    if (nav.isActive) {
      if (spaceProvider.selectedPoi?.puid != poi.puid) {
        spaceProvider.selectPoi(poi);
      }
    } else {
      try {
        await spaceProvider.navigateToPoi(poi);
      } catch (e) {
        debugPrint('[CampusPanel] result chain failed: $e');
        spaceProvider.selectPoi(poi);
      }
    }
    _focusPoiIfAvailable(poi);
  }

  void _focusPoiIfAvailable(PoiModel poi) {
    final focus = ref.read(mapFocusRequesterProvider);
    focus?.call(poi.latLng, 18.0);
  }


  Widget _buildBuildingContext(SpaceModel building) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final floors = spaceProvider.floors;
    final selectedFloor = spaceProvider.selectedFloor;

    final List<Widget> content;
    if (spaceProvider.isLoadingFloors) {
      content = const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (spaceProvider.floorsErrorMessage != null) {
      content = [
        _InfoRow(
          icon: Icons.error_outline,
          text: spaceProvider.floorsErrorMessage!,
          actionLabel: 'Retry',
          onAction: () =>
              spaceProvider.loadFloorsForSelectedSpace(forceReload: true),
        ),
      ];
    } else if (floors.isEmpty) {
      content = const [
        _InfoRow(
          icon: Icons.info_outline,
          text: 'No indoor floors mapped for this building.',
        ),
      ];
    } else {
      content = [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final floor in floors)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _FloorChip(
                    label: floor.displayName,
                    isSelected: selectedFloor?.floorNumber == floor.floorNumber,
                    onTap: () => spaceProvider.selectFloor(floor),
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.apartment,
                    size: 22, color: AppTheme.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(building.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      building.description?.isNotEmpty == true
                          ? building.description!
                          : (building.address ?? building.spaceType),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text('Floors',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textTertiary)),
        const SizedBox(height: 8),
        ...content,
        const SizedBox(height: 16),
        // CORRECTION PASS (#8): building routing restored in the redesigned
        // UI — uses the EXISTING `requestRouteToBuilding` cascade.
        _buildBuildingRouteActions(building),
      ],
    );
  }

  Widget _buildBuildingRouteActions(SpaceModel building) {
    final spaceProvider = provider.Provider.of<SpaceProvider>(context);
    final navController = provider.Provider.of<NavigationController>(context);
    final hasRoute = spaceProvider.hasActiveNavigationRoute;
    final isNavActive = navController.isActive;

    final String label;
    final IconData icon;
    final Color bg;
    final VoidCallback? onPressed;

    if (isNavActive) {
      label = 'Navigating…';
      icon = Icons.stop_circle;
      bg = AppTheme.primary.withValues(alpha: 0.4);
      onPressed = null;
    } else if (hasRoute) {
      label = 'Clear Route';
      icon = Icons.alt_route;
      bg = const Color(0xFF059669);
      onPressed = () {
        spaceProvider.clearNavigationRoute();
        navController.terminateNavigation();
      };
    } else {
      final loading = spaceProvider.isLoadingNavigationRoute;
      label = loading ? 'Routing…' : 'Route Here';
      icon = loading ? Icons.hourglass_top : Icons.directions;
      bg = AppTheme.primary;
      onPressed =
          loading ? null : () => spaceProvider.requestRouteToBuilding(building);
    }

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 18),
            label: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ],
    );
  }


  // ─────────────────────── FLOOR CONTEXT ───────────────────────

  Widget _buildFloorContext(SpaceProvider spaceProvider) {
    final pois = spaceProvider.pois
        .where((p) =>
            !PoiClassification.isConnector(p) &&
            !PoiClassification.isEntrance(p) &&
            !PoiClassification.isDoor(p) &&
            p.name.isNotEmpty)
        .toList();

    final List<Widget> content;
    if (spaceProvider.isLoadingPois) {
      content = const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (spaceProvider.poiErrorMessage != null) {
      content = [
        _InfoRow(
          icon: Icons.error_outline,
          text: spaceProvider.poiErrorMessage!,
          actionLabel: 'Retry',
          onAction: () =>
              spaceProvider.loadPoisForSelectedFloor(forceReload: true),
        ),
      ];
    } else if (pois.isEmpty) {
      content = const [
        _InfoRow(
          icon: Icons.info_outline,
          text: 'No points of interest on this floor.',
        ),
      ];
    } else {
      // POIs render as the SAME compact card grid used for Buildings, so the
      // selection experience is unified (Building → card, POI → card).
      // Filters and selection semantics are unchanged — only the presentation
      // is card-based instead of a plain list.
      content = [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final columns = w >= 620 ? 5 : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.74,
              ),
              itemCount: pois.length,
              itemBuilder: (context, i) {
                final poi = pois[i];
                return _PoiCard(
                  poi: poi,
                  isSelected: spaceProvider.selectedPoi?.puid == poi.puid,
                  onTap: () => spaceProvider.selectPoi(poi),
                );
              },
            );
          },
        ),
      ];
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        Text('Points of Interest',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textTertiary)),
        const SizedBox(height: 8),
        ...content,
      ],
    );
  }

  // ─────────────────────── DESTINATION VIEW ───────────────────────

  Widget _buildDestination(SpaceProvider spaceProvider) {
    final poi = spaceProvider.selectedPoi!;
    final navController = provider.Provider.of<NavigationController>(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        PoiDetailCard(
          poi: poi,
          onClose: () {
            // BUG-8 closure semantics preserved: ending a preview tears down
            // through terminateNavigation which clears the single store.
            if (navController.isPreview) navController.terminateNavigation();
            spaceProvider.clearSelectedPoi();
          },
          onNavigate: () async {
            // "Route Here": calculate the route, then FIT THE ENTIRE ROUTE
            // into the available map area (camera refinement).
            await spaceProvider.requestRouteToSelectedPoi();
            if (spaceProvider.hasActiveNavigationRoute) {
              _fitRouteBoundsIfAvailable(spaceProvider);
            }
          },
          onClearRoute: () {
            spaceProvider.clearNavigationRoute();
            navController.terminateNavigation();
          },
          onStartDirections: () =>
              _startDirectionsForPoi(spaceProvider, poi),
          onEndNavigation: () {
            navController.terminateNavigation();
            spaceProvider.clearNavigationRoute();
          },
          isLoadingRoute: spaceProvider.isLoadingNavigationRoute,
          hasActiveRoute: spaceProvider.hasActiveNavigationRoute,
          isNavigating: navController.isActive,
          isRouteUnsupported: spaceProvider.isNavigationRouteUnsupported,
          routeMessage: spaceProvider.hasActiveNavigationRoute
              ? 'Route ready on floor ${spaceProvider.selectedFloor?.floorNumber ?? '-'}'
              : spaceProvider.navigationRouteErrorMessage,
          quickAccessItemBuilder: () => QuickAccessItem.fromPoi(
            poi,
            addedAt: DateTime.now().millisecondsSinceEpoch,
            category: CategoryDeriver.fromPoiType(poi.poisType).name,
          ),
        ),
      ],
    );
  }

  /// GATE VIEW — rendered in the SAME bottom selection/detail panel as
  /// Buildings and POIs (not as a top overlay), so the Search/Directions bar
  /// stays unobstructed. Selecting a gate behaves like selecting a
  /// Building/POI from a UX perspective. Navigation reuses
  /// [SpaceProvider.requestRouteToGate].
  Widget _buildGateContext(SpaceProvider spaceProvider) {
    final gate = spaceProvider.selectedGate!;
    final navController = provider.Provider.of<NavigationController>(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        GateDetailCard(
          gate: gate,
          onClose: () => spaceProvider.clearSelectedGate(),
          onNavigate: () async {
            await spaceProvider.requestRouteToGate(gate);
            if (spaceProvider.hasActiveNavigationRoute) {
              _fitRouteBoundsIfAvailable(spaceProvider);
            }
          },
          isLoadingRoute: spaceProvider.isLoadingNavigationRoute,
          routeMessage: spaceProvider.hasActiveNavigationRoute
              ? 'Route ready to ${gate.name}'
              : spaceProvider.navigationRouteErrorMessage,
          isNavigating: navController.isActive,
          onEndNavigation: () {
            navController.terminateNavigation();
            spaceProvider.clearNavigationRoute();
          },
        ),
      ],
    );
  }

  void _fitRouteBoundsIfAvailable(SpaceProvider spaceProvider) {
    final fitter = ref.read(routeBoundsFitterProvider);
    if (fitter != null) fitter(spaceProvider);
  }

  /// Directions entry shared by the Destination view and service result
  /// cards.
  ///
  /// NAVIGATION CAMERA REFINEMENT:
  ///  * Retarget during a live session → stay in FOLLOW mode (no refit; the
  ///    existing follow pipeline keeps the camera on the user).
  ///  * Fresh start → existing preview/start flow, then the panel collapses
  ///    to the compact navigation bar and `resumeFollowMode()` hands the
  ///    camera to the EXISTING follow pipeline (nav zooms around the user,
  ///    lower-third framing) — never the whole-route view.
  Future<void> _startDirectionsForPoi(
      SpaceProvider spaceProvider, PoiModel poi) async {
    final navController =
        provider.Provider.of<NavigationController>(context, listen: false);
    if (navController.isActive) {
      await navController.retargetDestination(poi);
      return;
    }
    // CORRECTION PASS (#9 root cause): requestRouteToSelectedPoi requires
    // building+floor+POI residency. The old manual space-only setup left
    // `_selectedFloor` null on fresh sessions → routing silently failed.
    // `navigateToPoi` establishes the full chain via the EXISTING flow.
    try {
      await spaceProvider.navigateToPoi(poi);
    } catch (e) {
      debugPrint('[CampusPanel] destination chain failed: $e');
    }
    if (!spaceProvider.hasActiveNavigationRoute) {
      await spaceProvider.requestRouteToSelectedPoi();
    }
    navController.startRoutePreview(
      destinationPuid: poi.puid,
      destinationSpace: spaceProvider.selectedSpace!,
    );
    navController.startActiveNavigation();
    navController.resumeFollowMode();
    ref.read(navPanelOpenProvider.notifier).state = false;
  }

  // (_buildSectionHeader removed — section headers superseded by the
  //  Buildings|Services switch and card grids; Quick Access/Recent sections
  //  were removed in the correction pass.)
}

// ══════════════════════════ private widgets ══════════════════════════

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.category,
    required this.count,
    required this.onTap,
    this.label,
  });

  final EntityCategory category;
  final String? label;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cardBorder),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Icon(category.icon, size: 20, color: category.color),
              ),
              const SizedBox(height: 6),
              Text(label ?? category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              Text('$count',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuildingResultCard extends StatelessWidget {
  const _BuildingResultCard({
    required this.name,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.onDirections,
  });

  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: selected ? 1.0 : 0.75,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.cardBorder,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.apartment,
                          size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.textPrimary)),
                    ),
                    if (selected)
                      const Icon(Icons.my_location,
                          size: 16, color: AppTheme.primary),
                  ],
                ),
                const Spacer(),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textTertiary)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Route Here',
                        style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceScopeLine extends StatelessWidget {
  const _ServiceScopeLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.filter_center_focus,
            size: 14, color: AppTheme.textTertiary),
        const SizedBox(width: 6),
        Flexible(
          child: Text('Scope: $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
        ),
      ],
    );
  }
}

class _ServiceResultCard extends StatelessWidget {
  const _ServiceResultCard({
    required this.poi,
    required this.buildingName,
    required this.selected,
    required this.onTap,
    required this.onDirections,
  });

  final PoiModel poi;
  final String? buildingName;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final category = CategoryDeriver.fromPoiType(poi.poisType);
    return Opacity(
      opacity: selected ? 1.0 : 0.75,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.cardBorder,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: category.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child:
                          Icon(category.icon, size: 18, color: category.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(poi.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppTheme.textPrimary)),
                    ),
                    if (selected)
                      const Icon(Icons.my_location,
                          size: 16, color: AppTheme.primary),
                  ],
                ),
                const Spacer(),
                Text(
                  [
                    ?buildingName,
                    'Floor ${poi.floorNumber}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textTertiary),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions, size: 16),
                    label: const Text('Directions',
                        style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentedSwitch extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Row(
        children: [
          _segment(ref, CampusPanelTab.buildings,
              icon: Icons.location_city, label: 'Buildings'),
          _segment(ref, CampusPanelTab.services,
              icon: Icons.grid_view, label: 'Services'),
        ],
      ),
    );
  }

  Widget _segment(
    WidgetRef ref,
    CampusPanelTab value, {
    required IconData icon,
    required String label,
  }) {
    final active = ref.watch(campusPanelTabProvider) == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ref.read(campusPanelTabProvider.notifier).state = value,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: active ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: active ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color:
                            active ? Colors.white : AppTheme.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloorChip extends StatelessWidget {
  const _FloorChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.layers_outlined,
                size: 14,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(label,
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : AppTheme.textPrimary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PoiCard extends StatelessWidget {
  const _PoiCard({
    required this.poi,
    required this.isSelected,
    required this.onTap,
  });

  final PoiModel poi;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final category = CategoryDeriver.fromPoiType(poi.poisType);
    return Opacity(
      opacity: isSelected ? 1.0 : 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: category.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(category.icon,
                      size: 14, color: category.color),
                ),
                const Spacer(),
                Text(poi.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.12,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 3),
                Text(poi.poisType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textTertiary)),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}


class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.space,
    required this.isSelected,
    required this.onTap,
  });

  final SpaceModel space;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCode = space.bucode != null && space.bucode!.isNotEmpty;
    return Opacity(
      opacity: isSelected ? 1.0 : 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.cardBorder,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.apartment,
                      size: 14, color: AppTheme.primary),
                ),
                const Spacer(),
                Text(space.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w700,
                        fontSize: 11.5,
                        height: 1.12,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 3),
                Text(hasCode ? space.bucode! : space.spaceType,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 8.5,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textTertiary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// CORRECTION #2: visible left/right arrows for any PageView-based carousel.
///
/// Purely presentational + navigation: page index comes from the parent
/// (which derives it from the EXISTING PageController listener), so arrows,
/// swipes and programmatic jumps can never disagree. Arrows hide at the
/// first/last item.
class _CarouselArrows extends StatelessWidget {
  const _CarouselArrows({
    required this.page,
    required this.count,
    required this.child,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int count;
  final Widget child;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (page > 0)
          _ArrowButton(
            icon: Icons.chevron_left,
            alignment: Alignment.centerLeft,
            onTap: onPrev,
          ),
        if (page < count - 1)
          _ArrowButton(
            icon: Icons.chevron_right,
            alignment: Alignment.centerRight,
            onTap: onNext,
          ),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.alignment,
    required this.onTap,
  });

  final IconData icon;
  final Alignment alignment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          shape: const CircleBorder(
              side: BorderSide(color: AppTheme.cardBorder)),
          elevation: 2,
          shadowColor: Colors.black26,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Icon(icon, size: 20, color: AppTheme.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}