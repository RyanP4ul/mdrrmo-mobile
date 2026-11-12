import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdrrmo_flutter/services/voice_calls.dart';
import 'package:mdrrmo_flutter/services/internet_connection.dart';

VoiceCall call({bool ended = false}) => VoiceCall.fromJson({
  'id': 'call-1',
  'report_id': 12,
  'report_reference': 'RPT-12',
  'status': ended ? 'ended' : 'active',
  'joinable': !ended,
  'participants': [
    {'role': 'resident', 'uid': 1},
    {'role': 'dispatcher', 'uid': 2},
    {'role': 'driver/responder', 'uid': 3},
  ],
});

class FakeCallsApi extends VoiceCallsApi {
  bool forbidden = false;
  bool ended = false;
  int tokens = 0;
  @override
  Future<VoiceCredentials> credentials(String id) async {
    tokens++;
    if (forbidden) throw StateError('Forbidden');
    return VoiceCredentials.fromJson({
      'app_id': 'public',
      'channel': 'server-channel',
      'uid': 1,
      'token': 'secret',
    });
  }

  @override
  Future<VoiceCall> show(String id) async => call(ended: ended);
}

class FakeTransport implements VoiceTransport {
  VoiceEvents? events;
  VoiceCredentials? credentials;
  bool closed = false;
  bool muted = false;
  bool loud = true;
  String? renewed;
  @override
  Future<void> connect(VoiceCredentials credentials, VoiceEvents events) async {
    this.credentials = credentials;
    this.events = events;
    events.connected();
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> mute(bool muted) async {
    this.muted = muted;
  }

  @override
  Future<void> speaker(bool enabled) async {
    loud = enabled;
  }

  @override
  Future<void> renew(String token) async {
    renewed = token;
  }
}

class DelayedJoinTransport extends FakeTransport {
  bool joined = false;
  bool rejectSpeaker = false;
  int speakerRequests = 0;

  @override
  Future<void> connect(VoiceCredentials credentials, VoiceEvents events) async {
    this.credentials = credentials;
    this.events = events;
  }

  void finishJoining() {
    joined = true;
    events!.connected();
  }

  @override
  Future<void> speaker(bool enabled) async {
    speakerRequests++;
    if (!joined || rejectSpeaker) throw AgoraRtcException(code: -3);
    await super.speaker(enabled);
  }
}

void main() {
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://example.test/api');
  });

  testWidgets('speaker routing waits for Agora to confirm the channel joined', (
    tester,
  ) async {
    final connection = InternetConnection(
      probe: () async => true,
      initiallyOnline: true,
    );
    final transport = DelayedJoinTransport();
    final voice = VoiceCallController(
      api: FakeCallsApi(),
      connection: connection,
      transport: () => transport,
      microphonePermission: () async => true,
    );
    await voice.join(call());
    expect(voice.phase, VoicePhase.joining);
    expect(transport.speakerRequests, 0);
    expect(transport.closed, isFalse);
    transport.finishJoining();
    await tester.pump();
    expect(voice.phase, VoicePhase.connected);
    expect(transport.speakerRequests, 1);
    expect(voice.error, isNull);
    voice.dispose();
    connection.dispose();
  });

  testWidgets('a speaker-routing error does not tear down a connected call', (
    tester,
  ) async {
    final connection = InternetConnection(
      probe: () async => true,
      initiallyOnline: true,
    );
    final transport = DelayedJoinTransport()..rejectSpeaker = true;
    final voice = VoiceCallController(
      api: FakeCallsApi(),
      connection: connection,
      transport: () => transport,
      microphonePermission: () async => true,
    );
    await voice.join(call());
    transport.finishJoining();
    await tester.pump();
    expect(voice.phase, VoicePhase.connected);
    expect(transport.closed, isFalse);
    expect(voice.error, contains('speaker setting'));
    transport.rejectSpeaker = false;
    await voice.toggleSpeaker();
    expect(transport.loud, isFalse);
      expect(voice.error, isNull);
    voice.dispose();
    connection.dispose();
  });

  test('joins the server channel and tracks all three participants and audio controls', () async {
    final api = FakeCallsApi();
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
    await voice.join(call());
    expect(transport.credentials!.channel, 'server-channel');
    expect(voice.uid, 1);
    expect(voice.phase, VoicePhase.connected);
    transport.events!.peerJoined(2);
    transport.events!.peerJoined(3);
    expect(voice.peers, {2, 3});
    transport.events!.peerLeft(3);
    expect(voice.peers, {2});
    await voice.toggleMute();
    expect(transport.muted, true);
    await voice.toggleSpeaker();
    expect(transport.loud, false);
    await voice.leave();
    expect(transport.closed, true);
    expect(voice.phase, VoicePhase.idle);
    voice.dispose();
  });

  test('denied microphone permission never requests credentials or opens the engine', () async {
    final api = FakeCallsApi();
    var opened = false;
    final voice = VoiceCallController(
      connection: InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      ),
      api: api,
      transport: () {
        opened = true;
        return FakeTransport();
      },
      microphonePermission: () async => false,
    );
    await voice.join(call());
    expect(api.tokens, 0);
    expect(opened, false);
    expect(voice.phase, VoicePhase.idle);
    expect(voice.error, contains('microphone'));
    voice.dispose();
  });

  test('leaving during the permission prompt prevents a late join', () async {
    final api = FakeCallsApi();
    final permission = Completer<bool>();
    final voice = VoiceCallController(
      connection: InternetConnection(
        probe: () async => true,
        initiallyOnline: true,
      ),
      api: api,
      microphonePermission: () => permission.future,
    );
    final joining = voice.join(call());
    await voice.leave();
    permission.complete(true);
    await joining;
    expect(api.tokens, 0);
    expect(voice.phase, VoicePhase.idle);
    voice.dispose();
  });

  test(
    'leaving during the connectivity check cancels a pending automatic join',
    () async {
      final probe = Completer<bool>();
      final connection = InternetConnection(
        probe: () => probe.future,
        initiallyOnline: true,
      );
      final api = FakeCallsApi();
      var permissions = 0;
      final voice = VoiceCallController(
        connection: connection,
        api: api,
        transport: FakeTransport.new,
        microphonePermission: () async {
          permissions++;
          return true;
        },
      );
      final joining = voice.join(call());
      await voice.leave();
      probe.complete(true);
      await joining;
      expect(permissions, 0);
      expect(api.tokens, 0);
      expect(voice.phase, VoicePhase.idle);
      voice.dispose();
      connection.dispose();
    },
  );

  testWidgets('token rejection releases audio and reports expired access', (
    tester,
  ) async {
    final api = FakeCallsApi();
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
    await voice.join(call());
    transport.events!.renew();
    await tester.pump();
    expect(transport.renewed, 'secret');
    api.forbidden = true;
    transport.events!.renew();
    await tester.pump();
    expect(transport.closed, true);
    expect(voice.phase, VoicePhase.idle);
    expect(voice.error, contains('expired or changed'));
    voice.dispose();
  });

  testWidgets(
    'server ending the call releases the microphone on the next poll',
    (tester) async {
      final api = FakeCallsApi();
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
      await voice.join(call());
      api.ended = true;
      await tester.pump(const Duration(seconds: 5));
      expect(transport.closed, true);
      expect(voice.call, null);
      expect(voice.error, contains('ended'));
      voice.dispose();
    },
  );

  test(
    'disposing an open call closes audio and ignores late SDK callbacks',
    () async {
      final transport = FakeTransport();
      final voice = VoiceCallController(
        connection: InternetConnection(
          probe: () async => true,
          initiallyOnline: true,
        ),
        api: FakeCallsApi(),
        transport: () => transport,
        microphonePermission: () async => true,
      );
      await voice.join(call());
      voice.dispose();
      transport.events!.peerJoined(3);
      transport.events!.connected();
      await Future<void>.delayed(Duration.zero);
      expect(transport.closed, true);
      expect(voice.peers, isEmpty);
    },
  );
}
