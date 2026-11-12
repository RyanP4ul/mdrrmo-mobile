import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/kit.dart';
import 'maintenance_form_screen.dart';
import 'responder_widgets.dart';

class ResponderTeamScreen extends StatelessWidget {
  const ResponderTeamScreen({super.key});

  Future<void> _role(
    BuildContext context,
    ResponderState state,
    TeamRole team,
    bool driver,
  ) async {
    try {
      await state.setTeamRole(team.teamId, driver);
      if (context.mounted) {
        snack(
          context,
          driver ? 'You are now the team Driver.' : 'You are now a Responder.',
        );
      }
    } catch (error) {
      if (context.mounted) snack(context, apiErrorMessage(error));
    }
  }

  Future<void> _switchVehicle(
    BuildContext context,
    ResponderState state,
    TeamRole team,
    int vehicleId,
  ) async {
    try {
      await state.switchTeamVehicle(team.teamId, vehicleId);
      if (context.mounted) {
        snack(context, 'Active ambulance updated.');
      }
    } catch (error) {
      if (context.mounted) snack(context, apiErrorMessage(error));
    }
  }

  Future<void> _call(BuildContext context, TeamMember member) async {
    try {
      final phone = member.contact.replaceAll(RegExp(r'[^+0-9]'), '');
      if (phone.isEmpty || !await launchUrl(Uri(scheme: 'tel', path: phone))) {
        throw StateError('No phone dialer is available on this device.');
      }
    } catch (error) {
      if (context.mounted) snack(context, apiErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ResponderScope.of(context);
    final palette = MdrrmoColors.of(context);
    final busy =
        state.isLoading ||
        state.isSaving ||
        !state.hasLoaded ||
        state.loadError != null;
    final active = state.teams.where((member) => member.online).length;

    return RefreshIndicator(
      onRefresh: state.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ResponderHeading(
                  'Your team',
                  subtitle: 'Choose your team role and stay connected.',
                ),
                if (state.isLoading && !state.hasLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (state.loadError != null) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.wifiOff,
                    title: 'Could not refresh your team',
                    message: apiErrorMessage(state.loadError!),
                    action: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: state.isLoading ? null : state.load,
                      icon: const Icon(AppIcons.refresh, size: 17),
                      label: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (state.teamRoles.isEmpty && state.hasLoaded)
                  const AppStateView(
                    icon: AppIcons.users,
                    title: 'No active team membership',
                    message:
                        'Ask the dispatcher to link your account to a response team.',
                  ),
                for (final team in state.teamRoles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: ResponderPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              '${team.teamName}: Driver',
                              style: MdrrmoTypography.titleMd.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Text(
                                team.locked
                                    ? 'Your role: ${team.role}. Complete active dispatches or service trips before changing roles.'
                                    : team.isDriver
                                    ? 'You are the Driver. Only you can view and start dispatches on Home. Switch off to become a Responder.'
                                    : !team.canBeDriver
                                    ? '${team.driverName ?? 'Another member'} is the Driver. The current Driver must switch back or dispatch must reassign the role.'
                                    : 'You are a Responder. Switch on to become the team Driver.',
                                style: MdrrmoTypography.bodySm.copyWith(
                                  height: 1.45,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ),
                            value: team.isDriver,
                            onChanged:
                                busy ||
                                    team.locked ||
                                    (!team.isDriver && !team.canBeDriver)
                                ? null
                                : (value) =>
                                      _role(context, state, team, value),
                          ),
                          if (team.activeVehicle != null ||
                              team.vehicles.isNotEmpty) ...[
                            Divider(height: AppSpacing.xxl, color: palette.border),
                            _TeamAmbulanceSection(
                              team: team,
                              busy: busy,
                              onSwitchVehicle: (vehicleId) => _switchVehicle(
                                context,
                                state,
                                team,
                                vehicleId,
                              ),
                              onReportMaintenance: (vehicleId) =>
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ResponderScope(
                                        state: state,
                                        child: MaintenanceFormScreen(
                                          initialVehicleId: vehicleId,
                                        ),
                                      ),
                                    ),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                ResponderHeading(
                  'Team directory',
                  subtitle: '$active of ${state.teams.length} recently active',
                ),
                if (state.teams.isEmpty && state.hasLoaded)
                  const ResponderEmptyState(
                    icon: AppIcons.users,
                    title: 'No team members yet',
                    message:
                        'Members appear here when dispatch links you to a response team.',
                  ),
                for (final member in state.teams)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ResponderPanel(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Row(
                        children: [
                          InitialsAvatar(
                            member.name,
                            online: member.online,
                            size: 44,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.name,
                                  style: MdrrmoTypography.titleMd.copyWith(
                                    color: palette.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  member.role,
                                  style: MdrrmoTypography.bodySm.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  member.online
                                      ? 'Active in the last 90 seconds'
                                      : 'Not recently active',
                                  style: MdrrmoTypography.labelSm.copyWith(
                                    color: member.online
                                        ? palette.success
                                        : palette.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            tooltip: member.contact.isEmpty
                                ? 'No phone number recorded'
                                : 'Call ${member.name}',
                            onPressed: member.contact.isEmpty
                                ? null
                                : () => _call(context, member),
                            icon: const Icon(AppIcons.phoneCall, size: 19),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamAmbulanceSection extends StatelessWidget {
  const _TeamAmbulanceSection({
    required this.team,
    required this.busy,
    required this.onSwitchVehicle,
    required this.onReportMaintenance,
  });

  final TeamRole team;
  final bool busy;
  final ValueChanged<int> onSwitchVehicle;
  final ValueChanged<int?> onReportMaintenance;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final vehicle = team.activeVehicle ?? team.vehicles.firstOrNull;
    if (vehicle == null) return const SizedBox.shrink();

    final statusColor = switch (vehicle.status) {
      'available' => palette.success,
      'maintenance' => palette.warning,
      'offline' => palette.textMuted,
      _ => palette.brand,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            Text(
              'Assigned ambulance',
              style: MdrrmoTypography.labelSm.copyWith(
                color: palette.textMuted,
              ),
            ),
            AppStatusBadge(
              vehicle.status.toUpperCase(),
              color: statusColor,
              icon: AppIcons.ambulance,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 68,
                height: 52,
                child: vehicle.photoUrl != null && vehicle.photoUrl!.isNotEmpty
                    ? Image.network(
                        vehicle.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const _AmbulancePlaceholder(),
                      )
                    : const _AmbulancePlaceholder(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.displayName,
                    style: MdrrmoTypography.titleMd.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Plate No: ${vehicle.number}',
                    style: MdrrmoTypography.bodySm.copyWith(
                      fontWeight: FontWeight.w600,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (vehicle.hasMaintenanceWarning) ...[
          const SizedBox(height: AppSpacing.md),
          AppBanner(
            tone: AppBannerTone.warning,
            icon: AppIcons.alert,
            message: vehicle.maintenanceWarning?.trim().isNotEmpty == true
                ? vehicle.maintenanceWarning!
                : 'This ambulance is currently marked for maintenance.',
          ),
        ],
        if (team.vehicles.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<int>(
            initialValue: team.vehicles.any((v) => v.id == vehicle.id)
                ? vehicle.id
                : null,
            decoration: const InputDecoration(
              labelText: 'Switch active ambulance',
            ),
            isExpanded: true,
            items: [
              for (final item in team.vehicles)
                DropdownMenuItem<int>(
                  value: item.id,
                  enabled: item.status != 'maintenance',
                  child: Text(
                    '${item.displayName} (${item.number}) - ${item.status}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: busy || !team.isDriver || team.locked
                ? null
                : (selectedId) {
                    if (selectedId != null && selectedId != vehicle.id) {
                      onSwitchVehicle(selectedId);
                    }
                  },
          ),
        ],
        if (team.isDriver) ...[
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: 'Report maintenance',
            icon: AppIcons.wrench,
            kind: AppButtonKind.outline,
            onPress: busy ? null : () => onReportMaintenance(vehicle.id),
          ),
        ],
      ],
    );
  }
}

class _AmbulancePlaceholder extends StatelessWidget {
  const _AmbulancePlaceholder();

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.brandTint,
        border: Border.all(color: palette.brand.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(
        AppIcons.ambulance,
        color: palette.brand,
        size: 24,
      ),
    );
  }
}
