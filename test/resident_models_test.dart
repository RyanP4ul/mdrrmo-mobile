import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';
import 'package:mdrrmo_flutter/data/models.dart';

void main() {
  test('incident types retain server-defined names', () {
    final type = IncidentType.fromApiName('Flood Response');

    expect(type.label, 'Flood Response');
    expect(type.icon, IncidentType.disaster.icon);
  });

  for (final entry in vehicleTypes.entries) {
    test('${entry.key} survives a profile read and save', () {
      final profile = DriverProfile.fromJson({'vehicle_type': entry.key});
      expect(profile.vehicleType, entry.value);
      expect(profile.apiVehicleType, entry.key);
    });
  }

  for (final entry in {
    '14:30': 14,
    '2:30 PM': 14,
    '12:30 AM': 0,
    '12:30 PM': 12,
    '09:30:00': 9,
  }.entries) {
    test('schedule time ${entry.key} is displayed correctly', () {
      final schedule = ScheduleRequest.fromJson({
        'id': 1,
        'service_type': 'Medical Mission',
        'preferred_date': '2030-01-01',
        'preferred_time': entry.key,
        'address': 'Town hall',
        'status': 'pending',
      });
      expect(schedule.when.hour, entry.value);
      expect(schedule.when.minute, 30);
    });
  }

  test(
    'invalid schedule time is rejected instead of appearing at midnight',
    () {
      expect(
        () => ScheduleRequest.fromJson({
          'id': 1,
          'service_type': 'Other',
          'preferred_date': '2030-01-01',
          'preferred_time': '25:99',
          'address': 'Town hall',
        }),
        throwsFormatException,
      );
    },
  );

  test('incident selection remains valid after refreshing categories', () {
    expect(
      IncidentType.fromApiName('Flood'),
      IncidentType.fromApiName('Flood'),
    );
    expect(
      {IncidentType.fromApiName('Flood'): 42}[IncidentType.fromApiName(
        'Flood',
      )],
      42,
    );
  });

  test('resident approval and report references are retained', () {
    expect(
      ResidentProfile.fromJson({'registration_status': 'accepted'}).canSubmit,
      isTrue,
    );
    expect(
      ResidentProfile.fromJson({'registration_status': 'pending'}).canSubmit,
      isFalse,
    );
    expect(
      ReportRecord.fromJson({
        'id': 12,
        'reference': 'RPT-2030-ABC',
        'type': 'Flood',
        'location': 'Town hall',
        'reported_at': '2030-01-01T08:00:00Z',
        'status': 'pending',
      }).reference,
      'RPT-2030-ABC',
    );
  });
}
