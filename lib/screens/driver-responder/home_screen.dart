import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/driver_realtime.dart';
import '../../services/driver_tracking.dart';
import '../../services/internet_connection.dart';
import '../../services/pending_submissions.dart';
import '../../services/route_navigation.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/kit.dart';
import '../../ui/resilient_tiles.dart';
import '../location_access_gate.dart';
import '../record_details_screen.dart';
import 'driver_form_screen.dart';
import 'emergency_form_screen.dart';
import 'home_assignments_section.dart';
import 'maintenance_form_screen.dart';
import 'responder_widgets.dart';

const _serviceCenter = LatLng(14.820102853773369, 120.90161078377581);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.realtime,
    required this.tracking,
  });

  final DriverRealtime realtime;
  final DriverTracking tracking;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _map = MapController();
  int _servicesRefreshKey = 0;
  int _pendingSyncCount = 0;

  @override
  void initState() {
    super.initState();
    PendingSubmissions.changes.addListener(_loadPendingCount);
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final list = await PendingSubmissions.read();
      if (mounted) setState(() => _pendingSyncCount = list.length);
    } catch (_) {}
  }

  @override
  void dispose() {
    PendingSubmissions.changes.removeListener(_loadPendingCount);
    _map.dispose();
    super.dispose();
  }

  Future<void> _refresh(ResponderState state) async {
    try {
      await Future.wait([
        state.load(),
        widget.realtime.refreshFleet(),
        _loadPendingCount(),
      ]);
      if (mounted) setState(() => _servicesRefreshKey++);
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.realtime,
      widget.tracking,
      InternetConnection.instance,
    ]),
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final state = ResponderScope.of(context);
    final palette = MdrrmoColors.of(context);
    final name = state.profile.name.trim().split(' ').first;
    final ready =
        state.hasLoaded &&
        !state.isLoading &&
        !state.isSaving &&
        state.loadError == null;

    return RefreshIndicator(
      onRefresh: () => _refresh(state),
      child: ListView(
        key: const ValueKey('responder-home-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name.isEmpty ? 'Dispatch' : 'Hello, $name',
                          style: MdrrmoTypography.displaySm.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          fmtDate(DateTime.now()),
                          style: MdrrmoTypography.bodySm.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                    ResponderTag(
                      !state.hasLoaded ? 'Loading' : state.profile.status,
                      color: !state.hasLoaded
                          ? palette.textMuted
                          : switch (state.availability) {
                              Availability.available => palette.success,
                              Availability.dispatched => palette.brand,
                              Availability.offDuty => palette.textMuted,
                            },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _ConnectionStrip(
                  realtime: widget.realtime,
                  tracking: widget.tracking,
                ),
                const SizedBox(height: AppSpacing.md),
                if (!state.hasLoaded && state.isLoading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Center(
                      child: CircularProgressIndicator(color: palette.brand),
                    ),
                  ),
                if (state.loadError != null) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.wifiOff,
                    title: 'Could not refresh assignments',
                    message: apiErrorMessage(state.loadError!),
                    action: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: state.isLoading
                            ? null
                            : () => _refresh(state),
                        child: const Text('Try again'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_pendingSyncCount > 0) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.upload,
                    title:
                        '$_pendingSyncCount unsynced ${_pendingSyncCount == 1 ? 'report' : 'reports'}',
                    message: 'Saved locally and waiting to sync.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!state.canDispatch && state.hasLoaded) ...[
                  const AppBanner(
                    tone: AppBannerTone.info,
                    icon: AppIcons.info,
                    message:
                        'Dispatches on Home are available to the team Driver. Switch role in Team if needed.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (state.canDispatch)
                  HomeAssignmentsSection(
                    key: ValueKey(_servicesRefreshKey),
                    api: state.api,
                    assignmentsLoaded: state.hasLoaded,
                    assignmentsError: state.loadError,
                    onRefreshAssignments: state.load,
                    activeAssignments: [
                      for (final item in state.assignments)
                        ResponderAssignmentCard(
                          key: ValueKey('emergency-${item.id}'),
                          assignment: item,
                          busy: state.isSaving && state.assignment?.id == item.id,
                          enabled: ready && item.canAdvance,
                          onAdvance: () => _advance(context, state, item),
                          onDetails: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ResponderScope(
                                state: state,
                                child: RecordDetailsScreen(
                                  id: item.id,
                                  driver: true,
                                  onChanged: state.load,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
                const ResponderHeading('Around you'),
                _MapHero(
                  controller: _map,
                  state: state,
                  positions: widget.realtime.positions,
                  devicePosition: MapLocationScope.of(context),
                ),
                const SizedBox(height: AppSpacing.xl),
                const ResponderHeading('Tools'),
                AppSectionGroup(
                  children: [
                    if (state.isDriver) ...[
                      AppRowItem(
                        title: 'Driver Form',
                        subtitle: 'Trip authorization and fuel log',
                        showChevron: true,
                        enabled: ready,
                        onTap: ready
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ResponderScope(
                                    state: state,
                                    child: DriverFormScreen(
                                      initialReportId: state.assignment?.id,
                                      initialAssignment: state.assignment,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      ),
                      AppRowItem(
                        title: 'Maintenance Report',
                        subtitle: 'Report an ambulance issue',
                        showChevron: true,
                        enabled: ready,
                        onTap: ready
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ResponderScope(
                                    state: state,
                                    child: const MaintenanceFormScreen(),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ] else
                      AppRowItem(
                        title: 'Report an emergency',
                        subtitle: 'Send a field incident to dispatch',
                        showChevron: true,
                        enabled: ready,
                        onTap: ready
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ResponderScope(
                                    state: state,
                                    child: const EmergencyFormScreen(),
                                  ),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _advance(
    BuildContext context,
    ResponderState state,
    Assignment assignment,
  ) async {
    final step = assignment.step;
    if (step == 1) return; // En route -> On scene is automatic within 5m.

    if (step == 3) {
      if (assignment.hospitalId == null) {
        await navigateToDestination(
          context,
          latitude: assignment.latitude,
          longitude: assignment.longitude,
          address: assignment.pickup,
          reportId: assignment.id,
          responderState: state,
        );
        return;
      }
      final confirmed = await confirmDialog(
        context,
        title: 'Arrived at hospital?',
        body:
            'This confirms arrival at the hospital and moves the dispatch to History.',
        confirmLabel: 'Arrived',
      );
      if (!confirmed) return;
    }

    int? hospitalId;
    String? destination;
    if (step == 2) {
      final hospitals = await state.api.fetchHospitals(assignment.id);
      final nearest = hospitals.where((h) => h.isAvailable).firstOrNull;
      if (nearest == null) {
        if (context.mounted) {
          snack(
            context,
            'No available hospital found. Open Navigate to review hospitals.',
          );
        }
        return;
      }
      hospitalId = nearest.id;
      destination = nearest.name;
    }

    try {
      state.selectAssignment(assignment.id);
      await state.advanceAssignment(
        hospitalId: hospitalId,
        destination: destination,
      );
      if (!context.mounted) return;
      final resolved =
          step == 3 &&
          !state.assignments.any((item) => item.id == assignment.id);
      snack(
        context,
        step == 0
            ? 'Dispatch acknowledged. Starting navigation...'
            : step == 2
            ? 'Transporting to ${destination ?? 'nearest hospital'}.'
            : state.assignment == null
            ? 'Arrived at hospital. Dispatch saved to History.'
            : 'Dispatch progress updated.',
      );
      if (step == 0 || step == 2) {
        await navigateToDestination(
          context,
          latitude: assignment.latitude,
          longitude: assignment.longitude,
          address: assignment.pickup,
          reportId: assignment.id,
          responderState: state,
        );
        return;
      }
      if (resolved && state.isDriver && context.mounted) {
        final fillNow = await confirmDialog(
          context,
          title: 'Fill up Driver Form?',
          body:
              'Emergency Response #${assignment.id} is resolved. Would you like to fill up the Driver Form now?',
          confirmLabel: 'Fill Driver Form',
        );
        if (fillNow && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ResponderScope(
                state: state,
                child: DriverFormScreen(
                  initialReportId: assignment.id,
                  initialAssignment: assignment,
                ),
              ),
            ),
          );
        }
      }
    } catch (error) {
      if (context.mounted) {
        snack(
          context,
          'Could not update assignment: ${apiErrorMessage(error)}',
        );
      }
    }
  }
}

class ResponderAssignmentCard extends StatelessWidget {
  const ResponderAssignmentCard({
    super.key,
    required this.assignment,
    required this.busy,
    required this.enabled,
    required this.onAdvance,
    required this.onDetails,
  });

  final Assignment assignment;
  final bool busy, enabled;
  final VoidCallback onAdvance, onDetails;

  Future<void> _navigate(BuildContext context) => navigateToDestination(
    context,
    latitude: assignment.latitude,
    longitude: assignment.longitude,
    address: assignment.pickup,
    reportId: assignment.id,
  );

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final step = assignment.step.clamp(0, Assignment.steps.length - 1);
    final hasLocation =
        assignment.latitude != null && assignment.longitude != null;

    return ResponderPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      onTap: onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                'Incident #${assignment.id}',
                style: MdrrmoTypography.tabular(
                  MdrrmoTypography.labelSm.copyWith(color: palette.textMuted),
                ),
              ),
              ResponderTag(
                '${priorityLabel(assignment.priority)} priority',
                color: Semantic.priority(assignment.priority),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            assignment.emergencyType,
            style: MdrrmoTypography.titleLg.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            assignment.pickup,
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          StepperBar(
            labels: step == 0
                ? [Assignment.steps.first]
                : Assignment.steps.sublist(1),
            current: step == 0 ? 0 : step - 1,
          ),
          if (assignment.hasActionButton) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: busy ? 'Saving...' : assignment.actionLabel,
              loading: busy,
              onPress:
                  enabled && (step != 3 || assignment.hospitalId != null)
                  ? onAdvance
                  : null,
            ),
          ] else if (step == 1) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: palette.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'En route · Marks On scene automatically within 5 m.',
                style: MdrrmoTypography.bodySm.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm + 2),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: hasLocation || assignment.pickup.trim().isNotEmpty
                ? () => _navigate(context)
                : null,
            child: const Text('Navigate', overflow: TextOverflow.ellipsis),
          ),
          if (!assignment.canAdvance ||
              (step == 3 && assignment.hospitalId == null) ||
              !hasLocation) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              !assignment.canAdvance
                  ? 'Waiting for dispatcher confirmation.'
                  : step == 3 && assignment.hospitalId == null
                  ? 'Open Navigate to select a hospital.'
                  : 'No map pin recorded. Confirm destination in Navigate.',
              textAlign: TextAlign.center,
              style: MdrrmoTypography.labelSm.copyWith(
                color: palette.warning,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectionStrip extends StatelessWidget {
  const _ConnectionStrip({required this.realtime, required this.tracking});

  final DriverRealtime realtime;
  final DriverTracking tracking;

  Future<void> _openDetails(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final attention = tracking.error != null;
    return showAppSheet<void>(
      context,
      title: 'Connection & GPS',
      builder: (sheetCtx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppSectionGroup(
            children: [
              AppRowItem(
                title: 'Dispatch channel',
                subtitle: realtime.status,
                trailing: AppStatusBadge(
                  realtime.connected ? 'Online' : 'Reconnecting',
                  color: realtime.connected
                      ? palette.success
                      : palette.warning,
                  dot: true,
                ),
              ),
              AppRowItem(
                title: 'GPS telemetry',
                subtitle: attention
                    ? '${tracking.error} Retrying.'
                    : tracking.active
                    ? tracking.lastSent == null
                          ? 'Waiting for first GPS fix.'
                          : 'Last sent at ${TimeOfDay.fromDateTime(tracking.lastSent!).format(sheetCtx)}.'
                    : 'Enable location to share position.',
              ),
            ],
          ),
          if (!realtime.connected) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Reconnect',
              onPress: () {
                realtime.reconnect();
                Navigator.pop(sheetCtx);
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final offline =
        InternetConnection.instance.hasChecked &&
        !InternetConnection.instance.online;
    final attention = offline || tracking.error != null || !realtime.connected;
    final label = offline
        ? 'Offline · Updates queued'
        : tracking.error != null
        ? 'GPS retrying'
        : !realtime.connected
        ? 'Live updates reconnecting'
        : tracking.active
        ? 'Live sync & GPS active'
        : 'Live updates connected';
    final dotColor = offline
        ? palette.danger
        : attention
        ? palette.warningIcon
        : palette.success;

    return Surface(
      padding: EdgeInsets.zero,
      tint: attention ? palette.warningTint : palette.surface,
      borderColor: offline
          ? palette.danger.withValues(alpha: 0.40)
          : attention
          ? palette.warning.withValues(alpha: 0.35)
          : null,
      onTap: () => _openDetails(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Text(
                label,
                style: MdrrmoTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              'Details',
              style: MdrrmoTypography.labelSm.copyWith(
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapHero extends StatelessWidget {
  const _MapHero({
    required this.controller,
    required this.state,
    required this.positions,
    this.devicePosition,
  });

  final List<Map<String, dynamic>> positions;
  final GpsFix? devicePosition;
  final MapController controller;
  final ResponderState state;

  List<LatLng> get _focusPoints => [
    if (devicePosition != null)
      LatLng(devicePosition!.latitude, devicePosition!.longitude),
    if (state.assignment?.latitude != null &&
        state.assignment?.longitude != null)
      LatLng(state.assignment!.latitude!, state.assignment!.longitude!),
  ];

  void _recenter() {
    final points = _focusPoints;
    if (points.length > 1) {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(32),
          maxZoom: 15,
        ),
      );
    } else {
      controller.move(points.firstOrNull ?? _serviceCenter, 14.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Container(
      height: 176,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - 1),
        child: Stack(
          children: [
            FlutterMap(
              key: ValueKey(
                '${state.assignment?.id}:${state.assignment?.latitude}:${state.assignment?.longitude}:${devicePosition != null}',
              ),
              mapController: controller,
              options: MapOptions(
                initialCenter:
                    state.assignment?.latitude != null &&
                        state.assignment?.longitude != null
                    ? LatLng(
                        state.assignment!.latitude!,
                        state.assignment!.longitude!,
                      )
                    : _focusPoints.firstOrNull ?? _serviceCenter,
                initialCameraFit: _focusPoints.length > 1
                    ? CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(_focusPoints),
                        padding: const EdgeInsets.all(32),
                        maxZoom: 15,
                      )
                    : null,
                initialZoom: 14.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                ),
              ),
              children: [
                const ResilientTiles(),
                MarkerLayer(
                  markers: [
                    for (final driver in positions)
                      Marker(
                        point: LatLng(
                          (driver['lat'] as num).toDouble(),
                          (driver['lng'] as num).toDouble(),
                        ),
                        width: 76,
                        height: 52,
                        child: Tooltip(
                          message: '${driver['name']} - ${driver['status']}',
                          child: Column(
                            children: [
                              Icon(AppIcons.user, color: palette.success),
                              Text(
                                '${driver['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MdrrmoTypography.labelSm.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (devicePosition != null)
                      Marker(
                        point: LatLng(
                          devicePosition!.latitude,
                          devicePosition!.longitude,
                        ),
                        width: 32,
                        height: 32,
                        child: Tooltip(
                          message: 'Your device location',
                          child: Icon(
                            AppIcons.locate,
                            color: palette.brand,
                            size: 24,
                          ),
                        ),
                      ),
                  ],
                ),
                if (state.assignment?.latitude != null &&
                    state.assignment?.longitude != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          state.assignment!.latitude!,
                          state.assignment!.longitude!,
                        ),
                        width: 44,
                        height: 44,
                        child: Icon(
                          AppIcons.pin,
                          size: 36,
                          color: palette.danger,
                        ),
                      ),
                    ],
                  ),
                const RichAttributionWidget(
                  alignment: AttributionAlignment.bottomLeft,
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  state.assignment == null ? 'Service area' : 'Incident area',
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Semantics(
                button: true,
                label: 'Recenter map',
                child: Material(
                  color: palette.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    side: BorderSide(color: palette.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    onTap: _recenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      child: Icon(
                        AppIcons.locate,
                        size: 18,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
