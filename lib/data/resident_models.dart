import 'package:material_ui/material_ui.dart';

import '../ui/kit.dart';

enum ReporterType { victim, witness }

enum IncidentStatus {
  active,
  responding,
  resolved,
  invalid,
  withdrawn,
  unknown,
}

enum NotificationKind { resolved, onTheWay, received, submitted, rate }

class IncidentType {
  const IncidentType(
    this.label,
    this.icon,
    this.color,
    this.onColor, {
    this.hint,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color onColor; // readable text colour on top of [color]
  final String? hint;

  @override
  bool operator ==(Object other) =>
      other is IncidentType && other.label == label;
  @override
  int get hashCode => label.hashCode;

  static const fire = IncidentType(
    'Fire',
    AppIcons.fire,
    Color(0xFFE11D48),
    Colors.white,
  );
  static const medical = IncidentType(
    'Medical Emergency',
    AppIcons.medical,
    Color(0xFF16A34A),
    Colors.white,
  );
  static const disaster = IncidentType(
    'Disaster',
    AppIcons.alert,
    Color(0xFFFACC15),
    Color(0xFF422006),
    hint: 'Earthquakes, floods, etc.',
  );
  static const vehicular = IncidentType(
    'Vehicular Accident',
    AppIcons.car,
    Color(0xFF2563EB),
    Colors.white,
  );
  static const trauma = IncidentType(
    'Trauma',
    AppIcons.trauma,
    Color(0xFF9333EA),
    Colors.white,
  );
  static const ambulance = IncidentType(
    'Ambulance Services',
    AppIcons.ambulance,
    Color(0xFF0D9488),
    Colors.white,
  );

  factory IncidentType.fromJson(Map<String, dynamic> json) {
    final fallback = IncidentType.fromApiName(json['name'] as String);
    final hex = (json['color']?.toString() ?? '').replaceFirst('#', '');
    final parsed = RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(hex)
        ? int.tryParse(hex, radix: 16)
        : null;
    final color = parsed == null ? fallback.color : Color(0xFF000000 | parsed);
    return IncidentType(
      fallback.label,
      fallback.icon,
      color,
      color.computeLuminance() > .45 ? Colors.black : Colors.white,
      hint: fallback.hint,
    );
  }

  static IncidentType fromApiName(String name) {
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final style = normalized.contains('fire')
        ? fire
        : normalized.contains('vehicle') || normalized.contains('accident')
        ? vehicular
        : normalized.contains('trauma') || normalized.contains('rescue')
        ? trauma
        : normalized.contains('medical') || normalized.contains('ambulance')
        ? medical
        : normalized.contains('disaster') ||
              normalized.contains('flood') ||
              normalized.contains('earthquake')
        ? disaster
        : const IncidentType(
            '',
            AppIcons.alert,
            Color(0xFF6B7280),
            Colors.white,
          );

    return IncidentType(
      name,
      style.icon,
      style.color,
      style.onColor,
      hint: style.hint,
    );
  }
}

enum SchedulePurpose {
  ambulanceStandby('Ambulance Standby', AppIcons.ambulance, Color(0xFF0D9488)),
  medicalMission('Medical Mission', AppIcons.medical, Color(0xFF9333EA)),
  fireInspection('Fire Safety Inspection', AppIcons.fire, Color(0xFFE11D48)),
  disasterDrill('Disaster Drill', AppIcons.drill, Color(0xFFD97706)),
  firstAidTraining('First Aid Training', AppIcons.safety, Color(0xFF2563EB)),
  other('Other', AppIcons.relief, Color(0xFF0891B2));

  const SchedulePurpose(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

class ResidentProfile {
  const ResidentProfile({
    required this.name,
    required this.contact,
    required this.address,
    this.email = '',
    this.registrationStatus = 'pending',
  });
  final String name;
  final String contact;
  final String address;
  final String email;
  final String registrationStatus;
  bool get canSubmit => registrationStatus == 'accepted';

  String get firstName => name.split(' ').first;

  factory ResidentProfile.fromJson(Map<String, dynamic> json) {
    final name =
        json['name']?.toString() ??
        [
          json['first_name'],
          json['last_name'],
        ].whereType<String>().where((part) => part.isNotEmpty).join(' ');
    final address =
        json['address']?.toString() ??
        [
          json['house_no'],
          json['street'],
          json['barangay'],
          json['city'],
          json['province'],
        ].whereType<String>().where((part) => part.isNotEmpty).join(', ');

    return ResidentProfile(
      name: name,
      contact:
          json['contact']?.toString() ??
          json['contact_number']?.toString() ??
          '',
      address: address,
      email: json['email']?.toString() ?? '',
      registrationStatus: json['registration_status']?.toString() ?? 'pending',
    );
  }
}

class RecentIncident {
  const RecentIncident(this.type, this.location, this.status, this.time);
  final IncidentType type;
  final String location;
  final IncidentStatus status;
  final DateTime time;
}

class ReportRecord {
  const ReportRecord({
    required this.id,
    required this.type,
    required this.location,
    required this.time,
    required this.status,
    this.reference = '',
  });
  final int id;
  final String reference;
  final IncidentType type;
  final String location;
  final DateTime time;
  final IncidentStatus status;

  factory ReportRecord.fromJson(Map<String, dynamic> json) => ReportRecord(
    id: json['id'] as int,
    reference: json['reference']?.toString() ?? '#${json['id']}',
    type: IncidentType.fromApiName(json['type'] as String),
    location: json['location'] as String,
    time: DateTime.parse(json['reported_at'] as String).toLocal(),
    status: switch (json['status'] as String) {
      'pending' => IncidentStatus.active,
      'acknowledged' || 'dispatched' => IncidentStatus.responding,
      'resolved' => IncidentStatus.resolved,
      'invalid' => IncidentStatus.invalid,
      'withdrawn' => IncidentStatus.withdrawn,
      _ => IncidentStatus.unknown,
    },
  );
}

class ResidentNotification {
  ResidentNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.time,
    this.unread = false,
    this.relatedId,
    this.relatedKind,
  });
  final int id;
  final NotificationKind kind;
  final String message;
  final DateTime time;
  bool unread;
  final int? relatedId;
  final String? relatedKind;

  factory ResidentNotification.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'general';
    final title = json['title'] as String? ?? '';
    final message = json['message'] as String? ?? title;
    final searchable = '$type $title $message'.toLowerCase();

    return ResidentNotification(
      id: json['id'] as int,
      kind: searchable.contains('resolved')
          ? NotificationKind.resolved
          : searchable.contains('on the way') ||
                searchable.contains('dispatched')
          ? NotificationKind.onTheWay
          : type == 'report_update'
          ? NotificationKind.received
          : NotificationKind.submitted,
      message: message,
      time: DateTime.parse(json['created_at'] as String).toLocal(),
      unread: json['read_at'] == null,
      relatedId: json['related_id'] as int?,
      relatedKind: switch (json['related_type']?.toString().split('\\').last) {
        'EmergencyReport' => 'report',
        'ServiceSchedule' => 'schedule',
        _ => null,
      },
    );
  }
}

class ScheduleRequest {
  const ScheduleRequest({
    required this.id,
    required this.purpose,
    required this.destination,
    required this.when,
    required this.status,
    this.notes = '',
  });
  final int id;
  final SchedulePurpose purpose;
  final String destination;
  final DateTime when;
  final String status;
  final String notes;
  bool get canCancel =>
      ['pending', 'acknowledged', 'confirmed'].contains(status);

  factory ScheduleRequest.fromJson(Map<String, dynamic> json) {
    final serviceType = json['service_type'] as String;
    final purpose = SchedulePurpose.values.firstWhere(
      (item) => item.label == serviceType,
      orElse: () => SchedulePurpose.other,
    );
    final date = DateTime.parse(json['preferred_date'] as String);
    final time = json['preferred_time'] as String;
    final timeMatch = RegExp(
      r'^(\d{1,2}):(\d{2})(?::00)?\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(time.trim());
    if (timeMatch == null) {
      throw FormatException('Invalid schedule time: $time');
    }
    var hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final period = timeMatch.group(3)?.toUpperCase();
    if (minute > 59 || (period == null ? hour > 23 : hour < 1 || hour > 12)) {
      throw FormatException('Invalid schedule time: $time');
    }
    if (period != null) hour = hour % 12 + (period == 'PM' ? 12 : 0);
    final when = DateTime(date.year, date.month, date.day, hour, minute);

    return ScheduleRequest(
      id: json['id'] as int,
      purpose: purpose,
      destination: json['address'] as String,
      when: when,
      status: json['status'] as String? ?? 'pending',
      notes: json['notes'] as String? ?? '',
    );
  }
}
