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

  void _openSos() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SosScreen(guest: true)),
    );
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
                onPressed: _openSos,
                style: TextButton.styleFrom(
                  backgroundColor: palette.dangerTint,
                  foregroundColor: palette.danger,
                  minimumSize: const Size(48, 38),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    side: BorderSide(
                      color: palette.danger.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                icon: const Icon(AppIcons.phoneCall, size: 15),
                label: Text(
                  'SOS',
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: palette.surfaceSubtle,
              border: Border(bottom: BorderSide(color: palette.border)),
            ),
            child: ContentFrame(
              child: Row(
                children: [
                  Icon(
                    AppIcons.info,
                    size: 16,
                    color: palette.brand,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Guest mode — no account needed. Prefer to talk? Tap SOS.',
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              top: false,
              child: ResidentReportScreen(
                guestApi: _api,
                onDone: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
