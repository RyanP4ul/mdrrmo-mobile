import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/data/input_validation.dart';
import 'package:mdrrmo_flutter/data/models.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';

void main() {
  test('phone normalization matches the server PH mobile contract', () {
    expect(InputValidation.phone('0912 345-6789'), isNull);
    expect(InputValidation.phone('+63 912 345 6789'), isNull);
    expect(InputValidation.phone('----------'), isNotNull);
    expect(InputValidation.phone('+12345678901'), isNotNull);
  });
  test('names match the database first and last name limits', () {
    expect(InputValidation.name('Taylor Resident'), isNull);
    expect(InputValidation.name('Taylor'), isNotNull);
    expect(InputValidation.name('${'A' * 61} Resident'), isNotNull);
    expect(InputValidation.text('x' * 256, 'Location', 255), isNotNull);
  });
  test('nonfinite and out-of-range map coordinates are rejected', () {
    expect(InputValidation.coordinates(14.8, 120.9), isNull);
    expect(InputValidation.coordinates(double.nan, 120.9), isNotNull);
    expect(InputValidation.coordinates(91, 120.9), isNotNull);
    expect(InputValidation.coordinates(14, -181), isNotNull);
  });
  test('unknown statuses are not presented as invalid or responding', () {
    final record = ReportRecord.fromJson({
      'id': 1,
      'type': 'Flood',
      'location': 'Town hall',
      'reported_at': '2030-01-01T00:00:00Z',
      'status': 'future-status',
    });
    expect(record.status, IncidentStatus.unknown);
    final dispatch = Dispatch.fromJson({
      'id': 1,
      'reported_at': '2030-01-01T00:00:00Z',
      'status': 'future-status',
      'priority': 'low',
    });
    expect(dispatch.status, DispatchStatus.unknown);
    expect(() => priorityFromApi('unsupported'), throwsFormatException);
    expect(
      () => DriverProfile.fromJson({'vehicle_type': 'new-type'}),
      throwsFormatException,
    );
  });
}
