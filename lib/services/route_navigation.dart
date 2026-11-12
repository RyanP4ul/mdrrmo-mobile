import 'package:material_ui/material_ui.dart';
import 'package:latlong2/latlong.dart';

import '../screens/route_navigation_screen.dart';
import '../ui/kit.dart';

Future<void> navigateToDestination(
  BuildContext context, {
  String address = '',
  double? latitude,
  double? longitude,
  int? reportId,
}) async {
  final hasCoordinates =
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  if (!hasCoordinates && address.trim().isEmpty) {
    snack(
      context,
      'No destination recorded. Contact the dispatcher for the service location.',
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => RouteNavigationScreen(
        address: address.trim(),
        destination: hasCoordinates ? LatLng(latitude, longitude) : null,
        reportId: reportId,
      ),
    ),
  );
}
