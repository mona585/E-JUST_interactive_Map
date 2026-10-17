import '../models/position_estimate.dart';
import '../models/position_fix.dart';
import '../models/user_location.dart';

/// Read + effect seam between the navigation engine and the presentation
/// layer.
///
/// The engine owns every navigation decision and all transient session
/// bookkeeping; it observes canonical positioning evidence (never UI
/// selection) and emits state/effect notifications back through this port.
/// Implemented by [NavigationViewModel].
abstract class NavigationPilotPort {
  PositionFix? get currentFix;
  UserLocation? get currentLocation;
  UserLocation? get gpsLocation;
  PositionEstimate? get latestIndoorEstimate;
  bool get hasGpsFix;
  bool get isIndoorWifiActive;
  bool get gpsDegraded;
  DateTime now();
  void notifyChanged();
}