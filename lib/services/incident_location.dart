import 'dart:async';

import 'package:latlong2/latlong.dart';
import 'package:location/location.dart';

import '../data/input_validation.dart';
import 'driver_tracking.dart';

abstract interface class IncidentLocationSource {
  Future<LatLng> current();
}

abstract interface class DetailedLocationSource
    implements IncidentLocationSource {
  Future<GpsFix> currentFix();
}

abstract interface class StreamingLocationSource
    implements DetailedLocationSource {
  Stream<GpsFix> watchFixes();
}

class IncidentLocationException implements Exception {
  const IncidentLocationException(this.message);
  final String message;
}

/// Gets a single foreground fix for an incident pin; does not start tracking.
class DeviceIncidentLocation implements StreamingLocationSource {
  final Location _location = Location();

  @override
  Future<LatLng> current() async {
    final fix = await currentFix();
    return LatLng(fix.latitude, fix.longitude);
  }

  @override
  Future<GpsFix> currentFix() async {
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
    final rawTime = fix.time;
    return _toGpsFix(fix, lat, lng, rawTime);
  }

  @override
  Stream<GpsFix> watchFixes() async* {
    if (!await _location.serviceEnabled() &&
        !await _location.requestService()) {
      return;
    }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    if (permission != PermissionStatus.granted &&
        permission != PermissionStatus.grantedLimited) {
      return;
    }
    await _location.changeSettings(
      accuracy: LocationAccuracy.navigation,
      interval: 2000,
      distanceFilter: 3,
    );
    await for (final fix in _location.onLocationChanged) {
      final lat = fix.latitude;
      final lng = fix.longitude;
      if (InputValidation.coordinates(lat, lng) != null) continue;
      yield _toGpsFix(fix, lat, lng, fix.time);
    }
  }

  GpsFix _toGpsFix(LocationData fix, double lat, double lng, double? rawTime) {
    return GpsFix(
      latitude: lat,
      longitude: lng,
      accuracy: fix.accuracy ?? double.infinity,
      time: rawTime != null && rawTime.isFinite
          ? DateTime.fromMillisecondsSinceEpoch(rawTime.round())
          : DateTime.fromMillisecondsSinceEpoch(0),
      speed: fix.speed,
      heading: fix.heading,
    );
  }
}
