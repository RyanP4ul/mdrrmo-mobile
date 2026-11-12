import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mdrrmo_flutter/data/api_client.dart';
import 'package:mdrrmo_flutter/screens/operations_app.dart';
import 'package:mdrrmo_flutter/screens/record_details_screen.dart';

class OperationsAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(
      options.path.endsWith('/dashboard')
          ? {
              'name': 'Office staff',
              'role': 'admin',
              'pending_reports': 3,
              'active_dispatches': 1,
              'pending_schedules': 0,
              'pending_residents': 2,
              'available_vehicles': 5,
              'automatic_dispatch': false,
              'dispatch_policy': 'Staff controlled',
            }
          : {'data': [], 'next_before': null},
    ),
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

Widget app(Widget child) {
  final theme = FTheme.neutral.light.touch;
  return MaterialApp(
    theme: theme.toApproximateMaterialTheme(),
    builder: (context, child) => FTheme(
      data: theme,
      child: FToaster(child: FTooltipGroup(child: child!)),
    ),
    home: child,
  );
}

void main() {
  testWidgets(
    'staff dashboard loads and opens the paginated report interface',
    (tester) async {
      dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'staff-token'});
      final previous = dio.httpClientAdapter;
      dio.httpClientAdapter = OperationsAdapter();
      await tester.pumpWidget(app(const OperationsApp(role: 'admin')));
      await tester.pumpAndSettle();
      expect(find.text('MDRRMO Admin'), findsOneWidget);
      expect(find.text('Pending reports: 3'), findsOneWidget);
      expect(find.text('Automatic dispatch: Off'), findsOneWidget);
      expect(find.text('Announcements and advisories'), findsNothing);
      await tester.tap(find.text('Reports and dispatch'));
      await tester.pumpAndSettle();
      expect(find.text('Search all records'), findsOneWidget);
      expect(find.text('No records match these filters.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      dio.httpClientAdapter = previous;
    },
  );
  testWidgets(
    'shared edit form renders native controls and retains values after server failure',
    (tester) async {
      await tester.pumpWidget(
        app(
          ApiEditScreen(
            title: 'Edit record',
            initial: const {'name': 'Initial value'},
            fields: const [
              EditField('name', 'Name'),
              EditField('status', 'Status', options: {'pending': 'Pending'}),
            ],
            save: (_) async {
              throw StateError('Server unavailable');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Updated value');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pending').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Updated value'), findsOneWidget);
      expect(find.text('Server unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
