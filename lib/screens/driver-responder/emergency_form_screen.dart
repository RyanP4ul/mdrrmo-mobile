import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/input_validation.dart';
import '../../data/models.dart';
import '../../services/incident_location.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/form_page.dart';
import '../../ui/kit.dart';
import '../../ui/resilient_tiles.dart';
import '../record_details_screen.dart';
import 'responder_widgets.dart';

const _serviceCenter = LatLng(14.8153, 120.9094);

class EmergencyFormScreen extends StatefulWidget {
  const EmergencyFormScreen({super.key, this.locationSource});

  final IncidentLocationSource? locationSource;

  @override
  State<EmergencyFormScreen> createState() => _EmergencyFormScreenState();
}

class _EmergencyFormScreenState extends State<EmergencyFormScreen> {
  final _key = GlobalKey<FormState>();
  final _location = TextEditingController();
  final _patient = TextEditingController();
  final _age = TextEditingController();
  final _symptoms = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNumber = TextEditingController();
  final _mapController = MapController();

  IncidentTypeOption? _type;
  Priority _priority = Priority.medium;
  LatLng? _pin;
  bool _mapReady = false;
  bool _locating = false;
  bool _sending = false;
  bool _submitted = false;
  int _locationRequest = 0;
  String? _locationError;
  String? _error;

  @override
  void dispose() {
    _locationRequest++;
    _location.dispose();
    _patient.dispose();
    _age.dispose();
    _symptoms.dispose();
    _contactPerson.dispose();
    _contactNumber.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating || _sending || _submitted) return;
    final request = ++_locationRequest;
    setState(() {
      _locating = true;
      _locationError = null;
      _error = null;
    });
    try {
      final point = await (widget.locationSource ?? DeviceIncidentLocation())
          .current();
      if (!mounted || request != _locationRequest) return;
      setState(() => _pin = point);
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

  Future<void> _submit() async {
    if (_sending || _submitted || _locating) return;
    if (!_key.currentState!.validate()) {
      setState(
        () => _error = 'Please complete all highlighted fields before submitting.',
      );
      return;
    }

    final selectedType = _type;
    final pin = _pin;
    if (selectedType == null) {
      setState(
        () => _error = 'Choose an emergency type available from MDRRMO.',
      );
      return;
    }
    if (pin == null) {
      setState(() => _error = 'Tap the map or use GPS to pin the incident.');
      return;
    }

    setState(() => _sending = true);
    final confirmed = await confirmDialog(
      context,
      title: 'Submit emergency report?',
      body:
          'This sends the report to dispatchers for review. It does not create an assignment or dispatch a team.',
      confirmLabel: 'Submit report',
    );
    if (!mounted) return;
    if (!confirmed) {
      setState(() => _sending = false);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ResponderScope.of(context).submitEmergency(
        EmergencyReport(
          incidentTypeId: selectedType.id,
          priority: _priority,
          pickup: _location.text.trim(),
          latitude: pin.latitude,
          longitude: pin.longitude,
          patientName: _patient.text.trim(),
          patientAge: int.parse(_age.text.trim()),
          symptoms: _symptoms.text.trim(),
          contactPerson: _contactPerson.text.trim(),
          contactNumber: _contactNumber.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() => _submitted = true);
      final reference = ResponderScope.of(context).submittedReference;
      snack(
        context,
        'Report ${reference ?? ''} submitted for dispatcher review.',
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Could not submit report: ${apiErrorMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final state = ResponderScope.of(context);
    final incidentTypes = state.incidentTypes;
    if (_type == null && incidentTypes.isNotEmpty) {
      _type = incidentTypes.first;
      _priority = _type!.priority;
    }

    if (_submitted) {
      return AppScaffold(
        header: pushedHeader(context, 'Report received'),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            ContentFrame(
              child: ResponderPanel(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        color: palette.successTint,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        AppIcons.checkCircle,
                        size: 38,
                        color: palette.success,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Reference: ${state.submittedReference ?? 'Saved'}',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your report has been submitted for dispatcher review. It is available in Reports I submitted.',
                      textAlign: TextAlign.center,
                      style: MdrrmoTypography.bodyMd.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (state.submittedId != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RecordDetailsScreen(
                              id: state.submittedId!,
                              driver: true,
                            ),
                          ),
                        ),
                        child: const Text('View submitted report'),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: AppButton(
                        label: 'Done',
                        onPress: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return FormPage(
      title: 'Emergency report',
      formKey: _key,
      submitLabel: _submitted
          ? 'Done'
          : _sending
          ? 'Submitting…'
          : 'Submit report',
      onSubmit: _submitted
          ? () => Navigator.of(context).pop()
          : _sending || _locating
          ? null
          : _submit,
      children: [
        if (_error != null) ...[
          AppBanner(
            tone: AppBannerTone.danger,
            icon: AppIcons.alert,
            message: _error!,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (state.isLoading)
          const Center(child: CircularProgressIndicator())
        else if (incidentTypes.isEmpty)
          AppBanner(
            tone: AppBannerTone.danger,
            icon: AppIcons.alert,
            message: state.loadError == null
                ? 'No incident types are currently available from MDRRMO.'
                : 'Could not load incident types: ${apiErrorMessage(state.loadError!)}',
          )
        else
          FormGroup(
            title: 'Emergency details',
            icon: AppIcons.alert,
            fields: [
              AppSelect(
                label: 'Emergency type',
                options: incidentTypes.map((option) => option.name).toList(),
                value: _type!.name,
                onChange: (name) => setState(() {
                  _type = incidentTypes.firstWhere(
                    (option) => option.name == name,
                  );
                  _priority = _type!.priority;
                }),
              ),
              AppSelect(
                label: 'Priority level',
                options: const ['Low', 'Medium', 'High', 'Critical'],
                value: priorityLabel(_priority),
                onChange: (value) => setState(
                  () => _priority = Priority.values.firstWhere(
                    (priority) => priorityLabel(priority) == value,
                  ),
                ),
              ),
              AppTextField(
                controller: _location,
                label: 'Incident location',
                hint: 'Street, barangay, landmark',
                validator: _required('Enter the incident location'),
              ),
              AppButton(
                label: _locating
                    ? 'Getting your location...'
                    : 'Use my current location',
                icon: AppIcons.locate,
                kind: AppButtonKind.outline,
                loading: _locating,
                onPress: _locating || _sending ? null : _useCurrentLocation,
              ),
              if (_locationError != null)
                AppBanner(
                  tone: AppBannerTone.warning,
                  icon: AppIcons.alert,
                  message: _locationError!,
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tap the map to pin the incident location.',
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  if (_pin != null)
                    TextButton.icon(
                      onPressed: _locating || _sending
                          ? null
                          : () {
                              setState(() {
                                _pin = null;
                                _locationError = null;
                              });
                              if (_mapReady) {
                                _mapController.move(_serviceCenter, 15);
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
                    color: _pin != null
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
                        initialCenter: _serviceCenter,
                        initialZoom: 15,
                        onMapReady: () {
                          _mapReady = true;
                          if (_pin != null) {
                            _mapController.move(_pin!, 16);
                          }
                        },
                        onTap: _locating || _sending
                            ? null
                            : (_, point) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _pin = point;
                                  _error = null;
                                });
                              },
                      ),
                      children: [
                        const ResilientTiles(),
                        if (_pin != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _pin!,
                                width: 44,
                                height: 48,
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
                            TextSourceAttribution('© OpenStreetMap contributors'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_pin != null)
                Text(
                  'Pinned: ${_pin!.latitude.toStringAsFixed(5)}, ${_pin!.longitude.toStringAsFixed(5)}',
                  style: MdrrmoTypography.tabular(
                    MdrrmoTypography.labelSm.copyWith(color: palette.brand),
                  ),
                ),
            ],
          ),
        if (!state.isLoading && incidentTypes.isNotEmpty) ...[
          FormGroup(
            title: 'Patient information',
            icon: AppIcons.user,
            fields: [
              AppTextField(
                controller: _patient,
                label: 'Patient name',
                hint: 'Full name',
                validator: _required('Enter the patient name'),
              ),
              AppTextField(
                controller: _age,
                label: 'Patient age',
                hint: 'Years',
                keyboardType: TextInputType.number,
                validator: (value) {
                  final age = int.tryParse(value?.trim() ?? '');
                  return age == null || age < 0 || age > 120
                      ? 'Enter a valid age'
                      : null;
                },
              ),
              AppTextField(
                controller: _symptoms,
                maxLength: 2000,
                label: 'Symptoms / condition',
                hint: 'Describe what is happening',
                maxLines: 3,
                validator: _required('Describe the symptoms or condition'),
              ),
            ],
          ),
          FormGroup(
            title: 'Contact information',
            icon: AppIcons.phone,
            fields: [
              AppTextField(
                controller: _contactPerson,
                label: 'Contact person',
                hint: 'Who should we call?',
                validator: _required('Enter a contact person'),
              ),
              AppTextField(
                controller: _contactNumber,
                label: 'Contact number',
                hint: '09XX XXX XXXX',
                keyboardType: TextInputType.phone,
                maxLength: 20,
                validator: InputValidation.phone,
              ),
            ],
          ),
        ],
      ],
    );
  }

  String? Function(String?) _required(String message) =>
      (value) => value == null || value.trim().isEmpty ? message : null;
}
