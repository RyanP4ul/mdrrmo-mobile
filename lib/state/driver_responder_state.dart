import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../data/api/driver_service.api.dart';
import '../data/models.dart';
import '../data/paged_records.dart';
import '../data/input_validation.dart';

import 'package:dio/dio.dart' show DioException, CancelToken;

class ResponderState extends ChangeNotifier {
  ResponderState({DriverApi? api}) : _api = api ?? DriverApi() {
    unawaited(load());
  }

  final DriverApi _api;
  DriverApi get api => _api;

  Availability availability = Availability.offDuty;
  Assignment? assignment;
  List<Assignment> assignments = [];
  int unreadCount = 0;
  int? submittedId;
  List<TeamMember> teams = const [];
  List<TeamRole> teamRoles = const [];
  bool canDispatch = false;
  bool get isDriver =>
      teamRoles.isEmpty || teamRoles.any((role) => role.isDriver);
  List<Dispatch> history = const [];
  List<IncidentTypeOption> incidentTypes = const [];
  DriverProfile profile = DriverProfile();
  bool isLoading = true;
  bool isSaving = false;
  Object? loadError;
  Object? actionError;
  bool _isDisposed = false;
  bool _loading = false;
  bool hasLoaded = false;
  String? submittedReference;
  List<DriverVehicle> vehicles = [];
  int? selectedVehicleId;
  int? historyNext;
  bool loadingHistory = false;
  bool _expandedHistory = false;
  Object? historyError;

  Future<void> load() async {
    if (_loading || isSaving || _isDisposed) return;
    _loading = true;
    isLoading = true;
    loadError = null;
    _notify();

    try {
      final results = await Future.wait([
        _api.fetchBootstrap(),
        _api.fetchHistoryPage(),
      ]);
      if (_isDisposed) return;

      final bootstrap = results[0] as Map<String, dynamic>;
      final historyPage = results[1] as RecordPage;
      final nextProfile = DriverProfile.fromJson(
        _requiredMap(bootstrap['profile']),
      );
      final nextTeams = _parseList(bootstrap['teams'], TeamMember.fromJson);
      final nextTeamRoles = bootstrap['team_roles'] == null
          ? <TeamRole>[]
          : _parseList(bootstrap['team_roles'], TeamRole.fromJson);
      final nextTypes = _parseList(
        bootstrap['incident_types'],
        IncidentTypeOption.fromJson,
      );
      final nextAssignments = bootstrap['assignments'] is List
          ? _parseList(bootstrap['assignments'], Assignment.fromJson)
          : <Assignment>[];
      final nextAssignment = nextAssignments.isNotEmpty
          ? (nextAssignments.where((a) => a.id == assignment?.id).firstOrNull ??
                nextAssignments.first)
          : bootstrap['assignment'] == null
          ? null
          : Assignment.fromJson(_requiredMap(bootstrap['assignment']));
      final nextUnread = bootstrap['unread_count'] ?? 0;
      if (nextUnread is! int || nextUnread < 0) {
        throw const FormatException('Invalid unread count.');
      }
      final nextHistory = historyPage.items.map(Dispatch.fromJson).toList();
      final nextVehicles = bootstrap['vehicles'] == null
          ? <DriverVehicle>[]
          : _parseList(bootstrap['vehicles'], DriverVehicle.fromJson);
      final activeVehicleId = _requiredMap(bootstrap['profile'])['vehicle_id'];
      if (activeVehicleId != null && activeVehicleId is! int) {
        throw const FormatException('Invalid selected vehicle.');
      }
      final nextSelected = nextAssignment != null
          ? nextAssignment.vehicleId ?? activeVehicleId as int?
          : nextVehicles.any((v) => v.id == selectedVehicleId)
          ? selectedVehicleId
          : activeVehicleId as int?;
      final selected = nextVehicles
          .where((v) => v.id == nextSelected)
          .firstOrNull;
      final nextAvailability = nextAssignment == null
          ? _availabilityFromApi(
              selected?.status ??
                  _requiredMap(bootstrap['profile'])['vehicle_status'],
            )
          : Availability.dispatched;
      if (selected != null) {
        nextProfile.vehicleType = selected.label;
        nextProfile.vehicleNumber = selected.number;
      }
      nextProfile.status = _labelFromAvailability(nextAvailability);
      final overlapsHistory = nextHistory.any(
        (item) => history.any((old) => old.id == item.id),
      );
      vehicles = nextVehicles;
      selectedVehicleId = nextSelected;
      profile = nextProfile;
      teams = nextTeams;
      teamRoles = nextTeamRoles;
      canDispatch =
          bootstrap['can_dispatch'] as bool? ??
          (nextTeamRoles.isEmpty || nextTeamRoles.any((role) => role.isDriver));
      incidentTypes = nextTypes;
      assignment = nextAssignment;
      assignments = nextAssignments.isNotEmpty
          ? nextAssignments
          : nextAssignment == null
          ? []
          : [nextAssignment];
      unreadCount = nextUnread;
      history = hasLoaded
          ? mergeRecords(
              nextHistory,
              history,
              (item) => item.recordId ?? item.id,
            )
          : nextHistory;
      if (!_expandedHistory || !overlapsHistory) {
        historyNext = historyPage.nextBefore;
        _expandedHistory = false;
      }
      availability = nextAvailability;
      hasLoaded = true;
    } catch (error) {
      if (_isDisposed) return;
      if (error is DioException && CancelToken.isCancel(error)) return;
      loadError = error;
    } finally {
      _loading = false;
      if (!_isDisposed) {
        isLoading = false;
        _notify();
      }
    }
  }

  Future<void> advanceAssignment() async {
    final activeAssignment = assignment;
    if (!canDispatch ||
        _isDisposed ||
        activeAssignment == null ||
        isSaving ||
        _loading ||
        loadError != null) {
      return;
    }

    final nextStatus = switch (activeAssignment.step) {
      0 => 'en-route',
      1 => 'on-scene',
      _ => 'available',
    };
    await _runAction(() async {
      final updated = await _api.updateAssignmentStatus(
        activeAssignment.id,
        nextStatus,
      );
      if (_isDisposed) return;
      if (updated == null) {
        assignments.removeWhere((item) => item.id == activeAssignment.id);
        assignment = assignments.firstOrNull;
        selectedVehicleId = assignment?.vehicleId ?? selectedVehicleId;
        final nextVehicle = vehicles
            .where((v) => v.id == selectedVehicleId)
            .firstOrNull;
        if (nextVehicle != null) {
          profile.vehicleType = nextVehicle.label;
          profile.vehicleNumber = nextVehicle.number;
        }
        availability = assignment == null
            ? Availability.available
            : Availability.dispatched;
        profile.status = _labelFromAvailability(availability);
        try {
          final page = await _api.fetchHistoryPage();
          if (_isDisposed) return;
          history = mergeRecords(
            page.items.map(Dispatch.fromJson).toList(),
            history,
            (item) => item.recordId ?? item.id,
          );
          if (!_expandedHistory) historyNext = page.nextBefore;
        } catch (error) {
          loadError = error;
        }
      } else {
        assignment = Assignment.fromJson(updated);
        assignments = [
          for (final a in assignments)
            if (a.id == assignment!.id) assignment! else a,
        ];
        availability = Availability.dispatched;
        profile.status = _labelFromAvailability(availability);
      }
    });
  }

  Future<void> setAvailability(Availability value) async {
    if (_isDisposed ||
        assignment != null ||
        isSaving ||
        _loading ||
        !hasLoaded ||
        loadError != null) {
      return;
    }
    if (selectedVehicleId == null) {
      throw StateError('Choose your vehicle first.');
    }
    await _runAction(() async {
      final status = value == Availability.available ? 'available' : 'offline';
      final savedStatus = await _api.updateAvailability(
        status,
        vehicleId: selectedVehicleId,
      );
      if (_isDisposed) return;
      availability = _availabilityFromApi(savedStatus);
      profile.status = _labelFromAvailability(availability);
    });
  }

  Future<void> saveProfile({
    required String name,
    required String contact,
    String vehicleType = '',
    String vehicleNumber = '',
  }) async {
    if (_isDisposed || isSaving || _loading) {
      throw StateError('Please wait for the current request to finish.');
    }
    final validation =
        InputValidation.name(name) ?? InputValidation.phone(contact);
    if (validation != null) throw ArgumentError(validation);
    await _runAction(() async {
      final saved = await _api.updateProfile(
        name: name,
        vehicleId: selectedVehicleId,
        contact: contact,
        vehicleType: vehicleType,
        vehicleNumber: vehicleNumber,
      );
      if (_isDisposed) return;
      profile = DriverProfile.fromJson(saved);
      availability = assignment == null
          ? _availabilityFromApi(saved['vehicle_status'])
          : Availability.dispatched;
      profile.status = _labelFromAvailability(availability);
    });
  }

  Future<void> submitEmergency(EmergencyReport report) async {
    if (_isDisposed || isSaving || _loading) {
      throw StateError('Please wait for the current request to finish.');
    }
    final validation =
        InputValidation.text(report.pickup, 'Incident location', 255) ??
        InputValidation.coordinates(report.latitude, report.longitude) ??
        InputValidation.text(report.patientName, 'Patient name', 255) ??
        InputValidation.text(report.symptoms, 'Symptoms', 2000) ??
        InputValidation.text(report.contactPerson, 'Contact person', 255) ??
        InputValidation.phone(report.contactNumber);
    if (validation != null) throw ArgumentError(validation);
    if (report.patientAge == null ||
        report.patientAge! < 0 ||
        report.patientAge! > 120) {
      throw ArgumentError('Enter a valid age');
    }
    await _runAction(() async {
      final saved = await _api.submitReport({
        'incident_type_id': report.incidentTypeId,
        'location': report.pickup,
        'lat': report.latitude,
        'lng': report.longitude,
        'priority': _priorityToApi(report.priority),
        'patient_name': report.patientName,
        'patient_age': report.patientAge,
        'symptoms': report.symptoms,
        'contact_person': report.contactPerson,
        'contact_number': InputValidation.normalizePhone(report.contactNumber),
      });
      if (!_isDisposed) {
        submittedReference = saved['reference']?.toString();
        submittedId = saved['id'] as int?;
      }
    });
  }

  void selectAssignment(int id) {
    if (_isDisposed || isSaving || _loading) return;
    assignment = assignments.firstWhere((a) => a.id == id);
    selectedVehicleId = assignment!.vehicleId ?? selectedVehicleId;
    final vehicle = vehicles
        .where((item) => item.id == selectedVehicleId)
        .firstOrNull;
    if (vehicle != null) {
      profile.vehicleType = vehicle.label;
      profile.vehicleNumber = vehicle.number;
    }
    _notify();
  }

  void selectVehicle(int id) {
    if (_isDisposed || isSaving || _loading || assignment != null) return;
    final vehicle = vehicles.firstWhere((item) => item.id == id);
    selectedVehicleId = id;
    profile.vehicleType = vehicle.label;
    profile.vehicleNumber = vehicle.number;
    availability = _availabilityFromApi(vehicle.status);
    profile.status = _labelFromAvailability(availability);
    _notify();
  }

  Future<void> loadMoreHistory() async {
    final cursor = historyNext;
    if (_isDisposed || _loading || isSaving || cursor == null) return;
    loadingHistory = true;
    historyError = null;
    isSaving = true;
    _notify();
    try {
      final page = await _api.fetchHistoryPage(before: cursor);
      if (_isDisposed) return;
      history = mergeRecords(
        history,
        page.items.map(Dispatch.fromJson).toList(),
        (item) => item.recordId ?? item.id,
      );
      historyNext = page.nextBefore;
      _expandedHistory = true;
    } catch (error) {
      if (!_isDisposed) historyError = error;
    } finally {
      loadingHistory = false;
      isSaving = false;
      _notify();
    }
  }

  Future<void> _runAction(Future<void> Function() action) async {
    isSaving = true;
    actionError = null;
    _notify();
    try {
      await action();
    } catch (error) {
      actionError = error;
      rethrow;
    } finally {
      isSaving = false;
      _notify();
    }
  }

  Future<void> setTeamRole(int teamId, bool driver) async {
    if (_isDisposed || isSaving || _loading) return;
    final previousRoles = teamRoles;
    final role = driver ? 'Driver' : 'Responder';
    teamRoles = [
      for (final team in teamRoles)
        if (team.teamId == teamId)
          TeamRole(
            teamId: team.teamId,
            teamName: team.teamName,
            role: role,
            canBeDriver: team.canBeDriver,
            locked: team.locked,
            driverName: team.driverName,
            activeVehicleId: team.activeVehicleId,
            activeVehicle: team.activeVehicle,
            vehicles: team.vehicles,
          )
        else
          team,
    ];
    try {
      await _runAction(() async {
        final data = await _api.updateTeamRole(teamId, role);
        final nextRoles = _parseList(data['team_roles'], TeamRole.fromJson);
        final nextMembers = _parseList(data['teams'], TeamMember.fromJson);
        if (_isDisposed) return;
        teamRoles = nextRoles;
        teams = nextMembers;
        canDispatch =
            assignments.isNotEmpty || nextRoles.any((team) => team.isDriver);
      });
    } catch (_) {
      teamRoles = previousRoles;
      _notify();
      await load();
      rethrow;
    }
  }

  Future<void> switchTeamVehicle(int teamId, int vehicleId) async {
    if (_isDisposed || isSaving || _loading) return;
    try {
      await _runAction(() async {
        final data = await _api.switchTeamVehicle(teamId, vehicleId);
        if (_isDisposed) return;
        if (data['team_roles'] != null) {
          teamRoles = _parseList(data['team_roles'], TeamRole.fromJson);
        }
        if (data['vehicles'] != null) {
          vehicles = _parseList(data['vehicles'], DriverVehicle.fromJson);
        }
        selectedVehicleId = vehicleId;
        final vehicle = vehicles
            .where((item) => item.id == vehicleId)
            .firstOrNull;
        if (vehicle != null) {
          profile.vehicleType = vehicle.label;
          profile.vehicleNumber = vehicle.number;
          availability = _availabilityFromApi(vehicle.status);
          profile.status = _labelFromAvailability(availability);
        }
      });
    } catch (_) {
      await load();
      rethrow;
    }
    await load();
  }

  Future<Map<String, dynamic>> submitMaintenanceReport({
    required int vehicleId,
    required String issueType,
    required String severity,
    required String description,
    int? mileage,
    bool recommendOutOfService = false,
  }) async {
    if (_isDisposed || isSaving || _loading) {
      throw StateError('Please wait for the current request to finish.');
    }
    if (!isDriver) {
      throw StateError('Only the team Driver can submit maintenance reports.');
    }
    final validation = InputValidation.text(
      description,
      'Issue description',
      2000,
    );
    if (validation != null) throw ArgumentError(validation);
    late Map<String, dynamic> created;
    await _runAction(() async {
      created = await _api.submitMaintenanceReport({
        'vehicle_id': vehicleId,
        'issue_type': issueType,
        'severity': severity,
        'mileage': ?mileage,
        'description': description.trim(),
        'recommend_out_of_service': recommendOutOfService,
      });
    });
    await load();
    return created;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _api.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  Map<String, dynamic> _requiredMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid driver data from the server.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<T> _parseList<T>(Object? value, T Function(Map<String, dynamic>) parse) {
    if (value is! List) {
      throw const FormatException('Invalid list from the server.');
    }
    return value.map((item) => parse(_requiredMap(item))).toList();
  }

  Availability _availabilityFromApi(Object? status) {
    return switch (status?.toString().toLowerCase()) {
      'available' => Availability.available,
      'offline' || 'maintenance' => Availability.offDuty,
      'en-route' || 'on-scene' || 'returning' => Availability.dispatched,
      _ => throw FormatException('Unsupported vehicle status: $status'),
    };
  }

  String _labelFromAvailability(Availability value) => switch (value) {
    Availability.available => 'Available',
    Availability.dispatched => 'Dispatched',
    Availability.offDuty => 'Off duty',
  };

  String _priorityToApi(Priority value) => value.name;
}

class ResponderScope extends InheritedNotifier<ResponderState> {
  const ResponderScope({
    super.key,
    required ResponderState state,
    required super.child,
  }) : super(notifier: state);

  static ResponderState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ResponderScope>()!.notifier!;
}
