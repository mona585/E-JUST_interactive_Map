/// Status of RadioMap acquisition and native engine readiness for the selected floor.
enum RadioMapStatus { idle, loading, ready, unsupported, error }

/// Status of Floorplan tiles acquisition and rendering readiness.
enum FloorplanStatus { idle, loading, ready, unsupported, error }

/// Status of indoor Points of Interest (POIs) acquisition for the selected floor.
enum PoiStatus { idle, loading, ready, error }

/// Status of an Anyplace navigation route request.
enum NavigationRouteStatus { idle, loading, ready, unsupported, error }