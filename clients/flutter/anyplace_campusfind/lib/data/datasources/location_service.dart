import '../models/user_location.dart';

/// Permission status enumeration for location requests.
enum LocationPermissionStatus {
  /// Permission has been granted (while in use or always).
  granted,

  /// Permission was denied by the user.
  denied,

  /// Permission was permanently denied (user selected 'Don't ask again' or system policy).
  deniedForever,

  /// Location services (GPS hardware) are disabled on the device.
  serviceDisabled,
}

/// Abstract contract defining outdoor GPS location operations.
///
/// This interface decouples location acquisition from the UI and state layers,
/// and allows clean separation between outdoor GPS positioning and the future
/// indoor Wi-Fi RadioMap positioning subsystem.
abstract class LocationService {
  /// Checks whether location services are enabled on the device.
  Future<bool> isLocationServiceEnabled();

  /// Checks the current permission status without prompting the user.
  Future<LocationPermissionStatus> checkPermission();

  /// Requests location permissions from the user.
  Future<LocationPermissionStatus> requestPermission();

  /// Obtains the current GPS position of the device.
  ///
  /// Returns `null` if location services are disabled, permissions are denied,
  /// or a position could not be acquired.
  Future<UserLocation?> getCurrentPosition();

  /// Returns a stream of real-time GPS location updates.
  ///
  /// [distanceFilter] is in meters; small values (e.g. 0.3) maximize
  /// navigation responsiveness at the cost of more callbacks.
  Stream<UserLocation> getPositionStream({double distanceFilter = 0.3});
}
