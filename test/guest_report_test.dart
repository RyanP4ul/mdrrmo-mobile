import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api/guest_report_api.dart';
import 'package:mdrrmo_flutter/data/resident_models.dart';
import 'package:mdrrmo_flutter/screens/resident/report_screen.dart';
import 'package:mdrrmo_flutter/services/incident_location.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';

class GuestAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool failOnce = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'POST' && failOnce) {
      failOnce = false;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(
        options.method == 'GET'
            ? {
                'incident_types': [
                  {'id': 8, 'name': 'Medical Emergency', 'color': '#4169e1'},
                ],
              }
            : {'reference': 'RPT-GUEST-123'},
      ),
      options.method == 'GET' ? 200 : 201,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class GuestUiApi extends GuestReportApi {
  GuestUiApi() : super(Dio());
  Map<String, dynamic>? submitted;
  int loads = 0;

  @override
  Future<Map<IncidentType, int>> fetchTypes() async {
    loads++;
    return {IncidentType.medical: 8};
  }

  @override
  Future<String> submitReport(Map<String, dynamic> payload) async {
    submitted = payload;
    return 'RPT-GUEST-123';
  }
}

class GuestLocation implements IncidentLocationSource {
  @override
  Future<LatLng> current() async => const LatLng(14.8153, 120.9094);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guest API sends no authorization and retries a timeout with the same submission key', () async {
    final adapter = GuestAdapter();
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    final api = GuestReportApi(client);
    final types = await api.fetchTypes();
    expect(types.values.single, 8);
    final payload = {'incident_type_id': 8, 'description': 'Needs help'};
    await expectLater(api.submitReport(payload), throwsA(isA<DioException>()));
    expect(await api.submitReport(payload), 'RPT-GUEST-123');
    final posts = adapter.requests
        .where((request) => request.method == 'POST')
        .toList();
    expect(
      posts.first.headers['Idempotency-Key'],
      posts.last.headers['Idempotency-Key'],
    );
    expect(posts.first.path, '/guest/reports');
    expect(
      adapter.requests.every(
        (request) => !request.headers.containsKey('Authorization'),
      ),
      isTrue,
    );
    api.dispose();
    client.close();
  });

  testWidgets(
    'guest reporting works without a resident session and confirms only the submission reference',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
      final cache = Directory('.tmp/guest-map-cache')
        ..createSync(recursive: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => cache.absolute.path,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      final api = GuestUiApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: AppTheme.light,
            child: FToaster(child: FTooltipGroup(child: child!)),
          ),
          home: Scaffold(
            body: ResidentReportScreen(
              guestApi: api,
              locationSource: GuestLocation(),
              onDone: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.loads, 1);
      expect(find.textContaining('Guest access is limited'), findsOneWidget);
      expect(find.text('My reports'), findsNothing);
      expect(find.text('Schedule'), findsNothing);
      await tester.tap(find.text('Medical Emergency'));
      await tester.pumpAndSettle();

      Future<void> enter(String label, String value) async {
        final field = find.byWidgetPredicate(
          (widget) => widget is AppTextField && widget.label == label,
        );
        await tester.ensureVisible(field);
        await tester.enterText(
          find.descendant(of: field, matching: find.byType(EditableText)),
          value,
        );
      }

      await enter('Your full name', 'Juan Dela Cruz');
      await enter('Contact number', '09171234567');
      await enter('Location', 'Municipal Hall');
      await tester.ensureVisible(find.text('Use my current location'));
      await tester.tap(find.text('Use my current location'));
      await tester.pumpAndSettle();
      await enter('Details', 'A person needs medical attention.');
      await tester.tap(find.text('Send report to MDRRMO'));
      await tester.pumpAndSettle();
      expect(api.submitted?['incident_type_id'], 8);
      expect(api.submitted?['reporter_name'], 'Juan Dela Cruz');
      expect(api.submitted?['lat'], 14.8153);
      expect(find.text('Report sent!'), findsOneWidget);
      expect(find.text('RPT-GUEST-123'), findsOneWidget);
      expect(
        find.textContaining('Guest access does not include report tracking'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
