import 'package:material_ui/material_ui.dart';

import '../../data/resident_models.dart';
import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../ui/page_loader.dart';
import '../record_details_screen.dart';
import 'resident_widgets.dart';

class ResidentHistoryScreen extends StatefulWidget {
  const ResidentHistoryScreen({super.key});
  @override
  State<ResidentHistoryScreen> createState() => _ResidentHistoryScreenState();
}

class _ResidentHistoryScreenState extends State<ResidentHistoryScreen> {
  bool _openOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
    final reports = state.reports
        .where(
          (report) =>
              !_openOnly ||
              report.status == IncidentStatus.active ||
              report.status == IncidentStatus.responding,
        )
        .toList();

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
                const ResidentHeading('My reports'),
                Segmented<bool>(
                  value: _openOnly,
                  onChanged: (value) => setState(() => _openOnly = value),
                  options: const [
                    SegmentOption(false, 'All reports'),
                    SegmentOption(true, 'In progress'),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (reports.isEmpty)
                  ResidentEmptyState(
                    icon: AppIcons.form,
                    title: _openOnly
                        ? 'No reports in progress'
                        : 'No reports yet',
                    message: _openOnly
                        ? 'Choose All reports to review previous incidents.'
                        : 'Use Report an incident on Home to contact MDRRMO.',
                  )
                else
                  AppSectionGroup(
                    children: [
                      for (final report in reports)
                        ResidentReportCard(
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
                    ],
                  ),
                PageLoader(
                  hasMore: state.hasMore('reports'),
                  loading:
                      state.loadingPage == 'reports' ||
                      state.isLoading ||
                      state.isSaving,
                  error: state.pageErrors['reports'],
                  onLoad: () => state.loadMore('reports'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
