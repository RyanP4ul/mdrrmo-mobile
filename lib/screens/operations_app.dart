import 'package:dio/dio.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../ui/data_refresh.dart';
import '../ui/kit.dart';
import '../ui/logout_action.dart';
import 'account_screen.dart';
import 'fleet_map_screen.dart';
import 'record_browser_screen.dart';
import 'record_details_screen.dart';
import 'voice_calls_screen.dart';

class OperationsApp extends StatefulWidget {
  const OperationsApp({super.key, required this.role});
  final String role;
  @override
  State<OperationsApp> createState() => _OperationsAppState();
}

class _OperationsAppState extends State<OperationsApp> {
  final _cancel = CancelToken();
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false;
  bool get _admin => widget.role == 'admin';
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '/operations/dashboard',
        cancelToken: _cancel,
      );
      if (mounted) setState(() => _data = response.data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return DataRefresh(
      onRefresh: _load,
      child: AppScaffold(
        header: FHeader(
          title: Row(
            children: [
              const LogoMark(size: 28),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _admin ? 'MDRRMO Admin' : 'MDRRMO Dispatcher',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          suffixes: [
            if (!_admin) const VoiceCallsButton(dispatcher: true),
            FHeaderAction(
              icon: const Icon(AppIcons.refresh),
              onPress: _busy ? null : _load,
            ),
            FHeaderAction(
              icon: const Icon(AppIcons.user),
              onPress: () => _open(const AccountScreen()),
            ),
            FHeaderAction(
              icon: const Icon(AppIcons.logout),
              onPress: () => logoutFrom(context),
            ),
          ],
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxxl,
          ),
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_error != null) ...[
              AppBanner(
                tone: AppBannerTone.danger,
                icon: AppIcons.wifiOff,
                message: apiErrorMessage(_error!),
                action: TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('Retry'),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (_data != null) ...[
              Surface(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${_data!['name']}',
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final entry in {
                      'Pending reports': _data!['pending_reports'],
                      'Active dispatches': _data!['active_dispatches'],
                      'Pending schedules': _data!['pending_schedules'],
                      'Pending residents': _data!['pending_residents'],
                      'Active drivers / responders':
                          _data!['active_responders'],
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(
                          '${entry.key}: ${entry.value}',
                          style: MdrrmoTypography.bodyMd.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Automatic dispatch: ${_data!['automatic_dispatch'] == true ? 'Enabled' : 'Off'}',
                      style: MdrrmoTypography.bodySm.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _data!['automatic_dispatch'] == true
                            ? palette.success
                            : palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${_data!['dispatch_policy']}',
                      style: MdrrmoTypography.labelSm.copyWith(
                        fontWeight: FontWeight.w400,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            Text(
              'Operations modules',
              style: MdrrmoTypography.titleMd.copyWith(
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          _button(
            'Reports and dispatch',
            () => _open(
              RecordBrowserScreen(
                title: 'Reports and dispatch',
                path: '/operations/reports',
                filters: {
                  'status': {
                    for (final s in [
                      'pending',
                      'acknowledged',
                      'dispatched',
                      'resolved',
                      'invalid',
                      'withdrawn',
                    ])
                      s: s,
                  },
                },
                label: (r) => '${r['reference']} - ${r['status']}',
                subtitle: (r) => '${r['type']} - ${r['location']}',
                onOpen: (context, r) => _report(context, r['id'] as int),
              ),
            ),
          ),
          _button(
            'Service schedules',
            () => _open(
              RecordBrowserScreen(
                title: 'Service schedules',
                path: '/operations/schedules',
                filters: {
                  'status': {
                    for (final s in [
                      'pending',
                      'confirmed',
                      'declined',
                      'completed',
                      'cancelled',
                    ])
                      s: s,
                  },
                },
                label: (r) => '${r['service_type']} - ${r['status']}',
                subtitle: (r) => '${r['address']} - ${r['preferred_date']}',
                onOpen: _schedule,
              ),
            ),
          ),
          _button(
            'Response teams and shifts',
            () => _open(
              RecordBrowserScreen(
                title: 'Response teams',
                path: '/operations/teams',
                label: (r) => '#${r['id']} ${r['team_name']} - ${r['status']}',
                subtitle: (r) =>
                    'Capabilities: ${(r['specializations'] as List?)?.join(', ') ?? 'None configured'}',
                onCreate: (context) => _teamForm(context),
                onOpen: (context, r) => _team(context, r['id'] as int),
              ),
            ),
          ),
          _button(
            'Driver / Responder locations',
            () => _open(const FleetMapScreen()),
          ),
          if (_admin) ...[
            for (final role in [
              'resident',
              'driver/responder',
              'dispatcher',
              'admin',
            ])
              _button(
                '${role == 'resident' ? 'Resident approvals' : 'Accounts'}: $role',
                () => _open(_accounts(role)),
              ),
            _button(
              'Vehicle management',
              () => _open(
                RecordBrowserScreen(
                  title: 'Vehicle management',
                  path: '/operations/vehicles',
                  filters: {
                    'status': {
                      for (final s in [
                        'available',
                        'maintenance',
                        'offline',
                        'en-route',
                        'on-scene',
                      ])
                        s: s,
                    },
                  },
                  label: (r) =>
                      '${r['name'] ?? r['type']} (${r['number']}) - ${r['status']}',
                  subtitle: (r) =>
                      'Team: ${r['team_name'] ?? 'Unassigned'}${r['maintenance_warning'] != null ? '\nWarning: ${r['maintenance_warning']}' : ''}',
                  onCreate: (context) => _vehicleForm(context),
                  onOpen: (context, r) => _vehicleForm(context, r),
                ),
              ),
            ),
            _button(
              'Maintenance reports',
              () => _open(
                RecordBrowserScreen(
                  title: 'Maintenance reports',
                  path: '/operations/maintenance-reports',
                  filters: {
                    'status': {
                      for (final s in [
                        'pending',
                        'acknowledged',
                        'approved',
                        'in_maintenance',
                        'resolved',
                        'rejected',
                      ])
                        s: s,
                    },
                  },
                  label: (r) =>
                      '${r['reference']} • ${r['vehicle_number'] ?? 'Ambulance'} - ${r['status']}',
                  subtitle: (r) =>
                      '${r['issue_type']} (${r['severity']}) • Reported by ${r['reporter_name'] ?? 'Driver'}\n${r['description'] ?? ''}',
                  onOpen: (context, r) => _reviewMaintenance(context, r),
                ),
              ),
            ),
            _button(
              'Incident categories',
              () => _open(
                RecordBrowserScreen(
                  title: 'Incident categories',
                  path: '/operations/incident-types',
                  label: (r) => '${r['name']} - ${r['priority']}',
                  subtitle: (r) => '${r['description']}',
                  onCreate: (context) => _typeForm(context),
                  onOpen: (context, r) => _type(context, r),
                ),
              ),
            ),
            _button(
              'Audit logs',
              () => _open(
                RecordBrowserScreen(
                  title: 'Audit logs',
                  path: '/operations/audit-logs',
                  label: (r) => '${r['action']} - ${r['user_name']}',
                  subtitle: (r) => '${r['details']}\n${r['created_at']}',
                ),
              ),
            ),
            _button('Automatic dispatch settings', () => _automatic(context)),
          ],
          _button('Retry waiting automatic dispatches', () async {
            try {
              final response = await dio.post<Map<String, dynamic>>(
                '/operations/automatic-dispatch/retry',
              );
              if (context.mounted) {
                snack(
                  context,
                  '${response.data?['dispatched']} report(s) dispatched.',
                );
              }
              await _load();
            } catch (error) {
              if (context.mounted) snack(context, apiErrorMessage(error));
            }
          }),
        ],
      ),
    ),
  );
  }
  Widget _button(String label, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppButton(label: label, onPress: _busy ? null : action),
  );

  Future<void> _report(
    BuildContext context,
    int id,
  ) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OperationsDetails(
        title: 'Report details',
        path: '/operations/reports/$id',
        fields: const [
          'reference',
          'type',
          'status',
          'priority',
          'location',
          'description',
          'reporter_name',
          'reporter_contact',
          'reported_at',
          'acknowledged_at',
          'resolved_at',
          'withdrawn_at',
          'withdrawal_reason',
          'team_name',
          'driver_name',
          'automatic_dispatch',
          'victim_info',
          'patient_form',
        ],
        actions: (context, r, run) => [
          if (!_admin &&
              ['pending', 'acknowledged', 'dispatched'].contains(r['status']))
            TextButton.icon(
              icon: const Icon(AppIcons.phoneCall),
              label: const Text('Three-way voice call'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      VoiceCallsScreen(dispatcher: true, reportId: id),
                ),
              ),
            ),
          if (r['status'] == 'pending')
            TextButton(
              onPressed: () => run(() async {
                await dio.patch(
                  '/operations/reports/$id',
                  data: {'status': 'acknowledged'},
                );
              }),
              child: const Text('Acknowledge'),
            ),
          if ([
            'pending',
            'acknowledged',
            'dispatched',
          ].contains(r['status'])) ...[
            TextButton(
              onPressed: () => run(() async {
                final team = await pickRecord(
                  context,
                  title: 'Choose response team',
                  path: '/operations/teams',
                  label: (r) => '${r['team_name']} - ${r['status']}',
                );
                if (team != null && context.mounted) {
                  final yes = await confirmDialog(
                    context,
                    title: 'Dispatch this team?',
                    body:
                        'Assign ${team['team_name']} to ${r['reference']}? This updates the website and responder assignment.',
                    confirmLabel: 'Dispatch',
                  );
                  if (yes) {
                    await dio.post(
                      '/operations/reports/$id/assign',
                      data: {'team_id': team['id']},
                    );
                  }
                }
              }),
              child: const Text('Assign response team'),
            ),
            TextButton(
              onPressed: () => run(() async {
                final yes = await confirmDialog(
                  context,
                  title: 'Mark report invalid?',
                  body: 'This ends any active assignment for this report.',
                  confirmLabel: 'Mark invalid',
                );
                if (yes) {
                  await dio.patch(
                    '/operations/reports/$id',
                    data: {'status': 'invalid'},
                  );
                }
              }),
              child: const Text('Mark invalid'),
            ),
          ],
          if (_admin && r['status'] == 'dispatched')
            TextButton(
              onPressed: () => run(() async {
                final yes = await confirmDialog(
                  context,
                  title: 'Close dispatch?',
                  body: 'Mark this response resolved and release the assigned driver/responder?',
                  confirmLabel: 'Resolve',
                );
                if (yes) {
                  await dio.patch(
                    '/operations/reports/$id',
                    data: {'status': 'resolved'},
                  );
                }
              }),
              child: const Text('Resolve dispatch'),
            ),
        ],
      ),
    ),
  );

  Future<void> _schedule(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    final id = record['id'];
    final needsAssignment =
        record['status'] == 'confirmed' && record['responders_count'] == 0;
    if (![
      'pending',
      'acknowledged',
      'confirmed',
      'en-route',
      'on-scene',
    ].contains(record['status'])) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Schedule #$id - ${record['status']}'),
          content: SingleChildScrollView(
            child: SelectableText(
              '${record['service_type']}\n${record['address']}\n${record['preferred_date']} ${record['preferred_time']}\nNotes: ${record['notes'] ?? 'None'}\nReason: ${record['decline_reason'] ?? 'None'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Review schedule #$id',
          initial: {
            'decision': record['status'] == 'pending'
                ? 'acknowledged'
                : record['status'] == 'acknowledged' || needsAssignment
                ? 'confirmed'
                : 'completed',
          },
          notice:
              '${record['service_type']}\n${record['address']}\n${record['preferred_date']} ${record['preferred_time']}\nNotes: ${record['notes'] ?? 'None'}\nResident: ${(record['resident'] as Map?)?['full_name'] ?? ''}',
          fields: [
            EditField(
              'decision',
              'Decision',
              options: record['status'] == 'pending'
                  ? {'acknowledged': 'Acknowledge', 'declined': 'Decline'}
                  : record['status'] == 'acknowledged'
                  ? {
                      'confirmed': 'Assign team and confirm',
                      'declined': 'Decline',
                    }
                  : needsAssignment
                  ? {'confirmed': 'Assign response team'}
                  : {'completed': 'Complete'},
            ),
            const EditField(
              'reason',
              'Reason (required when declining)',
              max: 500,
              lines: 3,
              required: false,
            ),
          ],
          save: (values) async {
            if (values['decision'] == 'confirmed') {
              final team = await pickRecord(
                context,
                title: 'Choose response team',
                path: '/operations/teams',
                label: (team) => '${team['team_name']} - ${team['status']}',
              );
              if (team == null) {
                throw StateError(
                  'Choose a response team to confirm the service.',
                );
              }
              values['team_id'] = team['id'];
            }
            await dio.patch('/operations/schedules/$id', data: values);
          },
        ),
      ),
    );
  }

  RecordBrowserScreen _accounts(String role) => RecordBrowserScreen(
    title: '$role accounts',
    path: '/operations/accounts',
    fixed: {'role': role},
    filters: role == 'resident'
        ? {
            'registration_status': {
              for (final s in ['pending', 'accepted', 'declined']) s: s,
            },
          }
        : const {},
    label: (r) => '${r['name']} - ${r['registration_status'] ?? r['status']}',
    subtitle: (r) => '${r['email']} | ${r['contact_number']}',
    onCreate: (context) => _accountForm(context, role),
    onOpen: (context, r) async {
      if (role == 'resident') {
        final choice = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text('${r['name']}'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'accepted'),
                child: const Text('Approve registration'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'declined'),
                child: const Text('Decline registration'),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'edit'),
                child: const Text('Edit account'),
              ),
            ],
          ),
        );
        if (choice == null || !context.mounted) return;
        if (choice != 'edit') {
          try {
            await dio.patch(
              '/operations/accounts/${r['account_key']}/review',
              data: {'decision': choice},
            );
          } catch (error) {
            if (context.mounted) snack(context, apiErrorMessage(error));
          }
          return;
        }
      }
      if (context.mounted) await _accountForm(context, role, r);
    },
  );
  Future<void> _accountForm(
    BuildContext context,
    String role, [
    Map<String, dynamic>? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: record == null ? 'Create $role account' : 'Edit account',
          initial: {'status': 'active', ...?record},
          fields: [
            const EditField('first_name', 'First name', max: 60),
            const EditField('last_name', 'Last name', max: 60),
            const EditField('email', 'Email'),
            const EditField('contact_number', 'PH contact number', max: 20),
            const EditField(
              'status',
              'Account status',
              options: {
                'active': 'Active',
                'inactive': 'Inactive',
                'suspended': 'Suspended',
              },
            ),
            if (record == null)
              const EditField(
                'password',
                'Initial password (at least 8 characters)',
                secret: true,
                max: 128,
              ),
            const EditField('barangay', 'Barangay', required: false, max: 120),
            const EditField('city', 'City', required: false, max: 120),
            const EditField('province', 'Province', required: false, max: 120),
          ],
          save: (values) async {
            values['role'] = role;
            if (record == null) {
              await dio.post('/operations/accounts', data: values);
            } else {
              await dio.put(
                '/operations/accounts/${record['account_key']}',
                data: values,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _teamForm(
    BuildContext context, [
    Map<String, dynamic>? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: record == null ? 'Create response team' : 'Edit response team',
          initial: {
            'status': 'active',
            ...?record,
            'capabilities':
                (record?['specializations'] as List?)?.join(', ') ?? '',
          },
          notice: 'Enter exact incident category names separated by commas, or * to declare capability for all incident types. Automatic dispatch requires a matching capability and a current on-shift driver.',
          fields: const [
            EditField('team_name', 'Team name', max: 120),
            EditField(
              'status',
              'Status',
              options: {
                'active': 'Active',
                'inactive': 'Inactive',
                'on-leave': 'On leave',
                'off-duty': 'Off duty',
              },
            ),
            EditField(
              'capabilities',
              'Incident capabilities (comma separated)',
              max: 2000,
              lines: 3,
              required: false,
            ),
          ],
          save: (values) async {
            values['specializations'] =
                (values.remove('capabilities') as String)
                    .split(',')
                    .map((v) => v.trim())
                    .where((v) => v.isNotEmpty)
                    .toSet()
                    .toList();
            if (record == null) {
              await dio.post('/operations/teams', data: values);
            } else {
              await dio.put('/operations/teams/${record['id']}', data: values);
            }
          },
        ),
      ),
    );
  }

  Future<void> _team(BuildContext context, int id) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OperationsDetails(
            title: 'Team and shift roster',
            path: '/operations/teams/$id',
            fields: const [
              'team_name',
              'status',
              'specializations',
              'members',
              'shifts',
            ],
            actions: (context, r, run) => [
              TextButton(
                onPressed: () => run(() => _teamForm(context, r)),
                child: const Text('Edit team'),
              ),
              TextButton(
                onPressed: () => run(() => _memberForm(context, id)),
                child: const Text('Add team member'),
              ),
              for (final member in (r['members'] as List? ?? []))
                TextButton(
                  onPressed: () => run(
                    () => _memberForm(
                      context,
                      id,
                      Map<String, dynamic>.from(member as Map),
                    ),
                  ),
                  child: Text('Edit ${member['name']}'),
                ),
              TextButton(
                onPressed: () => run(() => _shiftForm(context, id, r)),
                child: const Text('Create shift'),
              ),
              for (final shift in (r['shifts'] as List? ?? []))
                TextButton(
                  onPressed: () => run(
                    () => _shiftForm(
                      context,
                      id,
                      r,
                      Map<String, dynamic>.from(shift as Map),
                    ),
                  ),
                  child: Text('Edit shift #${shift['id']}'),
                ),
            ],
          ),
        ),
      );
  Future<void> _memberForm(
    BuildContext context,
    int team, [
    Map<String, dynamic>? member,
  ]) async {
    final linked = await pickRecord(
      context,
      title: 'Choose linked driver/responder',
      path: '/operations/drivers',
      label: (r) => '${r['name']} - ${r['contact_number']}',
    );
    if (linked == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Team member',
          initial: {
            'name': linked['name'],
            'status': 'active',
            'role': 'Driver/Responder',
            ...?member,
            if (member != null &&
                [
                  'Driver',
                  'Responder',
                  'Driver/Responder',
                ].contains(member['role']))
              'role': 'Driver/Responder',
          },
          fields: const [
            EditField('name', 'Roster name', max: 120),
            EditField(
              'role',
              'Role',
              options: {
                'Driver/Responder': 'Driver/Responder',
                'Medic': 'Medic',
                'Team leader': 'Team leader',
              },
            ),
            EditField(
              'status',
              'Status',
              options: {
                'active': 'Active',
                'inactive': 'Inactive',
                'on-leave': 'On leave',
                'off-duty': 'Off duty',
              },
            ),
          ],
          save: (values) async {
            values['user_id'] = linked['id'];
            if (member == null) {
              await dio.post('/operations/teams/$team/members', data: values);
            } else {
              await dio.put(
                '/operations/teams/$team/members/${member['id']}',
                data: values,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _shiftForm(
    BuildContext context,
    int team,
    Map<String, dynamic> record, [
    Map<String, dynamic>? shift,
  ]) async {
    final members = record['members'] as List? ?? [];
    if (members.isEmpty) {
      snack(context, 'Add team members first.');
      return;
    }
    final selected = (shift?['members'] as List? ?? [])
        .map((m) => m['id'] as int)
        .toSet();
    final ids = await showDialog<Set<int>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: const Text('Shift roster'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final m in members)
                    CheckboxListTile(
                      title: Text('${m['name']} (${m['role']})'),
                      value: selected.contains(m['id']),
                      onChanged: (value) => set(() {
                        if (value == true) {
                          selected.add(m['id'] as int);
                        } else {
                          selected.remove(m['id']);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
    if (ids == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Team shift',
          initial: {'status': 'off-shift', ...?shift},
          notice: 'Enter actual start/end times with a timezone. Only on-shift roster members in the current time window can be automatically dispatched.',
          fields: const [
            EditField(
              'start_time',
              'Shift start (ISO date/time)',
              timestamp: true,
            ),
            EditField('end_time', 'Shift end (ISO date/time)', timestamp: true),
            EditField(
              'status',
              'Shift status',
              options: {
                'on-shift': 'On shift',
                'off-shift': 'Off shift',
                'on-break': 'On break',
              },
            ),
          ],
          save: (values) async {
            values['member_ids'] = ids.toList();
            for (final field in ['start_time', 'end_time']) {
              values[field] = DateTime.parse(values[field] as String)
                  .toUtc()
                  .toIso8601String();
            }
            if (shift == null) {
              await dio.post('/operations/teams/$team/shifts', data: values);
            } else {
              await dio.put(
                '/operations/teams/$team/shifts/${shift['id']}',
                data: values,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _typeForm(
    BuildContext context, [
    Map<String, dynamic>? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Incident category',
          initial: {'color': '#6b7280', 'priority': 'high', ...?record},
          fields: const [
            EditField('name', 'Name', max: 80),
            EditField('description', 'Description', max: 500, lines: 3),
            EditField(
              'priority',
              'Priority',
              options: {
                'low': 'Low',
                'medium': 'Medium',
                'high': 'High',
                'critical': 'Critical',
              },
            ),
            EditField('color', 'Color (#RRGGBB)', max: 7),
          ],
          save: (values) async {
            if (record == null) {
              await dio.post('/operations/incident-types', data: values);
            } else {
              await dio.put(
                '/operations/incident-types/${record['id']}',
                data: values,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _type(BuildContext context, Map<String, dynamic> record) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('${record['name']}'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('Edit category'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Delete unused category'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'edit') {
      await _typeForm(context, record);
    } else if (choice == 'delete') {
      try {
        await dio.delete('/operations/incident-types/${record['id']}');
      } catch (error) {
        if (context.mounted) snack(context, apiErrorMessage(error));
      }
    }
  }

  Future<void> _automatic(BuildContext context) async {
    final enabled = _data?['automatic_dispatch'] == true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Automatic dispatch settings',
          initial: {'enabled': enabled ? 'true' : 'false'},
          notice: 'Enabling this processes new and existing pending reports under the displayed capability/shift/availability rules. Reports without an eligible resource stay pending. The scheduler retries waiting reports every minute; Retry waiting automatic dispatches can run it immediately.',
          fields: const [
            EditField(
              'enabled',
              'Automatic dispatch',
              options: {
                'false': 'Off - staff dispatch manually',
                'true': 'Enabled',
              },
            ),
            EditField(
              'current_password',
              'Administrator password',
              secret: true,
              max: 128,
            ),
          ],
          save: (values) async {
            values['enabled'] = values['enabled'] == 'true';
            await dio.put('/operations/automatic-dispatch', data: values);
          },
        ),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _vehicleForm(
    BuildContext context, [
    Map<String, dynamic>? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: record == null ? 'Add vehicle' : 'Edit vehicle',
          initial: {
            'status': 'available',
            'type': 'Ambulance',
            ...?record,
          },
          notice:
              'Manage ambulance availability, plate number, photo URL, and maintenance status. Setting status to maintenance prevents dispatch until resolved.',
          fields: const [
            EditField('name', 'Vehicle name (optional)', max: 120, required: false),
            EditField('number', 'Plate / unit number', max: 50),
            EditField('type', 'Vehicle type', max: 100),
            EditField(
              'response_team_id',
              'Assigned response team ID (optional)',
              numeric: true,
              required: false,
            ),
            EditField(
              'status',
              'Availability / status',
              options: {
                'available': 'Available',
                'maintenance': 'Under maintenance',
                'offline': 'Offline',
                'en-route': 'En route',
                'on-scene': 'On scene',
              },
            ),
            EditField(
              'photo_url',
              'Ambulance photo URL (optional)',
              max: 500,
              required: false,
            ),
            EditField(
              'maintenance_warning',
              'Maintenance warning banner (optional)',
              max: 500,
              lines: 3,
              required: false,
            ),
          ],
          save: (values) async {
            final teamRaw = values['response_team_id']?.toString().trim() ?? '';
            values['response_team_id'] =
                teamRaw.isEmpty ? null : int.tryParse(teamRaw);
            for (final key in ['name', 'photo_url', 'maintenance_warning']) {
              if ((values[key]?.toString().trim() ?? '').isEmpty) {
                values[key] = null;
              }
            }
            if (record == null) {
              await dio.post('/operations/vehicles', data: values);
            } else {
              await dio.put(
                '/operations/vehicles/${record['id']}',
                data: values,
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _reviewMaintenance(
    BuildContext context,
    Map<String, dynamic> record,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Review ${record['reference']}',
          initial: {
            'status': record['status'] == 'pending'
                ? 'acknowledged'
                : record['status'],
            'admin_notes': record['admin_notes'] ?? '',
          },
          notice:
              'Vehicle: ${record['vehicle_name'] ?? 'Ambulance'} (${record['vehicle_number'] ?? '-'})\n'
              'Team: ${record['team_name'] ?? 'Unassigned'}\n'
              'Reported by: ${record['reporter_name'] ?? 'Driver'}\n'
              'Issue: ${record['issue_type']} (${record['severity']})\n'
              'Out-of-service recommended: ${record['recommend_out_of_service'] == true ? 'Yes' : 'No'}\n'
              'Description: ${record['description'] ?? ''}',
          fields: const [
            EditField(
              'status',
              'Review decision / status',
              options: {
                'acknowledged': 'Acknowledge report',
                'approved': 'Approve for maintenance',
                'in_maintenance': 'Mark vehicle in maintenance',
                'resolved': 'Resolve & restore vehicle availability',
                'rejected': 'Reject report',
              },
            ),
            EditField(
              'admin_notes',
              'Admin review notes (optional)',
              max: 1000,
              lines: 3,
              required: false,
            ),
          ],
          save: (values) async {
            if ((values['admin_notes']?.toString().trim() ?? '').isEmpty) {
              values['admin_notes'] = null;
            }
            await dio.patch(
              '/operations/maintenance-reports/${record['id']}/review',
              data: values,
            );
          },
        ),
      ),
    );
  }
}

typedef OperationRunner = Future<void> Function(Future<void> Function());

class OperationsDetails extends StatefulWidget {
  const OperationsDetails({
    super.key,
    required this.title,
    required this.path,
    required this.fields,
    required this.actions,
  });
  final String title, path;
  final List<String> fields;
  final List<Widget> Function(
    BuildContext,
    Map<String, dynamic>,
    OperationRunner,
  )
  actions;
  @override
  State<OperationsDetails> createState() => _OperationsDetailsState();
}

class _OperationsDetailsState extends State<OperationsDetails> {
  final _cancel = CancelToken();
  Map<String, dynamic>? _data;
  Object? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await dio.get<Map<String, dynamic>>(
        widget.path,
        cancelToken: _cancel,
      );
      if (mounted) setState(() => _data = response.data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    header: pushedHeader(context, widget.title),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null) ...[
          AppBanner(
            tone: AppBannerTone.danger,
            icon: AppIcons.wifiOff,
            message: apiErrorMessage(_error!),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_data != null) ...[
          Surface(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final field in widget.fields)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      '${field.replaceAll('_', ' ')}: ${_readable(_data![field])}',
                      style: MdrrmoTypography.bodySm.copyWith(height: 1.45),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AbsorbPointer(
            absorbing: _busy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.actions(context, _data!, _run),
            ),
          ),
        ],
        TextButton(
          onPressed: _busy ? null : _load,
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
  String _readable(Object? value) {
    if (value == null) return 'Not recorded';
    if (value is Map) {
      return value.entries
          .where(
            (e) => ![
              'posted_by_type',
              'reported_by_type',
              'user_type',
              'password',
              'remember_token',
            ].contains(e.key),
          )
          .map(
            (e) =>
                '${e.key.toString().replaceAll('_', ' ')}: ${_readable(e.value)}',
          )
          .join('\n');
    }
    if (value is List) return value.map(_readable).join('\n');
    return '$value';
  }
}
