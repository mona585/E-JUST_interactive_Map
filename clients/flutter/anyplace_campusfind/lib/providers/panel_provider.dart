import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/category_deriver.dart';

/// Active segment of the campus dynamic-content switch
/// (UI/UX REDESIGN PHASE 3). Buildings is the default at cold start.
enum CampusPanelTab { buildings, services }

final campusPanelTabProvider =
    StateProvider<CampusPanelTab>((ref) => CampusPanelTab.buildings);

/// Context of the bottom dynamic content area.
///
/// Kept INDEPENDENT from `SpaceProvider.selectedSpace` so the explicit Back
/// affordance can return to the campus list without dropping the building
/// selection (map zoom/context stay intact until the user clears it).
/// Floor/POI/service contexts are added by Phases 4–6.
enum PanelContext { campus, building }

final panelContextProvider =
    StateProvider<PanelContext>((ref) => PanelContext.campus);

/// Bridge (Phase 4): lets the dynamic content panel request route-bounds
/// fitting that is performed BY the map layer. [MapScreen] registers its
/// implementation on mount and clears it on dispose — the panel stays free
/// of camera concerns and the camera stays free of UI concerns.
typedef RouteBoundsFitter = void Function(dynamic spaceProvider);

final routeBoundsFitterProvider =
    StateProvider<RouteBoundsFitter?>((ref) => null);

/// The active service type inside the Services tab (Phase 5). Null = the
/// type grid is showing; non-null = a type is chosen and its scoped results
/// view is active (results carousel itself arrives in Phase 6).
final activeServiceProvider = StateProvider<EntityCategory?>((ref) => null);

/// Bridge (Phase 6): lets the panel request a generic camera focus (target +
/// zoom) performed BY the map layer. Registered by [MapScreen] on mount.
/// Uses dynamic args to avoid coupling the provider file to map types.
typedef MapFocusRequester = void Function(dynamic target, double zoom);

final mapFocusRequesterProvider =
    StateProvider<MapFocusRequester?>((ref) => null);

/// NAVIGATION REFINEMENT: while a navigation session is active, the dynamic
/// panel is replaced by the compact navigation bar. This flag tracks whether
/// the user has re-expanded the full panel during the CURRENT session
/// (navigation keeps running either way). It is force-reset when a new
/// session starts.
final navPanelOpenProvider = StateProvider<bool>((ref) => false);
