import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/data/models.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';

void main() {
  test('assignment progress uses trip events when vehicle availability is unchanged', () {
    final base = <String, dynamic>{
      'id': 1,
      'status': 'dispatched',
      'vehicle_status': 'available',
      'priority': 'high',
    };
    expect(Assignment.fromJson(base).actionLabel, 'Start trip');
    final enRoute = Assignment.fromJson({
      ...base,
      'trip': {'started_at': '2026-11-12T08:00:00Z'},
    });
    expect(enRoute.step, 1);
    expect(enRoute.actionLabel, 'Mark as on scene');
    final onScene = Assignment.fromJson({
      ...base,
      'trip': {
        'started_at': '2026-11-12T08:00:00Z',
        'on_scene_at': '2026-11-12T08:10:00Z',
      },
    });
    expect(onScene.step, 2);
    expect(onScene.actionLabel, 'Complete dispatch');
    expect(
      Assignment.fromJson({...base, 'response_status': 'returning'})
          .actionLabel,
      'Complete dispatch',
    );
    expect(
      Assignment.fromJson({
        ...base,
        'response_status': 'available',
        'vehicle_status': 'en-route',
      }).step,
      0,
    );
  });
  test('server colors override inferred styles and invalid colors retain the fallback', () {
    final configured = IncidentType.fromJson({
      'name': 'Fire',
      'color': '#123456',
    });
    expect(configured.color.toARGB32(), 0xFF123456);
    expect(configured.icon, IncidentType.fire.icon);
    expect(
      IncidentType.fromJson({'name': 'Fire', 'color': 'invalid'}).color,
      IncidentType.fire.color,
    );
    expect(
      IncidentType.fromJson({'name': 'New service', 'color': '#ffffff'}).onColor
          .toARGB32(),
      0xFF000000,
    );
  });
  test('notifications navigate only to supported record kinds and retain numeric IDs', () {
    for (final kind in {
      'EmergencyReport': 'report',
      'ServiceSchedule': 'schedule',
    }.entries) {
      final n = ResidentNotification.fromJson({
        'id': 1,
        'created_at': '2030-01-01T00:00:00Z',
        'related_id': 42,
        'related_type': 'App\\Models\\${kind.key}',
      });
      expect(n.relatedId, 42);
      expect(n.relatedKind, kind.value);
    }
    final unknown = ResidentNotification.fromJson({
      'id': 1,
      'created_at': '2030-01-01T00:00:00Z',
      'related_id': 42,
      'related_type': 'Unexpected',
    });
    expect(unknown.relatedKind, isNull);
  });
  Map<String, dynamic> dispatch() => {
    'id': 1,
    'reference': 'RPT-1',
    'reported_at': '2030-01-01T00:00:00Z',
    'resolved_at': '2030-01-01T03:00:00Z',
    'status': 'resolved',
    'priority': 'high',
  };
  test('unrecorded transport is unknown and resolution is never used as patient arrival', () {
    final d = Dispatch.fromJson(dispatch());
    expect(d.arrivedAt, isNull);
    expect(d.durationMin, isNull);
    expect(d.distanceKm, isNull);
  });
  test('transport uses actual pickup and arrival times and driver-reported distance', () {
    final d = Dispatch.fromJson({
      ...dispatch(),
      'trip': {
        'destination': 'Hospital',
        'picked_up_at': '2030-01-01T01:00:00Z',
        'arrived_at': '2030-01-01T01:25:00Z',
        'distance_km': 8.5,
      },
    });
    expect(d.destination, 'Hospital');
    expect(d.durationMin, 25);
    expect(d.distanceKm, 8.5);
    expect(d.arrivedAt, DateTime.utc(2030, 1, 1, 1, 25));
  });
  test('withdrawn reports stay distinct from dispatcher rejection', () {
    final r = ReportRecord.fromJson({
      ...dispatch(),
      'status': 'withdrawn',
      'type': 'Medical',
      'location': 'Town hall',
    });
    expect(r.status, IncidentStatus.withdrawn);
  });
}
