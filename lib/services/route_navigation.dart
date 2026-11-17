import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart';

import '../screens/route_navigation_screen.dart';
import '../state/driver_responder_state.dart';
import '../ui/kit.dart';

class ScheduleNavigationInfo {
  const ScheduleNavigationInfo({
    required this.scheduleId,
    required this.status,
    required this.pickupAddress,
    this.destinationAddress = '',
    this.serviceType = '',
    this.residentName = '',
    this.onStatusUpdated,
  });

  final int scheduleId;
  final String status;
  final String pickupAddress;
  final String destinationAddress;
  final String serviceType;
  final String residentName;
  final Future<void> Function()? onStatusUpdated;
}

String extractScheduleDestination(Map<String, dynamic> record) {
  final explicit =
      '${record['destination'] ?? record['destination_address'] ?? ''}'.trim();
  if (explicit.isNotEmpty) return explicit;
  final notes = '${record['notes'] ?? ''}';
  for (final rawLine in notes.split('\n')) {
    final line = rawLine.trim();
    if (line.toLowerCase().startsWith('destination:')) {
      final value = line.substring('destination:'.length).trim();
      if (value.isNotEmpty) return value;
    }
  }
  return '';
}

ScheduleNavigationInfo? scheduleNavFromRecord(
  Map<String, dynamic> record, {
  Future<void> Function()? onStatusUpdated,
}) {
  final rawId = record['id'];
  final id = rawId is int ? rawId : int.tryParse('$rawId');
  if (id == null) return null;
  final pickup =
      '${record['pickup_address'] ?? record['address'] ?? ''}'.trim();
  final destination = extractScheduleDestination(record);
  return ScheduleNavigationInfo(
    scheduleId: id,
    status: '${record['status'] ?? 'confirmed'}'.toLowerCase().trim(),
    pickupAddress: pickup,
    destinationAddress: destination,
    serviceType: '${record['service_type'] ?? ''}'.trim(),
    residentName: '${record['resident'] ?? ''}'.trim(),
    onStatusUpdated: onStatusUpdated,
  );
}

Future<void> navigateToDestination(
  BuildContext context, {
  String address = '',
  double? latitude,
  double? longitude,
  int? reportId,
  ResponderState? responderState,
  ScheduleNavigationInfo? schedule,
}) async {
  final hasCoordinates =
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  final hasScheduleAddress =
      schedule != null &&
      (schedule.pickupAddress.isNotEmpty ||
          schedule.destinationAddress.isNotEmpty);
  if (!hasCoordinates && address.trim().isEmpty && !hasScheduleAddress) {
    snack(
      context,
      'No destination recorded. Contact the dispatcher for the service location.',
    );
    return;
  }
  final resolvedResponderState =
      responderState ?? ResponderScope.maybeOf(context);
  final effectiveAddress = address.trim().isNotEmpty
      ? address.trim()
      : (schedule?.status == 'on-scene'
            ? (schedule?.destinationAddress ?? '')
            : (schedule?.pickupAddress ?? ''));
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RouteNavigationScreen(
        address: effectiveAddress,
        destination: hasCoordinates ? LatLng(latitude, longitude) : null,
        reportId: reportId,
        responderState: resolvedResponderState,
        schedule: schedule,
      ),
    ),
  );
}
