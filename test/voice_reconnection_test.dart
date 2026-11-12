import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';
import 'package:mdrrmo_flutter/services/voice_calls.dart';

import 'voice_calls_test.dart' show FakeCallsApi, FakeTransport, call;

class RecoveringCallsApi extends FakeCallsApi {
  bool unavailable = false;
  Completer<VoiceCall>? pending;

  @override
  Future<VoiceCall> show(String id) async {
    if (unavailable) throw StateError('Temporary server outage');
    if (pending != null) return pending!.future;
    return super.show(id);
  }
}

void main() {
  late RecoveringCallsApi api;
  late InternetConnection connection;
  late VoiceCallController voice;
  late List<FakeTransport> transports;
  late bool reachable;
  late int permissions;

  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
    reachable = true;
    permissions = 0;
    api = RecoveringCallsApi();
    transports = [];
    connection = InternetConnection(
      probe: () async => reachable,
      initiallyOnline: true,
    );
    voice = VoiceCallController(
      api: api,
      connection: connection,
      transport: () {
        final transport = FakeTransport();
        transports.add(transport);
        return transport;
      },
      microphonePermission: () async {
        permissions++;
        return true;
      },
    );
  });

  tearDown(() {
    voice.dispose();
    connection.dispose();
  });

  testWidgets(
    'restores the same call and audio settings when internet returns',
    (tester) async {
      await voice.join(call());
      await voice.toggleMute();
      await voice.toggleSpeaker();
      final oldEvents = transports.first.events!;
      reachable = false;
      await connection.check();
      await tester.pump();
      expect(transports.first.closed, isTrue);
      expect(voice.phase, VoicePhase.reconnecting);
      expect(voice.call!.id, 'call-1');

      // Events from the abandoned engine must not claim a successful reconnect.
      oldEvents.connected();
      expect(voice.phase, VoicePhase.reconnecting);
      reachable = true;
      await connection.check();
      await tester.pump();
      expect(voice.phase, VoicePhase.connected);
      expect(transports.length, 2);
      expect(api.tokens, 2);
      expect(permissions, 1);
      expect(transports.last.muted, isTrue);
      expect(transports.last.loud, isFalse);
      await voice.leave();
    },
  );

  testWidgets('a failed audio transport reconnects without another join tap', (
    tester,
  ) async {
    await voice.join(call());
    transports.first.events!.failed('Lost connection');
    await tester.pump(const Duration(seconds: 3));
    expect(voice.phase, VoicePhase.connected);
    expect(transports.first.closed, isTrue);
    expect(transports.length, 2);
    expect(permissions, 1);
    await voice.leave();
  });

  testWidgets('temporary API failures retry without ending the call', (
    tester,
  ) async {
    await voice.join(call());
    api.unavailable = true;
    await tester.pump(const Duration(seconds: 5));
    expect(voice.phase, VoicePhase.reconnecting);
    await tester.pump(const Duration(seconds: 3));
    expect(voice.call!.id, 'call-1');
    api.unavailable = false;
    await tester.pump(const Duration(seconds: 3));
    expect(voice.phase, VoicePhase.connected);
    expect(api.tokens, 2);
    await voice.leave();
  });

  testWidgets('an ended call is never rejoined during recovery', (
    tester,
  ) async {
    await voice.join(call());
    reachable = false;
    await connection.check();
    api.ended = true;
    reachable = true;
    await connection.check();
    await tester.pump();
    expect(voice.phase, VoicePhase.idle);
    expect(voice.call, isNull);
    expect(api.tokens, 1);
    expect(transports.length, 1);
  });

  testWidgets('leaving cancels recovery even with a pending server response', (
    tester,
  ) async {
    await voice.join(call());
    api.pending = Completer<VoiceCall>();
    transports.first.events!.failed('Lost connection');
    await tester.pump(const Duration(seconds: 3));
    await voice.leave();
    api.pending!.complete(call());
    await tester.pump(const Duration(seconds: 10));
    expect(voice.phase, VoicePhase.idle);
    expect(api.tokens, 1);
    expect(transports.length, 1);
  });
}
