import 'package:material_ui/material_ui.dart';

import '../data/api/guest_report_api.dart';
import '../ui/kit.dart';
import 'resident/report_screen.dart';
import 'sos_screen.dart';

class GuestReportPage extends StatefulWidget {
  const GuestReportPage({super.key, this.api});
  final GuestReportApi? api;

  @override
  State<GuestReportPage> createState() => _GuestReportPageState();
}

class _GuestReportPageState extends State<GuestReportPage> {
  late final _api = widget.api ?? GuestReportApi();

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return AppScaffold(
      childPad: false,
      header: pushedHeader(
        context,
        'Guest incident report',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Semantics(
              button: true,
              label: 'SOS - Call dispatcher',
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SosScreen(guest: true)),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: palette.danger,
                  minimumSize: const Size(48, 44),
                ),
                icon: const Icon(AppIcons.phoneCall, size: 16),
                label: const Text('SOS'),
              ),
            ),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ResidentReportScreen(
          guestApi: _api,
          onDone: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}
