import 'package:flutter/services.dart';
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
                const ResponderHeading('Your team'),
                if (state.isLoading && !state.hasLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (state.loadError != null) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.wifiOff,
                    title: 'Could not refresh team',
                    message: apiErrorMessage(state.loadError!),
                    action: TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: state.isLoading ? null : state.load,
                      child: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (state.teamRoles.isEmpty && state.hasLoaded)
                  const AppStateView(
                    icon: AppIcons.users,
                    title: 'No team assigned',
                    message: 'Contact dispatch to join a response team.',
                  ),
                for (final team in state.teamRoles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _TeamCard(
                      team: team,
                      busy: busy,
                      onToggleRole: (value) =>
                          _role(context, state, team, value),
                      onSwitchVehicle: (vehicleId) =>
                          _switchVehicle(context, state, team, vehicleId),
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
                  ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Members',
                          style: MdrrmoTypography.titleMd.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (state.teams.isNotEmpty)
                        Text(
                          '$active active',
                          style: MdrrmoTypography.labelSm.copyWith(
                            color: active > 0
                                ? palette.success
                                : palette.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (state.teams.isEmpty && state.hasLoaded)
                  Surface(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'No team members listed yet.',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  )
                else if (state.teams.isNotEmpty)
                  AppSectionGroup(
                    children: [
                      for (final member in state.teams)
                        _MemberRow(
                          member: member,
                          onCall: member.contact.isEmpty
                              ? null
                              : () => _call(context, member),
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
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.busy,
    required this.onToggleRole,
    required this.onSwitchVehicle,
    required this.onReportMaintenance,
  });

  final TeamRole team;
  final bool busy;
  final ValueChanged<bool> onToggleRole;
  final ValueChanged<int> onSwitchVehicle;
  final ValueChanged<int?> onReportMaintenance;

  String? get _roleNotice {
    if (team.locked) {
      return 'Complete active dispatches before changing roles.';
    }
    if (!team.isDriver && !team.canBeDriver) {
      return '${team.driverName ?? 'Another member'} is the Driver.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final hasVehicle = team.activeVehicle != null || team.vehicles.isNotEmpty;
    final canSwitch =
        !(busy || team.locked || (!team.isDriver && !team.canBeDriver));

    return ResponderPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            team.teamName,
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          TeamRoleToggle(
            key: ValueKey('team-role-toggle-${team.teamId}'),
            isDriver: team.isDriver,
            onChanged: canSwitch ? onToggleRole : null,
          ),
          if (_roleNotice != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _roleNotice!,
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          if (hasVehicle) ...[
            Divider(height: AppSpacing.xl, color: palette.border),
            _TeamAmbulanceSection(
              team: team,
              busy: busy,
              onSwitchVehicle: onSwitchVehicle,
              onReportMaintenance: onReportMaintenance,
            ),
          ],
        ],
      ),
    );
  }
}

/// Two-sided pill toggle with `Driver` on the left and `Responder` on the right.
class TeamRoleToggle extends StatelessWidget {
  const TeamRoleToggle({
    super.key,
    required this.isDriver,
    required this.onChanged,
  });

  final bool isDriver;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final enabled = onChanged != null;

    Widget option({required String label, required bool driverValue}) {
      final selected = isDriver == driverValue;
      return Expanded(
        child: Semantics(
          button: true,
          enabled: enabled,
          selected: selected,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: !enabled || selected
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onChanged!(driverValue);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? palette.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: MdrrmoTypography.bodySm.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: enabled ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: palette.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            option(label: 'Driver', driverValue: true),
            option(label: 'Responder', driverValue: false),
          ],
        ),
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
    final statusLabel = vehicle.status.isEmpty
        ? 'Unknown'
        : '${vehicle.status[0].toUpperCase()}${vehicle.status.substring(1)}';

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
            AppStatusBadge(statusLabel, color: statusColor, dot: true),
          ],
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (vehicle.photoUrl != null && vehicle.photoUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: 56,
                  height: 44,
                  child: Image.network(
                    vehicle.photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _AmbulanceThumb(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ] else ...[
              const _AmbulanceThumb(),
              const SizedBox(width: AppSpacing.md),
            ],
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
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (team.vehicles.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<int>(
            initialValue: team.vehicles.any((v) => v.id == vehicle.id)
                ? vehicle.id
                : null,
            decoration: const InputDecoration(
              labelText: 'Switch ambulance',
            ),
            isExpanded: true,
            items: [
              for (final item in team.vehicles)
                DropdownMenuItem<int>(
                  value: item.id,
                  enabled: item.status != 'maintenance',
                  child: Text(
                    item.status == 'maintenance'
                        ? '${item.displayName} (${item.number}) · Maintenance'
                        : '${item.displayName} (${item.number})',
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
            kind: AppButtonKind.outline,
            onPress: busy ? null : () => onReportMaintenance(vehicle.id),
          ),
        ],
      ],
    );
  }
}

class _AmbulanceThumb extends StatelessWidget {
  const _AmbulanceThumb();

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: palette.brandTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Icon(
        AppIcons.ambulance,
        color: palette.brand,
        size: 20,
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.onCall,
  });

  final TeamMember member;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          InitialsAvatar(
            member.name,
            online: member.online,
            size: 40,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: MdrrmoTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${member.role} · ${member.online ? 'Active' : 'Offline'}',
                  style: MdrrmoTypography.bodySm.copyWith(
                    color: member.online
                        ? palette.success
                        : palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onCall != null)
            IconButton.filledTonal(
              style: IconButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              tooltip: 'Call ${member.name}',
              onPressed: onCall,
              icon: const Icon(AppIcons.phoneCall, size: 18),
            ),
        ],
      ),
    );
  }
}
