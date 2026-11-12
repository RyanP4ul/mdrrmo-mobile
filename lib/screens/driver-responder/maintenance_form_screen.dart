import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/form_page.dart';
import '../../ui/kit.dart';
import 'responder_widgets.dart';

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

  void _openReportSheet(Map<String, dynamic> report) {
    final palette = MdrrmoColors.of(context);
    final status = '${report['status'] ?? 'pending'}'.replaceAll('_', ' ');
    showAppSheet<void>(
      context,
      title: '${report['plate_number'] ?? 'Vehicle'} · ${report['issue_type'] ?? ''}',
      subtitle: report['reference']?.toString(),
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: AppStatusBadge(
              status,
              color: _statusColor(palette, report['status']),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${report['description'] ?? 'No details recorded.'}',
            style: MdrrmoTypography.bodyMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          if (report['mileage'] != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Odometer reading: ${report['mileage']} km',
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          if (report['admin_notes'] != null &&
              '${report['admin_notes']}'.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppBanner(
              tone: AppBannerTone.info,
              icon: AppIcons.infoCircle,
              title: 'Admin note',
              message: '${report['admin_notes']}',
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

    return AppScaffold(
      header: pushedHeader(context, 'Driver maintenance report'),
      child: RefreshIndicator(
        onRefresh: () => _loadReports(state),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            ContentFrame(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Segmented<bool>(
                    value: _showHistory,
                    onChanged: (val) => setState(() => _showHistory = val),
                    options: [
                      const SegmentOption(false, 'New report'),
                      SegmentOption(
                        true,
                        _reports.isEmpty
                            ? 'History'
                            : 'History (${_reports.length})',
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_showHistory) ...[
                    const ResponderHeading(
                      'Recent maintenance reports',
                      subtitle: 'Track Admin review and approval status.',
                    ),
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
                    else
                      for (final report in _reports)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: ResponderPanel(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            onTap: () => _openReportSheet(report),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${report['plate_number'] ?? 'Vehicle'} · ${report['issue_type'] ?? ''}',
                                        style: MdrrmoTypography.titleMd.copyWith(
                                          color: palette.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    AppStatusBadge(
                                      '${report['status'] ?? 'pending'}'
                                          .replaceAll('_', ' '),
                                      color: _statusColor(
                                        palette,
                                        report['status'],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  '${report['description'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: MdrrmoTypography.bodySm.copyWith(
                                    color: palette.textSecondary,
                                  ),
                                ),
                                if (report['admin_notes'] != null &&
                                    '${report['admin_notes']}'
                                        .trim()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    'Admin note: ${report['admin_notes']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: MdrrmoTypography.labelSm.copyWith(
                                      color: palette.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                  ] else ...[
                    if (_error != null) ...[
                      AppBanner(
                        tone: AppBannerTone.danger,
                        icon: AppIcons.alert,
                        message: _error!,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (vehicles.isEmpty)
                      const AppStateView(
                        icon: AppIcons.ambulance,
                        title: 'No vehicle assigned',
                        message:
                            'No vehicle is assigned to your team yet. Ask an Administrator to link an ambulance to your team.',
                      )
                    else
                      Form(
                        key: _key,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FormGroup(
                              title: 'Ambulance & issue details',
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
                                      (v) =>
                                          '${v.number} · ${v.displayName}' ==
                                          value,
                                      orElse: () => selectedVehicle,
                                    );
                                    setState(() => _vehicleId = found.id);
                                  },
                                ),
                                AppSelect(
                                  label: 'Issue category',
                                  options: _issueTypes,
                                  value: _issueType,
                                  onChange: (value) =>
                                      setState(() => _issueType = value),
                                ),
                                AppSelect(
                                  label: 'Severity',
                                  options: const [
                                    'Low',
                                    'Medium',
                                    'High',
                                    'Critical',
                                  ],
                                  value: priorityLabel(_severity),
                                  onChange: (value) => setState(
                                    () => _severity = Priority.values.firstWhere(
                                      (priority) =>
                                          priorityLabel(priority) == value,
                                    ),
                                  ),
                                ),
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
                                  validator: (value) =>
                                      value == null || value.trim().isEmpty
                                      ? 'Describe the maintenance issue'
                                      : null,
                                ),
                                AppSwitchRow(
                                  title:
                                      'Recommend placing ambulance under maintenance',
                                  subtitle:
                                      'Flags this unit as out of service until cleared by Admin.',
                                  value: _recommendOutOfService,
                                  onChanged: _saving
                                      ? null
                                      : (val) => setState(
                                          () => _recommendOutOfService = val,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            AppButton(
                              label: _saving
                                  ? 'Submitting…'
                                  : 'Submit maintenance report',
                              loading: _saving,
                              onPress: _saving ? null : _submit,
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
