import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:mdrrmo_flutter/screens/sos_screen.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';
import 'package:mdrrmo_flutter/services/voice_calls.dart';
import 'package:mdrrmo_flutter/ui/kit.dart';

import 'voice_calls_test.dart' show FakeCallsApi, FakeTransport, call;

void main() {
  setUp(
    () => dotenv.loadFromString(
      envString:
          'API_URL=https://example.test/api\nDISPATCHER_PHONE=+639123456789',
    ),
  );

  test(
    'a transient failed probe does not interrupt an online connection',
    () async {
      var attempts = 0;
      final connection = InternetConnection(
        initiallyOnline: true,
        probe: () async => ++attempts > 1,
      );
      final states = <bool>[];
      connection.addListener(() => states.add(connection.online));

      expect(await connection.check(), isTrue);
      expect(attempts, 2);
      expect(states, [true]);
      connection.dispose();
    },
  );

  testWidgets('offline banner waits for the first connectivity result', (
    tester,
  ) async {
    final probe = Completer<bool>();
    final connection = InternetConnection(probe: () => probe.future);
    await tester.pumpWidget(
      MaterialApp(
        home: OfflineSosGate(
          connection: connection,
          child: const Scaffold(body: Text('Resident services')),
        ),
      ),
    );
    final check = connection.check();
    expect(find.text('Offline SOS'), findsNothing);
    probe.complete(false);
    await check;
    await tester.pump();
    expect(find.text('Offline SOS'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets('SOS opened from the offline banner restores internet calling', (
    tester,
  ) async {
    var reachable = false;
    final connection = InternetConnection(probe: () async => reachable);
    final navigator = GlobalKey<NavigatorState>();
    await connection.check();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        builder: (_, child) => OfflineSosGate(
          connection: connection,
          navigatorKey: navigator,
          child: child!,
        ),
        home: const Scaffold(body: Text('Resident services')),
      ),
    );
    await tester.tap(find.text('Offline SOS'));
    await tester.pumpAndSettle();
    expect(find.text('Start Free Internet Call'), findsNothing);
    reachable = true;
    await connection.check();
    await tester.pumpAndSettle();
    expect(find.text('Start Free Internet Call'), findsOneWidget);
    expect(find.text('Offline SOS'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets(
    'offline guest has only SOS and launches a cellular tel URI without personal details',
    (tester) async {
      final connection = InternetConnection(probe: () async => false);
      Uri? dialed;
      await tester.pumpWidget(
        MaterialApp(
          home: SosScreen(
            guest: true,
            connection: connection,
            dial: (uri) async {
              dialed = uri;
              return true;
            },
          ),
        ),
      );
      expect(find.text('Offline SOS'), findsOneWidget);
      expect(find.text('Start Free Internet Call'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text('Call Hotline Now'));
      await tester.pump();
      expect(dialed.toString(), 'tel:+639123456789');
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets(
    'online guest can call with no details and a fresh offline check prevents internet calling',
    (tester) async {
      var reachable = true;
      var starts = 0;
      final connection = InternetConnection(
        probe: () async => reachable,
        initiallyOnline: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SosScreen(
            guest: true,
            connection: connection,
            startSystemCall: (details) async {
              expect(details, isEmpty);
              starts++;
            },
          ),
        ),
      );
      expect(find.text('Call Hotline Now'), findsOneWidget);
      expect(find.text('Start Free Internet Call'), findsOneWidget);
      expect(find.text('Native-to-Native Call'), findsNothing);
      expect(find.text('System-to-System Call'), findsNothing);
      expect(find.text('Not sure which one to choose?'), findsOneWidget);
      await tester.ensureVisible(find.text('Start Free Internet Call'));
      await tester.tap(find.text('Start Free Internet Call'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      reachable = false;
      await tester.ensureVisible(find.text('Start Free Internet Call'));
      await tester.tap(find.text('Start Free Internet Call'));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(find.text('Start Free Internet Call'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets(
    'SOS screen renders cleanly on small screens with 2.0x text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final connection = InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: SosScreen(guest: true, connection: connection),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Call Hotline Now'), findsOneWidget);
      expect(find.text('Start Free Internet Call'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets(
    'offline gate shows non-blocking banner over current route and restores on reconnect',
    (tester) async {
      var reachable = true;
      final connection = InternetConnection(
        probe: () async => reachable,
        initiallyOnline: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (_, child) =>
              OfflineSosGate(connection: connection, child: child!),
          home: const Scaffold(body: Text('Resident services')),
        ),
      );
      expect(find.text('Resident services'), findsOneWidget);
      reachable = false;
      await connection.check();
      await tester.pumpAndSettle();
      expect(find.text('Resident services'), findsOneWidget);
      expect(find.text('Offline mode — limited connection'), findsOneWidget);
      expect(find.text('Offline SOS'), findsOneWidget);
      reachable = true;
      await connection.check();
      await tester.pumpAndSettle();
      expect(find.text('Resident services'), findsOneWidget);
      expect(find.text('Offline mode — limited connection'), findsNothing);
      expect(find.text('Offline SOS'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  test('offline joining requests no credentials and losing connectivity releases active audio', () async {
    var reachable = false;
    final connection = InternetConnection(probe: () async => reachable);
    final api = FakeCallsApi();
    final transport = FakeTransport();
    final controller = VoiceCallController(
      api: api,
      connection: connection,
      transport: () => transport,
      microphonePermission: () async => true,
    );
    await controller.join(call());
    expect(api.tokens, 0);
    reachable = true;
    await controller.join(call());
    expect(controller.phase, VoicePhase.connected);
    reachable = false;
    await connection.check();
    await Future<void>.delayed(Duration.zero);
    expect(transport.closed, isTrue);
    expect(controller.phase, VoicePhase.reconnecting);
    expect(controller.call?.id, call().id);
    controller.dispose();
    connection.dispose();
  });
  testWidgets(
    'persistent audio reconnection times out and releases the microphone',
    (tester) async {
      var reachable = true;
      final connection = InternetConnection(
        probe: () async => reachable,
        initiallyOnline: true,
      );
      final transport = FakeTransport();
      final controller = VoiceCallController(
        api: FakeCallsApi(),
        connection: connection,
        transport: () => transport,
        microphonePermission: () async => true,
      );
      await controller.join(call());
      reachable = false;
      await connection.check();
      await tester.pump(const Duration(seconds: 31));
      expect(transport.closed, isTrue);
      expect(controller.phase, VoicePhase.idle);
      controller.dispose();
      connection.dispose();
    },
  );

  testWidgets(
    'offline banner consumes top safe area so headers have no gap beneath it',
    (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 40);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);

      final connection = InternetConnection(probe: () async => false);
      await connection.check();
      final theme = FTheme.neutral.light.touch;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toApproximateMaterialTheme(),
          builder: (_, child) => FTheme(
            data: theme,
            child: OfflineSosGate(connection: connection, child: child!),
          ),
          home: AppScaffold(
            header: FHeader(title: const Text('Balagtas MDRRMO')),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bannerRect = tester.getRect(
        find.ancestor(
          of: find.text('Offline mode — limited connection'),
          matching: find.byType(Material),
        ).first,
      );
      final titleRect = tester.getRect(find.text('Balagtas MDRRMO'));
      expect(bannerRect.top, 0);
      expect(titleRect.top - bannerRect.bottom, lessThan(24));
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );
}
