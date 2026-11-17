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
  final _address = TextEditingController();
  final _destination = TextEditingController();
  final _notes = TextEditingController();
  SchedulePurpose? _purpose;
  DateTime? _date;
  TimeOfDay? _time;
  bool _sending = false;
  bool _creating = false;
  bool _addressInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAddressFromProfile();
  }

  void _syncAddressFromProfile() {
    if (_addressInitialized || _address.text.trim().isNotEmpty) return;
    final residentAddress = ResidentScope.of(context).profile.address.trim();
    if (residentAddress.isNotEmpty) {
      _address.text = residentAddress;
      _addressInitialized = true;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _destination.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid =>
      _purpose != null &&
      _address.text.trim().isNotEmpty &&
      _destination.text.trim().isNotEmpty &&
      _date != null &&
      _time != null;

  void _openNewRequest() {
    setState(() => _creating = true);
    _syncAddressFromProfile();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      useRootNavigator: true,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      useRootNavigator: true,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _time = picked);
  }

  String? get _timeLabel {
    final t = _time;
    if (t == null) return null;
    return fmtTime(DateTime(2000, 1, 1, t.hour, t.minute));
  }

  Future<void> _submit() async {
    if (_sending || !_valid) return;
    final state = ResidentScope.of(context);
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
    final dest = _destination.text.trim();
    final rawNotes = _notes.text.trim();
    final combinedNotes = dest.isEmpty
        ? rawNotes
        : rawNotes.isEmpty
        ? 'Destination: $dest'
        : 'Destination: $dest\n$rawNotes';
    setState(() => _sending = true);
    try {
      await state.submitSchedule(
        purpose: _purpose!,
        address: _address.text.trim(),
        when: when,
        notes: combinedNotes,
      );
      if (!mounted) return;
      setState(() {
        _creating = false;
        _purpose = null;
        _date = null;
        _time = null;
        _addressInitialized = false;
        _address.text = state.profile.address.trim();
        _addressInitialized = _address.text.isNotEmpty;
        _destination.clear();
        _notes.clear();
      });
      snack(context, 'Service request sent to MDRRMO.');
    } catch (error) {
      if (mounted) {
        snack(context, 'Could not send request: ${apiErrorMessage(error)}');
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
                      const ResidentHeading('Services'),
                      Segmented<bool>(
                        value: _creating,
                        onChanged: _sending
                            ? (_) {}
                            : (creating) {
                                setState(() => _creating = creating);
                                if (creating) _syncAddressFromProfile();
                              },
                        options: const [
                          SegmentOption(false, 'My requests'),
                          SegmentOption(true, 'New request'),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_creating)
                        ..._buildForm(context)
                      else ...[
                        if (state.schedules.isEmpty)
                          _EmptyServicesCard(onRequest: _openNewRequest)
                        else ...[
                          for (var i = 0; i < state.schedules.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpacing.sm + 2),
                            _ScheduleRequestCard(
                              request: state.schedules[i],
                              busy: state.isSaving || state.isLoading,
                              onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => RecordDetailsScreen(
                                    id: state.schedules[i].id,
                                    schedule: true,
                                    onChanged: state.load,
                                  ),
                                ),
                              ),
                              onCancel: () => _cancel(state.schedules[i]),
                            ),
                          ],
                        ],
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
                  child: ListenableBuilder(
                    listenable: Listenable.merge([_address, _destination]),
                    builder: (context, _) {
                      final canSubmit = _valid && state.profile.canSubmit;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppButton(
                            label: _sending
                                ? 'Sending...'
                                : 'Send service request',
                            loading: _sending,
                            onPress: canSubmit && !_sending ? _submit : null,
                          ),
                          if (!state.profile.canSubmit) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Unlocks after account approval.',
                              textAlign: TextAlign.center,
                              style: MdrrmoTypography.labelSm.copyWith(
                                color: palette.textMuted,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
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

  List<Widget> _buildForm(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final purposes = SchedulePurpose.values;
    final dateField = _SchedulePickerBox(
      label: 'Date',
      placeholder: 'Choose a date',
      value: _date == null ? null : fmtDate(_date!),
      onTap: _pickDate,
    );
    final timeField = _SchedulePickerBox(
      label: 'Time',
      placeholder: 'Choose a time',
      value: _timeLabel,
      onTap: _pickTime,
    );

    return [
      Text(
        'Service type',
        style: MdrrmoTypography.titleMd.copyWith(color: palette.textPrimary),
      ),
      const SizedBox(height: AppSpacing.sm + 2),
      LayoutBuilder(
        builder: (context, constraints) {
          final singleColumn =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.35;
          if (singleColumn) {
            return Column(
              children: [
                for (var i = 0; i < purposes.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.sm),
                  _PurposeOptionTile(
                    purposes[i],
                    selected: _purpose == purposes[i],
                    onTap: () => setState(() => _purpose = purposes[i]),
                  ),
                ],
              ],
            );
          }
          return Column(
            children: [
              for (var i = 0; i < purposes.length; i += 2) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _PurposeOptionTile(
                        purposes[i],
                        selected: _purpose == purposes[i],
                        onTap: () => setState(() => _purpose = purposes[i]),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (i + 1 < purposes.length)
                      Expanded(
                        child: _PurposeOptionTile(
                          purposes[i + 1],
                          selected: _purpose == purposes[i + 1],
                          onTap: () =>
                              setState(() => _purpose = purposes[i + 1]),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: AppSpacing.lg),
      ResidentPanel(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.25) {
                  return Column(
                    children: [
                      dateField,
                      const SizedBox(height: AppSpacing.md),
                      timeField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: dateField),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: timeField),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md + 2),
            AppTextField(
              controller: _address,
              label: 'Address',
              hint: 'Street, barangay, or landmark',
              maxLength: 255,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md + 2),
            AppTextField(
              controller: _destination,
              label: 'Destination',
              hint: 'Facility or drop-off location',
              maxLength: 255,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md + 2),
            AppTextField(
              controller: _notes,
              label: 'Notes',
              hint: 'Extra details for MDRRMO',
              required: false,
              maxLength: 1000,
              maxLines: 2,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
    ];
  }
}

class _EmptyServicesCard extends StatelessWidget {
  const _EmptyServicesCard({required this.onRequest});

  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Text(
            'No service requests yet',
            textAlign: TextAlign.center,
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Schedule ambulance standby, training, or community support.',
            textAlign: TextAlign.center,
            style: MdrrmoTypography.bodySm.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Request a service',
            kind: AppButtonKind.secondary,
            onPress: onRequest,
          ),
        ],
      ),
    );
  }
}

class _ScheduleRequestCard extends StatelessWidget {
  const _ScheduleRequestCard({
    required this.request,
    required this.busy,
    required this.onOpen,
    required this.onCancel,
  });

  final ScheduleRequest request;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final (statusLabel, statusColor, _) = residentStatusPresentation(
      request.status,
      palette,
      schedule: true,
    );

    return Surface(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      onTap: onOpen,
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
                request.purpose.label,
                style: MdrrmoTypography.titleMd.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              AppStatusBadge(statusLabel, color: statusColor, dot: true),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${fmtDate(request.when)} · ${fmtTime(request.when)}',
            style: MdrrmoTypography.tabular(
              MdrrmoTypography.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (request.destination.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              request.destination,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
          if (request.canCancel) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            Divider(height: 1, color: palette.border),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: palette.danger,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
                onPressed: busy ? null : onCancel,
                child: const Text('Cancel request'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PurposeOptionTile extends StatelessWidget {
  const _PurposeOptionTile(
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
        color: selected ? palette.brandTint : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: selected ? palette.brand : palette.border,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? palette.brand : purpose.color,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
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

class _SchedulePickerBox extends StatelessWidget {
  const _SchedulePickerBox({
    required this.label,
    required this.placeholder,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String placeholder;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final selected = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MdrrmoTypography.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: '$label, ${value ?? placeholder}',
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected
                      ? palette.brand.withValues(alpha: 0.55)
                      : palette.border,
                ),
              ),
              child: Text(
                value ?? placeholder,
                style: MdrrmoTypography.tabular(
                  MdrrmoTypography.bodyMd.copyWith(
                    color: selected ? palette.textPrimary : palette.textMuted,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
