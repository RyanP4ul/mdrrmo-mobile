import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api_client.dart';
import '../../data/models.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/form_page.dart';
import '../../ui/kit.dart';

class _DispatchOption {
  const _DispatchOption({
    required this.reportId,
    required this.reference,
    required this.tripDate,
    required this.driverName,
    required this.vehicle,
    required this.authorizedPassenger,
    required this.destination,
    required this.purpose,
    required this.isActive,
    required this.hasDriverForm,
  });

  final int reportId;
  final String reference;
  final String tripDate;
  final String driverName;
  final String vehicle;
  final String authorizedPassenger;
  final String destination;
  final String purpose;
  final bool isActive;
  final bool hasDriverForm;

  String get label =>
      '$reference · $purpose (${isActive ? 'Active' : 'Resolved'}${hasDriverForm ? ' · Saved' : ''})';
}

class DriverFormScreen extends StatefulWidget {
  const DriverFormScreen({
    super.key,
    this.initialReportId,
    this.initialAssignment,
    this.initialDispatch,
    this.initialRecord,
  });

  final int? initialReportId;
  final Assignment? initialAssignment;
  final Dispatch? initialDispatch;
  final Map<String, dynamic>? initialRecord;

  @override
  State<DriverFormScreen> createState() => _DriverFormScreenState();
}

class _DriverFormScreenState extends State<DriverFormScreen> {
  final _key = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _cancel = CancelToken();

  // Authorization controllers
  late final TextEditingController _tripDate;
  late final TextEditingController _assignedDriver;
  late final TextEditingController _governmentVehicle;
  late final TextEditingController _authorizedPassenger;
  late final TextEditingController _destination;
  late final TextEditingController _purpose;

  // Fuel controllers (computed fields backed by ValueNotifier updates)
  late final TextEditingController _balanceInTank;
  late final TextEditingController _issuedByOffice;
  late final TextEditingController _purchasedDuringTrip;
  late final TextEditingController _totalAvailableFuel;
  late final TextEditingController _fuelUsedDuringTrip;
  late final TextEditingController _remainingFuel;
  late final TextEditingController _gearOilUsed;

  bool _initialized = false;
  bool _loadingForm = false;
  bool _saving = false;
  bool _updatingComputedFuel = false;
  bool _canReloadOnError = false;
  String _revision = 'new';
  String? _error;

  List<_DispatchOption> _options = const [];
  int? _selectedReportId;

  ResponderState? _maybeState(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ResponderScope>()
      ?.notifier;

  @override
  void initState() {
    super.initState();
    _tripDate = TextEditingController();
    _assignedDriver = TextEditingController();
    _governmentVehicle = TextEditingController();
    _authorizedPassenger = TextEditingController();
    _destination = TextEditingController();
    _purpose = TextEditingController();

    _balanceInTank = TextEditingController();
    _issuedByOffice = TextEditingController();
    _purchasedDuringTrip = TextEditingController();
    _totalAvailableFuel = TextEditingController();
    _fuelUsedDuringTrip = TextEditingController();
    _remainingFuel = TextEditingController();
    _gearOilUsed = TextEditingController();

    for (final c in [
      _balanceInTank,
      _issuedByOffice,
      _purchasedDuringTrip,
      _fuelUsedDuringTrip,
    ]) {
      c.addListener(_recalculateFuel);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final state = _maybeState(context);
    _options = state == null
        ? _buildStandaloneOptions()
        : _buildDispatchOptions(state);
    _selectedReportId =
        widget.initialReportId ??
        widget.initialAssignment?.id ??
        widget.initialDispatch?.recordId ??
        _options.firstOrNull?.reportId;

    final selected = _options
        .where((o) => o.reportId == _selectedReportId)
        .firstOrNull;
    _applyDefaults(state, selected);
    if (_selectedReportId != null) {
      final reportId = _selectedReportId!;
      Future.microtask(() {
        if (!mounted || _selectedReportId != reportId) return;
        _loadRemoteForm(state, reportId);
      });
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    for (final c in [
      _balanceInTank,
      _issuedByOffice,
      _purchasedDuringTrip,
      _fuelUsedDuringTrip,
    ]) {
      c.removeListener(_recalculateFuel);
    }
    for (final c in [
      _tripDate,
      _assignedDriver,
      _governmentVehicle,
      _authorizedPassenger,
      _destination,
      _purpose,
      _balanceInTank,
      _issuedByOffice,
      _purchasedDuringTrip,
      _totalAvailableFuel,
      _fuelUsedDuringTrip,
      _remainingFuel,
      _gearOilUsed,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _recalculateFuel() {
    if (_updatingComputedFuel) return;
    final balanceText = _balanceInTank.text.trim();
    final issuedText = _issuedByOffice.text.trim();
    final purchasedText = _purchasedDuringTrip.text.trim();
    final usedText = _fuelUsedDuringTrip.text.trim();

    final hasSupply =
        balanceText.isNotEmpty ||
        issuedText.isNotEmpty ||
        purchasedText.isNotEmpty;
    final hasAnyFuel = hasSupply || usedText.isNotEmpty;
    final balance = double.tryParse(balanceText) ?? 0;
    final issued = double.tryParse(issuedText) ?? 0;
    final purchased = double.tryParse(purchasedText) ?? 0;
    final total = balance + issued + purchased;

    _updatingComputedFuel = true;
    try {
      if (hasSupply) {
        _totalAvailableFuel.text = _formatLiters(total);
      } else {
        _totalAvailableFuel.clear();
      }
      final currentTotal =
          double.tryParse(_totalAvailableFuel.text.trim()) ?? total;
      if (hasAnyFuel) {
        final used = double.tryParse(usedText) ?? 0;
        _remainingFuel.text = _formatLiters(currentTotal - used);
      } else {
        _remainingFuel.clear();
      }
    } finally {
      _updatingComputedFuel = false;
    }
  }

  String _formatLiters(double value) {
    final rounded = (value * 100).round() / 100;
    if (rounded == rounded.truncateToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _defaultDriverName(ResponderState? state) {
    if (state == null) {
      return '${widget.initialRecord?['driver'] ?? ''}'.trim();
    }
    if (state.profile.name.trim().isNotEmpty) {
      return state.profile.name.trim();
    }
    for (final role in state.teamRoles) {
      if (role.driverName != null && role.driverName!.trim().isNotEmpty) {
        return role.driverName!.trim();
      }
    }
    return '';
  }

  String _defaultVehicleLabel(ResponderState? state, {int? vehicleId}) {
    if (state == null) {
      return '${widget.initialRecord?['vehicle'] ?? ''}'.trim();
    }
    final allVehicles = [
      for (final team in state.teamRoles) ...team.vehicles,
      ...state.vehicles,
    ];
    final targetId = vehicleId ?? state.selectedVehicleId;
    final match =
        allVehicles.where((v) => v.id == targetId).firstOrNull ??
        state.teamRoles
            .map((t) => t.activeVehicle)
            .whereType<DriverVehicle>()
            .firstOrNull ??
        allVehicles.firstOrNull;
    if (match != null) {
      return match.name.trim().isNotEmpty
          ? '${match.number} · ${match.name}'
          : '${match.number} · ${match.label}';
    }
    if (state.profile.vehicleNumber.trim().isNotEmpty) {
      return '${state.profile.vehicleNumber} · ${state.profile.vehicleType}';
    }
    return '';
  }

  String _teamRespondersPassengerFallback(
    ResponderState? state,
    String primaryPassenger,
  ) {
    if (state == null) return primaryPassenger.trim();
    final driverName = _defaultDriverName(state).toLowerCase();
    final responders = state.teams
        .where(
          (m) =>
              m.role.toLowerCase() != 'driver' &&
              m.name.trim().isNotEmpty &&
              m.name.trim().toLowerCase() != driverName,
        )
        .map((m) => m.name.trim())
        .toList();
    final parts = <String>[
      if (primaryPassenger.trim().isNotEmpty) primaryPassenger.trim(),
      for (final r in responders)
        if (!primaryPassenger.toLowerCase().contains(r.toLowerCase())) r,
    ];
    return parts.join(', ');
  }

  List<_DispatchOption> _buildStandaloneOptions() {
    final id = widget.initialReportId;
    final r = widget.initialRecord;
    if (id == null) return const [];
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return [
      _DispatchOption(
        reportId: id,
        reference: '${r?['reference'] ?? 'RPT-$id'}',
        tripDate: today,
        driverName: '${r?['driver'] ?? ''}'.trim(),
        vehicle: '${r?['vehicle'] ?? ''}'.trim(),
        authorizedPassenger: '${r?['authorized_passenger'] ?? ''}'.trim(),
        destination: '${r?['location'] ?? ''}'.trim(),
        purpose: 'Emergency Response - ${r?['type'] ?? 'Emergency'}',
        isActive: true,
        hasDriverForm: r?['driver_form'] is Map,
      ),
    ];
  }

  List<_DispatchOption> _buildDispatchOptions(ResponderState state) {
    final seen = <int>{};
    final list = <_DispatchOption>[];

    void addAssignment(Assignment a, {required bool isActive}) {
      if (!seen.add(a.id)) return;
      final date = (a.reportedAt ?? DateTime.now())
          .toIso8601String()
          .substring(0, 10);
      final dest =
          a.destination != 'Destination not recorded' &&
              a.destination.trim().isNotEmpty
          ? a.destination
          : a.pickup;
      final passenger = a.authorizedPassenger.trim().isNotEmpty
          ? a.authorizedPassenger.trim()
          : _teamRespondersPassengerFallback(state, a.patientName);
      list.add(
        _DispatchOption(
          reportId: a.id,
          reference: a.reference.isNotEmpty ? a.reference : 'RPT-${a.id}',
          tripDate: date,
          driverName: _defaultDriverName(state),
          vehicle: _defaultVehicleLabel(state, vehicleId: a.vehicleId),
          authorizedPassenger: passenger,
          destination: dest,
          purpose: 'Emergency Response - ${a.emergencyType}',
          isActive: isActive,
          hasDriverForm: a.hasDriverForm,
        ),
      );
    }

    if (widget.initialAssignment != null) {
      final a = widget.initialAssignment!;
      final stillActive = state.assignments.any((item) => item.id == a.id);
      addAssignment(a, isActive: stillActive);
    }

    for (final a in state.assignments) {
      addAssignment(a, isActive: true);
    }

    void addDispatchRecord(Dispatch d) {
      if (d.recordId == null || !seen.add(d.recordId!)) return;
      final dest =
          d.destination != 'Destination not recorded' &&
              d.destination.trim().isNotEmpty
          ? d.destination
          : d.pickup;
      final passenger = d.authorizedPassenger.trim().isNotEmpty
          ? d.authorizedPassenger.trim()
          : _teamRespondersPassengerFallback(state, d.patientName);
      list.add(
        _DispatchOption(
          reportId: d.recordId!,
          reference: d.id,
          tripDate: d.time.toIso8601String().substring(0, 10),
          driverName: d.driver.trim().isNotEmpty && d.driver != 'You'
              ? d.driver
              : _defaultDriverName(state),
          vehicle:
              d.vehicle != 'Vehicle not assigned' && d.vehicle.trim().isNotEmpty
              ? d.vehicle
              : _defaultVehicleLabel(state),
          authorizedPassenger: passenger,
          destination: dest,
          purpose: 'Emergency Response - ${d.emergencyType}',
          isActive: false,
          hasDriverForm: d.hasDriverForm,
        ),
      );
    }

    if (widget.initialDispatch != null) {
      addDispatchRecord(widget.initialDispatch!);
    }

    for (final d in state.history) {
      if (d.status == DispatchStatus.invalid) continue;
      addDispatchRecord(d);
    }

    return list;
  }

  void _applyDefaults(ResponderState? state, _DispatchOption? option) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    _tripDate.text = option?.tripDate ?? today;
    _assignedDriver.text = option?.driverName.isNotEmpty == true
        ? option!.driverName
        : _defaultDriverName(state);
    _governmentVehicle.text = option?.vehicle.isNotEmpty == true
        ? option!.vehicle
        : _defaultVehicleLabel(state);
    _authorizedPassenger.text = option?.authorizedPassenger.isNotEmpty == true
        ? option!.authorizedPassenger
        : _teamRespondersPassengerFallback(state, '');
    _destination.text = option?.destination ?? '';
    _purpose.text = option?.purpose ?? 'Emergency Response';

    _updatingComputedFuel = true;
    try {
      _balanceInTank.clear();
      _issuedByOffice.clear();
      _purchasedDuringTrip.clear();
      _totalAvailableFuel.clear();
      _fuelUsedDuringTrip.clear();
      _remainingFuel.clear();
      _gearOilUsed.clear();
    } finally {
      _updatingComputedFuel = false;
    }
  }

  Future<void> _loadRemoteForm(ResponderState? state, int reportId) async {
    setState(() {
      _loadingForm = true;
      _error = null;
      _canReloadOnError = false;
    });
    try {
      final data = state != null
          ? await state.api.fetchReportForm(reportId)
          : (await dio.get<Map<String, dynamic>>(
                  '/driver-responder/reports/$reportId/patient',
                  cancelToken: _cancel,
                ))
                .data ??
                const <String, dynamic>{};
      if (!mounted || _selectedReportId != reportId) return;
      _revision = data['revision']?.toString() ?? 'new';
      final defaults = data['defaults'] is Map
          ? Map<String, dynamic>.from(data['defaults'] as Map)
          : const <String, dynamic>{};
      final form = data['form'] is Map
          ? Map<String, dynamic>.from(data['form'] as Map)
          : const <String, dynamic>{};
      final driver = form['driver_section'] is Map
          ? Map<String, dynamic>.from(form['driver_section'] as Map)
          : const <String, dynamic>{};

      String pick(String key, String currentFallback) {
        final savedVal = driver[key]?.toString().trim() ?? '';
        if (savedVal.isNotEmpty) return savedVal;
        final defVal = defaults[key]?.toString().trim() ?? '';
        if (defVal.isNotEmpty) return defVal;
        return currentFallback;
      }

      _tripDate.text = pick('tripDate', _tripDate.text);
      _assignedDriver.text = pick('driverName', _assignedDriver.text);
      _governmentVehicle.text = pick(
        'governmentCardPlateNo',
        _governmentVehicle.text,
      );
      final savedPassenger =
          driver['authorizedPassenger']?.toString().trim() ??
          driver['passengerName']?.toString().trim() ??
          '';
      _authorizedPassenger.text = savedPassenger.isNotEmpty
          ? savedPassenger
          : pick('authorizedPassenger', _authorizedPassenger.text);
      _destination.text = pick('placeVisitedInspected', _destination.text);
      _purpose.text = pick('purpose', _purpose.text);

      _updatingComputedFuel = true;
      try {
        _balanceInTank.text = driver['balanceInTank']?.toString() ?? '';
        _issuedByOffice.text = driver['issuedByOffice']?.toString() ?? '';
        _purchasedDuringTrip.text =
            driver['purchasedDuringTrip']?.toString() ?? '';
        _totalAvailableFuel.text =
            driver['totalAvailableFuel']?.toString() ?? '';
        _fuelUsedDuringTrip.text =
            driver['fuelUsedDuringTrip']?.toString() ?? '';
        _remainingFuel.text = driver['remainingFuel']?.toString() ?? '';
        _gearOilUsed.text = driver['gearOilUsed']?.toString() ?? '';
      } finally {
        _updatingComputedFuel = false;
      }
      _recalculateFuel();
    } catch (error) {
      // Surface HTTP/server errors (such as 403/500) so the user can see or retry;
      // offline/mocked environments without a response retain local defaults.
      final hasHttpResponse =
          error is DioException && error.response != null;
      if (hasHttpResponse && mounted && _selectedReportId == reportId) {
        setState(() {
          _error = apiErrorMessage(error);
          _canReloadOnError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingForm = false);
    }
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_tripDate.text.trim()) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _tripDate.text = picked.toIso8601String().substring(0, 10));
    }
  }

  double? _parseOptionalFuel(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  String? _validateNonNegativeFuel(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null;
    final parsed = double.tryParse(v);
    if (parsed == null || !parsed.isFinite || parsed < 0) {
      return 'Enter a valid liters amount (0 or higher)';
    }
    return null;
  }

  void _showFormError(String message, {bool canReload = false}) {
    setState(() {
      _error = message;
      _canReloadOnError = canReload;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_key.currentState!.validate()) {
      _showFormError('Please complete the required fields highlighted below.');
      return;
    }
    if (_tripDate.text.trim().isEmpty) {
      _showFormError('Select the trip date before submitting.');
      return;
    }
    final reportId = _selectedReportId;
    if (reportId == null) {
      _showFormError(
        'No dispatch record selected. Complete or receive a dispatch first.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _canReloadOnError = false;
    });
    final state = _maybeState(context);
    final payload = <String, dynamic>{
      'tripDate': _tripDate.text.trim(),
      'driverName': _assignedDriver.text.trim(),
      'governmentCardPlateNo': _governmentVehicle.text.trim(),
      'authorizedPassenger': _authorizedPassenger.text.trim(),
      'passengerName': _authorizedPassenger.text.trim(),
      'placeVisitedInspected': _destination.text.trim(),
      'purpose': _purpose.text.trim(),
      'balanceInTank': _parseOptionalFuel(_balanceInTank.text),
      'issuedByOffice': _parseOptionalFuel(_issuedByOffice.text),
      'purchasedDuringTrip': _parseOptionalFuel(_purchasedDuringTrip.text),
      'totalAvailableFuel': _parseOptionalFuel(_totalAvailableFuel.text),
      'fuelUsedDuringTrip': _parseOptionalFuel(_fuelUsedDuringTrip.text),
      'remainingFuel': _parseOptionalFuel(_remainingFuel.text),
      'gearOilUsed': _parseOptionalFuel(_gearOilUsed.text),
    };

    try {
      if (state != null) {
        await state.api.saveDriverForm(
          reportId,
          revision: _revision,
          driverSection: payload,
        );
        await state.load();
      } else {
        await dio.put(
          '/driver-responder/reports/$reportId/patient',
          data: {
            'revision': _revision,
            'driver_section': payload,
          },
          cancelToken: _cancel,
        );
      }
      if (!mounted) return;
      snack(context, 'Driver Form submitted and synced to Website Reports.');
      Navigator.of(context).pop(true);
    } catch (error) {
      final statusCode =
          error is DioException ? error.response?.statusCode : null;
      if (mounted) {
        _showFormError(
          apiErrorMessage(error),
          canReload: statusCode == 409,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _maybeState(context);
    final selectedOption = _options
        .where((o) => o.reportId == _selectedReportId)
        .firstOrNull;

    return FormPage(
      title: 'Driver Form',
      formKey: _key,
      scrollController: _scroll,
      submitLabel: _saving ? 'Submitting…' : 'Submit Driver Form',
      onSubmit: _saving || _loadingForm ? null : _submit,
      children: [
        if (_loadingForm)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.md),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_error != null) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppBanner(
                tone: AppBannerTone.danger,
                icon: AppIcons.alert,
                message: _error!,
              ),
              if (_canReloadOnError && _selectedReportId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    kind: AppButtonKind.secondary,
                    label: 'Reload Latest Form',
                    onPress: _loadingForm || _saving
                        ? null
                        : () => _loadRemoteForm(state, _selectedReportId!),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_options.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.lg),
            child: AppStateView(
              icon: AppIcons.route,
              title: 'No dispatch selected',
              message:
                  'Receive or complete an emergency dispatch to submit a Driver Form.',
            ),
          )
        else if (_options.length > 1 || widget.initialRecord == null)
          _DriverSection(
            title: 'Dispatch',
            fields: [
              AppSelect(
                label: 'Select Dispatch',
                options: [for (final o in _options) o.label],
                value: (selectedOption ?? _options.first).label,
                onChange: (label) {
                  final next = _options.firstWhere(
                    (o) => o.label == label,
                    orElse: () => _options.first,
                  );
                  if (next.reportId == _selectedReportId) return;
                  setState(() {
                    _selectedReportId = next.reportId;
                    _revision = 'new';
                  });
                  _applyDefaults(state, next);
                  _loadRemoteForm(state, next.reportId);
                },
              ),
            ],
          ),
        _DriverSection(
          title: 'Authorization',
          fields: [
            AppDateField(
              label: 'Trip Date',
              valueText: _tripDate.text.trim().isEmpty
                  ? null
                  : _tripDate.text.trim(),
              onPick: _saving ? null : _pickDate,
              enabled: !_saving,
            ),
            AppTextField(
              controller: _assignedDriver,
              label: 'Assigned Driver',
              hint: 'e.g. Juan Dela Cruz',
              maxLength: 120,
            ),
            AppTextField(
              controller: _governmentVehicle,
              label: 'Government Vehicle',
              hint: 'e.g. RESCUE 01 · Alpha Unit 1',
              maxLength: 120,
            ),
            AppTextField(
              controller: _authorizedPassenger,
              label: 'Authorized Passenger',
              hint: 'Responders or patient names',
              maxLength: 255,
              required: false,
            ),
            AppTextField(
              controller: _destination,
              label: 'Destination / Place to Visit',
              hint: 'Incident or hospital location',
              maxLength: 255,
            ),
            AppTextField(
              controller: _purpose,
              label: 'Purpose of Trip',
              hint: 'e.g. Emergency Response',
              maxLength: 255,
            ),
          ],
        ),
        _DriverSection(
          title: 'Fuel',
          fields: [
            _FuelSummaryStrip(
              totalController: _totalAvailableFuel,
              remainingController: _remainingFuel,
            ),
            AppTextField(
              controller: _balanceInTank,
              label: 'Balance in Tank (L)',
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              required: false,
              validator: _validateNonNegativeFuel,
            ),
            AppTextField(
              controller: _issuedByOffice,
              label: 'Issued by Office (L)',
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              required: false,
              validator: _validateNonNegativeFuel,
            ),
            AppTextField(
              controller: _purchasedDuringTrip,
              label: 'Purchased During Trip (L)',
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              required: false,
              validator: _validateNonNegativeFuel,
            ),
            AppTextField(
              controller: _fuelUsedDuringTrip,
              label: 'Fuel Used During Trip (L)',
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              required: false,
              validator: _validateNonNegativeFuel,
            ),
            AppTextField(
              controller: _gearOilUsed,
              label: 'Gear Oil Used (L)',
              hint: '0.0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              required: false,
              validator: _validateNonNegativeFuel,
            ),
          ],
        ),
      ],
    );
  }
}

class _DriverSection extends StatelessWidget {
  const _DriverSection({required this.title, required this.fields});

  final String title;
  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              title,
              style: MdrrmoTypography.titleMd.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          Surface(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  fields[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelSummaryStrip extends StatelessWidget {
  const _FuelSummaryStrip({
    required this.totalController,
    required this.remainingController,
  });

  final TextEditingController totalController;
  final TextEditingController remainingController;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([totalController, remainingController]),
      builder: (context, _) {
        final totalText = totalController.text.trim();
        final remainingText = remainingController.text.trim();
        final remainingValue = double.tryParse(remainingText);
        final negativeRemaining =
            remainingValue != null && remainingValue < 0;

        Widget metric(String label, String raw, {Color? valueColor}) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: MdrrmoTypography.labelSm.copyWith(
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                raw.isEmpty ? '— L' : '$raw L',
                style: MdrrmoTypography.tabular(
                  MdrrmoTypography.titleLg.copyWith(
                    color: valueColor ?? palette.textPrimary,
                  ),
                ),
              ),
            ],
          );
        }

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: palette.border),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 260 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    metric('Total Available Fuel (L)', totalText),
                    Divider(height: AppSpacing.lg, color: palette.border),
                    metric(
                      'Remaining Fuel (L)',
                      remainingText,
                      valueColor: negativeRemaining
                          ? palette.danger
                          : remainingText.isNotEmpty
                          ? palette.brand
                          : null,
                    ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: metric('Total Available Fuel (L)', totalText),
                    ),
                    VerticalDivider(
                      width: AppSpacing.lg,
                      thickness: 1,
                      color: palette.border,
                    ),
                    Expanded(
                      child: metric(
                        'Remaining Fuel (L)',
                        remainingText,
                        valueColor: negativeRemaining
                            ? palette.danger
                            : remainingText.isNotEmpty
                            ? palette.brand
                            : null,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
