import 'dart:async';

import 'package:flutter/widgets.dart';

import 'auth_service.dart';
import 'driver_tracking.dart';

/// Sends the signed-in driver/responder coordinates once OS access is ready.
class AutomaticDriverTracking with WidgetsBindingObserver {
  AutomaticDriverTracking(this.tracking, {bool? background})
    : background = background ?? NativeGpsSource.supportsBackground {
    tracking.addListener(_trackingChanged);
    AuthService.sessionExpired.addListener(_sessionExpired);
    WidgetsBinding.instance.addObserver(this);
  }

  final DriverTracking tracking;
  final bool background;
  bool _enabled = false;
  bool _access = false, _foreground = true, _signedIn = true;
  bool _disposed = false, _running = false, _dirty = false;
  Timer? _retry;
  Future<void>? _stopping;

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _changed();
  }

  void setLocationAccess(bool ready) {
    if (_access == ready) return;
    _access = ready;
    _changed();
  }

  bool get _eligible =>
      !_disposed &&
      _signedIn &&
      _access &&
      (_foreground || background) &&
      _enabled;

  void _changed() {
    _retry?.cancel();
    _retry = null;
    // Invalidate a pending permission/API request before it can open a stale
    // session. The reconciliation loop waits for all cleanup before restarting.
    if (_running && tracking.busy && !_eligible) {
      _stopping ??= tracking.stop().whenComplete(() => _stopping = null);
    }
    _dirty = true;
    unawaited(_reconcile());
  }

  Future<void> _reconcile() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      while (_dirty && !_disposed) {
        _dirty = false;
        await _stopping;
        if (tracking.active && !_eligible) {
          await tracking.stop();
        }
        if (!_eligible || tracking.active || _retry != null) continue;
        await tracking.start(inBackground: background);
        await _stopping;
        if (!tracking.active && _eligible && !_dirty) _scheduleRetry();
      }
    } finally {
      _running = false;
    }
  }

  void _trackingChanged() {
    if (!_running && !tracking.active && !tracking.busy && _eligible) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (_retry != null || _disposed) return;
    _retry = Timer(const Duration(seconds: 30), () {
      _retry = null;
      _dirty = true;
      unawaited(_reconcile());
    });
  }

  void _sessionExpired() {
    _signedIn = false;
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      // The map gate rechecks OS access before a foreground session restarts.
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      if (!background) {
        _access = false;
        _changed();
      }
    }
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    tracking.removeListener(_trackingChanged);
    AuthService.sessionExpired.removeListener(_sessionExpired);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(tracking.stop());
  }
}
