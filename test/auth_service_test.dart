import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mdrrmo_flutter/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'saved-token'});
  });

  for (final role in ['admin', 'dispatcher']) {
    test('$role cannot sign in and an old staff session cannot be restored', () async {
      final service = AuthService(
        client: MockClient(
          (request) async => http.Response(
            request.method == 'POST'
                ? '{"token":"staff-token","user":{"id":9,"role":"$role","account_key":"$role-9"}}'
                : '{"user":{"id":9,"role":"$role","account_key":"$role-9"}}',
            200,
          ),
        ),
      );
      await expectLater(
        service.login(email: 'staff@example.test', password: 'password'),
        throwsException,
      );
      expect(await service.getToken(), 'saved-token');
      await expectLater(
        service.getMe(),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(await service.hasToken(), false);
    });
  }

  for (final role in ['resident', 'driver/responder']) {
    test('$role can sign in and restore a supported mobile session', () async {
      final service = AuthService(
        client: MockClient(
          (request) async => http.Response(
            request.method == 'POST'
                ? '{"token":"mobile-token","user":{"id":9,"role":"$role"}}'
                : '{"user":{"id":9,"role":"$role"}}',
            200,
          ),
        ),
      );
      expect(
        (await service.login(
          email: 'mobile@example.test',
          password: 'password',
        ))['role'],
        role,
      );
      expect(await service.getToken(), 'mobile-token');
      expect((await service.getMe())['role'], role);
    });
  }

  test('current user lookup sends the stored bearer token', () async {
    final service = AuthService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/mobile/me');
        expect(request.headers['Authorization'], 'Bearer saved-token');
        return http.Response(
          '{"user":{"id":1,"role":"resident","name":"Taylor"}}',
          200,
        );
      }),
    );
    expect((await service.getMe())['role'], 'resident');
  });

  test('rejected sessions delete the invalid stored token', () async {
    final service = AuthService(
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(service.getMe(), throwsA(isA<SessionExpiredException>()));
    expect(await service.hasToken(), isFalse);
  });

  test('temporary server failure preserves the session for retry', () async {
    final service = AuthService(
      client: MockClient((_) async => http.Response('{}', 503)),
    );
    await expectLater(service.getMe(), throwsException);
    expect(await service.getToken(), 'saved-token');
  });

  test(
    'logout clears the local token even when the server is offline',
    () async {
      final service = AuthService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      await service.logout();
      expect(await service.hasToken(), isFalse);
    },
  );

  test('a late expired request cannot clear a newly issued token', () async {
    final service = AuthService();
    await service.clearSession(expectedToken: 'older-token', notify: true);
    expect(await service.getToken(), 'saved-token');
  });
  test('concurrent logout calls share a single server revocation', () async {
    var requests = 0;
    final service = AuthService(
      client: MockClient((_) async {
        requests++;
        await Future<void>.delayed(Duration.zero);
        return http.Response('{}', 200);
      }),
    );
    await Future.wait([service.logout(), service.logout()]);
    expect(requests, 1);
    expect(await service.hasToken(), isFalse);
  });
  test(
    'overlapping sign-in requests are rejected across service instances',
    () async {
      final gate = Completer<void>();
      var secondRequests = 0;
      final first = AuthService(
        client: MockClient((_) async {
          await gate.future;
          return http.Response(
            '{"token":"new-token","user":{"id":1,"role":"resident"}}',
            200,
          );
        }),
      );
      final second = AuthService(
        client: MockClient((_) async {
          secondRequests++;
          return http.Response('{}', 500);
        }),
      );
      final pending = first.login(
        email: 'first@example.test',
        password: 'Password123',
      );
      await expectLater(first.logout(), throwsStateError);
      await expectLater(
        second.login(email: 'second@example.test', password: 'Password123'),
        throwsStateError,
      );
      gate.complete();
      await pending;
      expect(secondRequests, 0);
      expect(await first.getToken(), 'new-token');
    },
  );
}
