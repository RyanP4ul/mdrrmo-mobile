import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api_client.dart';
import 'package:mdrrmo_flutter/screens/record_details_screen.dart';
import 'package:mdrrmo_flutter/screens/responder_records_screen.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';
import 'package:mdrrmo_flutter/ui/record_widgets.dart';

import 'responder_ui_test.dart' show app;

class PresentationAdapter implements HttpClientAdapter {
  final read = <int>{8};
  final cursors = <int?>[];
  final paths = <String>[];
  bool failMore = false;
  Map<String, dynamic> notification(int id) => {
    'id': id,
    'report_id': id == 9 ? null : 12,
    'schedule_id': id == 9 ? 42 : null,
    'title': id == 9
        ? 'Service schedule assigned'
        : id == 8
        ? 'Emergency assignment received'
        : 'Earlier assignment update',
    'message': 'Your response team has a new assignment. Open the details to review the location and coordinate your response.',
    'kind': id == 9 ? 'schedule_assigned' : 'assigned',
    'created_at': '2030-01-02T09:00:00Z',
    'read_at': read.contains(id) ? '2030-01-02T10:00:00Z' : null,
  };
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    Object data;
    if (options.method == 'PATCH') {
      read.add(int.parse(options.path.split('/')[3]));
      data = {'message': 'Read'};
    } else if (options.path.endsWith('/notifications')) {
      final before = options.queryParameters['before'] as int?;
      cursors.add(before);
      if (before != null && failMore) {
        failMore = false;
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }
      data = {
        'data': [
          for (final id in before == null ? [9, 8] : [7]) notification(id),
        ],
        'next_before': before == null ? 8 : null,
      };
    } else {
      final schedule = options.path.contains('/schedules/');
      data = {
        'id': schedule ? 42 : 12,
        'reference': schedule ? null : 'RPT-12',
        'status': schedule ? 'confirmed' : 'dispatched',
        'service_type': 'Medical Mission',
        'type': 'Medical emergency',
        'priority': 'high',
        'address': 'Municipal hall, Balagtas, Bulacan',
        'location':
            'A long incident address in Barangay San Juan, Balagtas, Bulacan',
        'description': 'A detailed description of the reported incident that should remain readable and selectable on narrow displays with larger text.',
        'preferred_date': '2030-01-02',
        'preferred_time': '09:30',
        'resident': 'Maria Santos',
        'contact': '09171234567',
        'reported_at': '2030-01-02T09:00:00Z',
        'acknowledged_at': '2030-01-02T09:05:00Z',
        'team': null,
      };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late PresentationAdapter adapter;
  late HttpClientAdapter previous;
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'driver-token'});
    previous = dio.httpClientAdapter;
    adapter = PresentationAdapter();
    dio.httpClientAdapter = adapter;
  });
  tearDown(() => dio.httpClientAdapter = previous);

  test('record formatting keeps civil service dates and makes status and time readable', () {
    expect(
      recordTimestamp('2030-01-02T00:00:00Z', dateOnly: true),
      'Jan 2, 2030',
    );
    expect(recordTime('09:30:00'), '9:30 AM');
    expect(recordTime('00:05'), '12:05 AM');
    expect(recordTimestamp(null), 'Not recorded');
    expect(readableLabel('on-scene'), 'On Scene');
    expect(readableLabel('patientName'), 'Patient Name');
  });

  testWidgets(
    'notification filters mark updates read and open the correct scheduled-service details on compact screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var changes = 0;
      await tester.pumpWidget(
        app(
          ResponderRecordsScreen(
            inbox: true,
            onChanged: () async {
              changes++;
            },
          ),
          scale: 1.4,
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unread').first);
      await tester.pumpAndSettle();
      expect(find.text('Emergency assignment received'), findsNothing);
      expect(find.text('Service schedule assigned'), findsOneWidget);
      await tester.tap(find.text('Service schedule assigned'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(adapter.read, contains(9));
      expect(changes, 1);
      expect(find.byType(RecordDetailsScreen), findsOneWidget);
      expect(adapter.paths, contains('/driver-responder/schedules/42'));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('No unread updates here'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'older notifications retain existing cards after retry and automatic refresh',
    (tester) async {
      await tester.pumpWidget(app(const ResponderRecordsScreen(inbox: true)));
      await tester.pumpAndSettle();
      adapter.failMore = true;
      await tester.scrollUntilVisible(
        find.text('Load more'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Load more'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Try again'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(adapter.cursors, [null, 8, 8]);
      expect(find.text('Earlier assignment update'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Earlier assignment update'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'report cards expose status, grouped details, timeline and honest empty assignment states with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 840);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(
          const RecordDetailsScreen(id: 12, driver: true),
          scale: 1.5,
          dark: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dispatched'), findsOneWidget);
      expect(find.text('High Priority'), findsOneWidget);
      expect(find.text('Voice call invitations'), findsNothing);
      expect(find.text('Edit trip record'), findsNothing);
      expect(find.text('Driver Form'), findsNothing);
      expect(find.text('Patient-care form'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Awaiting team assignment'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Awaiting team assignment'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Activity timeline'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Activity timeline'), findsOneWidget);
      expect(find.text('2030-01-02T09:00:00Z'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'responder notifications use resident card layout and support Mark all read',
    (tester) async {
      var changes = 0;
      await tester.pumpWidget(
        app(
          ResponderRecordsScreen(
            inbox: true,
            onChanged: () async {
              changes++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 unread'), findsOneWidget);
      expect(find.byIcon(AppIcons.chevron), findsWidgets);
      expect(find.text('Mark all read'), findsOneWidget);

      await tester.tap(find.text('Mark all read'));
      await tester.pumpAndSettle();

      expect(adapter.read, contains(9));
      expect(changes, 1);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('1 unread'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
