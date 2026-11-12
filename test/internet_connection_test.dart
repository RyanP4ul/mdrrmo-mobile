import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mdrrmo_flutter/services/dispatcher_phone.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';

Dio fakeClient(FutureOr<Response<dynamic>> Function(RequestOptions) respond) =>
    Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            handler.resolve(await respond(options));
          },
        ),
      );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    DispatcherPhone.number.value = '+639123456789';
  });

  testWidgets(
    'a slow successful probe does not report offline after four seconds',
    (tester) async {
      final connection = InternetConnection(
        probe: () async {
          await Future<void>.delayed(const Duration(seconds: 8));
          return true;
        },
      );
      var completed = false;
      bool? result;
      final check = connection.check().then((online) {
        completed = true;
        result = online;
      });
      await tester.pump(const Duration(seconds: 8));
      expect(completed, isTrue);
      expect(result, isTrue);
      expect(connection.online, isTrue);
      await check;
      connection.dispose();
    },
  );

  test('a pending phone lookup cannot delay the health check or erase the cached number', () async {
    final contact = Completer<Response<dynamic>>();
    final contactStarted = Completer<RequestOptions>();
    final connection = InternetConnection(
      clientFactory: () => fakeClient((options) {
        expect(options.uri.host, 'example.test');
        expect(options.uri.path, '/api/connectivity');
        if (options.queryParameters['include_contact'] == 1) {
          contactStarted.complete(options);
          return contact.future;
        }
        expect(options.queryParameters.containsKey('include_contact'), isFalse);
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'service': 'mdrrmo'},
        );
      }),
    );

    expect(await connection.check(), isTrue);
    final contactOptions = await contactStarted.future;
    expect(DispatcherPhone.number.value, '+639123456789');
    contact.complete(Response(requestOptions: contactOptions, statusCode: 500));
    await Future<void>.delayed(Duration.zero);
    expect(connection.online, isTrue);
    expect(DispatcherPhone.number.value, '+639123456789');
    connection.dispose();
  });

  test('phone refresh is separate and limited to once per minute', () async {
    var healthChecks = 0;
    var contacts = 0;
    final connection = InternetConnection(
      clientFactory: () => fakeClient((options) {
        if (options.queryParameters['include_contact'] == 1) {
          contacts++;
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {'service': 'mdrrmo', 'dispatcher_phone': '+639111111111'},
          );
        }
        healthChecks++;
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'service': 'mdrrmo'},
        );
      }),
    );
    expect(await connection.check(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(await connection.check(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(healthChecks, 2);
    expect(contacts, 1);
    expect(DispatcherPhone.number.value, '+639111111111');
    connection.dispose();
  });

  for (final data in [
    null,
    '<html>Sign in to Wi-Fi</html>',
    {'service': 'other'},
  ]) {
    test('rejects an unrelated server response: $data', () async {
      var attempts = 0;
      final connection = InternetConnection(
        clientFactory: () => fakeClient((options) {
          attempts++;
          return Response(requestOptions: options, statusCode: 200, data: data);
        }),
      );
      expect(await connection.check(), isFalse);
      expect(attempts, 2);
      expect(connection.hasChecked, isTrue);
      connection.dispose();
    });
  }
}
