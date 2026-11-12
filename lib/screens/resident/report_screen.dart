import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/api/guest_report_api.dart';
import '../../data/input_validation.dart';
import '../../data/resident_models.dart';
import '../../services/incident_location.dart';
import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../ui/resilient_tiles.dart';
import '../../widgets/res_widgets.dart';
import 'resident_widgets.dart';

enum _Step { pick, details, sent }

const _balagtas = LatLng(14.8153, 120.9094);

class ResidentReportScreen extends StatefulWidget {
  const ResidentReportScreen({
    super.key,
    required this.onDone,
    this.locationSource,
    this.guestApi,
  });

  final VoidCallback onDone;
  final IncidentLocationSource? locationSource;
  final GuestReportApi? guestApi;

  @override
  State<ResidentReportScreen> createState() => _ResidentReportScreenState();
}

class _ResidentReportScreenState extends State<ResidentReportScreen> {
  final _formKey = GlobalKey<FormState>();
  _Step _step = _Step.pick;
  ReporterType _reporter = ReporterType.victim;
  IncidentType? _type;
  LatLng _pin = _balagtas;
  bool _pinSelected = false;
  String? _sentReference;
  bool _sending = false;
  bool _allowExit = false;
  bool _confirmingExit = false;
  bool _locating = false;
  String? _locationError;
  String? _submitError;
  int _locationRequest = 0;
  bool _mapReady = false;

  final _location = TextEditingController();
  final _notes = TextEditingController();
  final _mapController = MapController();
  bool _prefilled = false;
  final _guestName = TextEditingController();
  final _guestContact = TextEditingController();
  Map<IncidentType, int> _guestTypes = {};
  bool _loadingTypes = false;
  Object? _typesError;

  bool get _isGuest => widget.guestApi != null;

  @override
  void initState() {
    super.initState();
    if (_isGuest) unawaited(_loadGuestTypes());
  }

  Future<void> _loadGuestTypes() async {
    if (_loadingTypes) return;
    setState(() {
      _loadingTypes = true;
      _typesError = null;
    });
    try {
      final types = await widget.guestApi!.fetchTypes();
      if (mounted) setState(() => _guestTypes = types);
    } catch (error) {
      if (mounted) setState(() => _typesError = error);
    } finally {
      if (mounted) setState(() => _loadingTypes = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilled) return;
    _prefilled = true;
    if (!_isGuest) _location.text = ResidentScope.of(context).profile.address;
  }

  @override
  void dispose() {
    _locationRequest++;
    _location.dispose();
    _notes.dispose();
    _guestName.dispose();
    _guestContact.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _locating) return;
    setState(() => _submitError = null);

    if (!(_formKey.currentState?.validate() ?? true)) {
      setState(
        () => _submitError = 'Please complete all highlighted fields above.',
      );
      return;
    }

    if (_isGuest) {
      final error =
          InputValidation.name(_guestName.text) ??
          InputValidation.phone(_guestContact.text);
      if (error != null) {
        setState(() => _submitError = error);
        return;
      }
    }
    if (_location.text.trim().isEmpty) {
      setState(() => _submitError = 'Please enter the incident location.');
      return;
    }
    if (_notes.text.trim().isEmpty) {
      setState(() => _submitError = 'Please describe what is happening.');
      return;
    }
    if (!_pinSelected) {
      setState(() => _submitError = 'Tap the map to pin the incident location.');
      return;
    }

    setState(() => _sending = true);
    try {
      final reference = _isGuest
          ? await widget.guestApi!.submitReport({
              'incident_type_id': _guestTypes[_type]!,
              'reporter_type': _reporter.name,
              'reporter_name': InputValidation.normalizeName(_guestName.text),
              'reporter_contact': InputValidation.normalizePhone(
                _guestContact.text,
              ),
              'location': _location.text.trim(),
              'lat': _pin.latitude,
              'lng': _pin.longitude,
              'description': _notes.text.trim(),
            })
          : (await ResidentScope.of(context).submitReport(
              type: _type!,
              reporter: _reporter,
              location: _location.text.trim(),
              pin: _pin,
              notes: _notes.text.trim(),
            )).reference;
      if (!mounted) return;
      setState(() {
        _sentReference = reference;
        _step = _Step.sent;
      });
    } catch (error) {
      if (mounted) {
        final msg = 'Could not send the report: ${apiErrorMessage(error)}';
        setState(() => _submitError = msg);
        snack(context, msg);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _reset() {
    setState(() {
      _locationRequest++;
      _locating = false;
      _locationError = null;
      _submitError = null;
      _step = _Step.pick;
      _type = null;
      _reporter = ReporterType.victim;
      _pin = _balagtas;
      _pinSelected = false;
      _notes.clear();
      _location.text = _isGuest
          ? ''
          : ResidentScope.of(context).profile.address;
    });
  }

  Future<void> _useCurrentLocation() async {
    if (_locating || _sending) return;
    final request = ++_locationRequest;
    setState(() {
      _locating = true;
      _locationError = null;
      _submitError = null;
    });
    try {
      final point = await (widget.locationSource ?? DeviceIncidentLocation())
          .current();
      if (!mounted || request != _locationRequest || _step != _Step.details) {
        return;
      }
      setState(() {
        _pin = point;
        _pinSelected = true;
      });
      if (_mapReady) _mapController.move(point, 16);
    } catch (error) {
      if (!mounted || request != _locationRequest) return;
      setState(
        () => _locationError = error is IncidentLocationException
            ? error.message
            : error is TimeoutException
            ? 'Getting your GPS location took too long. Try again outside, or tap the map to place the pin.'
            : 'Could not get your current location. Check location permission, or tap the map to place the pin.',
      );
    } finally {
      if (mounted && request == _locationRequest) {
        setState(() => _locating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowExit || (!_sending && _step != _Step.details),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _confirmingExit) return;
        if (_sending) {
          snack(context, 'Please wait while your report is being sent.');
          return;
        }
        _confirmingExit = true;
        final discard = await confirmDialog(
          context,
          title: 'Leave this report?',
          body: 'Your unsent report details will not be saved.',
          confirmLabel: 'Discard report',
          cancelLabel: 'Keep editing',
          destructive: true,
        );
        _confirmingExit = false;
        if (!mounted || !discard) return;
        setState(() => _allowExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(
          key: ValueKey(_step),
          child: switch (_step) {
            _Step.pick => _buildPick(context),
            _Step.details => _buildDetails(context),
            _Step.sent => _buildSent(context),
          },
        ),
      ),
    );
  }

  // ── Step 1: who + what ──
  Widget _buildPick(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final types = _isGuest
        ? _guestTypes.keys.toList()
        : ResidentScope.of(context).incidentTypes;

    return ListView(
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
              if (_isGuest) ...[
                const AppBanner(
                  tone: AppBannerTone.info,
                  icon: AppIcons.infoCircle,
                  message:
                      'Guest access is limited to submitting incident reports. Sign in for report history, schedules and notifications.',
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              const ResidentFormStep(step: 1, label: 'INCIDENT TYPE'),
              const ResidentHeading(
                'What happened?',
                subtitle:
                    'Choose the type of incident, then add the location and details.',
              ),
              Text(
                'How are you involved?',
                style: MdrrmoTypography.labelSm.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final reporter in ReporterType.values)
                    ChoiceChip(
                      label: Text(
                        reporter == ReporterType.victim
                            ? 'I need help'
                            : 'I witnessed it',
                      ),
                      selected: _reporter == reporter,
                      selectedColor: palette.brandTint,
                      checkmarkColor: palette.brand,
                      side: BorderSide(
                        color: _reporter == reporter
                            ? palette.brand
                            : palette.border,
                      ),
                      onSelected: (_) => setState(() => _reporter = reporter),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Incident type',
                style: MdrrmoTypography.labelSm.copyWith(
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_loadingTypes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: palette.brand),
                  ),
                ),
              if (types.isEmpty && !_loadingTypes)
                AppStateView(
                  icon: AppIcons.infoCircle,
                  title: 'Incident categories unavailable',
                  message: _typesError == null
                      ? 'No incident categories are available. Refresh or contact MDRRMO.'
                      : 'Could not load incident categories. Check your connection and try again.',
                  accent: palette.warningIcon,
                  action: AppButton(
                    label: 'Retry categories',
                    kind: AppButtonKind.outline,
                    onPress: _isGuest
                        ? _loadGuestTypes
                        : ResidentScope.of(context).load,
                  ),
                ),
              for (final type in types)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _TypeTile(type, onTap: () => _choose(type)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _choose(IncidentType t) {
    HapticFeedback.selectionClick();
    setState(() {
      _type = t;
      _step = _Step.details;
      _mapReady = false;
      _submitError = null;
    });
  }

  // ── Step 2: where ──
  Widget _buildDetails(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final type = _type!;

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              children: [
                ContentFrame(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _sending
                              ? null
                              : () => setState(() {
                                  _locationRequest++;
                                  _locating = false;
                                  _locationError = null;
                                  _submitError = null;
                                  _step = _Step.pick;
                                }),
                          icon: const Icon(AppIcons.back, size: 16),
                          label: const Text('Change incident type'),
                        ),
                      ),
                      const ResidentFormStep(
                        step: 2,
                        label: 'LOCATION & DETAILS',
                      ),
                      Surface(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Row(
                          children: [
                            IncidentTile(type, size: 42),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    type.label,
                                    style: MdrrmoTypography.titleMd.copyWith(
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Reporting as ${_reporter == ReporterType.victim ? 'victim' : 'witness'}',
                                    style: MdrrmoTypography.bodySm.copyWith(
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isGuest) ...[
                        AppTextField(
                          controller: _guestName,
                          label: 'Your full name',
                          hint: 'First and last name',
                          maxLength: 121,
                          validator: InputValidation.name,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppTextField(
                          controller: _guestContact,
                          label: 'Contact number',
                          hint: '09xxxxxxxxx or +639xxxxxxxxx',
                          maxLength: 20,
                          keyboardType: TextInputType.phone,
                          validator: InputValidation.phone,
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      AppTextField(
                        controller: _location,
                        maxLength: 255,
                        label: 'Location',
                        hint: 'Street, barangay, landmark',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: _locating
                            ? 'Getting your location…'
                            : 'Use my current location',
                        icon: AppIcons.locate,
                        kind: AppButtonKind.outline,
                        loading: _locating,
                        onPress: _locating || _sending
                            ? null
                            : _useCurrentLocation,
                      ),
                      if (_locationError != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        AppBanner(
                          tone: AppBannerTone.danger,
                          icon: AppIcons.alert,
                          message: _locationError!,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Pin location',
                              style: MdrrmoTypography.labelSm.copyWith(
                                color: palette.textPrimary,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _locating || _sending
                                ? null
                                : () {
                                    setState(() {
                                      _pin = _balagtas;
                                      _pinSelected = false;
                                      _locationError = null;
                                    });
                                    if (_mapReady) {
                                      _mapController.move(_balagtas, 15.5);
                                    }
                                  },
                            icon: const Icon(AppIcons.locate, size: 15),
                            label: const Text('Reset map'),
                          ),
                        ],
                      ),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: _pinSelected
                                ? palette.brand.withValues(alpha: 0.45)
                                : palette.border,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md - 1),
                          child: SizedBox(
                            height: 220,
                            child: FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _pin,
                                initialZoom: 15.5,
                                onMapReady: () {
                                  _mapReady = true;
                                  if (_pinSelected) {
                                    _mapController.move(_pin, 16);
                                  }
                                },
                                onTap: _locating || _sending
                                    ? null
                                    : (_, point) {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          _pin = point;
                                          _pinSelected = true;
                                          _locationError = null;
                                          _submitError = null;
                                        });
                                      },
                              ),
                              children: [
                                const ResilientTiles(),
                                if (_pinSelected)
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: _pin,
                                        width: 44,
                                        height: 52,
                                        alignment: Alignment.topCenter,
                                        child: Icon(
                                          AppIcons.pin,
                                          size: 40,
                                          color: palette.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                                const RichAttributionWidget(
                                  alignment: AttributionAlignment.bottomLeft,
                                  attributions: [
                                    TextSourceAttribution(
                                      '© OpenStreetMap contributors',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_pinSelected)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Latitude: ${_pin.latitude.toStringAsFixed(6)} · Longitude: ${_pin.longitude.toStringAsFixed(6)}',
                            textAlign: TextAlign.center,
                            style: MdrrmoTypography.tabular(
                              MdrrmoTypography.labelSm.copyWith(
                                color: palette.brand,
                              ),
                            ),
                          ),
                        ),
                      Center(
                        child: Text(
                          _pinSelected
                              ? 'Check the address and pin match the incident. Tap the map to adjust.'
                              : 'Use your current location or tap the map to select the incident location.',
                          textAlign: TextAlign.center,
                          style: MdrrmoTypography.bodySm.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppTextField(
                        controller: _notes,
                        maxLength: 2000,
                        label: 'Details',
                        hint: 'What is happening? Anyone hurt?',
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                      ),
                      if (_submitError != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        AppBanner(
                          tone: AppBannerTone.danger,
                          icon: AppIcons.alert,
                          message: _submitError!,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
          child: SafeArea(
            top: false,
            child: ContentFrame(
              child: AppButton(
                label: _sending ? 'Sending report...' : 'Send report to MDRRMO',
                icon: AppIcons.send,
                loading: _sending,
                onPress:
                    _sending ||
                        _locating ||
                        (!_isGuest &&
                            !ResidentScope.of(context).profile.canSubmit)
                    ? null
                    : _send,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 3: confirmation ──
  Widget _buildSent(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        36,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        ContentFrame(
          child: Surface(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: palette.successTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    AppIcons.checkCircle,
                    size: 32,
                    color: palette.success,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Report sent!',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.displaySm.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _isGuest
                      ? 'MDRRMO received your report. Keep this reference when contacting MDRRMO. Guest access does not include report tracking or notifications.'
                      : 'MDRRMO received report $_sentReference. A dispatcher will review it. You\'ll see updates in Notifications.',
                  textAlign: TextAlign.center,
                  style: MdrrmoTypography.bodyMd.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                if (_isGuest) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceSubtle,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: palette.border),
                    ),
                    child: SelectableText(
                      _sentReference ?? '',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.tabular(
                        MdrrmoTypography.titleLg.copyWith(color: palette.brand),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Done',
                  onPress: () {
                    _reset();
                    widget.onDone();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile(this.type, {required this.onTap});
  final IncidentType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: EdgeInsets.zero,
      child: AppRowItem(
        onTap: onTap,
        showChevron: true,
        padding: const EdgeInsets.all(AppSpacing.md + 2),
        leading: IncidentTile(type, soft: true, size: 44),
        title: type.label,
        subtitle: type.hint ?? 'Add location and incident details',
        trailing: Icon(AppIcons.chevron, color: palette.textMuted, size: 18),
      ),
    );
  }
}
