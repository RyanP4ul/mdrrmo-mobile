import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/services/automatic_driver_tracking.dart';
import 'package:mdrrmo_flutter/services/auth_service.dart';

import 'vehicle_tracking_test.dart' show FakeGps, TrackingAdapter;

import 'package:dio/dio.dart';
import 'package:mdrrmo_flutter/services/driver_tracking.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle(WidgetTester tester) async {
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
  }

  testWidgets(
    'automatically sends driver coordinates without any vehicle or assignment and stops when disabled',
    (tester) async {
      final gps = FakeGps();
      final adapter = TrackingAdapter();
      final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter;
      final tracking = DriverTracking(source: gps, client: client);
      final automatic = AutomaticDriverTracking(tracking, background: true);
      automatic.setEnabled(true);
      await settle(tester);
      expect(tracking.active, isFalse);
      expect(adapter.requests, isEmpty);
      automatic.setLocationAccess(true);
      await settle(tester);
      expect(
        tracking.active,
        isTrue,
        reason:
            '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
      );
      final payload = adapter.requests.first.data as Map;
      expect(payload['notice_version'], 'driver-2026-11-04');
      expect(payload.containsKey('vehicle_id'), isFalse);
      expect(payload.containsKey('report_id'), isFalse);
      expect(payload.containsKey('consent'), isFalse);
      automatic.setEnabled(false);
      await settle(tester);
      expect(tracking.active, isFalse);
      automatic.dispose();
      tracking.dispose();
      await settle(tester);
      await gps.positions.close();
      client.close();
    },
  );

  testWidgets(
    'losing location access stops sending and restoring it restarts automatically',
    (tester) async {
      final gps = FakeGps();
      final adapter = TrackingAdapter();
      final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter;
      final tracking = DriverTracking(source: gps, client: client);
      final automatic = AutomaticDriverTracking(tracking, background: true);
      automatic.setEnabled(true);
      automatic.setLocationAccess(true);
      await settle(tester);
      expect(
        tracking.active,
        isTrue,
        reason:
            '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
      );
      automatic.setLocationAccess(false);
      await settle(tester);
      expect(tracking.active, isFalse);
      automatic.setLocationAccess(true);
      await settle(tester);
      expect(
        tracking.active,
        isTrue,
        reason:
            '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
      );
      AuthService.sessionExpired.value++;
      await settle(tester);
      expect(tracking.active, isFalse);
      automatic.setLocationAccess(true);
      await tester.pump(const Duration(minutes: 1));
      expect(tracking.active, isFalse);
      automatic.dispose();
      tracking.dispose();
      await settle(tester);
      await gps.positions.close();
      client.close();
    },
  );

  testWidgets('cancels a pending start when location permission is lost', (
    tester,
  ) async {
    final gps = FakeGps()..permission = Completer<void>();
    final adapter = TrackingAdapter();
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    final tracking = DriverTracking(source: gps, client: client);
    final automatic = AutomaticDriverTracking(tracking, background: true);
    automatic.setEnabled(true);
    automatic.setLocationAccess(true);
    await settle(tester);
    expect(tracking.busy, isTrue);
    automatic.setEnabled(false);
    gps.permission!.complete();
    await settle(tester);
    expect(tracking.active, isFalse);
    expect(adapter.requests, isEmpty);
    automatic.dispose();
    tracking.dispose();
    await settle(tester);
    await gps.positions.close();
    client.close();
  });

  testWidgets(
    'failed starts retry with a delay instead of looping and cancel when disabled',
    (tester) async {
      final gps = FakeGps()..fail = true;
      final adapter = TrackingAdapter();
      final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
        ..httpClientAdapter = adapter;
      final tracking = DriverTracking(source: gps, client: client);
      final automatic = AutomaticDriverTracking(tracking, background: true);
      automatic.setEnabled(true);
      automatic.setLocationAccess(true);
      await settle(tester);
      expect(tracking.active, isFalse);
      gps.fail = false;
      await tester.pump(const Duration(seconds: 29));
      expect(adapter.requests, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(
        tracking.active,
        isTrue,
        reason:
            '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
      );
      automatic.setEnabled(false);
      await settle(tester);
      await tester.pump(const Duration(minutes: 1));
      expect(tracking.active, isFalse);
      automatic.dispose();
      tracking.dispose();
      await settle(tester);
      await gps.positions.close();
      client.close();
    },
  );

  testWidgets('foreground-only devices recheck access after returning to the app', (
    tester,
  ) async {
    final gps = FakeGps();
    final adapter = TrackingAdapter();
    final client = Dio(BaseOptions(baseUrl: 'https://example.test/api'))
      ..httpClientAdapter = adapter;
    final tracking = DriverTracking(source: gps, client: client);
    final automatic = AutomaticDriverTracking(tracking, background: false);
    automatic.setEnabled(true);
    automatic.setLocationAccess(true);
    await settle(tester);
    expect(
      tracking.active,
      isTrue,
      reason:
          '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
    );
    automatic.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle(tester);
    expect(tracking.active, isFalse);
    automatic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    expect(tracking.active, isFalse);
    automatic.setLocationAccess(true);
    await settle(tester);
    expect(
      tracking.active,
      isTrue,
      reason:
          '${tracking.error}; busy=${tracking.busy}; requests=${adapter.requests.length}; stopped=${gps.stopped}',
    );
    automatic.dispose();
    tracking.dispose();
    await settle(tester);
    await gps.positions.close();
    client.close();
  });
}
