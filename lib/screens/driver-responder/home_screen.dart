import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../services/driver_realtime.dart';
import '../../services/driver_tracking.dart';
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

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _refresh(ResponderState state) async {
    try {
      await Future.wait([state.load(), widget.realtime.refreshFleet()]);
      if (mounted) setState(() => _servicesRefreshKey++);
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.realtime, widget.tracking]),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty
                                ? 'Ready when it matters.'
                                : 'Hello, $name',
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
                    ),
                    const SizedBox(width: AppSpacing.sm),
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
                const SizedBox(height: AppSpacing.lg),
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
                    title: 'Your information could not be refreshed.',
                    message: apiErrorMessage(state.loadError!),
                    action: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: state.isLoading
                            ? null
                            : () => _refresh(state),
                        icon: const Icon(AppIcons.refresh, size: 16),
                        label: const Text('Try again'),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (!state.canDispatch && state.hasLoaded) ...[
                  const AppBanner(
                    tone: AppBannerTone.info,
                    icon: AppIcons.info,
                    message:
                        'Dispatches on Home are available to the team Driver. You are currently a Responder. Check Team to see the current Driver.',
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
                          onDriverForm: state.isDriver
                              ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ResponderScope(
                                      state: state,
                                      child: DriverFormScreen(
                                        initialReportId: item.id,
                                        initialAssignment: item,
                                      ),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
                const SizedBox(height: AppSpacing.xl),
                const ResponderHeading(
                  'Around you',
                  subtitle: 'Your location and the assigned incident.',
                ),
                _MapHero(
                  controller: _map,
                  state: state,
                  positions: widget.realtime.positions,
                  devicePosition: MapLocationScope.of(context),
                ),
                const SizedBox(height: AppSpacing.md),
                _ConnectionCard(
                  realtime: widget.realtime,
                  tracking: widget.tracking,
                ),
                const SizedBox(height: AppSpacing.xl),
                const ResponderHeading('Tools & support'),
                if (state.isDriver) ...[
                  ResponderShortcut(
                    icon: AppIcons.badgeCheck,
                    title: 'Authorization & fuel form',
                    subtitle: 'Driver Form: passenger and fuel log',
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
                  const SizedBox(height: AppSpacing.sm),
                  ResponderShortcut(
                    icon: AppIcons.wrench,
                    title: 'Maintenance Report',
                    subtitle: 'Report ambulance issues (Driver only)',
                    color: palette.warningIcon,
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
                  const SizedBox(height: AppSpacing.sm),
                ],
                ResponderShortcut(
                  icon: AppIcons.pin,
                  title: 'Report an emergency',
                  subtitle: 'Send a new incident to dispatch',
                  color: palette.danger,
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
    final isCompleting = assignment.step == 2;
    if (isCompleting) {
      final confirmed = await confirmDialog(
        context,
        title: 'Complete dispatch?',
        body:
            'This closes the assignment and moves it to History. Make sure the response is complete.',
        confirmLabel: 'Complete dispatch',
      );
      if (!confirmed) return;
    }
    try {
      state.selectAssignment(assignment.id);
      await state.advanceAssignment();
      if (!context.mounted) return;
      final resolved =
          isCompleting &&
          !state.assignments.any((item) => item.id == assignment.id);
      snack(
        context,
        state.assignment == null
            ? 'Dispatch completed. Saved to History.'
            : 'Dispatch progress updated.',
      );
      if (resolved && state.isDriver && context.mounted) {
        final fillNow = await confirmDialog(
          context,
          title: 'Fill up Driver Form?',
          body:
              'Emergency Response #${assignment.id} is resolved. Would you like to fill up the Driver Form now? (You can also fill it later from Dispatch or Tools & support.)',
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
    this.onDriverForm,
  });

  final Assignment assignment;
  final bool busy, enabled;
  final VoidCallback onAdvance, onDetails;
  final VoidCallback? onDriverForm;

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
    final step = assignment.step.clamp(0, 2);
    final hasLocation =
        assignment.latitude != null && assignment.longitude != null;

    return ResponderPanel(
      accent: palette.brand,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              const ResponderTag('EMERGENCY RESPONSE', icon: AppIcons.form),
              ResponderTag(
                '${priorityLabel(assignment.priority)} priority',
                color: Semantic.priority(assignment.priority),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            assignment.emergencyType,
            style: MdrrmoTypography.titleLg.copyWith(color: palette.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'Incident #${assignment.id}',
            style: MdrrmoTypography.tabular(
              MdrrmoTypography.labelSm.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceSubtle,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: palette.brandTint,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    AppIcons.pin,
                    color: palette.brand,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'INCIDENT LOCATION',
                        style: MdrrmoTypography.labelSm.copyWith(
                          color: palette.textMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        assignment.pickup,
                        style: MdrrmoTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          StepperBar(labels: Assignment.steps, current: step),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: busy ? 'Saving update...' : assignment.actionLabel,
            icon: step == 0
                ? AppIcons.navigation
                : step == 1
                ? AppIcons.pin
                : AppIcons.checkCircle,
            loading: busy,
            onPress: enabled ? onAdvance : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _AssignmentActionTile(
                    icon: AppIcons.navigation,
                    label: 'Navigate',
                    onPressed:
                        hasLocation || assignment.pickup.trim().isNotEmpty
                        ? () => _navigate(context)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _AssignmentActionTile(
                    icon: AppIcons.form,
                    label: 'View report',
                    onPressed: onDetails,
                  ),
                ),
                if (onDriverForm != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _AssignmentActionTile(
                      icon: assignment.hasDriverForm
                          ? AppIcons.checkCircle
                          : AppIcons.badgeCheck,
                      label: 'Driver Form',
                      onPressed: onDriverForm,
                      iconColor: assignment.hasDriverForm
                          ? palette.success
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            !assignment.canAdvance
                ? 'Waiting for dispatcher confirmation.'
                : step == 0
                ? 'Start your trip when you are ready to leave.'
                : step == 1
                ? 'Update your status once you reach the incident.'
                : 'Complete the dispatch when the response is finished.',
            textAlign: TextAlign.center,
            style: MdrrmoTypography.labelSm.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!hasLocation)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'No map pin recorded. Confirm the destination in navigation.',
                textAlign: TextAlign.center,
                style: MdrrmoTypography.labelSm.copyWith(
                  color: palette.textMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssignmentActionTile extends StatelessWidget {
  const _AssignmentActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final enabled = onPressed != null;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        side: BorderSide(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: enabled ? (iconColor ?? palette.brand) : palette.textMuted,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MdrrmoTypography.labelSm.copyWith(
              color: enabled ? palette.textPrimary : palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.realtime, required this.tracking});

  final DriverRealtime realtime;
  final DriverTracking tracking;

  Future<void> _openDetails(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final attention = tracking.error != null;
    return showAppSheet<void>(
      context,
      title: 'Live updates & GPS',
      subtitle: 'Dispatch tracking connection diagnostics',
      builder: (sheetCtx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppSectionGroup(
            children: [
              AppRowItem(
                leading: Icon(
                  realtime.connected ? AppIcons.wifi : AppIcons.wifiOff,
                  color: realtime.connected ? palette.success : palette.warningIcon,
                  size: 18,
                ),
                title: 'Dispatch channel',
                subtitle: realtime.status,
              ),
              AppRowItem(
                leading: Icon(
                  attention ? AppIcons.alert : AppIcons.locate,
                  color: attention ? palette.warningIcon : palette.brand,
                  size: 18,
                ),
                title: 'GPS telemetry',
                subtitle: attention
                    ? 'Location update failed. ${tracking.error} Retrying automatically.'
                    : tracking.active
                    ? tracking.lastSent == null
                          ? 'Waiting for your first GPS update.'
                          : 'Last location shared at ${TimeOfDay.fromDateTime(tracking.lastSent!).format(sheetCtx)}.'
                    : 'Keep location enabled to share your position with dispatch.',
              ),
            ],
          ),
          if (!realtime.connected) ...[
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Reconnect live updates',
              icon: AppIcons.refresh,
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
    final attention = tracking.error != null;
    final location = attention
        ? 'Location needs attention'
        : tracking.active
        ? 'Location sharing on'
        : tracking.busy
        ? 'Starting location sharing'
        : 'Location sharing inactive';

    return Surface(
      padding: EdgeInsets.zero,
      child: AppRowItem(
        onTap: () => _openDetails(context),
        showChevron: true,
        leading: Icon(
          attention ? AppIcons.wifiOff : AppIcons.radio,
          size: 20,
          color: attention ? palette.warningIcon : palette.brand,
        ),
        title: location,
        subtitle: realtime.connected
            ? 'Live updates connected'
            : 'Tap for connection details',
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
      height: 180,
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.assignment == null
                          ? 'Service area · Balagtas'
                          : 'Assigned incident · Balagtas',
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
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
