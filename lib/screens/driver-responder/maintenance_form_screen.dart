import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/form_page.dart';
import '../../ui/kit.dart';
import 'responder_widgets.dart';

enum _MaintenanceFilter { all, pending, active, closed }

class MaintenanceFormScreen extends StatefulWidget {
  const MaintenanceFormScreen({super.key, this.initialVehicleId});
  final int? initialVehicleId;

  @override
  State<MaintenanceFormScreen> createState() => _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends State<MaintenanceFormScreen> {
  static const _issueTypes = [
    'Engine / Mechanical',
    'Brakes / Tires',
    'Electrical / Siren / Lights',
    'Medical Equipment',
    'Preventive / Scheduled',
    'Other',
  ];

  final _key = GlobalKey<FormState>();
  final _mileage = TextEditingController();
  final _description = TextEditingController();

  int? _vehicleId;
  String _issueType = _issueTypes.first;
  Priority _severity = Priority.medium;
  bool _recommendOutOfService = false;
  bool _saving = false;
  bool _showHistory = false;
  _MaintenanceFilter _historyFilter = _MaintenanceFilter.all;
  String? _error;

  List<Map<String, dynamic>> _reports = [];
  bool _loadingReports = false;
  bool _fetchedOnce = false;

  @override
  void initState() {
    super.initState();
    _vehicleId = widget.initialVehicleId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = ResponderScope.of(context);
    final vehicles = _availableVehicles(state);
    if (_vehicleId == null && vehicles.isNotEmpty) {
      _vehicleId = state.selectedVehicleId ?? vehicles.first.id;
    }
    if (!_fetchedOnce && !_loadingReports) {
      _fetchedOnce = true;
      _loadReports(state);
    }
  }

  @override
  void dispose() {
    _mileage.dispose();
    _description.dispose();
    super.dispose();
  }

  List<DriverVehicle> _availableVehicles(ResponderState state) {
    final fromTeams = [
      for (final team in state.teamRoles)
        if (team.isDriver) ...team.vehicles,
    ];
    if (fromTeams.isNotEmpty) {
      final seen = <int>{};
      return [
        for (final v in fromTeams)
          if (seen.add(v.id)) v,
      ];
    }
    return state.vehicles;
  }

  Future<void> _loadReports(ResponderState state) async {
    setState(() => _loadingReports = true);
    try {
      final page = await state.api.fetchMaintenanceReportsPage();
      if (mounted) {
        setState(() => _reports = page.items);
      }
    } catch (_) {
      // Non-blocking if history fetch fails offline.
    } finally {
      if (mounted) setState(() => _loadingReports = false);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final state = ResponderScope.of(context);
    if (!state.isDriver) {
      setState(
        () => _error = 'Only the team Driver can submit maintenance reports.',
      );
      return;
    }
    if (!_key.currentState!.validate()) return;
    final vehicleId = _vehicleId;
    if (vehicleId == null) {
      setState(() => _error = 'Select the ambulance or vehicle to report.');
      return;
    }
    final mileageText = _mileage.text.trim();
    final mileage = mileageText.isEmpty ? null : int.tryParse(mileageText);
    if (mileageText.isNotEmpty && (mileage == null || mileage < 0)) {
      setState(() => _error = 'Enter a valid mileage number.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await state.submitMaintenanceReport(
        vehicleId: vehicleId,
        issueType: _issueType,
        severity: _severity.name,
        mileage: mileage,
        description: _description.text.trim(),
        recommendOutOfService: _recommendOutOfService,
      );
      if (!mounted) return;
      snack(
        context,
        'Maintenance report ${created['reference'] ?? ''} submitted to Admin.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() => _error = apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _statusColor(MdrrmoColors palette, Object? status) => switch (status) {
    'resolved' => palette.success,
    'rejected' => palette.danger,
    'approved' || 'in_maintenance' => palette.warning,
    _ => palette.brand,
  };

  Color _severityColor(MdrrmoColors palette, Object? rawSeverity) {
    final normalized = '$rawSeverity'.toLowerCase().trim();
    return switch (normalized) {
      'low' => palette.success,
      'medium' => palette.warning,
      'high' || 'critical' => palette.danger,
      _ => palette.brand,
    };
  }

  String _formatStatusLabel(Object? status) {
    final value = '${status ?? 'pending'}'.replaceAll('_', ' ').trim();
    if (value.isEmpty) return 'Pending';
    return value[0].toUpperCase() + value.substring(1);
  }

  String _formatTimestamp(Object? iso) {
    final parsed = DateTime.tryParse('${iso ?? ''}');
    if (parsed == null) return '';
    return '${fmtDay(parsed)} · ${fmtTime(parsed)}';
  }

  List<Map<String, dynamic>> get _filteredReports => _reports
      .where((report) {
        final status = '${report['status'] ?? 'pending'}'.toLowerCase().trim();
        return switch (_historyFilter) {
          _MaintenanceFilter.all => true,
          _MaintenanceFilter.pending =>
            status == 'pending' || status == 'acknowledged',
          _MaintenanceFilter.active =>
            status == 'approved' || status == 'in_maintenance',
          _MaintenanceFilter.closed =>
            status == 'resolved' || status == 'rejected',
        };
      })
      .toList(growable: false);

  void _openReportSheet(Map<String, dynamic> report) {
    final palette = MdrrmoColors.of(context);
    final statusLabel = _formatStatusLabel(report['status']);
    final severityRaw = '${report['severity'] ?? 'medium'}';
    final severityLabel = severityRaw.isEmpty
        ? 'Medium'
        : '${severityRaw[0].toUpperCase()}${severityRaw.substring(1)}';
    final created = _formatTimestamp(report['created_at']);
    final adminNotes = '${report['admin_notes'] ?? ''}'.trim();
    final reviewer = '${report['reviewer_name'] ?? ''}'.trim();
    final outOfService = report['recommend_out_of_service'] == true;

    showAppSheet<void>(
      context,
      title:
          '${report['plate_number'] ?? 'Vehicle'} · ${report['issue_type'] ?? ''}',
      subtitle: report['reference']?.toString(),
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              AppStatusBadge(
                statusLabel,
                color: _statusColor(palette, report['status']),
                dot: true,
              ),
              AppStatusBadge(
                '$severityLabel severity',
                color: _severityColor(palette, severityRaw),
                icon: AppIcons.alert,
              ),
              if (outOfService)
                AppStatusBadge(
                  'Out-of-service flagged',
                  color: palette.warning,
                  icon: AppIcons.shieldAlert,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Surface(
            padding: const EdgeInsets.all(AppSpacing.md),
            tint: palette.surfaceSubtle,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if ('${report['vehicle_name'] ?? ''}'.trim().isNotEmpty)
                  _SheetDetailRow(
                    label: 'Vehicle',
                    value: '${report['vehicle_name']}',
                  ),
                if (report['mileage'] != null)
                  _SheetDetailRow(
                    label: 'Odometer',
                    value: '${report['mileage']} km',
                  ),
                if (created.isNotEmpty)
                  _SheetDetailRow(label: 'Submitted', value: created),
                if (reviewer.isNotEmpty)
                  _SheetDetailRow(label: 'Reviewed by', value: reviewer),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Observed issue',
            style: MdrrmoTypography.labelSm.copyWith(
              color: palette.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${report['description'] ?? 'No details recorded.'}',
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textPrimary,
              height: 1.45,
            ),
          ),
          if (adminNotes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppBanner(
              tone: report['status'] == 'rejected'
                  ? AppBannerTone.danger
                  : AppBannerTone.info,
              icon: AppIcons.infoCircle,
              title: reviewer.isNotEmpty ? 'Admin note · $reviewer' : 'Admin note',
              message: adminNotes,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ResponderScope.of(context);
    final palette = MdrrmoColors.of(context);
    final vehicles = _availableVehicles(state);
    final selectedVehicle =
        vehicles.where((v) => v.id == _vehicleId).firstOrNull ??
        vehicles.firstOrNull;
    if (selectedVehicle != null && _vehicleId == null) {
      _vehicleId = selectedVehicle.id;
    }

    if (!state.isDriver) {
      return AppScaffold(
        header: pushedHeader(context, 'Maintenance report'),
        child: const Center(
          child: ContentFrame(
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: AppStateView(
                icon: AppIcons.wrench,
                title: 'Driver role required',
                message:
                    'Maintenance reporting is restricted to the team Driver. Switch to the Driver role in Team if you need to report an ambulance issue.',
              ),
            ),
          ),
        ),
      );
    }

    final showSubmitBar = !_showHistory && vehicles.isNotEmpty;

    return AppScaffold(
      childPad: false,
      header: pushedHeader(context, 'Driver maintenance report'),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm + 2,
              AppSpacing.lg,
              AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: ContentFrame(
              child: Segmented<bool>(
                value: _showHistory,
                onChanged: (val) => setState(() => _showHistory = val),
                options: [
                  const SegmentOption(
                    false,
                    'New report',
                    icon: AppIcons.wrench,
                  ),
                  SegmentOption(
                    true,
                    _reports.isEmpty
                        ? 'History'
                        : 'History (${_reports.length})',
                    icon: AppIcons.history,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadReports(state),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                children: [
                  ContentFrame(
                    child: _showHistory
                        ? _buildHistorySection(palette)
                        : _buildFormSection(palette, vehicles, selectedVehicle),
                  ),
                ],
              ),
            ),
          ),
          if (showSubmitBar)
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border(top: BorderSide(color: palette.border)),
              ),
              child: ContentFrame(
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      label: _saving
                          ? 'Submitting…'
                          : 'Submit maintenance report',
                      icon: _saving ? null : AppIcons.send,
                      loading: _saving,
                      onPress: _saving ? null : _submit,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFormSection(
    MdrrmoColors palette,
    List<DriverVehicle> vehicles,
    DriverVehicle? selectedVehicle,
  ) {
    if (vehicles.isEmpty) {
      return const AppStateView(
        icon: AppIcons.ambulance,
        title: 'No vehicle assigned',
        message:
            'No vehicle is assigned to your team yet. Ask an Administrator to link an ambulance to your team.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AppBanner(
            tone: AppBannerTone.danger,
            icon: AppIcons.alert,
            message: _error!,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (selectedVehicle != null) ...[
          _VehicleSummaryCard(vehicle: selectedVehicle),
          const SizedBox(height: AppSpacing.lg),
        ],
        Form(
          key: _key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormGroup(
                title: 'Ambulance & issue classification',
                icon: AppIcons.wrench,
                fields: [
                  AppSelect(
                    label: 'Ambulance / Vehicle',
                    options: [
                      for (final v in vehicles)
                        '${v.number} · ${v.displayName}',
                    ],
                    value:
                        '${selectedVehicle!.number} · ${selectedVehicle.displayName}',
                    onChange: (value) {
                      final found = vehicles.firstWhere(
                        (v) => '${v.number} · ${v.displayName}' == value,
                        orElse: () => selectedVehicle,
                      );
                      setState(() => _vehicleId = found.id);
                    },
                  ),
                  AppSelect(
                    label: 'Issue category',
                    options: _issueTypes,
                    value: _issueType,
                    onChange: (value) => setState(() => _issueType = value),
                  ),
                  _SeveritySelector(
                    value: _severity,
                    onChanged: _saving
                        ? null
                        : (priority) => setState(() => _severity = priority),
                  ),
                ],
              ),
              FormGroup(
                title: 'Inspection details',
                icon: AppIcons.form,
                fields: [
                  AppTextField(
                    controller: _mileage,
                    label: 'Current mileage / odometer (km)',
                    hint: 'Optional, e.g. 45200',
                    keyboardType: TextInputType.number,
                    required: false,
                  ),
                  AppTextField(
                    controller: _description,
                    label: 'Issue description',
                    hint:
                        'Describe the mechanical or equipment issue observed',
                    maxLines: 4,
                    maxLength: 2000,
                    textInputAction: TextInputAction.newline,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Describe the maintenance issue'
                        : null,
                  ),
                ],
              ),
              Surface(
                padding: EdgeInsets.zero,
                tint: _recommendOutOfService
                    ? palette.warningTint
                    : palette.surface,
                borderColor: _recommendOutOfService
                    ? palette.warning.withValues(alpha: 0.45)
                    : palette.border,
                child: AppSwitchRow(
                  title: 'Recommend placing ambulance under maintenance',
                  subtitle:
                      'Flags this unit as out of service until cleared by Admin.',
                  value: _recommendOutOfService,
                  onChanged: _saving
                      ? null
                      : (val) => setState(() => _recommendOutOfService = val),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(MdrrmoColors palette) {
    final filtered = _filteredReports;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ResponderHeading(
          'Recent maintenance reports',
          subtitle: 'Track Admin review, maintenance status, and notes.',
        ),
        if (_reports.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final filter in _MaintenanceFilter.values) ...[
                  _FilterPill(
                    label: switch (filter) {
                      _MaintenanceFilter.all => 'All (${_reports.length})',
                      _MaintenanceFilter.pending => 'Pending',
                      _MaintenanceFilter.active => 'In service',
                      _MaintenanceFilter.closed => 'Closed',
                    },
                    selected: _historyFilter == filter,
                    onTap: () => setState(() => _historyFilter = filter),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_loadingReports && _reports.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_reports.isEmpty)
          const AppStateView(
            icon: AppIcons.wrench,
            title: 'No maintenance reports yet',
            message:
                'Submitted maintenance requests for your ambulance will appear here.',
          )
        else if (filtered.isEmpty)
          AppStateView(
            icon: AppIcons.filter,
            title: 'No matching reports',
            message: 'No maintenance reports match this status filter.',
            action: AppButton(
              label: 'Show all reports',
              kind: AppButtonKind.outline,
              onPress: () =>
                  setState(() => _historyFilter = _MaintenanceFilter.all),
            ),
          )
        else
          for (final report in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _MaintenanceReportCard(
                report: report,
                statusColor: _statusColor(palette, report['status']),
                statusLabel: _formatStatusLabel(report['status']),
                severityColor: _severityColor(palette, report['severity']),
                timestamp: _formatTimestamp(report['created_at']),
                onTap: () => _openReportSheet(report),
              ),
            ),
      ],
    );
  }
}

class _VehicleSummaryCard extends StatelessWidget {
  const _VehicleSummaryCard({required this.vehicle});
  final DriverVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final statusLower = vehicle.status.toLowerCase().trim();
    final statusColor = switch (statusLower) {
      'available' => palette.success,
      'maintenance' || 'offline' => palette.warning,
      _ => palette.brand,
    };

    return Surface(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      tint: palette.surfaceSubtle,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.brandTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(AppIcons.ambulance, size: 22, color: palette.brand),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vehicle.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MdrrmoTypography.titleMd.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Plate No: ${vehicle.number}',
                  style: MdrrmoTypography.tabular(
                    MdrrmoTypography.bodySm.copyWith(
                      color: palette.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppStatusBadge(vehicle.status, color: statusColor, dot: true),
        ],
      ),
    );
  }
}

class _SeveritySelector extends StatelessWidget {
  const _SeveritySelector({required this.value, required this.onChanged});

  final Priority value;
  final ValueChanged<Priority>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final hint = switch (value) {
      Priority.low => 'Minor issue; vehicle remains safe for service.',
      Priority.medium => 'Needs attention soon; monitor during shifts.',
      Priority.high => 'Urgent issue affecting performance or safety.',
      Priority.critical => 'Unsafe to operate; immediate maintenance required.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Severity',
          style: MdrrmoTypography.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (var i = 0; i < Priority.values.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: _SeverityOptionTile(
                  priority: Priority.values[i],
                  selected: Priority.values[i] == value,
                  onTap: onChanged == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onChanged!(Priority.values[i]);
                        },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          hint,
          style: MdrrmoTypography.labelSm.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SeverityOptionTile extends StatelessWidget {
  const _SeverityOptionTile({
    required this.priority,
    required this.selected,
    required this.onTap,
  });

  final Priority priority;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final accent = switch (priority) {
      Priority.low => palette.success,
      Priority.medium => palette.warning,
      Priority.high || Priority.critical => palette.danger,
    };

    return Semantics(
      button: true,
      selected: selected,
      label: '${priorityLabel(priority)} severity',
      child: Material(
        color: selected
            ? accent.withValues(alpha: palette.isDark ? 0.24 : 0.12)
            : palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? accent : palette.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                priorityLabel(priority),
                style: MdrrmoTypography.labelSm.copyWith(
                  color: selected ? accent : palette.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Material(
      color: selected ? palette.brand : palette.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: selected ? palette.brand : palette.border,
            ),
          ),
          child: Text(
            label,
            style: MdrrmoTypography.labelSm.copyWith(
              color: selected ? palette.brandOn : palette.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _MaintenanceReportCard extends StatelessWidget {
  const _MaintenanceReportCard({
    required this.report,
    required this.statusColor,
    required this.statusLabel,
    required this.severityColor,
    required this.timestamp,
    required this.onTap,
  });

  final Map<String, dynamic> report;
  final Color statusColor;
  final String statusLabel;
  final Color severityColor;
  final String timestamp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final reference = '${report['reference'] ?? ''}'.trim();
    final severity = '${report['severity'] ?? ''}'.trim();
    final adminNotes = '${report['admin_notes'] ?? ''}'.trim();
    final outOfService = report['recommend_out_of_service'] == true;
    final mileage = report['mileage'];

    return ResponderPanel(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      accent: statusColor,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (reference.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceSubtle,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          reference,
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.labelSm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    if (severity.isNotEmpty)
                      AppStatusBadge(
                        '${severity[0].toUpperCase()}${severity.substring(1)}',
                        color: severityColor,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              AppStatusBadge(statusLabel, color: statusColor, dot: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${report['plate_number'] ?? 'Vehicle'} · ${report['issue_type'] ?? ''}',
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${report['description'] ?? ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MdrrmoTypography.bodySm.copyWith(
              color: palette.textSecondary,
              height: 1.4,
            ),
          ),
          if (mileage != null || outOfService || timestamp.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (mileage != null)
                  Text(
                    '$mileage km',
                    style: MdrrmoTypography.tabular(
                      MdrrmoTypography.labelSm.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                if (outOfService)
                  Text(
                    'Out-of-service flagged',
                    style: MdrrmoTypography.labelSm.copyWith(
                      color: palette.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (timestamp.isNotEmpty)
                  Text(
                    timestamp,
                    style: MdrrmoTypography.labelSm.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ],
          if (adminNotes.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: palette.brandTint,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: palette.brand.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    AppIcons.infoCircle,
                    size: 15,
                    color: palette.brand,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      adminNotes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SheetDetailRow extends StatelessWidget {
  const _SheetDetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: MdrrmoTypography.bodySm.copyWith(color: palette.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
