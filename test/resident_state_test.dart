import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:mdrrmo_flutter/data/paged_records.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/data/api/resident_service.api.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';
import 'package:mdrrmo_flutter/state/resident_state.dart';

class FakeResidentApi extends ResidentApi {
  FakeResidentApi() : super(Dio());
  bool failRefresh = false;
  int? cancelledId;
  int scheduleId = 9;
  String scheduleStatus = 'pending';
  List<Map<String, dynamic>> bootstrapReports = [];
  String profileName = 'Taylor Resident';
  bool badUnread = false;
  bool failPage = false;
  int? requestedCursor;
  Completer<void>? readWait;
  Completer<void>? bootstrapWait;
  int allReadCalls = 0;

  Map<String, dynamic> schedule(String status) => {
    'id': scheduleId,
    'service_type': 'Medical Mission',
    'preferred_date': '2030-01-01',
    'preferred_time': '14:30',
    'address': 'Town hall',
    'status': status,
  };

  @override
  Future<Map<String, dynamic>> fetchBootstrap() async {
    if (bootstrapWait != null) await bootstrapWait!.future;
    if (failRefresh) throw Exception('offline');
    return {
      'profile': {'name': profileName, 'registration_status': 'accepted'},
      'incident_types': [
        {'id': 3, 'name': 'Flood'},
      ],
      'reports': bootstrapReports,
      'schedules': [schedule(scheduleStatus)],
      'unread_count': badUnread ? 'invalid' : 51,
      'paging': {'schedules': scheduleId},
      'notifications': [
        {
          'id': 5,
          'type': 'general',
          'message': 'Update',
          'created_at': '2030-01-01T00:00:00Z',
          'read_at': null,
        },
      ],
    };
  }

  @override
  Future<void> markRead(int id) async {
    if (readWait != null) await readWait!.future;
  }

  @override
  Future<void> markAllRead() async {
    allReadCalls++;
  }

  @override
  Future<Map<String, dynamic>> submitReport({
    required int incidentTypeId,
    required String reporterType,
    required String location,
    required double latitude,
    required double longitude,
    required String description,
    Uint8List? photoBytes,
    String? photoName,
  }) async => {
    '_submission_replayed': true,
    'report': {...bootstrapReports.single, 'status': 'pending'},
    'notification': {
      'id': 5,
      'type': 'general',
      'message': 'Old receipt',
      'created_at': '2030-01-01T00:00:00Z',
      'read_at': null,
    },
  };
  @override
  Future<Map<String, dynamic>> submitSchedule({
    required String serviceType,
    required DateTime date,
    required String time,
    required String address,
    String notes = '',
  }) async => {
    '_submission_replayed': true,
    'schedule': schedule('pending'),
    'notification': {
      'id': 5,
      'type': 'general',
      'message': 'Old receipt',
      'created_at': '2030-01-01T00:00:00Z',
      'read_at': null,
    },
  };

  @override
  Future<RecordPage> fetchPage(String resource, int before) async {
    requestedCursor = before;
    if (failPage) throw Exception('offline');
    return RecordPage([
      {...schedule('pending'), 'id': before - 1},
    ], null);
  }

  @override
  Future<Map<String, dynamic>> cancelSchedule(int id) async {
    cancelledId = id;
    return {'schedule': schedule('cancelled')};
  }
}

void main() {
  Future<ResidentState> createState(FakeResidentApi api) async {
    final state = ResidentState(
      const ResidentProfile(name: '', contact: '', address: ''),
      api: api,
    );
    await Future<void>.delayed(Duration.zero);
    addTearDown(state.dispose);
    return state;
  }

  test('failed refresh retains the last successfully loaded records', () async {
    final api = FakeResidentApi();
    final state = await createState(api);
    expect(state.hasLoaded, isTrue);
    api.failRefresh = true;
    await state.load();
    expect(state.loadError, isNotNull);
    expect(state.profile.name, 'Taylor Resident');
    expect(state.schedules.single.id, 9);
  });

  test(
    'read actions maintain the server total beyond the loaded page',
    () async {
      final state = await createState(FakeResidentApi());
      expect(state.unreadCount, 51);
      await state.markRead(state.notifications.single);
      expect(state.unreadCount, 50);
      await state.markRead(state.notifications.single);
      expect(state.unreadCount, 50);
      await state.markAllRead();
      expect(state.unreadCount, 0);
    },
  );

  test(
    'cancellation sends the record ID and applies the saved response',
    () async {
      final api = FakeResidentApi();
      final state = await createState(api);
      await state.cancelSchedule(state.schedules.single);
      expect(api.cancelledId, 9);
      expect(state.schedules.single.status, 'cancelled');
      expect(state.schedules.single.canCancel, isFalse);
      expect(state.isSaving, isFalse);
    },
  );
  test(
    'pagination appends unique records and refresh preserves older pages',
    () async {
      final api = FakeResidentApi();
      final state = await createState(api);
      expect(state.hasMore('schedules'), isTrue);
      await state.loadMore('schedules');
      expect(api.requestedCursor, 9);
      expect(state.schedules.map((s) => s.id), [9, 8]);
      expect(state.hasMore('schedules'), isFalse);
      await state.load();
      expect(state.schedules.map((s) => s.id), [9, 8]);
      expect(state.hasMore('schedules'), isFalse);
    },
  );

  test('a non-overlapping refreshed head exposes the gap instead of skipping records', () async {
    final api = FakeResidentApi();
    final state = await createState(api);
    await state.loadMore('schedules');
    api.scheduleId = 99;
    await state.load();
    expect(state.hasMore('schedules'), isTrue);
    await state.loadMore('schedules');
    expect(api.requestedCursor, 99);
    expect(state.schedules.map((s) => s.id), [99, 98, 9, 8]);
  });

  test('page failure keeps its cursor and loaded records for retry', () async {
    final api = FakeResidentApi();
    final state = await createState(api);
    api.failPage = true;
    await state.loadMore('schedules');
    expect(state.schedules.single.id, 9);
    expect(state.pageErrors['schedules'], isNotNull);
    expect(state.hasMore('schedules'), isTrue);
    api.failPage = false;
    await state.loadMore('schedules');
    expect(state.schedules, hasLength(2));
    expect(state.pageErrors['schedules'], isNull);
  });

  test(
    'malformed metadata cannot partially replace the last valid profile',
    () async {
      final api = FakeResidentApi();
      final state = await createState(api);
      api.profileName = 'Bad response';
      api.badUnread = true;
      await state.load();
      expect(state.loadError, isNotNull);
      expect(state.profile.name, 'Taylor Resident');
    },
  );

  test(
    'notification writes do not overlap or decrement unread counts twice',
    () async {
      final api = FakeResidentApi();
      final state = await createState(api);
      api.readWait = Completer<void>();
      final first = state.markRead(state.notifications.single);
      await state.markAllRead();
      expect(api.allReadCalls, 0);
      api.readWait!.complete();
      await first;
      expect(state.unreadCount, 50);
    },
  );

  test(
    'late bootstrap results do not notify or populate a disposed session',
    () async {
      final api = FakeResidentApi()..bootstrapWait = Completer<void>();
      final state = ResidentState(
        const ResidentProfile(name: 'Initial', contact: '', address: ''),
        api: api,
      );
      var notifications = 0;
      state.addListener(() => notifications++);
      state.dispose();
      api.bootstrapWait!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(notifications, 0);
      expect(state.profile.name, 'Initial');
    },
  );
  test(
    'replaying a saved report preserves current status and unread totals',
    () async {
      final api = FakeResidentApi()
        ..bootstrapReports = [
          {
            'id': 42,
            'reference': 'RPT-42',
            'type': 'Flood',
            'location': 'Town hall',
            'reported_at': '2030-01-01T00:00:00Z',
            'status': 'resolved',
          },
        ];
      final state = await createState(api);
      final confirmed = await state.submitReport(
        type: IncidentType.fromApiName('Flood'),
        reporter: ReporterType.witness,
        location: 'Town hall',
        pin: const LatLng(14.8, 120.9),
        notes: 'Emergency',
      );
      expect(confirmed.reference, 'RPT-42');
      expect(state.reports.single.status, IncidentStatus.resolved);
      expect(state.notifications, hasLength(1));
      expect(state.unreadCount, 51);
      expect(state.recent, hasLength(1));
    },
  );

  test(
    'replaying a saved schedule does not restore an obsolete pending status',
    () async {
      final api = FakeResidentApi()..scheduleStatus = 'confirmed';
      final state = await createState(api);
      await state.submitSchedule(
        purpose: SchedulePurpose.medicalMission,
        address: 'Town hall',
        when: DateTime(2030, 1, 1, 14, 30),
      );
      expect(state.schedules.single.status, 'confirmed');
      expect(state.notifications, hasLength(1));
      expect(state.unreadCount, 51);
    },
  );
}
