enum Availability { available, dispatched, offDuty }

enum DispatchStatus { completed, invalid, unknown }

enum Priority { low, medium, high, critical }

const vehicleTypes = {
  'ambulance': 'Ambulance',
  'fire-truck': 'Fire Truck',
  'rescue-van': 'Rescue Vehicle',
  'police-car': 'Police Car',
  'utility-truck': 'Utility Truck',
};

String vehicleTypeToApi(String label) => vehicleTypes.entries
    .firstWhere(
      (entry) => entry.value == label,
      orElse: () => throw FormatException('Unsupported vehicle type: $label'),
    )
    .key;

Priority priorityFromApi(Object? value) {
  switch (value?.toString().toLowerCase()) {
    case 'low':
      return Priority.low;
    case 'medium':
      return Priority.medium;
    case 'critical':
      return Priority.critical;
    case 'high':
      return Priority.high;
    default:
      throw FormatException(
        'Unsupported priority received from the server: $value',
      );
  }
}

class TeamRole {
  const TeamRole({
    required this.teamId,
    required this.teamName,
    required this.role,
    required this.canBeDriver,
    required this.locked,
    this.driverName,
    this.activeVehicleId,
    this.activeVehicle,
    this.vehicles = const [],
  });
  final int teamId;
  final String teamName, role;
  final bool canBeDriver, locked;
  final String? driverName;
  final int? activeVehicleId;
  final DriverVehicle? activeVehicle;
  final List<DriverVehicle> vehicles;
  bool get isDriver => role == 'Driver';

  factory TeamRole.fromJson(Map<String, dynamic> json) {
    final rawVehicles = json['vehicles'];
    final parsedVehicles = rawVehicles is List
        ? rawVehicles
              .whereType<Map>()
              .map((v) => DriverVehicle.fromJson(Map<String, dynamic>.from(v)))
              .toList()
        : const <DriverVehicle>[];
    final rawActive = json['active_vehicle'];
    final parsedActive = rawActive is Map
        ? DriverVehicle.fromJson(Map<String, dynamic>.from(rawActive))
        : parsedVehicles.where((v) => v.isActive).firstOrNull ??
              parsedVehicles.firstOrNull;

    return TeamRole(
      teamId: json['team_id'] as int,
      teamName: json['team_name'] as String,
      role: json['role'] as String,
      canBeDriver: json['can_be_driver'] as bool,
      locked: json['locked'] as bool,
      driverName: json['driver_name'] as String?,
      activeVehicleId: json['active_vehicle_id'] as int? ?? parsedActive?.id,
      activeVehicle: parsedActive,
      vehicles: parsedVehicles,
    );
  }
}

class TeamMember {
  const TeamMember(
    this.name,
    this.role, {
    this.online = false,
    this.contact = '',
  });

  final String name;
  final String role;
  final bool online;
  final String contact;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      json['name'] as String? ?? 'Unknown',
      json['role'] as String? ?? 'No role assigned',
      online: json['online'] as bool? ?? false,
      contact: json['contact']?.toString() ?? '',
    );
  }
}

class Assignment {
  Assignment({
    required this.id,
    this.reference = '',
    required this.pickup,
    required this.destination,
    required this.emergencyType,
    required this.priority,
    required this.step,
    this.latitude,
    this.longitude,
    this.isNew = false,
    this.vehicleId,
    this.canAdvance = true,
    this.reportedAt,
    this.patientName = '',
    this.authorizedPassenger = '',
    this.hasDriverForm = false,
    this.hospitalId,
    this.unavailableHospitalIds = const [],
  });

  final int id;
  final String reference;
  final int? vehicleId;
  final bool canAdvance;
  final String pickup;
  final String destination;
  final String emergencyType;
  final Priority priority;
  final double? latitude;
  final double? longitude;
  final DateTime? reportedAt;
  final String patientName;
  final String authorizedPassenger;
  final bool hasDriverForm;
  final int? hospitalId;
  final List<int> unavailableHospitalIds;
  int step;
  bool isNew;

  static const steps = [
    'Start trip',
    'En route',
    'On scene',
    'Transporting',
    'Complete',
  ];
  static const actions = [
    'Start trip',
    'En route',
    'Transporting',
    'Complete dispatch',
    'Complete dispatch',
  ];

  bool get hasActionButton => step == 0 || step == 2 || step == 3;

  String get actionLabel => actions[step.clamp(0, actions.length - 1).toInt()];

  factory Assignment.fromJson(Map<String, dynamic> json) {
    final trip = json['trip'] as Map?;
    final tripStatus = trip?['arrived_at'] != null
        ? 'arrived'
        : trip?['picked_up_at'] != null
        ? 'transporting'
        : trip?['on_scene_at'] != null
        ? 'on-scene'
        : trip?['started_at'] != null
        ? 'en-route'
        : null;
    final vehicleStatus =
        (json['response_status'] ??
                tripStatus ??
                json['vehicle_status'] ??
                'available')
            .toString()
            .toLowerCase();
    final step = switch (vehicleStatus) {
      'en-route' => 1,
      'on-scene' || 'returning' => 2,
      'transporting' => 3,
      'arrived' => 4,
      'available' || 'offline' || 'maintenance' => 0,
      _ => throw FormatException(
        'Unsupported assignment vehicle status: $vehicleStatus',
      ),
    };
    final reportId = json['id'];
    if (reportId is! int) {
      throw const FormatException('Assignment is missing a valid report ID.');
    }

    final rawHospitalId = json['hospital_id'] ?? trip?['hospital_id'];
    final hospitalId = rawHospitalId is int
        ? rawHospitalId
        : int.tryParse('$rawHospitalId');
    final rawUnavailable =
        (json['unavailable_hospital_ids'] ??
                trip?['unavailable_hospital_ids'])
            as List?;
    final unavailableHospitalIds = rawUnavailable == null
        ? const <int>[]
        : rawUnavailable
              .map((e) => e is int ? e : int.tryParse('$e'))
              .whereType<int>()
              .toList(growable: false);

    return Assignment(
      id: reportId,
      reference: json['reference']?.toString() ?? 'RPT-$reportId',
      vehicleId: json['vehicle_id'] as int?,
      canAdvance: json['status'] == 'dispatched',
      pickup: json['location'] as String? ?? 'Location not provided',
      destination:
          (json['trip'] as Map?)?['destination']?.toString() ??
          'Destination not recorded',
      emergencyType: json['type'] as String? ?? 'Emergency',
      priority: priorityFromApi(json['priority']),
      step: step,
      latitude: (json['lat'] as num?)?.toDouble(),
      longitude: (json['lng'] as num?)?.toDouble(),
      isNew: json['status']?.toString() == 'dispatched',
      reportedAt: DateTime.tryParse(json['reported_at']?.toString() ?? ''),
      patientName: json['patient_name']?.toString() ?? '',
      authorizedPassenger: json['authorized_passenger']?.toString() ?? '',
      hasDriverForm: json['has_driver_form'] == true,
      hospitalId: hospitalId,
      unavailableHospitalIds: unavailableHospitalIds,
    );
  }
}

class Dispatch {
  const Dispatch({
    required this.id,
    this.recordId,
    required this.time,
    required this.pickup,
    required this.destination,
    required this.driver,
    required this.vehicle,
    required this.status,
    required this.durationMin,
    required this.distanceKm,
    required this.emergencyType,
    required this.priority,
    this.resolvedAt,
    this.transportArrivedAt,
    this.patientName = '',
    this.authorizedPassenger = '',
    this.hasDriverForm = false,
  });

  final String id;
  final int? recordId;
  final DateTime time;
  final String pickup;
  final String destination;
  final String driver;
  final String vehicle;
  final DispatchStatus status;
  final int? durationMin;
  final double? distanceKm;
  final String emergencyType;
  final Priority priority;
  final DateTime? resolvedAt;
  final String patientName;
  final String authorizedPassenger;
  final bool hasDriverForm;

  DateTime? get arrivedAt => transportArrivedAt;
  final DateTime? transportArrivedAt;

  static int? _tripDuration(Map? trip) {
    final pickup = DateTime.tryParse('${trip?['picked_up_at']}');
    final arrival = DateTime.tryParse('${trip?['arrived_at']}');
    return pickup == null || arrival == null
        ? null
        : arrival.difference(pickup).inMinutes;
  }

  factory Dispatch.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString().toLowerCase();
    final timestamp = DateTime.tryParse(json['reported_at']?.toString() ?? '');
    if (timestamp == null) {
      throw const FormatException('Dispatch is missing a valid report time.');
    }

    if (json['id'] is! int) {
      throw const FormatException('Dispatch is missing a valid ID.');
    }
    return Dispatch(
      recordId: json['id'] as int,
      id: json['reference']?.toString() ?? json['id']?.toString() ?? '',
      time: timestamp,
      pickup: json['location'] as String? ?? 'Location not provided',
      destination:
          (json['trip'] as Map?)?['destination']?.toString() ??
          'Destination not recorded',
      driver: json['driver'] as String? ?? 'You',
      vehicle: json['vehicle'] as String? ?? 'Vehicle not assigned',
      status: status == 'resolved'
          ? DispatchStatus.completed
          : status == 'invalid'
          ? DispatchStatus.invalid
          : DispatchStatus.unknown,
      durationMin: _tripDuration(json['trip'] as Map?),
      distanceKm: double.tryParse('${(json['trip'] as Map?)?['distance_km']}'),
      emergencyType: json['type'] as String? ?? 'Emergency',
      priority: priorityFromApi(json['priority']),
      resolvedAt: DateTime.tryParse(json['resolved_at']?.toString() ?? ''),
      transportArrivedAt: DateTime.tryParse(
        '${(json['trip'] as Map?)?['arrived_at']}',
      ),
      patientName: json['patient_name']?.toString() ?? '',
      authorizedPassenger: json['authorized_passenger']?.toString() ?? '',
      hasDriverForm: json['has_driver_form'] == true,
    );
  }
}

class DriverVehicle {
  const DriverVehicle(
    this.id,
    this.type,
    this.number,
    this.status, {
    this.name = '',
    this.photoUrl,
    this.maintenanceWarning,
    this.hasMaintenanceWarning = false,
    this.openMaintenanceCount = 0,
    this.isActive = false,
    this.canSelect = true,
  });
  final int id;
  final String type;
  final String number;
  final String status;
  final String name;
  final String? photoUrl;
  final String? maintenanceWarning;
  final bool hasMaintenanceWarning;
  final int openMaintenanceCount;
  final bool isActive;
  final bool canSelect;
  String get label => vehicleTypes[type] ?? type;
  String get displayName => name.trim().isNotEmpty ? name : '$label $number';
  factory DriverVehicle.fromJson(Map<String, dynamic> json) {
    final vStatus = (json['vehicle_status'] ?? json['status'])?.toString();
    final vNumber = (json['vehicle_number'] ?? json['plate_number'])
        ?.toString();
    if (json['id'] is! int ||
        json['vehicle_type'] is! String ||
        !vehicleTypes.containsKey(json['vehicle_type']) ||
        vNumber == null) {
      throw const FormatException('Invalid vehicle details from the server.');
    }
    if (![
      'available',
      'offline',
      'maintenance',
      'en-route',
      'on-scene',
      'returning',
    ].contains(vStatus)) {
      throw const FormatException(
        'Unsupported vehicle status from the server.',
      );
    }
    final warning = json['maintenance_warning']?.toString();
    return DriverVehicle(
      json['id'] as int,
      json['vehicle_type'] as String,
      vNumber,
      vStatus!,
      name: json['name']?.toString() ?? '',
      photoUrl: json['photo_url']?.toString(),
      maintenanceWarning: warning != null && warning.trim().isNotEmpty
          ? warning.trim()
          : null,
      hasMaintenanceWarning:
          json['has_maintenance_warning'] == true ||
          vStatus == 'maintenance' ||
          (warning != null && warning.trim().isNotEmpty),
      openMaintenanceCount:
          (json['open_maintenance_count'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] == true,
      canSelect: json['can_select'] as bool? ?? (vStatus != 'maintenance'),
    );
  }
}

class DriverProfile {
  DriverProfile({
    this.name = '',
    this.contact = '',
    this.vehicleType = 'Ambulance',
    this.vehicleNumber = '',
    this.status = 'Available',
  });

  String name;
  String contact;
  String vehicleType;
  String vehicleNumber;
  String status;

  String get apiVehicleType => vehicleTypeToApi(vehicleType);

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final rawType = json['vehicle_type']?.toString().toLowerCase();
    if (rawType != null && !vehicleTypes.containsKey(rawType)) {
      throw FormatException('Unsupported vehicle type: $rawType');
    }
    final vehicleType = vehicleTypes[rawType] ?? 'Ambulance';
    final rawStatus = json['vehicle_status']?.toString().toLowerCase();
    if (rawStatus != null &&
        ![
          'available',
          'offline',
          'maintenance',
          'en-route',
          'on-scene',
          'returning',
        ].contains(rawStatus)) {
      throw FormatException('Unsupported vehicle status: $rawStatus');
    }
    final status = switch (rawStatus) {
      'offline' || 'maintenance' => 'Off duty',
      'en-route' || 'on-scene' || 'returning' => 'Dispatched',
      _ => 'Available',
    };

    return DriverProfile(
      name: json['name'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      vehicleType: vehicleType,
      vehicleNumber: json['vehicle_number'] as String? ?? '',
      status: status,
    );
  }
}

class IncidentTypeOption {
  const IncidentTypeOption({
    required this.id,
    required this.name,
    required this.priority,
  });

  final int id;
  final String name;
  final Priority priority;

  factory IncidentTypeOption.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) {
      throw const FormatException('Incident type is missing a valid ID.');
    }
    return IncidentTypeOption(
      id: id,
      name: json['name'] as String? ?? 'Emergency',
      priority: priorityFromApi(json['priority']),
    );
  }
}

class EmergencyReport {
  const EmergencyReport({
    required this.incidentTypeId,
    required this.priority,
    required this.pickup,
    required this.latitude,
    required this.longitude,
    required this.patientName,
    required this.patientAge,
    required this.symptoms,
    required this.contactPerson,
    required this.contactNumber,
  });

  final int incidentTypeId;
  final Priority priority;
  final String pickup;
  final double latitude;
  final double longitude;
  final String patientName;
  final int? patientAge;
  final String symptoms;
  final String contactPerson;
  final String contactNumber;
}
