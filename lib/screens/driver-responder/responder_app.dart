import 'package:material_ui/material_ui.dart';

import '../../screens/driver-responder/shell.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/data_refresh.dart';
import '../../services/driver_tracking.dart';
import '../../services/automatic_driver_tracking.dart';
import '../../services/driver_realtime.dart';

import 'dart:async';

/// Entry point for the driver / responder experience. Owns its own state so it
/// never shares data with the resident module.
class ResponderApp extends StatefulWidget {
  const ResponderApp({super.key});

  @override
  State<ResponderApp> createState() => _ResponderAppState();
}

class _ResponderAppState extends State<ResponderApp> {
  final _state = ResponderState();
  final _tracking = DriverTracking();
  late final _automatic = AutomaticDriverTracking(_tracking);
  late final _live = DriverRealtime(onAssignmentChanged: _state.load);
  @override
  void initState() {
    super.initState();
    _state.addListener(_stateChanged);
    _stateChanged();
    unawaited(_live.start());
  }

  void _stateChanged() {
    _automatic.setEnabled(_state.hasLoaded);
  }

  @override
  void dispose() {
    _state.removeListener(_stateChanged);
    _automatic.dispose();
    _tracking.dispose();
    _live.dispose();
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataRefresh(
    onRefresh: () async {
      await Future.wait([_state.load(), _live.refreshFleet()]);
    },
    child: ResponderScope(
      state: _state,
      child: Shell(
        tracking: _tracking,
        realtime: _live,
        onLocationAccessChanged: _automatic.setLocationAccess,
      ),
    ),
  );
}
