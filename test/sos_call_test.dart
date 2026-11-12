import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/screens/voice_calls_screen.dart';
import 'package:mdrrmo_flutter/services/voice_calls.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';

import 'responder_ui_test.dart' show app;
import 'voice_calls_test.dart' show FakeCallsApi, FakeTransport, call;

class AvailableCallsApi extends FakeCallsApi {
  List<VoiceCall> available = [];

  @override
  Future<List<VoiceCall>> list() async => available;
}

VoiceCall sosCall({bool ended = false}) => VoiceCall.fromJson({
  'id': 'sos-call-1',
  'kind': 'sos',
  'report_id': null,
  'status': ended ? 'ended' : 'active',
  'joinable': !ended,
  'participants': [
    {'role': 'resident', 'uid': 1},
    {'role': 'dispatcher', 'uid': 2},
  ],
});

class SosCallsApi extends FakeCallsApi {
  int starts = 0;
  bool fail = false;
  @override
  Future<VoiceCall> createSos() async {
    starts++;
    if (fail) throw StateError('Call service unavailable');
    return sosCall();
  }

  @override
  Future<List<VoiceCall>> list() async => ended ? [] : [sosCall()];
  @override
  Future<void> end(String id) async {
    ended = true;
  }

  @override
  Future<VoiceCall> show(String id) async => sosCall(ended: ended);
}

void main() {
  setUp(
    () => dotenv.loadFromString(envString: 'API_URL=https://example.test/api'),
  );

  testWidgets('resident joins an available call without tapping Join call', (
    tester,
  ) async {
    final api = AvailableCallsApi()..available = [call()];
    final connection = InternetConnection(
      probe: () async => true,
      initiallyOnline: true,
    );
    final voice = VoiceCallController(
      api: api,
      connection: connection,
      transport: FakeTransport.new,
      microphonePermission: () async => true,
    );
    await tester.pumpWidget(
      app(VoiceCallsScreen(autoJoin: true, voiceFactory: () => voice)),
    );
    await tester.pumpAndSettle();
    expect(voice.phase, VoicePhase.connected);
    expect(api.tokens, 1);
    expect(find.text('Join call'), findsNothing);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(voice.phase, VoicePhase.idle);
    expect(api.tokens, 1);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets(
    'resident automatically joins a call that becomes available later',
    (tester) async {
      final api = AvailableCallsApi();
      final connection = InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      );
      final voice = VoiceCallController(
        api: api,
        connection: connection,
        transport: FakeTransport.new,
        microphonePermission: () async => true,
      );
      await tester.pumpWidget(
        app(VoiceCallsScreen(autoJoin: true, voiceFactory: () => voice)),
      );
      await tester.pumpAndSettle();
      expect(api.tokens, 0);
      api.available = [call()];
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(voice.phase, VoicePhase.connected);
      expect(api.tokens, 1);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets(
    'failed automatic join keeps manual retry without repeating permission prompts',
    (tester) async {
      final api = AvailableCallsApi()..available = [call()];
      var permissions = 0;
      final connection = InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      );
      final voice = VoiceCallController(
        api: api,
        connection: connection,
        transport: FakeTransport.new,
        microphonePermission: () async {
          permissions++;
          return false;
        },
      );
      await tester.pumpWidget(
        app(VoiceCallsScreen(autoJoin: true, voiceFactory: () => voice)),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(permissions, 1);
      expect(api.tokens, 0);
      expect(find.text('Join call'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets('dispatcher does not automatically answer resident calls', (
    tester,
  ) async {
    final api = AvailableCallsApi()..available = [sosCall()];
    final connection = InternetConnection(
      probe: () async => true,
      initiallyOnline: true,
    );
    final voice = VoiceCallController(
      api: api,
      connection: connection,
      transport: FakeTransport.new,
      microphonePermission: () async => true,
    );
    await tester.pumpWidget(
      app(
        VoiceCallsScreen(
          dispatcher: true,
          autoJoin: true,
          voiceFactory: () => voice,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.tokens, 0);
    expect(find.text('Join call'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    connection.dispose();
  });

  testWidgets(
    'SOS immediately creates a two-party call and waits for the dispatcher before showing connected',
    (tester) async {
      final api = SosCallsApi();
      final transport = FakeTransport();
      final voice = VoiceCallController(
        connection: InternetConnection(
          probe: () async => true,
          initiallyOnline: true,
        ),
        api: api,
        transport: () => transport,
        microphonePermission: () async => true,
      );
      await tester.pumpWidget(
        app(VoiceCallsScreen(autoStartSos: true, voiceFactory: () => voice)),
      );
      await tester.pumpAndSettle();
      expect(api.starts, 1);
      expect(find.text('Available calls'), findsNothing);
      expect(find.text('No other calls'), findsNothing);
      expect(transport.credentials?.uid, 1);
      expect(voice.call!.reportId, isNull);
      expect(voice.call!.participants.length, 2);
      expect(
        find.text('Calling dispatcher - waiting for an answer'),
        findsOneWidget,
      );
      transport.events!.peerJoined(2);
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsOneWidget);
      await tester.tap(find.text('End SOS call'));
      await tester.pumpAndSettle();
      expect(api.ended, isTrue);
      expect(transport.closed, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'failed SOS creation offers retry without claiming the call connected',
    (tester) async {
      final api = SosCallsApi()..fail = true;
      await tester.pumpWidget(
        app(
          VoiceCallsScreen(
            autoStartSos: true,
            voiceFactory: () => VoiceCallController(
              connection: InternetConnection(
                probe: () async => true,
                initiallyOnline: true,
              ),
              api: api,
              transport: () => FakeTransport(),
              microphonePermission: () async => true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Call service unavailable'), findsOneWidget);
      expect(find.text('Connected'), findsNothing);
      await tester.tap(find.text('Call dispatcher'));
      await tester.pumpAndSettle();
      expect(api.starts, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'SOS hides available calls while reconnecting and restores the call',
    (tester) async {
      var reachable = true;
      final connection = InternetConnection(
        probe: () async => reachable,
        initiallyOnline: true,
      );
      final api = SosCallsApi();
      final voice = VoiceCallController(
        connection: connection,
        api: api,
        transport: FakeTransport.new,
        microphonePermission: () async => true,
      );
      await tester.pumpWidget(
        app(VoiceCallsScreen(autoStartSos: true, voiceFactory: () => voice)),
      );
      await tester.pumpAndSettle();
      reachable = false;
      await connection.check();
      await tester.pumpAndSettle();
      expect(find.text('Reconnecting...'), findsOneWidget);
      expect(find.text('Available calls'), findsNothing);
      expect(find.text('No other calls'), findsNothing);
      reachable = true;
      await connection.check();
      await tester.pumpAndSettle();
      expect(voice.phase, VoicePhase.connected);
      expect(api.starts, 1);
      expect(api.tokens, 2);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );

  testWidgets(
    'SOS offers retry after a failed join without showing available calls',
    (tester) async {
      var allowMicrophone = false;
      final connection = InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      );
      final api = SosCallsApi();
      final voice = VoiceCallController(
        connection: connection,
        api: api,
        transport: FakeTransport.new,
        microphonePermission: () async => allowMicrophone,
      );
      await tester.pumpWidget(
        app(VoiceCallsScreen(autoStartSos: true, voiceFactory: () => voice)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry call'), findsOneWidget);
      expect(find.text('Available calls'), findsNothing);
      allowMicrophone = true;
      await tester.tap(find.text('Retry call'));
      await tester.pumpAndSettle();
      expect(voice.phase, VoicePhase.connected);
      await tester.pumpWidget(const SizedBox());
      connection.dispose();
    },
  );
}
