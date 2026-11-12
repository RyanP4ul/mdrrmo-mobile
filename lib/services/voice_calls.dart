import 'dart:async';
import 'dart:math';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../data/api_client.dart';
import '../data/api_errors.dart';
import 'internet_connection.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

class CallParticipant {
  const CallParticipant(this.role, this.uid);
  final String role;
  final int uid;
  String get label => role == 'driver/responder'
      ? 'Responder'
      : role == 'dispatcher'
      ? 'Dispatcher'
      : role == 'guest'
      ? 'Guest'
      : 'Resident';
}

class VoiceCall {
  VoiceCall.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      reportId = json['report_id'] as int?,
      kind = json['kind'] as String? ?? 'report',
      queueState = json['queue_state'] as String?,
      queuePosition = json['queue_position'] as int?,
      endReason = json['end_reason'] as String?,
      reference = json['report_reference'] as String?,
      status = json['status'] as String,
      joinable = json['joinable'] == true,
      participants = (json['participants'] as List)
          .map(
            (value) =>
                CallParticipant(value['role'] as String, value['uid'] as int),
          )
          .toList();
  final String id;
  final int? reportId;
  final String kind;
  final String? queueState;
  final int? queuePosition;
  final String? endReason;
  bool get isSos => kind == 'sos';
  final String? reference;
  final String status;
  final bool joinable;
  final List<CallParticipant> participants;
  String get label =>
      isSos ? 'SOS - Dispatcher' : reference ?? 'Report #$reportId';
}

class VoiceCredentials {
  VoiceCredentials.fromJson(Map<String, dynamic> json)
    : appId = json['app_id'] as String,
      channel = json['channel'] as String,
      uid = json['uid'] as int,
      token = json['token'] as String;
  final String appId;
  final String channel;
  final int uid;
  final String token;
}

class VoiceCallsApi {
  VoiceCallsApi({Dio? client}) : _client = client ?? dio;
  final Dio _client;
  static const path = '/communication/calls';
  Future<List<VoiceCall>> list() async {
    final calls = <VoiceCall>[];
    var page = 1;
    while (true) {
      final response = await _client.get<Map<String, dynamic>>(
        path,
        queryParameters: {'page': page},
      );
      calls.addAll(
        (response.data!['data'] as List).map(
          (value) => VoiceCall.fromJson(Map<String, dynamic>.from(value)),
        ),
      );
      if (response.data!['next_page_url'] == null) return calls;
      page++;
    }
  }

  Future<VoiceCall> show(String id) async => VoiceCall.fromJson(
    (await _client.get<Map<String, dynamic>>('$path/$id')).data!['data'],
  );
  Future<VoiceCall> create(int reportId) async => VoiceCall.fromJson(
    (await _client.post<Map<String, dynamic>>(
      path,
      data: {'report_id': reportId},
    )).data!['data'],
  );
  Future<VoiceCall> createSos() async => VoiceCall.fromJson(
    (await _client.post<Map<String, dynamic>>('$path/sos')).data!['data'],
  );
  Future<VoiceCredentials> credentials(String id) async =>
      VoiceCredentials.fromJson(
        (await _client.post<Map<String, dynamic>>('$path/$id/token'))
            .data!['data'],
      );
  Future<void> end(String id) async {
    await _client.post('$path/$id/end');
  }
}

/// Each guest call owns an unguessable capability. It grants access only to that
/// call and is never persisted, listed, or sent through the resident auth client.
class GuestVoiceCallsApi extends VoiceCallsApi {
  GuestVoiceCallsApi({this.details = const {}, Dio? client})
    : _guest =
          client ??
          Dio(
            BaseOptions(
              baseUrl: dotenv.get(
                'API_URL',
                fallback: 'http://10.0.2.2:8000/api',
              ),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'Accept': 'application/json'},
            ),
          );
  final Dio _guest;
  final Map<String, String> details;
  String? _id;
  static final String _sessionSecret = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  String? _secret = _sessionSecret;
  Options get _options => Options(headers: {'X-Guest-Call-Token': _secret});
  static const _path = '/guest/calls';
  @override
  Future<VoiceCall> createSos() async {
    if (_id != null) {
      final previous = await show(_id!);
      if (previous.joinable) return previous;
    }
    final result = await _guest.post<Map<String, dynamic>>(
      _path,
      data: details,
      options: _options,
    );
    _secret = result.data!['guest_token'] as String;
    final call = VoiceCall.fromJson(result.data!['data']);
    _id = call.id;
    return call;
  }

  @override
  Future<List<VoiceCall>> list() async => _id == null ? [] : [await show(_id!)];
  @override
  Future<VoiceCall> show(String id) async => VoiceCall.fromJson(
    (await _guest.get<Map<String, dynamic>>(
      '$_path/$id',
      options: _options,
    )).data!['data'],
  );
  @override
  Future<VoiceCredentials> credentials(String id) async =>
      VoiceCredentials.fromJson(
        (await _guest.post<Map<String, dynamic>>(
          '$_path/$id/token',
          options: _options,
        )).data!['data'],
      );
  @override
  Future<void> end(String id) async {
    await _guest.post('$_path/$id/end', options: _options);
  }
}

class VoiceEvents {
  const VoiceEvents({
    required this.connected,
    required this.peerJoined,
    required this.peerLeft,
    required this.renew,
    required this.failed,
    required this.reconnecting,
  });
  final VoidCallback connected;
  final ValueChanged<int> peerJoined;
  final ValueChanged<int> peerLeft;
  final VoidCallback renew;
  final ValueChanged<String> failed;
  final ValueChanged<bool> reconnecting;
}

abstract interface class VoiceTransport {
  Future<void> connect(VoiceCredentials credentials, VoiceEvents events);
  Future<void> renew(String token);
  Future<void> mute(bool muted);
  Future<void> speaker(bool enabled);
  Future<void> close();
}

class AgoraVoiceTransport implements VoiceTransport {
  RtcEngine? _engine;
  Future<void>? _connecting;
  Future<void>? _closing;
  bool _closed = false;
  @override
  Future<void> connect(VoiceCredentials credentials, VoiceEvents events) {
    return _connecting = _connect(credentials, events);
  }

  Future<void> _connect(
    VoiceCredentials credentials,
    VoiceEvents events,
  ) async {
    final engine = createAgoraRtcEngine();
    _engine = engine;
    await engine.initialize(
      RtcEngineContext(
        appId: credentials.appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    if (_closed) return;
    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (_, _) => events.connected(),
        onRejoinChannelSuccess: (_, _) => events.connected(),
        onUserJoined: (_, uid, _) => events.peerJoined(uid),
        onUserOffline: (_, uid, _) => events.peerLeft(uid),
        onTokenPrivilegeWillExpire: (_, _) => events.renew(),
        onRequestToken: (_) => events.renew(),
        onConnectionStateChanged: (_, state, _) {
          if (state == ConnectionStateType.connectionStateFailed) {
            events.failed('The call disconnected. Please try joining again.');
          } else if (state == ConnectionStateType.connectionStateConnected) {
            events.reconnecting(false);
          } else if (state == ConnectionStateType.connectionStateReconnecting ||
              state == ConnectionStateType.connectionStateDisconnected) {
            events.reconnecting(true);
          }
        },
        onError: (code, _) => events.failed(
          'Voice connection error (${code.name}). Please rejoin.',
        ),
      ),
    );
    await engine.enableAudio();
    if (_closed) return;
    await engine.setDefaultAudioRouteToSpeakerphone(true);
    if (_closed) return;
    await engine.joinChannel(
      token: credentials.token,
      channelId: credentials.channel,
      uid: credentials.uid,
      options: const ChannelMediaOptions(
        channelProfile: ChannelProfileType.channelProfileCommunication,
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        publishMicrophoneTrack: true,
        publishCameraTrack: false,
        autoSubscribeAudio: true,
        autoSubscribeVideo: false,
      ),
    );
  }

  @override
  Future<void> renew(String token) async {
    await _engine?.renewToken(token);
  }

  @override
  Future<void> mute(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  @override
  Future<void> speaker(bool enabled) async {
    await _engine?.setEnableSpeakerphone(enabled);
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    try {
      await _connecting;
    } catch (_) {
      /* Release partially initialized engines too. */
    }
    final engine = _engine;
    _engine = null;
    if (engine == null) return;
    try {
      await engine.leaveChannel();
    } finally {
      await engine.release();
    }
  }
}

enum VoicePhase { idle, joining, connected, reconnecting, leaving }

class VoiceCallController extends ChangeNotifier {
  VoiceCallController({
    VoiceCallsApi? api,
    VoiceTransport Function()? transport,
    Future<bool> Function()? microphonePermission,
    InternetConnection? connection,
  }) : connection = connection ?? InternetConnection.instance,
       api = api ?? VoiceCallsApi(),
       _transportFactory = transport ?? AgoraVoiceTransport.new,
       _permission =
           microphonePermission ??
           (() async => (await Permission.microphone.request()).isGranted) {
    this.connection.addListener(_connectionChanged);
  }
  final InternetConnection connection;
  bool get online => connection.online;
  Future<bool> ensureOnline() => connection.check();
  void _connectionChanged() {
    if (!online && call != null && phase != VoicePhase.leaving) {
      if (_hasMicrophonePermission) {
        _beginReconnect();
      } else {
        unawaited(leave('Internet calling is unavailable. Please try again.'));
      }
    } else if (online && phase == VoicePhase.reconnecting) {
      unawaited(_recover());
    }
    _notify();
  }

  final VoiceCallsApi api;
  final VoiceTransport Function() _transportFactory;
  final Future<bool> Function() _permission;
  VoiceTransport? _transport;
  VoiceCall? call;
  VoicePhase phase = VoicePhase.idle;
  String? error;
  int? uid;
  bool muted = false;
  bool speaker = true;
  final Set<int> peers = {};
  int _generation = 0;
  bool _disposed = false;
  bool _renewing = false;
  bool _checking = false;
  bool _changingAudio = false;
  Timer? _poll;
  Timer? _joinTimeout;
  Timer? _reconnectTimeout;
  Timer? _retryTimer;
  Future<void>? _closingTransport;
  bool _recovering = false;
  bool _hasMicrophonePermission = false;

  void _beginReconnect() {
    if (_disposed || call == null || phase == VoicePhase.leaving) return;
    ++_generation;
    _poll?.cancel();
    _joinTimeout?.cancel();
    phase = VoicePhase.reconnecting;
    peers.clear();
    final transport = _transport;
    _transport = null;
    final pendingClose = _closingTransport;
    _closingTransport = Future.wait<void>([
      ?pendingClose,
      if (transport != null) transport.close().catchError((Object _) {}),
    ]).then((_) {});
    _reconnectTimeout ??= Timer(const Duration(seconds: 30), () {
      unawaited(
        leave(
          'The call could not reconnect. Retry or use the native phone call option.',
        ),
      );
    });
    _retryTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_recover());
    });
    _notify();
  }

  bool _accessRejected(Object error) =>
      error is DioException &&
      {401, 403, 404, 409, 410}.contains(error.response?.statusCode);

  Future<void> _recover() async {
    if (_disposed ||
        _recovering ||
        phase != VoicePhase.reconnecting ||
        !online ||
        _transport != null) {
      return;
    }
    _recovering = true;
    final generation = _generation;
    bool current() => !_disposed && generation == _generation;
    try {
      await _closingTransport;
      if (!current()) return;
      final latest = await api.show(call!.id);
      if (!current()) return;
      if (latest.status != 'active' || !latest.joinable) {
        await leave('This call ended or its report assignment changed.');
        return;
      }
      call = latest;
      await _connect(latest, generation);
    } catch (error) {
      if (current() && _accessRejected(error)) {
        await leave(
          'Call access expired or changed. Rejoin if the call is still available.',
        );
      } else if (current()) {
        _beginReconnect();
      }
    } finally {
      _recovering = false;
    }
  }

  void _connected() {
    _joinTimeout?.cancel();
    _reconnectTimeout?.cancel();
    _reconnectTimeout = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    phase = VoicePhase.connected;
    error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> join(VoiceCall selected) async {
    if (phase != VoicePhase.idle || _disposed) return;
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    final reachable = await ensureOnline();
    if (!current()) return;
    if (!reachable || phase != VoicePhase.idle) {
      error =
          'Internet calling is unavailable. Use the native phone call option.';
      _notify();
      return;
    }
    phase = VoicePhase.joining;
    error = null;
    call = selected;
    _notify();
    try {
      if (!await _permission()) {
        if (current()) {
          await leave(
            'Allow microphone access in app settings to join the call.',
          );
        }
        return;
      }
      if (!current() || !online) return;
      _hasMicrophonePermission = true;
      await _connect(selected, generation);
    } catch (failure) {
      if (current()) {
        await leave(
          failure is AgoraRtcException
              ? 'Voice setup failed (Agora error ${failure.code}). Retry the call.'
              : failure is DioException
              ? 'Could not get call access. ${apiErrorMessage(failure)}'
              : selected.isSos
              ? 'Could not connect the SOS call. Check microphone permission and internet connection, then retry.'
              : 'Could not join the call. Check microphone permission, assignment, and internet connection.',
        );
      }
    }
  }

  Future<void> _connect(VoiceCall selected, int generation) async {
    bool current() => !_disposed && generation == _generation;
    final credentials = await api.credentials(selected.id);
    if (!current()) return;
    uid = credentials.uid;
    final transport = _transportFactory();
    _transport = transport;
    Future<void>? speakerSetup;
    void connected() {
      if (!current()) return;
      if (phase != VoicePhase.connected) _connected();
      // Joining is asynchronous: joinChannel returning does not mean that
      // the device is ready to change its current audio route.
      speakerSetup ??= _restoreSpeaker(transport, generation);
      unawaited(speakerSetup!);
    }

    if (phase == VoicePhase.joining) {
      _joinTimeout = Timer(const Duration(seconds: 30), () {
        if (current() && phase == VoicePhase.joining) {
          unawaited(leave('The connection timed out. Please try again.'));
        }
      });
    }
    await transport.connect(
      credentials,
      VoiceEvents(
        connected: connected,
        peerJoined: (peer) {
          if (current()) {
            peers.add(peer);
            _notify();
          }
        },
        peerLeft: (peer) {
          if (current()) {
            peers.remove(peer);
            _notify();
          }
        },
        renew: () {
          if (current()) unawaited(_renew(generation));
        },
        failed: (message) {
          if (current()) {
            if (phase == VoicePhase.joining) {
              unawaited(leave(message));
            } else {
              _beginReconnect();
            }
          }
        },
        reconnecting: (value) {
          if (current() && phase != VoicePhase.joining) {
            if (value) {
              _beginReconnect();
            } else {
              connected();
            }
          }
        },
      ),
    );
    if (!current()) {
      await transport.close();
      return;
    }
    await transport.mute(muted);
    if (!current()) return;
    await speakerSetup;
    if (!current()) return;
    _poll?.cancel();
    _poll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_check(generation)),
    );
  }

  Future<void> _restoreSpeaker(VoiceTransport transport, int generation) async {
    try {
      await transport.speaker(speaker);
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = 'The call is connected, but the speaker setting could not be applied. Try the speaker button again.';
        _notify();
      }
    }
  }

  Future<void> _renew(int generation) async {
    if (_renewing || call == null) return;
    _renewing = true;
    try {
      final credentials = await api.credentials(call!.id);
      if (generation == _generation && !_disposed) {
        await _transport?.renew(credentials.token);
      }
    } catch (error) {
      if (generation == _generation) {
        if (_accessRejected(error) || error is! DioException) {
          await leave(
            'Call access expired or changed. Rejoin if the call is still available.',
          );
        } else {
          _beginReconnect();
        }
      }
    } finally {
      _renewing = false;
    }
  }

  Future<void> _check(int generation) async {
    if (_checking || call == null || phase == VoicePhase.reconnecting) return;
    _checking = true;
    try {
      final latest = await api.show(call!.id);
      if (generation == _generation &&
          (latest.status != 'active' || !latest.joinable)) {
        await leave(switch (latest.endReason) {
          'rejected' => 'The dispatcher could not accept this call. Use the native phone call option.',
          'timeout' => 'The call request timed out. Retry or use the native phone call option.',
          'disconnected' =>
            'The call disconnected. Retry or use the native phone call option.',
          _ => 'This call ended or its report assignment changed.',
        });
      } else if (generation == _generation && !_disposed) {
        call = latest;
        _notify();
      }
    } catch (error) {
      if (generation == _generation) {
        if (_accessRejected(error)) {
          await leave(
            'Call access expired or changed. Rejoin if the call is still available.',
          );
        } else {
          _beginReconnect();
        }
      }
    } finally {
      _checking = false;
    }
  }

  Future<void> toggleMute() async {
    if (_transport == null || _changingAudio) return;
    _changingAudio = true;
    final generation = _generation;
    try {
      await _transport!.mute(!muted);
      if (generation == _generation) muted = !muted;
    } catch (_) {
      error = 'Could not change microphone settings.';
    } finally {
      _changingAudio = false;
      _notify();
    }
  }

  Future<void> toggleSpeaker() async {
    if (_transport == null || _changingAudio) return;
    _changingAudio = true;
    final generation = _generation;
    try {
      await _transport!.speaker(!speaker);
      if (generation == _generation) {
        speaker = !speaker;
        error = null;
      }
    } catch (_) {
      error = 'Could not change the audio output.';
    } finally {
      _changingAudio = false;
      _notify();
    }
  }

  Future<void> leave([String? message]) async {
    ++_generation;
    _hasMicrophonePermission = false;
    _poll?.cancel();
    _joinTimeout?.cancel();
    _reconnectTimeout?.cancel();
    _reconnectTimeout = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final transport = _transport;
    _transport = null;
    phase = VoicePhase.leaving;
    _notify();
    try {
      await _closingTransport;
      _closingTransport = null;
      await transport?.close();
    } catch (_) {
      /* Local teardown must complete even after disconnection. */
    }
    call = null;
    uid = null;
    peers.clear();
    muted = false;
    speaker = true;
    error = message;
    phase = VoicePhase.idle;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    connection.removeListener(_connectionChanged);
    unawaited(leave());
    super.dispose();
  }
}
