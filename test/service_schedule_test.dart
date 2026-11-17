import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api_client.dart';
import 'package:mdrrmo_flutter/data/api/driver_service.api.dart';
import 'package:mdrrmo_flutter/data/paged_records.dart';
import 'package:mdrrmo_flutter/screens/driver-responder/service_schedules_screen.dart';
import 'package:mdrrmo_flutter/screens/record_details_screen.dart';

import 'responder_ui_test.dart' show app;

class ScheduleAdapter implements HttpClientAdapter {
  String status = 'confirmed';
  final changes = <String>[];
  final queries = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    queries.add(options.queryParameters);
    if (options.method == 'PATCH') {
      status = (options.data as Map)['status'] as String;
      changes.add(status);
    }
    return ResponseBody.fromString(
      jsonEncode({
        'id': 42,
        'service_type': 'Medical Mission',
        'status': status,
        'preferred_date': '2030-01-02',
        'preferred_time': '09:30',
        'address': 'Municipal Hall, Balagtas, Bulacan',
        'resident': 'Maria Santos',
        'team_name': 'Team Alpha',
        'contact': '09171234567',
        'data': [],
        'next_before': null,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class PagedScheduleApi extends DriverApi {
  PagedScheduleApi() : super(Dio());
  final cursors = <int?>[];
  @override
  Future<RecordPage> fetchServiceSchedulesPage({
    int? before,
    bool today = false,
    bool active = false,
  }) async {
    cursors.add(before);
    return RecordPage([
      {
        'id': before == null ? 42 : 41,
        'service_type': before == null ? 'First service' : 'Older service',
        'status': 'confirmed',
        'address': 'Town hall',
      },
    ], before == null ? 42 : null);
  }
}

void main() {
  test(
    'schedule filters use boolean values accepted by Laravel query validation',
    () async {
      final adapter = ScheduleAdapter();
      final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter;
      await DriverApi(client)
          .fetchServiceSchedulesPage(active: true, today: true);
      expect(adapter.queries.single['active'], 1);
      expect(adapter.queries.single['today'], 1);
      client.close();
    },
  );

  testWidgets(
    'assigned service details advance through trip, arrival, and completion',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'driver-token'});
      final previous = dio.httpClientAdapter;
      final adapter = ScheduleAdapter();
      dio.httpClientAdapter = adapter;
      addTearDown(() => dio.httpClientAdapter = previous);
      var refreshes = 0;
      await tester.pumpWidget(
        app(
          RecordDetailsScreen(
            id: 42,
            driver: true,
            schedule: true,
            onChanged: () async {
              refreshes++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Municipal Hall, Balagtas, Bulacan'), findsOneWidget);
      expect(find.text('Navigate to pickup'), findsOneWidget);
      for (final label in [
        'Start service trip',
        'Mark on scene',
        'Complete service',
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm').last);
        await tester.pumpAndSettle();
      }
      expect(adapter.changes, ['en-route', 'on-scene', 'completed']);
      await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
      await tester.pumpAndSettle();
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Complete service'), findsNothing);
      expect(refreshes, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scheduled services load the next page without dropping existing assignments',
    (tester) async {
      final api = PagedScheduleApi();
      await tester.pumpWidget(app(ServiceSchedulesScreen(api: api)));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(api.cursors, [null, 42]);
      expect(find.text('First service'), findsOneWidget);
      expect(find.text('Older service'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
