# CHANGE-002 - Navigation value objects live in `domain/`, not `data/models/`

- Status: **APPROVED** (same reasoning and the same user decision as CHANGE-001)
- Phase: P7 (Navigation)
- Raised: during P7, before the navigation surface was completed
- `MASTER-PLAN.md` is not modified by this change.

## The conflict

`MASTER-PLAN.md` §8 **Project structure** lists, under
`data/models/`:

```
data/models/{campus_building,campus_gate,outdoor_route,route_progress,gps_sample}.dart
```

Two of those five files were implemented in P7 as domain value objects instead:

- `gps_sample.dart` - `GpsSample`, `GpsQuality` and `HeadingTracker`, created in
  P4 at `lib/domain/location/gps_sample.dart`.
- `route_progress` - implemented as `RouteProgress`, `Maneuver` and
  `ManeuverKind` inside `lib/domain/navigation/progress_tracker.dart`.

The same §8 Architecture rules that forced CHANGE-001 apply unchanged: the
import-boundary test enforces that `domain/` may import only `core/` and
`domain/`, and that presentation never imports `data/`.

## Resolution

- `GpsSample` / `GpsQuality` / `HeadingTracker` stay in `domain/location/`. A GPS
  fix is an input to the domain's position and progress decisions, produced by a
  data-layer source and consumed by `GpsGuard`, `ProgressTracker` and
  `ArrivalDetector`. Placing it in `data/models/` would mean every one of those
  domain services imports the data layer.
- `RouteProgress`, `Maneuver` and `ManeuverKind` stay in
  `domain/navigation/progress_tracker.dart`, next to the geometry that produces
  them. They are pure maths over an `OutdoorRoute`: no fields to parse, no
  validation, nothing to persist. Splitting them into a one-declaration file
  would add a file without adding a boundary.
- `GpsQuality` reads its accuracy thresholds from `core/config/app_config.dart`,
  which is why it is not a data model: the thresholds are shared configuration,
  not a parsing concern.

No `data/models/` file was created for either type, and no new dependency
direction was introduced.

## Verification

- `test/architecture/import_boundary_test.dart` passes, including "domain and
  presentation never import the data layer".
- `flutter analyze`: `No issues found!`
- `flutter test`: `00:08 +304: All tests passed!` (P6 closed at 233; P7 added 71)

## Files affected

- `clients/flutter/ejust_campusfind/lib/domain/location/gps_sample.dart`
  (kept here, from P4)
- `clients/flutter/ejust_campusfind/lib/domain/navigation/progress_tracker.dart`
  (holds `RouteProgress`, `Maneuver`, `ManeuverKind`)
- `clients/flutter/ejust_campusfind/lib/data/models/` - no navigation types added
