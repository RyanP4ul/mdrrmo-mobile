import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/internet_connection.dart';

/// Refreshes server data while the module is foregrounded and when it resumes.
class DataRefresh extends StatefulWidget {
  const DataRefresh({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<DataRefresh> createState() => _DataRefreshState();
}

class _DataRefreshState extends State<DataRefresh> with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InternetConnection.instance.addListener(_connectionChanged);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_foreground && InternetConnection.instance.online) {
        unawaited(widget.onRefresh());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && InternetConnection.instance.online) {
      unawaited(widget.onRefresh());
    }
  }

  void _connectionChanged() {
    if (_foreground && InternetConnection.instance.online) {
      unawaited(widget.onRefresh());
    }
  }

  @override
  void dispose() {
    InternetConnection.instance.removeListener(_connectionChanged);
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
