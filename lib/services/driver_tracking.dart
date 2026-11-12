import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:location/location.dart';

import '../data/api_client.dart';
import '../data/api_errors.dart';
import 'auth_service.dart';

class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.time,
    this.speed,
    this.heading,
  });
  final double latitude, longitude, accuracy;
  final DateTime time;
  final double? speed, heading;
  bool valid(DateTime now) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      accuracy.isFinite &&
      accuracy >= 0 &&
      accuracy <= 200 &&
      time.isAfter(now.subtract(const Duration(minutes: 2))) &&
      !time.isAfter(now.add(const Duration(seconds: 30)));
}

abstract class GpsSource {
  Future<void> start(bool background);
  Stream<GpsFix> get fixes;
  Future<void> stop();
}

class NativeGpsSource implements GpsSource {
  final Location _location = Location();
  static bool get supportsBackground =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  @override
  Future<void> start(bool background) async {
    if (!await _location.serviceEnabled() &&
        !await _location.requestService()) {
      throw StateError('Enable location services, then try again.');
    }
    var permission = await _location.hasPermission();
    if (permission == PermissionStatus.denied) {
      permission = await _location.requestPermission();
    }
    if (![
      PermissionStatus.granted,
      PermissionStatus.grantedLimited,
    ].contains(permission)) {
      throw StateError(
        'Location permission is required. Allow it in your device settings, then try again.',
      );
    }
    await _location.changeSettings(
      accuracy: LocationAccuracy.high,
      interval: 10000,
      distanceFilter: 0,
      pausesLocationUpdatesAutomatically: !background,
      backgroundInterval: 10000,
    );
    if (background) {
      if (!supportsBackground) {
        throw StateError(
          'Background location sharing is supported on Android and iOS.',
        );
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _location.changeNotificationOptions(
          title: 'MDRRMO responder location',
          subtitle: 'Sending your coordinates to the dispatcher',
          description:
              'Coordinates are sent automatically during your active dispatch.',
          onTapBringToFront: true,
        );
      }
      if (!await _location.enableBackgroundMode(
        enable: true,
        requireBackgroundPermission: false,
      )) {
        throw StateError(
          'Background sharing was not enabled. Check device permissions.',
        );
      }
    }
  }

  @override
  Stream<GpsFix> get fixes => _location.onLocationChanged
      .where((p) => p.accuracy != null && p.time != null)
      .map(
        (p) => GpsFix(
          latitude: p.latitude,
          longitude: p.longitude,
          accuracy: p.accuracy!,
          time: DateTime.fromMillisecondsSinceEpoch(
            p.time!.round(),
            isUtc: true,
          ),
          speed: p.speed != null && p.speed! >= 0 ? p.speed : null,
          heading: p.heading != null && p.heading! >= 0 ? p.heading : null,
        ),
      );
  @override
  Future<void> stop() async {
    if (supportsBackground) await _location.enableBackgroundMode(enable: false);
  }
}

class DriverTracking extends ChangeNotifier with WidgetsBindingObserver {
  DriverTracking({GpsSource? source, Dio? client})
    : _source = source ?? NativeGpsSource(),
      _client = client ?? dio {
    WidgetsBinding.instance.addObserver(this);
    AuthService.sessionExpired.addListener(_expired);
  }
  static const _sessionPath = '/driver-responder/location/sessions';
  final GpsSource _source;
  final Dio _client;
  StreamSubscription<GpsFix>? _subscription;
  Timer? _timer;
  CancelToken? _cancel;
  String? _session;
  GpsFix? _latest;
  bool background = false, busy = false, _disposed = false;
  Future<void>? _sendingWork;
  int _sequence = 0;
  int _generation = 0;
  DateTime? lastSent;
  String? error;
  bool get active => _session != null;
  Future<void> start({required bool inBackground}) async {
    if (busy || active) return;
    final generation = ++_generation;
    busy = true;
    error = null;
    _notify();
    try {
      await _source.start(inBackground);
      if (_disposed || generation != _generation) {
        await _safeStopSource();
        return;
      }
      _cancel = CancelToken();
      final response = await _client.post<Map<String, dynamic>>(
        _sessionPath,
        data: {
          'background': inBackground,
          'notice_version': 'driver-2026-11-04',
        },
        cancelToken: _cancel,
      );
      final session = response.data?['session_id'];
      if (session is! String || session.isEmpty) {
        throw const FormatException('Missing tracking session.');
      }
      if (_disposed || generation != _generation) {
        await _safeStopSource();
        try {
          await _client.delete('$_sessionPath/$session');
        } catch (_) {}
        return;
      }
      _session = session;
      background = inBackground;
      _sequence = 0;
      lastSent = null;
      _latest = null;
      _subscription = _source.fixes.listen(
        (fix) {
          _latest = fix;
          if (lastSent == null) unawaited(sendLatest());
        },
        onError: (Object e) {
          error = apiErrorMessage(e);
          _notify();
          unawaited(stop());
        },
      );
      _timer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => unawaited(sendLatest()),
      );
    } catch (e) {
      if (!_disposed && generation == _generation) error = apiErrorMessage(e);
      await _safeStopSource();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> sendLatest() {
    final pending = _sendingWork;
    if (pending != null) return pending;
    final work = _sendLatest();
    _sendingWork = work;
    return work.whenComplete(() => _sendingWork = null);
  }

  Future<void> _sendLatest() async {
    final fix = _latest, session = _session;
    if (_disposed || fix == null || session == null) return;
    if (!fix.valid(DateTime.now().toUtc())) {
      error = 'Waiting for a recent, accurate GPS reading.';
      _notify();
      return;
    }
    try {
      await _client.post(
        '$_sessionPath/$session/ping',
        data: {
          'sequence': ++_sequence,
          'lat': fix.latitude,
          'lng': fix.longitude,
          'accuracy': fix.accuracy,
          'observed_at': fix.time.toUtc().toIso8601String(),
          if (fix.speed != null) 'speed': fix.speed,
          if (fix.heading != null) 'heading': fix.heading,
        },
        cancelToken: _cancel,
      );
      if (_session == session && !_disposed) {
        lastSent = DateTime.now();
        error = null;
        _notify();
      }
    } catch (e) {
      if (_disposed || _session != session) return;
      if (!_disposed) {
        error = apiErrorMessage(e);
        _notify();
      }
      if (e is DioException &&
          [401, 403, 404, 409].contains(e.response?.statusCode)) {
        await stop();
      }
    }
  }

  Future<void> _safeStopSource() async {
    try {
      await _source.stop();
    } catch (error) {
      if (!_disposed) this.error = apiErrorMessage(error);
    }
  }

  Future<void> stop() async {
    _generation++;
    final session = _session;
    _session = null;
    _timer?.cancel();
    _timer = null;
    _cancel?.cancel();
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _source.stop();
    } catch (e) {
      if (!_disposed) error = apiErrorMessage(e);
    }
    if (session != null) {
      try {
        await _client.delete('$_sessionPath/$session');
      } catch (_) {
        /* A disconnected server expires the sharing lease. */
      }
    }
    _notify();
  }

  void _expired() {
    unawaited(stop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (active &&
        !background &&
        [
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.detached,
        ].contains(state)) {
      unawaited(stop());
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    AuthService.sessionExpired.removeListener(_expired);
    unawaited(stop());
    super.dispose();
  }
}
