import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';

class FakeGps extends GpsSource {
  final positions = StreamController<GpsFix>.broadcast(sync: true);
  bool fail = false;
  int stopped = 0;
  Completer<void>? permission;
  @override
  Future<void> start(bool background) async {
    if (fail) throw StateError('Permission denied');
    await permission?.future;
  }

  @override
  Stream<GpsFix> get fixes => positions.stream;
  @override
  Future<void> stop() async {
    stopped++;
  }
}

class TrackingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool expired = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final status = options.path.endsWith('/ping') && expired
        ? 409
        : options.path.endsWith('/sessions')
        ? 201
        : 200;
    return ResponseBody.fromString(
      jsonEncode(
        options.path.endsWith('/sessions')
            ? {'session_id': 'session-1'}
            : status == 409
            ? {'message': 'Tracking expired'}
            : {'accepted': true},
      ),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  DriverTracking setup(FakeGps source, TrackingAdapter adapter) {
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    final tracking = DriverTracking(source: source, client: client);
    addTearDown(() async {
      await tracking.stop();
      tracking.dispose();
      await source.positions.close();
      client.close();
    });
    return tracking;
  }

  GpsFix fix({double accuracy = 10}) => GpsFix(
    latitude: 14.8,
    longitude: 120.9,
    accuracy: accuracy,
    time: DateTime.now().toUtc(),
  );
  test('permission failure does not create a sharing session', () async {
    final source = FakeGps()..fail = true;
    final adapter = TrackingAdapter();
    final tracking = setup(source, adapter);
    await tracking.start(inBackground: false);
    expect(tracking.active, isFalse);
    expect(tracking.error, contains('Permission denied'));
    expect(adapter.requests, isEmpty);
    expect(source.stopped, greaterThan(0));
  });
  test('accurate positions use the bound session and poor accuracy is not sent', () async {
    final source = FakeGps();
    final adapter = TrackingAdapter();
    final tracking = setup(source, adapter);
    await tracking.start(inBackground: false);
    expect(tracking.active, isTrue, reason: tracking.error);
    source.positions.add(fix(accuracy: 500));
    await settle();
    expect(adapter.requests.where((r) => r.path.endsWith('/ping')), isEmpty);
    final reading = fix();
    expect(
      reading.valid(DateTime.now().toUtc()),
      isTrue,
      reason:
          '${reading.latitude}, ${reading.longitude}, ${reading.accuracy}, ${reading.time}, ${DateTime.now().toUtc()}',
    );
    source.positions.add(reading);
    await tracking.sendLatest();
    await settle();
    expect(
      adapter.requests.where((r) => r.path.endsWith('/ping')),
      isNotEmpty,
      reason: tracking.error,
    );
    final ping = adapter.requests.singleWhere((r) => r.path.endsWith('/ping'));
    expect(ping.path, endsWith('/sessions/session-1/ping'));
    expect((ping.data as Map)['lat'], 14.8);
    expect((ping.data as Map)['sequence'], 1);
    expect(tracking.lastSent, isNotNull);
    await tracking.stop();
    expect(tracking.active, isFalse);
    source.positions.add(fix());
    await settle();
    expect(adapter.requests.where((r) => r.path.endsWith('/ping')).length, 1);
  });
  test('foreground sharing stops on pause while explicitly enabled background sharing continues', () async {
    final source = FakeGps();
    final adapter = TrackingAdapter();
    final tracking = setup(source, adapter);
    await tracking.start(inBackground: false);
    tracking.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(tracking.active, isFalse);
    await tracking.start(inBackground: true);
    tracking.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(tracking.active, isTrue);
  });
  test('expired backend session stops native location sharing', () async {
    final source = FakeGps();
    final adapter = TrackingAdapter()..expired = true;
    final tracking = setup(source, adapter);
    await tracking.start(inBackground: true);
    source.positions.add(fix());
    await tracking.sendLatest();
    await settle();
    expect(tracking.active, isFalse);
    expect(source.stopped, greaterThan(0));
    expect(tracking.error, contains('expired'));
  });
  test(
    'stopping while permission is pending prevents a late tracking session',
    () async {
      final source = FakeGps()..permission = Completer<void>();
      final adapter = TrackingAdapter();
      final tracking = setup(source, adapter);
      final starting = tracking.start(inBackground: true);
      await tracking.stop();
      source.permission!.complete();
      await starting;
      expect(tracking.active, isFalse);
      expect(adapter.requests, isEmpty);
    },
  );
}
