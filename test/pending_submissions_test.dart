import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mdrrmo_flutter/services/pending_submissions.dart';

class SubmissionAdapter implements HttpClientAdapter {
  SubmissionAdapter(this.callback);
  final Future<ResponseBody> Function(RequestOptions) callback;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => callback(options);
  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const storage = FlutterSecureStorage();
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    FlutterSecureStorage.setMockInitialValues({
      'account_key': 'resident:1',
      'auth_token': 'token',
    });
  });
  const path = '/resident/reports';
  final payload = {'location': 'Town hall', 'description': 'Emergency'};
  void validate(Map<String, dynamic> data) {
    if (data['saved'] != true) throw const FormatException('Incomplete result');
  }

  ResponseBody result(int status, String content) => ResponseBody.fromString(
    content,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  test(
    'ambiguous timeout survives restart and retry uses the original key',
    () async {
      final keys = <String>[];
      final first = Dio()
        ..httpClientAdapter = SubmissionAdapter((options) async {
          keys.add(options.headers['Idempotency-Key'] as String);
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          );
        });
      await expectLater(
        PendingSubmissions.send(first, path, payload, validate: validate),
        throwsA(isA<DioException>()),
      );
      expect((await PendingSubmissions.read()).single.payload, payload);
      final afterRestart = Dio()
        ..httpClientAdapter = SubmissionAdapter((options) async {
          keys.add(options.headers['Idempotency-Key'] as String);
          return result(201, '{"saved":true}');
        });
      await PendingSubmissions.send(
        afterRestart,
        path,
        payload,
        validate: validate,
      );
      expect(keys[0], keys[1]);
      expect(await PendingSubmissions.read(), isEmpty);
    },
  );

  test('unconfirmed details cannot be replaced by a new submission', () async {
    await PendingSubmissions.prepare(path, payload);
    await expectLater(
      PendingSubmissions.prepare(path, {'location': 'Elsewhere'}),
      throwsStateError,
    );
    expect((await PendingSubmissions.read()).single.payload, payload);
  });

  test(
    'account switching keeps submissions separate, including late completion',
    () async {
      final first = await PendingSubmissions.prepare(path, payload);
      await storage.write(key: 'account_key', value: 'resident:2');
      expect(await PendingSubmissions.read(), isEmpty);
      final second = await PendingSubmissions.prepare(path, payload);
      expect(second.key, isNot(first.key));
      await PendingSubmissions.complete(
        first.key,
        storageKey: first.storageKey,
      );
      expect((await PendingSubmissions.read()).single.key, second.key);
      await storage.write(key: 'account_key', value: 'resident:1');
      expect(await PendingSubmissions.read(), isEmpty);
    },
  );

  test('parallel attempts prepare one durable key', () async {
    final attempts = await Future.wait([
      PendingSubmissions.prepare(path, payload),
      PendingSubmissions.prepare(path, payload),
    ]);
    expect(attempts[0].key, attempts[1].key);
    expect(await PendingSubmissions.read(), hasLength(1));
  });

  test(
    'definitive validation errors clear pending input for correction',
    () async {
      final client = Dio()
        ..httpClientAdapter = SubmissionAdapter(
          (_) async => result(422, '{"message":"Invalid location"}'),
        );
      await expectLater(
        PendingSubmissions.send(client, path, payload, validate: validate),
        throwsA(isA<DioException>()),
      );
      expect(await PendingSubmissions.read(), isEmpty);
    },
  );

  test('malformed success and server failure remain recoverable', () async {
    final broken = Dio()
      ..httpClientAdapter = SubmissionAdapter(
        (_) async => result(201, jsonEncode({'saved': false})),
      );
    await expectLater(
      PendingSubmissions.send(broken, path, payload, validate: validate),
      throwsFormatException,
    );
    final originalKey = (await PendingSubmissions.read()).single.key;
    final unavailable = Dio()
      ..httpClientAdapter = SubmissionAdapter((_) async => result(503, '{}'));
    await expectLater(
      PendingSubmissions.send(unavailable, path, payload, validate: validate),
      throwsA(isA<DioException>()),
    );
    expect((await PendingSubmissions.read()).single.key, originalKey);
  });
  test('saved submissions cannot send to an arbitrary external URL', () async {
    var requests = 0;
    final client = Dio()
      ..httpClientAdapter = SubmissionAdapter((_) async {
        requests++;
        return result(201, '{"saved":true}');
      });
    await expectLater(
      PendingSubmissions.send(
        client,
        'https://untrusted.test',
        payload,
        validate: validate,
      ),
      throwsArgumentError,
    );
    expect(requests, 0);
    expect(await PendingSubmissions.read(), isEmpty);
  });

  test('submission storage is separated between API environments', () async {
    final first = await PendingSubmissions.prepare(path, payload);
    dotenv.loadFromString(envString: 'API_URL=https://another.test/api');
    expect(await PendingSubmissions.read(), isEmpty);
    final second = await PendingSubmissions.prepare(path, payload);
    expect(second.key, isNot(first.key));
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    expect((await PendingSubmissions.read()).single.key, first.key);
  });
}
