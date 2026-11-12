import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/services/driver_realtime.dart';

class FakeSocket implements ReverbSocket {
  final input = StreamController<dynamic>.broadcast();
  final outgoing = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool closed = false;
  bool rejectConnection = false;
  @override
  Future<void> get ready => rejectConnection
      ? Future.error(StateError('sensitive internal socket details'))
      : Future.value();
  @override
  Stream<dynamic> get messages => input.stream;
  @override
  void send(String value) {
    final frame = Map<String, dynamic>.from(jsonDecode(value) as Map);
    sent.add(frame);
    outgoing.add(frame);
  }

  void emit(String event, Map<String, dynamic> data, {String? channel}) =>
      input.add(
        jsonEncode({
          'event': event,
          'data': jsonEncode(data),
          'channel': ?channel,
        }),
      );
  Future<Map<String, dynamic>> waitFor(String event) async {
    final existing = sent.where((e) => e['event'] == event);
    return existing.isNotEmpty
        ? existing.last
        : outgoing.stream
              .firstWhere((e) => e['event'] == event)
              .timeout(const Duration(seconds: 2));
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class RealtimeAdapter implements HttpClientAdapter {
  bool enabled = true;
  int authStatus = 200, configStatus = 200;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final response = options.path.endsWith('/realtime')
        ? {
            'enabled': enabled,
            'key': 'public-key',
            'host': 'localhost',
            'port': 8080,
            'secure': false,
            'channel': 'private-drivers.7',
          }
        : options.path.endsWith('/auth')
        ? {'auth': 'public-key:test-signature'}
        : {'data': [], 'snapshotAt': '2020-01-01T00:00:00Z'};
    return ResponseBody.fromString(
      jsonEncode(response),
      options.path.endsWith('/auth')
          ? authStatus
          : options.path.endsWith('/realtime')
          ? configStatus
          : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> until(DriverRealtime live, bool Function() condition) async {
  if (condition()) return;
  final done = Completer<void>();
  void listener() {
    if (condition() && !done.isCompleted) done.complete();
  }

  live.addListener(listener);
  try {
    await done.future.timeout(const Duration(seconds: 2));
  } finally {
    live.removeListener(listener);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('private Reverb handshake authorizes over HTTP and live frames move team driver markers', () async {
    final socket = FakeSocket(), adapter = RealtimeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    Uri? opened;
    var refreshes = 0;
    final live = DriverRealtime(
      client: client,
      open: (uri) {
        opened = uri;
        return socket;
      },
      onAssignmentChanged: () async {
        refreshes++;
      },
    );
    addTearDown(() async {
      live.dispose();
      await socket.input.close();
      await socket.outgoing.close();
      client.close();
    });
    await live.start();
    expect(opened!.scheme, 'ws');
    expect(opened!.path, '/app/public-key');
    expect(opened!.queryParameters.containsKey('token'), isFalse);
    socket.emit('pusher:connection_established', {
      'socket_id': '123.456',
      'activity_timeout': 30,
    });
    final subscription = await socket.waitFor('pusher:subscribe');
    expect((subscription['data'] as Map)['channel'], 'private-drivers.7');
    expect((subscription['data'] as Map)['auth'], 'public-key:test-signature');
    expect(adapter.requests.singleWhere((r) => r.path.endsWith('/auth')).data, {
      'socket_id': '123.456',
      'channel_name': 'private-drivers.7',
    });
    socket.emit(
      'pusher_internal:subscription_succeeded',
      {},
      channel: 'private-drivers.7',
    );
    await until(live, () => live.connected);
    socket.emit('driver.moved', {
      'id': 9,
      'lat': 14.8123,
      'lng': 120.9123,
      'plate': 'UNIT-9',
      'sentAt': '2030-01-01T00:01:00Z',
    }, channel: 'private-drivers.7');
    await until(live, () => live.positions.isNotEmpty);
    expect(live.positions.single['lat'], 14.8123);
    socket.emit('driver.moved', {
      'id': 9,
      'lat': 1,
      'lng': 2,
      'sentAt': '2029-01-01T00:01:00Z',
    }, channel: 'private-drivers.7');
    socket.emit('driver.moved', {
      'id': 10,
      'lat': 1,
      'lng': 2,
      'sentAt': '2030-01-01T00:01:00Z',
    }, channel: 'private-drivers.8');
    socket.emit('pusher:ping', {});
    await socket.waitFor('pusher:pong');
    expect(live.positions.length, 1);
    expect(live.positions.single['lat'], 14.8123);
    final before = refreshes;
    socket.emit('report.updated', {
      'id': 4,
      'status': 'dispatched',
    }, channel: 'private-drivers.7');
    await Future<void>.delayed(Duration.zero);
    expect(refreshes, greaterThan(before));
    live.stop();
    expect(live.connected, isFalse);
    expect(socket.closed, isTrue);
  });
  test('server disconnect enters reconnect state and disposal prevents new connections', () async {
    final socket = FakeSocket(), adapter = RealtimeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    var opens = 0;
    final live = DriverRealtime(
      client: client,
      open: (_) {
        opens++;
        return socket;
      },
    );
    await live.start();
    await live.start();
    expect(opens, 1);
    socket.emit('pusher:error', {'code': 4000});
    await until(live, () => live.status.contains('Reconnecting'));
    expect(live.connected, isFalse);
    expect(socket.closed, isTrue);
    live.dispose();
    await socket.input.close();
    await socket.outgoing.close();
    client.close();
  });
  test('socket failure identifies the configured host and port without leaking exception details', () async {
    final socket = FakeSocket()..rejectConnection = true;
    final adapter = RealtimeAdapter();
    final client = Dio()..httpClientAdapter = adapter;
    final live = DriverRealtime(client: client, open: (_) => socket);
    await live.start();
    expect(live.lastError, contains('localhost:8080'));
    expect(live.lastError, contains('Cannot connect to Reverb'));
    expect(live.status, contains('Reconnecting'));
    expect(live.status, isNot(contains('sensitive internal')));
    live.dispose();
    await socket.input.close();
    await socket.outgoing.close();
    client.close();
  });
  test(
    'private channel rejection displays the authorization HTTP status',
    () async {
      final socket = FakeSocket();
      final adapter = RealtimeAdapter()..authStatus = 403;
      final client = Dio()..httpClientAdapter = adapter;
      final live = DriverRealtime(client: client, open: (_) => socket);
      await live.start();
      socket.emit('pusher:connection_established', {'socket_id': '123.456'});
      await until(live, () => live.lastError != null);
      expect(live.lastError, contains('HTTP 403'));
      expect(live.status, contains('private channel'));
      expect(live.connected, isFalse);
      live.dispose();
      await socket.input.close();
      await socket.outgoing.close();
      client.close();
    },
  );
  test(
    'disabled server configuration is distinguished from an unreachable socket',
    () async {
      final adapter = RealtimeAdapter()..enabled = false;
      final client = Dio()..httpClientAdapter = adapter;
      var opens = 0;
      final live = DriverRealtime(
        client: client,
        open: (_) {
          opens++;
          return FakeSocket();
        },
      );
      await live.start();
      expect(opens, 0);
      expect(live.lastError, contains('disabled or unconfigured'));
      expect(live.connected, isFalse);
      live.dispose();
      client.close();
    },
  );
}
