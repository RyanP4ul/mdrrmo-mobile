import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../data/input_validation.dart';
import '../data/resident_models.dart';
import '../services/route_navigation.dart';
import '../ui/data_refresh.dart';
import '../ui/kit.dart';
import '../ui/record_widgets.dart';
import '../widgets/res_widgets.dart';

/// Fetches an authorized record when opened, including from older notifications.
class RecordDetailsScreen extends StatefulWidget {
  const RecordDetailsScreen({
    super.key,
    required this.id,
    this.driver = false,
    this.schedule = false,
    this.onChanged,
  });

  final int id;
  final bool driver;
  final bool schedule;
  final Future<void> Function()? onChanged;

  @override
  State<RecordDetailsScreen> createState() => _RecordDetailsScreenState();
}

class _RecordDetailsScreenState extends State<RecordDetailsScreen> {
  final _cancel = CancelToken();
  Map<String, dynamic>? _record;
  Object? _error;
  bool _busy = false;

  String get _path =>
      '/${widget.driver ? 'driver-responder' : 'resident'}/${widget.schedule ? 'schedules' : 'reports'}/${widget.id}';

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
        _path,
        cancelToken: _cancel,
      );
      if (response.data == null) throw const FormatException('Missing record.');
      if (mounted) setState(() => _record = response.data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await widget.onChanged?.call();
      if (mounted) snack(context, 'Saved.');
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load();
  }

  Future<void> _edit() async {
    final record = _record!;
    final fields = <EditField>[];
    List<dynamic> types = [];
    if (!widget.schedule) {
      try {
        final response = await dio.get<Map<String, dynamic>>(
          '/resident/bootstrap',
          cancelToken: _cancel,
        );
        types = response.data!['incident_types'] as List;
      } catch (error) {
        if (mounted) snack(context, apiErrorMessage(error));
        return;
      }
      fields.add(
        EditField(
          'incident_type_id',
          'Incident type',
          options: {
            for (final type in types) '${type['id']}': '${type['name']}',
          },
        ),
      );
      fields.add(
        const EditField(
          'reporter_type',
          'Reporter type',
          options: {'victim': 'Victim', 'witness': 'Witness'},
        ),
      );
      fields.addAll(const [
        EditField('location', 'Incident location', max: 255),
        EditField('description', 'Description', max: 2000, lines: 4),
        EditField('lat', 'Latitude', numeric: true),
        EditField('lng', 'Longitude', numeric: true),
      ]);
    } else {
      fields.add(
        EditField(
          'service_type',
          'Service',
          options: {
            for (final type in SchedulePurpose.values) type.label: type.label,
          },
        ),
      );
      fields.addAll(const [
        EditField('address', 'Destination', max: 255),
        EditField('preferred_date', 'Date (YYYY-MM-DD)', date: true),
        EditField('preferred_time', 'Time (24-hour HH:mm)'),
        EditField('notes', 'Notes', max: 1000, lines: 3, required: false),
      ]);
    }
    final initial = Map<String, dynamic>.from(record);
    if (widget.schedule) {
      initial['preferred_date'] = '${record['preferred_date']}'.substring(
        0,
        10,
      );
      initial['preferred_time'] = '${record['preferred_time']}'.substring(0, 5);
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: widget.schedule ? 'Edit schedule' : 'Edit report',
          fields: fields,
          initial: initial,
          save: (values) async {
            if (!widget.schedule) {
              final latitude = double.tryParse('${values['lat']}');
              final longitude = double.tryParse('${values['lng']}');
              final error = latitude == null || longitude == null
                  ? 'Enter valid coordinates'
                  : InputValidation.coordinates(latitude, longitude);
              if (error != null) throw ArgumentError(error);
              values['lat'] = latitude;
              values['lng'] = longitude;
              values['incident_type_id'] = int.parse(
                values['incident_type_id'] as String,
              );
            }
            await dio.put(
              _path,
              data: {...values, 'revision': record['revision']},
              cancelToken: _cancel,
            );
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      await widget.onChanged?.call();
      await _load();
    }
  }

  Future<void> _withdraw() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ApiEditScreen(
          title: 'Withdraw pending report',
          fields: const [
            EditField('reason', 'Reason for withdrawal', max: 1000, lines: 4),
          ],
          initial: const {},
          notice: 'This ends the pending request. The report remains in your history. For an urgent change after dispatch, contact MDRRMO.',
          save: (values) async {
            await dio.patch(
              '$_path/withdraw',
              data: values,
              cancelToken: _cancel,
            );
          },
        ),
      ),
    );
    if (saved == true && mounted) {
      await widget.onChanged?.call();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final r = _record;
    return DataRefresh(
      onRefresh: _load,
      child: AppScaffold(
        header: pushedHeader(
          context,
          widget.schedule
              ? (widget.driver
                    ? 'Assigned service schedule'
                    : 'Schedule details')
              : 'Report details',
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              ContentFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_busy && _record == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_error != null) ...[
                      RecordMessage(
                        title: 'Could not refresh this record',
                        message: apiErrorMessage(_error!),
                        icon: AppIcons.wifiOff,
                        onRetry: _busy ? null : _load,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (r != null) ...[
                      Builder(
                        builder: (context) {
                          final rawStatus = '${r['status'] ?? 'Unknown'}';
                          final residentBadge = !widget.driver
                              ? residentStatusPresentation(
                                  rawStatus,
                                  palette,
                                  schedule: widget.schedule,
                                )
                              : null;
                          final overviewSubtitle = widget.driver
                              ? _driverStatusSummary(
                                  rawStatus,
                                  schedule: widget.schedule,
                                )
                              : _residentStatusSummary(
                                  rawStatus,
                                  schedule: widget.schedule,
                                );
                          return RecordOverview(
                            reference:
                                '${r['reference'] ?? '${widget.schedule ? 'Schedule' : 'Report'} #${widget.id}'}',
                            title:
                                '${widget.schedule ? r['service_type'] ?? 'Scheduled service' : r['type'] ?? 'Emergency report'}',
                            status: rawStatus,
                            statusLabel: residentBadge?.$1,
                            statusColor: residentBadge?.$2,
                            subtitle: overviewSubtitle,
                            priority: widget.schedule || !widget.driver
                                ? null
                                : r['priority']?.toString(),
                            color: palette.brand,
                          );
                        },
                      ),
                      if (widget.driver &&
                          widget.schedule &&
                          [
                            'confirmed',
                            'en-route',
                            'on-scene',
                          ].contains(r['status'])) ...[
                        AppButton(
                          label: switch (r['status']) {
                            'confirmed' => 'Start service trip',
                            'en-route' => 'Mark on scene',
                            _ => 'Complete service',
                          },
                          onPress: _busy
                              ? null
                              : () async {
                                  final next = switch (r['status']) {
                                    'confirmed' => 'en-route',
                                    'en-route' => 'on-scene',
                                    _ => 'completed',
                                  };
                                  final confirmed = await confirmDialog(
                                    context,
                                    title: 'Update service status?',
                                    body:
                                        'Mark this service as $next? The resident and your team will be notified.',
                                    confirmLabel: 'Confirm',
                                  );
                                  if (!confirmed || !mounted) return;
                                  await _action(() async {
                                    await dio.patch(
                                      '$_path/status',
                                      data: {'status': next},
                                      cancelToken: _cancel,
                                    );
                                  });
                                },
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          label: r['status'] == 'on-scene'
                              ? 'Navigate to destination'
                              : 'Navigate to pickup',
                          icon: AppIcons.navigation,
                          kind: AppButtonKind.outline,
                          onPress: _busy
                              ? null
                              : () async {
                                  final navInfo = scheduleNavFromRecord(
                                    r,
                                    onStatusUpdated: () async {
                                      await widget.onChanged?.call();
                                      if (mounted) await _load();
                                    },
                                  );
                                  await navigateToDestination(
                                    context,
                                    address: r['status'] == 'on-scene' &&
                                            (navInfo?.destinationAddress
                                                    .isNotEmpty ??
                                                false)
                                        ? navInfo!.destinationAddress
                                        : '${r['pickup_address'] ?? r['address'] ?? ''}',
                                    schedule: navInfo,
                                  );
                                },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _RecordInformation(
                        record: r,
                        schedule: widget.schedule,
                        driver: widget.driver,
                      ),
                      if ((r['can_edit'] == true &&
                              (widget.driver || widget.schedule)) ||
                          (r['can_edit'] == true && !widget.schedule) ||
                          (!widget.driver &&
                              widget.schedule &&
                              [
                                'pending',
                                'acknowledged',
                                'confirmed',
                              ].contains(r['status']))) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AppSectionGroup(
                          children: [
                            if (r['can_edit'] == true &&
                                (widget.driver || widget.schedule))
                              AppRowItem(
                                title: widget.driver ? 'Edit' : 'Edit request',
                                subtitle: widget.schedule
                                    ? 'Update preferred date, time, or notes'
                                    : 'Update incident details',
                                showChevron: true,
                                enabled: !_busy,
                                onTap: _busy ? null : _edit,
                              ),
                            if (r['can_edit'] == true && !widget.schedule)
                              AppRowItem(
                                title: widget.driver
                                    ? 'Withdraw pending report'
                                    : 'Cancel pending report',
                                destructive: true,
                                enabled: !_busy,
                                onTap: _busy ? null : _withdraw,
                              ),
                            if (!widget.driver &&
                                widget.schedule &&
                                [
                                  'pending',
                                  'acknowledged',
                                  'confirmed',
                                ].contains(r['status']))
                              AppRowItem(
                                title: 'Cancel request',
                                destructive: true,
                                enabled: !_busy,
                                onTap: _busy
                                    ? null
                                    : () async {
                                        final confirm = await confirmDialog(
                                          context,
                                          title: 'Cancel this request?',
                                          body:
                                              'This cancels your scheduled assistance request with MDRRMO.',
                                          confirmLabel: 'Cancel request',
                                          destructive: true,
                                        );
                                        if (confirm) {
                                          await _action(() async {
                                            await dio.patch(
                                              '$_path/cancel',
                                              cancelToken: _cancel,
                                            );
                                          });
                                        }
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      if (r['can_care'] == true ||
                          r['can_edit_trip'] == true ||
                          r['can_fill_patient_form'] == true)
                        TripSummary(
                          trip: r['trip'] is Map
                              ? Map<String, dynamic>.from(r['trip'] as Map)
                              : null,
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _driverStatusSummary(String rawStatus, {required bool schedule}) {
  return switch (rawStatus.toLowerCase()) {
    'pending' => 'Waiting for review or assignment.',
    'dispatched' => 'Assigned for emergency response.',
    'acknowledged' || 'confirmed' => schedule
        ? 'Confirmed schedule ready to start.'
        : 'Dispatch acknowledged.',
    'en-route' => 'Team is en route to the location.',
    'on-scene' => 'Team is currently on scene.',
    'resolved' || 'completed' => 'Completed and archived.',
    'withdrawn' || 'cancelled' || 'declined' || 'invalid' => 'Closed record.',
    _ => 'Record status details are listed below.',
  };
}

String _residentStatusSummary(String rawStatus, {required bool schedule}) {
  return switch (rawStatus.toLowerCase()) {
    'pending' => schedule
        ? 'MDRRMO has received your request and is reviewing the schedule.'
        : 'MDRRMO has received your report and is reviewing it now.',
    'dispatched' ||
    'acknowledged' ||
    'confirmed' ||
    'en-route' ||
    'on-scene' =>
      'A response team is assigned. See team details and live progress below.',
    'resolved' || 'completed' => 'This response has been completed.',
    'withdrawn' || 'cancelled' => 'This request was cancelled.',
    'declined' || 'invalid' => 'Closed by MDRRMO.',
    _ => 'Updates from MDRRMO appear below.',
  };
}

class _RecordInformation extends StatelessWidget {
  const _RecordInformation({
    required this.record,
    required this.schedule,
    required this.driver,
  });

  final Map<String, dynamic> record;
  final bool schedule, driver;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final r = record;
    final activity = <String, dynamic>{
      if (!schedule) driver ? 'Reported' : 'Submitted': r['reported_at'],
      driver ? 'Acknowledged' : 'Received by MDRRMO': r['acknowledged_at'],
      if (schedule) ...{
        driver ? 'Trip started' : 'Team on the way': r['started_at'],
        driver ? 'On scene' : 'Team on site': r['arrived_at'],
        'Completed': r['completed_at'],
      } else ...{
        driver ? 'Resolved' : 'Completed': r['resolved_at'],
        driver ? 'Withdrawn' : 'Cancelled': r['withdrawn_at'],
      },
    }..removeWhere((_, value) => value == null || '$value'.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailSection(
          title: schedule ? 'Service details' : 'Incident details',
          children: [
            DetailField(
              schedule ? 'Pickup address' : 'Location',
              schedule ? (r['pickup_address'] ?? r['address']) : r['location'],
            ),
            if (schedule && extractScheduleDestination(r).isNotEmpty)
              DetailField('Destination', extractScheduleDestination(r)),
            if (schedule) ...[
              DetailField(
                'Preferred date & time',
                '${recordTimestamp(r['preferred_date'], dateOnly: true)} · ${recordTime(r['preferred_time'])}',
              ),
            ],
            DetailField(
              schedule ? 'Notes' : 'Description',
              schedule ? r['notes'] : r['description'],
              fallback: schedule
                  ? 'No additional notes provided.'
                  : 'No description recorded.',
            ),
            if (r['decline_reason'] != null)
              DetailField('Decline reason', r['decline_reason']),
            if (r['withdrawal_reason'] != null)
              DetailField('Withdrawal reason', r['withdrawal_reason']),
          ],
        ),
        DetailSection(
          title: 'Response team',
          children: [
            DetailField(
              'Assigned team',
              schedule ? r['team_name'] : r['team'],
              fallback: 'Awaiting team assignment',
            ),
            if (!schedule)
              DetailField(
                'Assigned responder',
                r['driver'],
                fallback: 'Awaiting responder assignment',
              ),
            if (schedule && r['resident'] != null)
              DetailField('Resident', r['resident']),
            if (schedule && r['contact'] != null)
              DetailField('Resident contact', r['contact']),
          ],
        ),
        if (activity.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, AppSpacing.sm),
                  child: Text(
                    'Activity timeline',
                    style: MdrrmoTypography.titleMd.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Surface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < activity.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final entry = activity.entries.elementAt(i);
                            final isLast = i == activity.length - 1;
                            final dotColor =
                                entry.key == 'Completed' ||
                                    entry.key == 'Resolved'
                                ? palette.success
                                : palette.brand;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: 18,
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 5),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: isLast
                                              ? dotColor
                                              : palette.borderStrong,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      bottom: isLast ? 0 : AppSpacing.md,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: MdrrmoTypography.bodyMd
                                              .copyWith(
                                                color: palette.textPrimary,
                                                fontWeight: isLast
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          recordTimestamp(entry.value),
                                          style: MdrrmoTypography.tabular(
                                            MdrrmoTypography.bodySm.copyWith(
                                              color: palette.textSecondary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (driver &&
            r['submitted_patient'] is Map &&
            (r['submitted_patient'] as Map).isNotEmpty)
          DetailSection(
            title: 'Submitted patient information',
            children: [
              for (final entry in (r['submitted_patient'] as Map).entries)
                DetailField(readableLabel(entry.key), entry.value),
            ],
          ),
        if (driver &&
            r['driver_form'] is Map &&
            (r['driver_form'] as Map).values.any(
              (v) => v != null && '$v'.trim().isNotEmpty,
            ))
          DetailSection(
            title: 'Driver Form (Authorization & Fuel)',
            children: [
              DetailField('Trip Date', (r['driver_form'] as Map)['tripDate']),
              DetailField(
                'Assigned Driver',
                (r['driver_form'] as Map)['driverName'],
              ),
              DetailField(
                'Government Vehicle',
                (r['driver_form'] as Map)['governmentCardPlateNo'],
              ),
              DetailField(
                'Authorized Passenger',
                (r['driver_form'] as Map)['authorizedPassenger'] ??
                    (r['driver_form'] as Map)['passengerName'],
              ),
              DetailField(
                'Destination / Place to Visit',
                (r['driver_form'] as Map)['placeVisitedInspected'],
              ),
              DetailField(
                'Purpose of Trip',
                (r['driver_form'] as Map)['purpose'],
              ),
              DetailField(
                'Balance in Tank (L)',
                (r['driver_form'] as Map)['balanceInTank'],
              ),
              DetailField(
                'Issued by Office (L)',
                (r['driver_form'] as Map)['issuedByOffice'],
              ),
              DetailField(
                'Purchased During Trip (L)',
                (r['driver_form'] as Map)['purchasedDuringTrip'],
              ),
              DetailField(
                'Total Available Fuel (L)',
                (r['driver_form'] as Map)['totalAvailableFuel'],
              ),
              DetailField(
                'Fuel Used During Trip (L)',
                (r['driver_form'] as Map)['fuelUsedDuringTrip'],
              ),
              DetailField(
                'Remaining Fuel (L)',
                (r['driver_form'] as Map)['remainingFuel'],
              ),
              DetailField(
                'Gear Oil Used (L)',
                (r['driver_form'] as Map)['gearOilUsed'],
              ),
            ],
          ),
      ],
    );
  }
}

class TripSummary extends StatelessWidget {
  const TripSummary({super.key, required this.trip});
  final Map<String, dynamic>? trip;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    if (t == null) {
      return const RecordMessage(
        title: 'Trip record',
        message: 'No trip information recorded.',
      );
    }
    final pickup = DateTime.tryParse('${t['picked_up_at']}');
    final arrival = DateTime.tryParse('${t['arrived_at']}');
    return DetailSection(
      title: 'Trip record',
      children: [
        DetailField('Destination', t['destination']),
        for (final entry in {
          'Started': t['started_at'],
          'On scene': t['on_scene_at'],
          'Pickup': t['picked_up_at'],
          'Arrived': t['arrived_at'],
        }.entries)
          DetailField(
            entry.key,
            recordTimestamp(entry.value),
          ),
        DetailField(
          'Driver-reported distance',
          t['distance_km'] == null ? null : '${t['distance_km']} km',
        ),
        DetailField(
          'Transport duration',
          pickup == null || arrival == null || arrival.isBefore(pickup)
              ? null
              : '${arrival.difference(pickup).inMinutes} minutes',
        ),
      ],
    );
  }
}

class EditField {
  const EditField(
    this.key,
    this.label, {
    this.max = 255,
    this.lines = 1,
    this.required = true,
    this.numeric = false,
    this.timestamp = false,
    this.secret = false,
    this.date = false,
    this.section,
    this.options,
  });

  final String key, label;
  final int max, lines;
  final bool required, numeric, timestamp, secret, date;
  final String? section;
  final Map<String, String>? options;
}

/// Reusable validated API form; failed saves retain all entered values.
class ApiEditScreen extends StatefulWidget {
  const ApiEditScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.initial,
    required this.save,
    this.notice,
  });

  final String title;
  final List<EditField> fields;
  final Map<String, dynamic> initial;
  final String? notice;
  final Future<void> Function(Map<String, dynamic>) save;

  @override
  State<ApiEditScreen> createState() => _ApiEditScreenState();
}

class _ApiEditScreenState extends State<ApiEditScreen> {
  final _key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _fields = {
      for (final f in widget.fields)
        f.key: TextEditingController(
          text: widget.initial[f.key]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(String key) async {
    final current = DateTime.tryParse(_fields[key]!.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      _fields[key]!.text = picked.toIso8601String().substring(0, 10);
    }
  }

  Future<void> _pickDateTime(String key) async {
    final current = DateTime.tryParse(_fields[key]!.text.trim())?.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    _fields[key]!.text = combined.toUtc().toIso8601String();
  }

  List<({String? title, List<EditField> fields})> _groupedFields() {
    final groups = <({String? title, List<EditField> fields})>[];
    for (final f in widget.fields) {
      if (groups.isEmpty || groups.last.title != f.section) {
        groups.add((title: f.section, fields: [f]));
      } else {
        groups.last.fields.add(f);
      }
    }
    return groups;
  }

  Widget _buildField(EditField f) {
    if (f.options != null) {
      return DropdownButtonFormField<String>(
        initialValue: f.options!.containsKey(_fields[f.key]!.text)
            ? _fields[f.key]!.text
            : null,
        decoration: InputDecoration(labelText: f.label),
        isExpanded: true,
        items: [
          for (final e in f.options!.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: _saving ? null : (v) => _fields[f.key]!.text = v ?? '',
        validator: (v) =>
            f.required && (v == null || v.isEmpty) ? 'Choose ${f.label}' : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _fields[f.key],
          enabled: !_saving,
          decoration: InputDecoration(
            labelText: f.label,
            suffixIcon: f.date
                ? IconButton(
                    tooltip: 'Pick date',
                    onPressed: _saving ? null : () => _pickDate(f.key),
                    icon: const Icon(AppIcons.calendar, size: 18),
                  )
                : f.timestamp
                ? IconButton(
                    tooltip: 'Pick date and time',
                    onPressed: _saving ? null : () => _pickDateTime(f.key),
                    icon: const Icon(AppIcons.clock, size: 18),
                  )
                : null,
          ),
          maxLength: f.max,
          maxLines: f.lines,
          obscureText: f.secret,
          keyboardType: f.numeric
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.text,
          validator: (v) {
            final value = v?.trim() ?? '';
            if (f.required && value.isEmpty) {
              return 'Enter ${f.label}';
            }
            if (f.numeric &&
                value.isNotEmpty &&
                (double.tryParse(value) == null ||
                    !double.parse(value).isFinite)) {
              return 'Enter a valid number';
            }
            if (f.timestamp &&
                value.isNotEmpty &&
                DateTime.tryParse(value) == null) {
              return 'Enter a valid date/time';
            }
            return null;
          },
        ),
        if (f.timestamp)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: _saving
                ? null
                : () => _fields[f.key]!.text = DateTime.now()
                      .toUtc()
                      .toIso8601String(),
            icon: const Icon(AppIcons.clock, size: 16),
            label: const Text('Record now'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final groups = _groupedFields();
    return AppScaffold(
      header: pushedHeader(context, widget.title),
      child: Form(
        key: _key,
        child: ListView(
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
                  if (widget.notice != null) ...[
                    AppBanner(
                      tone: AppBannerTone.info,
                      icon: AppIcons.infoCircle,
                      message: widget.notice!,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  if (_error != null) ...[
                    AppBanner(
                      tone: AppBannerTone.danger,
                      icon: AppIcons.alert,
                      message: apiErrorMessage(_error!),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  for (final group in groups) ...[
                    if (group.title != null) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          group.title!,
                          style: MdrrmoTypography.titleMd.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                    Surface(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final f in group.fields)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.lg,
                              ),
                              child: _buildField(f),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  AppButton(
                    label: _saving ? 'Saving...' : 'Save',
                    loading: _saving,
                    onPress: _saving
                        ? null
                        : () async {
                            if (!_key.currentState!.validate()) return;
                            setState(() {
                              _saving = true;
                              _error = null;
                            });
                            try {
                              await widget.save({
                                for (final e in _fields.entries)
                                  e.key: e.value.text.trim(),
                              });
                              if (context.mounted) Navigator.pop(context, true);
                            } catch (error) {
                              if (mounted) setState(() => _error = error);
                            } finally {
                              if (mounted) setState(() => _saving = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PatientCareScreen extends StatefulWidget {
  const PatientCareScreen({super.key, required this.reportId});
  final int reportId;

  @override
  State<PatientCareScreen> createState() => _PatientCareScreenState();
}

class _PatientCareScreenState extends State<PatientCareScreen> {
  Map<String, dynamic>? _data;
  Object? _error;
  final _cancel = CancelToken();

  String get _path => '/driver-responder/reports/${widget.reportId}/patient';

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
    setState(() => _error = null);
    try {
      final response = await dio.get<Map<String, dynamic>>(
        _path,
        cancelToken: _cancel,
      );
      if (mounted) setState(() => _data = response.data);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return AppScaffold(
        header: pushedHeader(context, 'Patient care'),
        child: _error == null
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ContentFrame(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: AppStateView(
                      icon: AppIcons.wifiOff,
                      title: 'Could not load patient form',
                      message: apiErrorMessage(_error!),
                      action: AppButton(label: 'Retry', onPress: _load),
                    ),
                  ),
                ),
              ),
      );
    }

    final form = Map<String, dynamic>.from((_data!['form'] as Map?) ?? {});
    final initial = <String, dynamic>{};
    final fields = Map<String, dynamic>.from(
      (form['emergency_section'] as Map?) ?? {},
    );
    for (final entry in fields.entries) {
      if (entry.key == 'vitalSigns' && entry.value is Map) {
        for (final vital in (entry.value as Map).entries) {
          initial['v.${vital.key}'] = vital.value;
        }
      } else {
        initial['e.${entry.key}'] = entry.value;
      }
    }
    initial.putIfAbsent('e.typeOfIncident', () => _data!['type']);

    return ApiEditScreen(
      title: 'Patient-care form',
      initial: initial,
      notice: 'Confidential clinical record (separated from Driver Form). Enter observed findings only. Times use 24-hour HH:mm.',
      fields: const [
        EditField(
          'e.timeReported',
          'Time reported (HH:mm)',
          required: false,
          section: 'Timing & incident',
        ),
        EditField(
          'e.timeOfArrival',
          'Time of arrival (HH:mm)',
          required: false,
          section: 'Timing & incident',
        ),
        EditField(
          'e.typeOfIncident',
          'Type of incident',
          max: 80,
          section: 'Timing & incident',
        ),
        EditField(
          'e.patientName',
          'Patient name',
          max: 120,
          required: false,
          section: 'Patient details',
        ),
        EditField(
          'e.age',
          'Age',
          numeric: true,
          required: false,
          section: 'Patient details',
        ),
        EditField(
          'e.sex',
          'Sex',
          options: {'Male': 'Male', 'Female': 'Female'},
          section: 'Patient details',
        ),
        EditField(
          'e.address',
          'Patient address',
          required: false,
          section: 'Patient details',
        ),
        EditField(
          'v.bloodPressure',
          'Blood pressure',
          max: 40,
          required: false,
          section: 'Vital signs',
        ),
        EditField(
          'v.pulseRate',
          'Pulse rate',
          max: 40,
          required: false,
          section: 'Vital signs',
        ),
        EditField(
          'v.respiration',
          'Respiration',
          max: 40,
          required: false,
          section: 'Vital signs',
        ),
        EditField(
          'e.allergies',
          'Allergies',
          max: 1000,
          required: false,
          lines: 3,
          section: 'Clinical findings & care',
        ),
        EditField(
          'e.medications',
          'Medications',
          max: 1000,
          required: false,
          lines: 3,
          section: 'Clinical findings & care',
        ),
        EditField(
          'e.assessmentComment',
          'Assessment',
          max: 2000,
          required: false,
          lines: 4,
          section: 'Clinical findings & care',
        ),
        EditField(
          'e.treatmentManagement',
          'Treatment / management',
          max: 2000,
          required: false,
          lines: 4,
          section: 'Clinical findings & care',
        ),
      ],
      save: (values) async {
        final emergency = <String, dynamic>{}, vitals = <String, dynamic>{};
        for (final entry in values.entries) {
          final key = entry.key.substring(2);
          final value = entry.value == '' ? null : entry.value;
          if (entry.key.startsWith('v.')) {
            vitals[key] = value;
          } else {
            emergency[key] = key == 'age' && value != null
                ? int.tryParse(value as String) ?? value
                : value;
          }
        }
        emergency['vitalSigns'] = vitals;
        await dio.put(
          _path,
          data: {
            'revision': _data!['revision'],
            'emergency_section': emergency,
          },
          cancelToken: _cancel,
        );
      },
    );
  }
}
