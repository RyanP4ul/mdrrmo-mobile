import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dispatcher_phone.dart';

/// Validates API reachability, rather than Wi-Fi alone. An unrelated external
/// connectivity service must not disable a reachable MDRRMO server.
class InternetConnection extends ChangeNotifier with WidgetsBindingObserver {
  InternetConnection({
    this._probe,
    this._clientFactory,
    bool initiallyOnline = false,
  }) : _online = initiallyOnline;

  static final instance = InternetConnection();
  final Future<bool> Function()? _probe;
  final Dio Function()? _clientFactory;
  DateTime? _lastContactRefresh;
  bool _online;
  bool get online => _online;
  bool _hasChecked = false;
  bool get hasChecked => _hasChecked;
  Timer? _timer;
  Future<bool>? _pending;
  bool _disposed = false;

  Dio _createClient() =>
      _clientFactory?.call() ??
      Dio(
        BaseOptions(
          baseUrl: dotenv.get('API_URL', fallback: 'http://10.0.2.2:8000/api'),
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
          followRedirects: false,
          headers: {'Accept': 'application/json'},
        ),
      );

  Future<bool> _probeServer() async {
    final client = _createClient();
    try {
      final response = await client.get(
        '/connectivity',
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
      );
      final reachable =
          response.statusCode == 200 &&
          response.data is Map &&
          response.data['service'] == 'mdrrmo';
      if (reachable) {
        unawaited(_refreshContact());
      }
      return reachable;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _refreshContact() async {
    final now = DateTime.now();
    if (_disposed ||
        (_lastContactRefresh != null &&
            now.difference(_lastContactRefresh!) <
                const Duration(minutes: 1))) {
      return;
    }
    _lastContactRefresh = now;
    final client = _createClient();
    try {
      // Phone lookup and storage cannot hold up the reachability result.
      final response = await client.get(
        '/connectivity',
        queryParameters: {
          'include_contact': 1,
          't': now.millisecondsSinceEpoch,
        },
      );
      if (!_disposed &&
          response.statusCode == 200 &&
          response.data is Map &&
          response.data['service'] == 'mdrrmo') {
        final phone = response.data['dispatcher_phone'];
        if (phone is String) await DispatcherPhone.update(phone);
      }
    } catch (_) {
      // Keep the previously cached or bundled number if lookup fails.
    } finally {
      client.close(force: true);
    }
  }

  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(check()),
    );
  }

  Future<bool> check() =>
      _pending ??= _check().whenComplete(() => _pending = null);

  Future<bool> _check() async {
    var result = false;
    // Confirm failures once before disabling services or releasing active audio.
    for (var attempt = 0; attempt < 2 && !_disposed; attempt++) {
      try {
        result = await (_probe?.call() ?? _probeServer()).timeout(
          const Duration(seconds: 16),
        );
      } catch (_) {
        result = false;
      }
      if (result) break;
    }
    if (!_disposed && (!_hasChecked || result != _online)) {
      _hasChecked = true;
      _online = result;
      notifyListeners();
    }
    return !_disposed && result;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
