import 'package:material_ui/material_ui.dart';

import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../record_details_screen.dart';
import '../sos_screen.dart';
import 'resident_widgets.dart';

class ResidentHomeScreen extends StatelessWidget {
  const ResidentHomeScreen({
    super.key,
    required this.onOpenReport,
    required this.onOpenReports,
    required this.onOpenServices,
    this.onSos,
  });

  final VoidCallback onOpenReport, onOpenReports, onOpenServices;
  final VoidCallback? onSos;

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
    final palette = MdrrmoColors.of(context);
    final approved = state.profile.canSubmit;
    final firstName = state.profile.firstName.trim();

    return RefreshIndicator(
      onRefresh: state.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ResidentHeading(
                  firstName.isEmpty ? 'Hello' : 'Hello, $firstName',
                  subtitle: 'Municipal emergency dispatch & community services',
                ),
                if (!approved) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.info,
                    title: state.profile.registrationStatus == 'declined'
                        ? 'Registration needs attention'
                        : 'Account awaiting approval',
                    message: state.profile.registrationStatus == 'declined'
                        ? 'Contact MDRRMO about your registration.'
                        : 'You can send reports and service requests once MDRRMO approves your account.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Surface(
                  borderColor: palette.danger.withValues(alpha: 0.25),
                  tint: Color.alphaBlend(
                    palette.danger.withValues(
                      alpha: palette.isDark ? 0.08 : 0.03,
                    ),
                    palette.surface,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xl,
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Semantics(
                          label: 'SOS. Call the dispatcher immediately',
                          button: true,
                          child: Container(
                            width: 132,
                            height: 132,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: palette.danger.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: FilledButton(
                              key: const ValueKey('resident-sos-button'),
                              style: FilledButton.styleFrom(
                                shape: const CircleBorder(),
                                padding: EdgeInsets.zero,
                                backgroundColor: palette.danger,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: palette.danger
                                    .withValues(alpha: 0.35),
                                disabledForegroundColor: Colors.white,
                                elevation: 0,
                              ),
                              onPressed:
                                  onSos ??
                                  () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          SosScreen(guest: !approved),
                                    ),
                                  ),
                              child: const Text(
                                'SOS',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Emergency help',
                        textAlign: TextAlign.center,
                        style: MdrrmoTypography.titleLg.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Tap SOS to choose an internet call or a regular phone call.',
                        textAlign: TextAlign.center,
                        style: MdrrmoTypography.bodySm.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                ResidentShortcut(
                  icon: AppIcons.pin,
                  title: 'Report an incident',
                  subtitle:
                      'Send incident details and a location pin to MDRRMO',
                  onTap: approved && !state.isSaving ? onOpenReport : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                ResidentShortcut(
                  icon: AppIcons.calendar,
                  title: 'Request a service',
                  subtitle: 'Schedule a non-emergency service with MDRRMO',
                  onTap: onOpenServices,
                ),
                const SizedBox(height: AppSpacing.xl),
                ResidentHeading(
                  'Recent reports',
                  trailing: TextButton(
                    onPressed: onOpenReports,
                    child: const Text('View all'),
                  ),
                ),
                if (state.reports.isEmpty)
                  const ResidentEmptyState(
                    icon: AppIcons.form,
                    title: 'No reports yet',
                    message: 'Your submitted reports and their status updates will appear here.',
                  ),
                for (final report in state.reports.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ResidentReportCard(
                      report: report,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecordDetailsScreen(
                            id: report.id,
                            onChanged: state.load,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
