import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/screens/record_browser_screen.dart';

class BrowserAdapter implements HttpClientAdapter {
  final queries = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    queries.add(Map<String, dynamic>.from(options.queryParameters));
    final search = options.queryParameters['search'];
    final older = options.queryParameters['before'] != null;
    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': older ? 1 : 2,
            'title': search == null
                ? (older ? 'Older report' : 'Recent report')
                : 'Matching report',
          },
        ],
        'next_before': older || search != null ? null : 2,
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

void main() {
  testWidgets(
    'search is sent to the server and resets pagination to the matching collection',
    (tester) async {
      final adapter = BrowserAdapter();
      final client = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      final theme = FTheme.neutral.light.touch;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toApproximateMaterialTheme(),
          builder: (context, child) => FTheme(
            data: theme,
            child: FToaster(child: FTooltipGroup(child: child!)),
          ),
          home: RecordBrowserScreen(
            title: 'Reports',
            path: '/reports',
            client: client,
            label: (r) => '${r['title']}',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Recent report'), findsOneWidget);
      await tester.tap(find.text('Load older matching records'));
      await tester.pumpAndSettle();
      expect(find.text('Older report'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'market');
      await tester.tap(find.text('Apply filters'));
      await tester.pumpAndSettle();
      expect(adapter.queries.last['search'], 'market');
      expect(adapter.queries.last.containsKey('before'), isFalse);
      expect(find.text('Matching report'), findsOneWidget);
      expect(find.text('Older report'), findsNothing);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(adapter.queries.last.containsKey('search'), isFalse);
      await tester.pumpWidget(const SizedBox());
      client.close();
    },
  );
}
