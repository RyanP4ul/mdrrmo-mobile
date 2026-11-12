import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/data/api/driver_service.api.dart';
import 'package:mdrrmo_flutter/data/models.dart';
import 'package:mdrrmo_flutter/data/paged_records.dart';
import 'package:mdrrmo_flutter/state/driver_responder_state.dart';

class FakeDriverApi extends DriverApi {
  FakeDriverApi() : super(Dio());
  bool assigned = false;
  List<int> activeIds = [];
  bool malformed = false;
  int? availabilityVehicle;
  bool multipleVehicles = false;
  List<int> historyIds = [100];
  Map<String, dynamic> dispatch(int id) => {
    'id': id,
    'reference': 'RPT-$id',
    'reported_at': '2030-01-01T00:00:00Z',
    'status': 'resolved',
    'priority': 'high',
  };
  @override
  Future<Map<String, dynamic>> fetchBootstrap() async => {
    'profile': {
      'name': malformed ? 'Invalid response' : 'Taylor Driver',
      'vehicle_type': malformed ? 'unknown' : 'ambulance',
      'vehicle_status': 'available',
      'vehicle_id': multipleVehicles ? null : 5,
    },
    'teams': [],
    'incident_types': [],
    'assignments': [
      for (final id in activeIds)
        {
          'id': id,
          'location': 'Location $id',
          'priority': 'high',
          'vehicle_status': 'available',
          'status': 'dispatched',
          'vehicle_id': id == 10 ? 5 : 6,
        },
    ],
    'assignment': assigned
        ? {
            'id': 10,
            'location': 'Town hall',
            'priority': 'high',
            'vehicle_status': 'available',
            'status': 'dispatched',
          }
        : null,
    'vehicles': [
      {
        'id': 5,
        'vehicle_type': 'ambulance',
        'vehicle_number': 'FIRST',
        'vehicle_status': 'available',
      },
      if (multipleVehicles)
        {
          'id': 6,
          'vehicle_type': 'fire-truck',
          'vehicle_number': 'SECOND',
          'vehicle_status': 'available',
        },
    ],
  };
  @override
  Future<RecordPage> fetchHistoryPage({int? before}) async => before == null
      ? RecordPage(historyIds.map(dispatch).toList(), 50)
      : RecordPage([dispatch(49)], null);
  @override
  Future<String> updateAvailability(String status, {int? vehicleId}) async {
    availabilityVehicle = vehicleId;
    return status;
  }
}

void main() {
  Future<ResponderState> load(FakeDriverApi api) async {
    final state = ResponderState(api: api);
    await Future<void>.delayed(Duration.zero);
    addTearDown(state.dispose);
    return state;
  }

  test('selecting among assignments survives refresh and uses the matching vehicle', () async {
    final api = FakeDriverApi()
      ..multipleVehicles = true
      ..activeIds = [10, 11];
    final state = await load(api);
    expect(state.assignments.map((a) => a.id), [10, 11]);
    state.selectAssignment(11);
    expect(state.assignment!.id, 11);
    expect(state.selectedVehicleId, 6);
    expect(state.profile.vehicleNumber, 'SECOND');
    await state.load();
    expect(state.assignment!.id, 11);
    expect(state.profile.vehicleNumber, 'SECOND');
    api.activeIds = [10];
    await state.load();
    expect(state.assignment!.id, 10);
    expect(state.selectedVehicleId, 5);
  });

  test(
    'a new assignment is discovered by refresh without signing out',
    () async {
      final api = FakeDriverApi();
      final state = await load(api);
      expect(state.assignment, isNull);
      api.assigned = true;
      await state.load();
      expect(state.assignment!.id, 10);
      expect(state.availability, Availability.dispatched);
    },
  );
  test('availability uses the explicitly selected team vehicle', () async {
    final api = FakeDriverApi()..multipleVehicles = true;
    final state = await load(api);
    expect(state.selectedVehicleId, isNull);
    await expectLater(
      state.setAvailability(Availability.available),
      throwsStateError,
    );
    state.selectVehicle(6);
    await state.setAvailability(Availability.offDuty);
    expect(api.availabilityVehicle, 6);
    expect(state.profile.vehicleNumber, 'SECOND');
    expect(state.profile.status, 'Off duty');
  });
  test(
    'history pagination survives a refresh and avoids duplicate references',
    () async {
      final api = FakeDriverApi();
      final state = await load(api);
      await state.loadMoreHistory();
      api.historyIds = [101, 100];
      await state.load();
      expect(state.history.map((d) => d.id), ['RPT-101', 'RPT-100', 'RPT-49']);
      expect(state.historyNext, isNull);
    },
  );
  test(
    'unsupported profile data does not replace the last valid snapshot',
    () async {
      final api = FakeDriverApi();
      final state = await load(api);
      api.malformed = true;
      await state.load();
      expect(state.loadError, isNotNull);
      expect(state.profile.name, 'Taylor Driver');
    },
  );
}
