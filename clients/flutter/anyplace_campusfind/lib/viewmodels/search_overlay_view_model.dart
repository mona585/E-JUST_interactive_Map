import 'package:flutter/foundation.dart';

import '../services/search_service.dart';

/// ViewModel for the From/To search overlay (MVVM).
///
/// Owns the mutable presentation state the overlay previously kept in its
/// widget `State` class:
///  * the query text driving result suggestions,
///  * whether the user is picking a custom origin (vs a destination),
/// plus the derived suggestion/result lists for each mode.
///
/// Delegates ranking/indexing to the injected [SearchService]; endpoint
/// selection/swap lives in the Riverpod direction providers (unchanged).
class SearchOverlayViewModel extends ChangeNotifier {
  SearchOverlayViewModel({SearchService? searchService})
    : _searchService = searchService ?? SearchService() {
    _searchService.addIndexListener(_onServiceChanged);
  }

  final SearchService _searchService;

  void _onServiceChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _searchService.removeIndexListener(_onServiceChanged);
    super.dispose();
  }

  /// Legacy suggestion cap shown when the query is empty.
  static const int suggestionLimit = 8;

  String _query = '';
  bool _pickingFrom = false;

  /// The injected search service (kept visible for index listeners).
  SearchService get searchService => _searchService;

  /// Current query text as typed.
  String get query => _query;

  /// Whether the "Choose origin" picker is active.
  bool get pickingFrom => _pickingFrom;

  /// Results for the destination picker (includes spaces/floors).
  List<SearchResult> get destinationResults =>
      _searchService.query(_query, includeSpacesAndFloors: true);

  /// Results for the origin picker (POI-only, matching the legacy `.where`
  /// filter by construction — [SearchService.query] returns POIs only when
  /// [includeSpacesAndFloors] is false).
  List<SearchResult> get originResults => _searchService.query(_query);

  /// Updates the query and notifies listeners.
  void setQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  /// Clears the query text.
  void clearQuery() => setQuery('');

  /// Enters the origin-picking mode.
  void beginPickingOrigin() {
    if (_pickingFrom) return;
    _pickingFrom = true;
    notifyListeners();
  }

  /// Leaves origin-picking mode (either by choosing an origin or cancelling).
  void endPickingOrigin() {
    if (!_pickingFrom) return;
    _pickingFrom = false;
    notifyListeners();
  }
}
