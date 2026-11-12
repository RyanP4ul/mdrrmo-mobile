import 'package:material_ui/material_ui.dart';

import '../../data/input_validation.dart';
import '../../data/resident_models.dart';
import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../ui/page_loader.dart';
import '../../widgets/res_widgets.dart';
import '../record_details_screen.dart';
import 'resident_widgets.dart';

class ResidentScheduleScreen extends StatefulWidget {
  const ResidentScheduleScreen({super.key});

  @override
  State<ResidentScheduleScreen> createState() => _ResidentScheduleScreenState();
}

class _ResidentScheduleScreenState extends State<ResidentScheduleScreen> {
  final _destination = TextEditingController();
  final _notes = TextEditingController();
  SchedulePurpose? _purpose;
  DateTime? _date;
  TimeOfDay? _time;
  bool _sending = false;
  bool _creating = false;

  @override
  void dispose() {
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid =>
      _purpose != null &&
      _destination.text.trim().isNotEmpty &&
      _date != null &&
      _time != null;

  Future<void> _pickDate() async {
    final now = DateTime.now();

    final d = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (!mounted) return;
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      useRootNavigator: true,
      initialTime: _time ?? TimeOfDay.now(),
    );

    if (!mounted) return;
    if (t != null) setState(() => _time = t);
  }

  String? get _timeLabel {
    final t = _time;
    if (t == null) return null;
    return fmtTime(DateTime(2000, 1, 1, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (_sending || !_valid) return;
    final s = ResidentScope.of(context);
    final when = DateTime(
      _date!.year,
      _date!.month,
      _date!.day,
      _time!.hour,
      _time!.minute,
    );
    if (InputValidation.scheduleTime(when) != null) {
      snack(context, 'Choose a future date and time.');
      return;
    }
    setState(() => _sending = true);
    try {
      await s.submitSchedule(
        purpose: _purpose!,
        address: _destination.text.trim(),
        when: when,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _creating = false;
        _purpose = null;
        _date = null;
        _time = null;
        _destination.clear();
        _notes.clear();
      });
      snack(context, 'Schedule request sent to MDRRMO');
    } catch (error) {
      if (mounted) {
        snack(
          context,
          'Could not send schedule request: ${apiErrorMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _cancel(ScheduleRequest request) async {
    final state = ResidentScope.of(context);
    final confirmed = await confirmDialog(
      context,
      title: 'Cancel service request?',
      body:
          'Cancel your ${request.purpose.label} request for ${fmtDate(request.when)}?',
      confirmLabel: 'Cancel request',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await state.cancelSchedule(request);
      if (mounted) snack(context, 'Service request cancelled.');
    } catch (error) {
      if (mounted) snack(context, apiErrorMessage(error));
    }
  }

  Color _statusColor(MdrrmoColors palette, String status) =>
      switch (status.toLowerCase()) {
        'confirmed' || 'completed' => palette.success,
        'declined' || 'cancelled' => palette.danger,
        _ => palette.warning,
      };

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
    final palette = MdrrmoColors.of(context);
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      const ResidentHeading(
                        'Community services',
                        subtitle:
                            'Plan non-emergency assistance with MDRRMO.',
                      ),
                      Segmented<bool>(
                        value: _creating,
                        onChanged: _sending
                            ? (_) {}
                            : (v) => setState(() => _creating = v),
                        options: const [
                          SegmentOption(false, 'My requests'),
                          SegmentOption(true, 'New request'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_creating)
                        ..._form(context)
                      else ...[
                        if (state.schedules.isEmpty)
                          const ResidentEmptyState(
                            icon: AppIcons.calendar,
                            title: 'No service requests yet',
                            message:
                                'Choose New request to plan an activity, training, inspection, or standby service.',
                          ),
                        for (final request in state.schedules)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ResidentPanel(
                              padding: const EdgeInsets.all(14),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecordDetailsScreen(
                                    id: request.id,
                                    schedule: true,
                                    onChanged: state.load,
                                  ),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 6,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'Request #${request.id}',
                                        style: MdrrmoTypography.tabular(
                                          MdrrmoTypography.labelSm.copyWith(
                                            color: palette.textMuted,
                                          ),
                                        ),
                                      ),
                                      Pill(
                                        request.status,
                                        color: _statusColor(
                                          palette,
                                          request.status,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    request.purpose.label,
                                    style: MdrrmoTypography.titleMd.copyWith(
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    request.destination,
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        AppIcons.calendar,
                                        size: 16,
                                        color: palette.brand,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          '${fmtDate(request.when)} · ${fmtTime(request.when)}',
                                          style: MdrrmoTypography.tabular(
                                            MdrrmoTypography.bodySm.copyWith(
                                              fontWeight: FontWeight.w500,
                                              color: palette.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.only(top: 8),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        top: BorderSide(color: palette.border),
                                      ),
                                    ),
                                    child: Wrap(
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      spacing: 10,
                                      children: [
                                        Text(
                                          'Tap to view details',
                                          style: MdrrmoTypography.labelSm
                                              .copyWith(color: palette.brand),
                                        ),
                                        if (request.canCancel)
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: palette.danger,
                                              minimumSize: const Size(0, 44),
                                            ),
                                            onPressed:
                                                state.isSaving ||
                                                    state.isLoading
                                                ? null
                                                : () => _cancel(request),
                                            child: const Text('Cancel request'),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        PageLoader(
                          hasMore: state.hasMore('schedules'),
                          loading:
                              state.isLoading ||
                              state.isSaving ||
                              state.loadingPage == 'schedules',
                          error: state.pageErrors['schedules'],
                          onLoad: () => state.loadMore('schedules'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_creating)
          Container(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border(top: BorderSide(color: palette.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: ContentFrame(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _destination,
                    builder: (context, _, _) {
                      final canSubmit = _valid && state.profile.canSubmit;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppButton(
                            label: _sending
                                ? 'Sending request...'
                                : 'Send service request',
                            icon: AppIcons.send,
                            loading: _sending,
                            onPress: canSubmit && !_sending ? _submit : null,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            !state.profile.canSubmit
                                ? 'Service requests are available after account approval.'
                                : !_valid
                                ? 'Choose a service, address, date, and time to continue.'
                                : 'MDRRMO will review and confirm your request.',
                            textAlign: TextAlign.center,
                            style: MdrrmoTypography.labelSm.copyWith(
                              color: palette.textMuted,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _form(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final profile = ResidentScope.of(context).profile;
    final purposes = SchedulePurpose.values;
    final date = PickerField(
      label: 'Date',
      icon: AppIcons.calendar,
      placeholder: 'Choose a date',
      value: _date == null ? null : fmtDate(_date!),
      onTap: _pickDate,
    );
    final time = PickerField(
      label: 'Time',
      icon: AppIcons.clock,
      placeholder: 'Choose a time',
      value: _timeLabel,
      onTap: _pickTime,
    );
    return [
      Text(
        'What service do you need?',
        style: MdrrmoTypography.titleMd.copyWith(color: palette.textPrimary),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < purposes.length; i += 2)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _PurposeChip(
                  purposes[i],
                  selected: _purpose == purposes[i],
                  onTap: () => setState(() => _purpose = purposes[i]),
                ),
              ),
              const SizedBox(width: 10),
              if (i + 1 < purposes.length)
                Expanded(
                  child: _PurposeChip(
                    purposes[i + 1],
                    selected: _purpose == purposes[i + 1],
                    onTap: () => setState(() => _purpose = purposes[i + 1]),
                  ),
                )
              else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      const SizedBox(height: 10),
      ResidentPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Where and when',
              style: MdrrmoTypography.titleMd.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _destination,
              label: 'Service address',
              hint: 'Street, barangay, or landmark',
              maxLength: 255,
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 340 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.2) {
                  return Column(
                    children: [date, const SizedBox(height: 14), time],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: date),
                    const SizedBox(width: 12),
                    Expanded(child: time),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _notes,
              label: 'Additional details',
              hint: 'Anything MDRRMO should know?',
              required: false,
              maxLength: 1000,
              maxLines: 3,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      ResidentPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your contact details',
              style: MdrrmoTypography.titleMd.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'From your resident account',
              style: MdrrmoTypography.labelSm.copyWith(
                color: palette.textMuted,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 14),
            LockedField(
              label: 'Name',
              icon: AppIcons.user,
              value: profile.name,
            ),
            const SizedBox(height: 10),
            LockedField(
              label: 'Contact number',
              icon: AppIcons.phone,
              value: profile.contact,
            ),
          ],
        ),
      ),
    ];
  }
}

class _PurposeChip extends StatelessWidget {
  const _PurposeChip(
    this.purpose, {
    required this.selected,
    required this.onTap,
  });

  final SchedulePurpose purpose;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: purpose.label,
      child: Material(
        color: selected
            ? palette.brandTint.withValues(alpha: palette.isDark ? 0.5 : 0.7)
            : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? palette.brand : palette.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(purpose.icon, size: 19, color: purpose.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    purpose.label,
                    style: MdrrmoTypography.bodySm.copyWith(
                      color: palette.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
