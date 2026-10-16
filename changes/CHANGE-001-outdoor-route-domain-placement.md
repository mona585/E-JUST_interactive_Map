# CHANGE-001 - `OutdoorRoute` lives in `domain/routing/`, not `data/models/`

- Status: **APPROVED**
- Phase: P6 (Routing)
- Raised: during P6, before the routing surface was completed
- `MASTER-PLAN.md` is not modified by this change.

## The conflict

`MASTER-PLAN.md` §8 contains two requirements that cannot both be satisfied for
this one file:

1. **Project structure** lists `outdoor_route.dart` under
   `data/models/{campus_building,campus_gate,outdoor_route,route_progress,gps_sample}.dart`.
2. **Architecture**, in the same section, states "Strict clean MVVM" and
   "domain services are pure", and §8's own import-boundary test (implemented as
   `test/architecture/import_boundary_test.dart`) enforces that `domain/` may
   import only `core/` and `domain/`.

§8's cascade makes `RoutePlanner` a pure domain service: it must return a route
for the UI, and `MASTER-PLAN.md` §9 requires every produced route to carry a
`RouteQuality`. A type that `domain/` returns cannot live in `data/models/`,
because producing it would require a `domain/` -> `data/` import, which the same
section forbids.

## Resolution

`OutdoorRoute` is a domain routing concept, not an I/O record. It is kept at
`lib/domain/routing/outdoor_route.dart` and the architectural dependency
direction is preserved:

- `domain/routing/route_planner.dart` returns `Result<OutdoorRoute>` with no
  `data/` import.
- `data/` may depend on `domain/`, so `CampusMapData.routingGates` projects
  `CampusGate` into the planner's own `RoutingGate` without reversing the
  direction.
- Moving the type to `data/models/` purely to match the file-tree line would
  have introduced either an illegal dependency direction or an indirection that
  exists only to satisfy the tree.

The dependency rule is the stronger and more specific requirement; the file-tree
entry is treated as the discrepancy.

## Verification

- `test/architecture/import_boundary_test.dart` passes, including "domain and
  presentation never import the data layer".
- `flutter analyze`: `No issues found!`
- `flutter test`: `00:07 +233: All tests passed!` (P5 closed at 209; P6 added 24)

## Files affected

- `clients/flutter/ejust_campusfind/lib/domain/routing/outdoor_route.dart`
  (kept here)
- `clients/flutter/ejust_campusfind/lib/data/models/campus_map_data.dart`
  (adds the `routingGates` projection; no `OutdoorRoute` in the data layer)
- `clients/flutter/ejust_campusfind/lib/data/datasources/osrm_client.dart`
  (returns the domain `PublicLeg`, not a data model)
