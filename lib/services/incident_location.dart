import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../data/input_validation.dart';

abstract interface class IncidentLocationSource {
  Future<LatLng> current();
}

class IncidentLocationException implements Exception {
  const IncidentLocationException(this.message);
  final String message;
}

/// Gets a single foreground fix for an incident pin; does not start tracking.
class DeviceIncidentLocation implements IncidentLocationSource {
  final Location _location = Location();

  @override
  Future<LatLng> current() async {
    if (!await _location.serviceEnabled() &&
        !await _location.requestService()) {
      throw const IncidentLocationException(
        'Turn on device location, then try again. You can also tap the map to place the pin.',
      );
    }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.grantedLimited) {
      throw const IncidentLocationException(
        'Allow location access in your device settings, or tap the map to place the incident pin.',
      );
    }
    final fix = await _location.getLocation().timeout(
      const Duration(seconds: 20),
    );
    final lat = fix.latitude;
    final lng = fix.longitude;
    if (InputValidation.coordinates(lat, lng) != null) {
      throw const IncidentLocationException(
        'Your device did not return a valid location. Try again or place the pin on the map.',
      );
    }
    return LatLng(lat, lng);
  }
}
