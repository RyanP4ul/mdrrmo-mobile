import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/api_client.dart';

abstract class ReverbSocket {
  Future<void> get ready;
  Stream<dynamic> get messages;
  void send(String value);
  Future<void> close();
}

class ChannelReverbSocket implements ReverbSocket {
  ChannelReverbSocket(Uri uri) : _channel = WebSocketChannel.connect(uri);
  final WebSocketChannel _channel;
  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<dynamic> get messages => _channel.stream;
  @override
  void send(String value) => _channel.sink.add(value);
  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}

/// Reverb's Pusher protocol over web_socket_channel; bearer auth stays on HTTPS.
class RealtimeConnectionIssue implements Exception {
  const RealtimeConnectionIssue(this.message);
  final String message;
}

class DriverRealtime extends ChangeNotifier with WidgetsBindingObserver {
  DriverRealtime({
    Dio? client,
    ReverbSocket Function(Uri)? open,
    this.onAssignmentChanged,
  }) : _api = client ?? dio,
       _open = open ?? ChannelReverbSocket.new {
    WidgetsBinding.instance.addObserver(this);
  }
  final Dio _api;
  final ReverbSocket Function(Uri) _open;
  final Future<void> Function()? onAssignmentChanged;
  final Map<int, Map<String, dynamic>> _fleet = {};
  final Map<int, DateTime> _versions = {};
  final _reportEvents = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get reportEvents => _reportEvents.stream;
  ReverbSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry, _heartbeat, _handshake;
  CancelToken? _requests;
  bool _running = false,
      _connecting = false,
      _disposed = false,
      _fetching = false;
  int _generation = 0, _attempt = 0;
  DateTime _lastReceived = DateTime.now();
  String? _channel;
  String _stage = 'configuration';
  String? serverAddress;
  String? lastError;
  bool connected = false;
  String status = 'Connecting to live updates';
  List<Map<String, dynamic>> get positions =>
      _fleet.values.toList(growable: false);

  Future<void> start() async {
    if (_disposed) return;
    _running = true;
    _retry?.cancel();
    await _connect();
  }

  Future<void> reconnect() async {
    stop();
    await start();
  }

  Future<void> _connect() async {
    if (!_running || _connecting || _disposed || connected || _socket != null) {
      return;
    }
    _connecting = true;
    final generation = ++_generation;
    _requests = CancelToken();
    status = 'Connecting to live updates';
    _stage = 'configuration';
    _notify();
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/driver-responder/realtime',
        cancelToken: _requests,
      );
      if (!_current(generation)) return;
      final config = response.data!;
      if (config['enabled'] != true) {
        throw const RealtimeConnectionIssue(
          'Live updates are disabled or unconfigured on the server.',
        );
      }
      final key = config['key'],
          host = config['host'],
          port = config['port'],
          channel = config['channel'];
      if (key is! String ||
          key.isEmpty ||
          host is! String ||
          host.isEmpty ||
          port is! int ||
          port < 1 ||
          port > 65535 ||
          channel is! String ||
          !RegExp(r'^private-drivers\.\d+$').hasMatch(channel)) {
        throw const RealtimeConnectionIssue(
          'The server returned invalid live-update settings.',
        );
      }
      _channel = channel;
      final configuredUrl = dotenv.isInitialized
          ? dotenv.get('REVERB_URL', fallback: '').trim()
          : '';
      Uri? reverbUrl;
      if (configuredUrl.isNotEmpty) {
        reverbUrl = Uri.tryParse(configuredUrl);
        if (reverbUrl == null ||
            reverbUrl.host.isEmpty ||
            !{'http', 'https'}.contains(reverbUrl.scheme)) {
          throw const RealtimeConnectionIssue(
            'REVERB_URL must be a valid HTTP or HTTPS URL.',
          );
        }
      }
      final socketHost = reverbUrl?.host ?? host;
      final socketPort = reverbUrl?.hasPort == true
          ? reverbUrl!.port
          : reverbUrl?.scheme == 'https'
          ? 443
          : reverbUrl?.scheme == 'http'
          ? 80
          : port;
      serverAddress = '$socketHost:$socketPort';
      _stage = 'socket';
      final socket = _open(
        Uri(
          scheme: reverbUrl?.scheme == 'https' || config['secure'] == true
              ? 'wss'
              : 'ws',
          host: socketHost,
          port: socketPort,
          path: '/app/$key',
          queryParameters: {
            'protocol': '7',
            'client': 'mdrrmo-flutter',
            'version': '1.0',
            'flash': 'false',
          },
        ),
      );
      _socket = socket;
      await socket.ready.timeout(const Duration(seconds: 10));
      if (!_current(generation)) {
        await socket.close();
        return;
      }
      _lastReceived = DateTime.now();
      _subscription = socket.messages.listen(
        (frame) {
          unawaited(
            _receive(
              frame,
              generation,
            ).catchError((Object error) => _failed(generation, error: error)),
          );
        },
        onDone: () =>
            _failed(generation, message: 'Reverb closed the connection.'),
        onError: (Object error) => _failed(generation, error: error),
      );
      _handshake = Timer(
        const Duration(seconds: 15),
        () => _failed(
          generation,
          message: _stage == 'authorization'
              ? 'Private-channel authorization timed out.'
              : 'Reverb did not confirm the private subscription.',
        ),
      );
      _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
        if (!_current(generation)) return;
        if (DateTime.now().difference(_lastReceived) >
            const Duration(seconds: 90)) {
          _failed(
            generation,
            message: 'Reverb stopped responding to heartbeat checks.',
          );
          return;
        }
        _send('pusher:ping', {});
      });
    } catch (error) {
      _failed(generation, error: error);
    } finally {
      if (generation == _generation) _connecting = false;
    }
  }

  bool _current(int generation) =>
      !_disposed && _running && generation == _generation;
  Map<String, dynamic> _map(Object? value) {
    if (value is String) value = jsonDecode(value);
    if (value is! Map) throw const FormatException('Invalid Reverb frame.');
    return Map<String, dynamic>.from(value);
  }

  Future<void> _receive(Object? raw, int generation) async {
    if (!_current(generation)) return;
    final frame = _map(raw);
    _lastReceived = DateTime.now();
    final event = frame['event'];
    if (event == 'pusher:ping') {
      _send('pusher:pong', {});
      return;
    }
    if (event == 'pusher:pong') return;
    if (event == 'pusher:error') {
      final data = _map(frame['data']);
      final code = data['code'];
      _failed(
        generation,
        message: code is int
            ? 'Reverb rejected the connection (code $code).'
            : 'Reverb rejected the connection.',
      );
      return;
    }
    if (event == 'pusher:connection_established') {
      final id = _map(frame['data'])['socket_id'];
      if (id is! String || !RegExp(r'^\d+\.\d+$').hasMatch(id)) {
        throw const FormatException('Invalid socket ID.');
      }
      _stage = 'authorization';
      final auth = await _api.post<Map<String, dynamic>>(
        '/driver-responder/broadcasting/auth',
        data: {'socket_id': id, 'channel_name': _channel},
        cancelToken: _requests,
      );
      if (!_current(generation)) return;
      final signature = auth.data?['auth'];
      if (signature is! String || signature.isEmpty) {
        throw const RealtimeConnectionIssue(
          'The server returned no private-channel authorization.',
        );
      }
      _stage = 'subscription';
      _send('pusher:subscribe', {'channel': _channel, 'auth': signature});
      return;
    }
    if (frame['channel'] != _channel) return;
    if (event == 'pusher_internal:subscription_succeeded') {
      _handshake?.cancel();
      connected = true;
      lastError = null;
      _stage = 'live';
      status = 'Live updates connected';
      _attempt = 0;
      _notify();
      await refreshFleet();
      if (_current(generation)) await onAssignmentChanged?.call();
      return;
    }
    if (event == 'driver.moved') {
      final value = _position(_map(frame['data']));
      if (value == null) return;
      final id = value['id'] as int;
      final time = DateTime.tryParse('${value['sentAt']}');
      if (time == null ||
          (_versions[id] != null && time.isBefore(_versions[id]!))) {
        return;
      }
      _versions[id] = time;
      _fleet[id] = value;
      _notify();
    } else if (event == 'report.updated') {
      final data = _map(frame['data']);
      if (data.isNotEmpty && !_disposed) _reportEvents.add(data);
      await onAssignmentChanged?.call();
    } else if (event == 'team.role.updated') {
      await onAssignmentChanged?.call();
    }
  }

  Map<String, dynamic>? _position(Map<String, dynamic> data) {
    final lat = data['lat'], lng = data['lng'];
    if (data['id'] is! int ||
        lat is! num ||
        lng is! num ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat.abs() > 90 ||
        lng.abs() > 180) {
      return null;
    }
    return data;
  }

  Future<void> refreshFleet() async {
    if (_disposed || _fetching || !_running) return;
    _fetching = true;
    final generation = _generation;
    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/driver-responder/locations',
        cancelToken: _requests,
      );
      if (!_current(generation)) return;
      final page = response.data!;
      final at = DateTime.parse(page['snapshotAt'] as String);
      final next = <int, Map<String, dynamic>>{};
      for (final item in page['data'] as List) {
        final value = _position(_map(item));
        if (value != null) next[value['id'] as int] = value;
      }
      for (final entry in _fleet.entries) {
        if (_versions[entry.key]?.isAfter(at) == true) {
          next[entry.key] = entry.value;
        }
      }
      _fleet
        ..clear()
        ..addAll(next);
      _notify();
    } catch (_) {
      /* Socket events continue; foreground refresh can retry the snapshot. */
    } finally {
      _fetching = false;
    }
  }

  void _send(String event, Map<String, dynamic> data) {
    try {
      _socket?.send(jsonEncode({'event': event, 'data': data}));
    } catch (error) {
      _failed(_generation, error: error);
    }
  }

  String _failureMessage(Object? error) {
    if (error is RealtimeConnectionIssue) return error.message;
    if (error is DioException) {
      final code = error.response?.statusCode;
      if (_stage == 'authorization') {
        return switch (code) {
          401 => 'Your session expired. Sign in again.',
          403 => 'Laravel denied the private channel (HTTP 403). Sign in again or check your account access.',
          404 => 'The private-channel authorization endpoint was not found (HTTP 404).',
          429 =>
            'Too many authorization attempts. Wait a moment and reconnect.',
          _ =>
            code == null
                ? 'Could not reach Laravel for private-channel authorization.'
                : 'Private-channel authorization failed (HTTP $code).',
        };
      }
      return code == null
          ? 'Could not reach Laravel to load live-update settings.'
          : 'Could not load live-update settings (HTTP $code).';
    }
    if (_stage == 'socket') {
      return 'Cannot connect to Reverb at ${serverAddress ?? 'the configured host'}. Check Wi-Fi, port access and the Reverb server.';
    }
    if (error is FormatException || error is TypeError) {
      return 'The server returned an invalid live-update response.';
    }
    return _stage == 'authorization'
        ? 'Private-channel authorization failed.'
        : 'The Reverb connection was interrupted.';
  }

  void _failed(int generation, {Object? error, String? message}) {
    if (!_current(generation)) return;
    ++_generation;
    _connecting = false;
    connected = false;
    lastError = message ?? _failureMessage(error);
    status = 'Live updates disconnected. $lastError Reconnecting...';
    _cleanup();
    _notify();
    final seconds = (1 << _attempt.clamp(0, 5)).clamp(1, 30);
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), () => unawaited(_connect()));
  }

  void _cleanup() {
    _handshake?.cancel();
    _heartbeat?.cancel();
    _requests?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close().catchError((Object _) {}));
  }

  void stop() {
    _running = false;
    ++_generation;
    connected = false;
    _connecting = false;
    _retry?.cancel();
    _cleanup();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      stop();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    unawaited(_reportEvents.close());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
