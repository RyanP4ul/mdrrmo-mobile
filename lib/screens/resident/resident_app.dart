import 'package:material_ui/material_ui.dart';

import '../../data/resident_models.dart';
import 'resident_shell.dart';
import '../../state/resident_state.dart';
import '../../ui/data_refresh.dart';

/// Entry point for the resident experience. Owns its own state and is fully
/// separate from the driver / responder module.
class ResidentApp extends StatefulWidget {
  const ResidentApp({super.key, required this.profile});

  final ResidentProfile profile;

  @override
  State<ResidentApp> createState() => _ResidentAppState();
}

class _ResidentAppState extends State<ResidentApp> {
  late final _state = ResidentState(widget.profile);

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DataRefresh(
    onRefresh: _state.load,
    child: ResidentScope(state: _state, child: const ResidentShell()),
  );
}
