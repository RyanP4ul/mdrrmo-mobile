import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../state/driver_responder_state.dart';
import '../../ui/kit.dart';
import '../../ui/page_loader.dart';
import 'dispatch_details_screen.dart';
import 'responder_widgets.dart';

enum _Filter { all, completed, invalid }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final state = ResponderScope.of(context);
    final palette = MdrrmoColors.of(context);
    final items = state.history
        .where(
          (dispatch) => switch (_filter) {
            _Filter.all => true,
            _Filter.completed => dispatch.status == DispatchStatus.completed,
            _Filter.invalid => dispatch.status == DispatchStatus.invalid,
          },
        )
        .toList();
    final groups = <String, List<Dispatch>>{};
    for (final dispatch in items) {
      groups.putIfAbsent(fmtDay(dispatch.time), () => []).add(dispatch);
    }

    return RefreshIndicator(
      onRefresh: state.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ResponderHeading(
                  'Dispatch history',
                  subtitle: 'Your past responses, all in one place.',
                ),
                Segmented<_Filter>(
                  value: _filter,
                  onChanged: (value) => setState(() => _filter = value),
                  options: const [
                    SegmentOption(_Filter.all, 'All'),
                    SegmentOption(_Filter.completed, 'Completed'),
                    SegmentOption(_Filter.invalid, 'Invalid'),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (state.isLoading && !state.hasLoaded)
                  const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.md),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (state.loadError != null) ...[
                  AppBanner(
                    tone: AppBannerTone.warning,
                    icon: AppIcons.wifiOff,
                    title: 'Could not refresh your history',
                    message: 'Pull down or try again.',
                    action: TextButton.icon(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: state.isLoading ? null : state.load,
                      icon: const Icon(AppIcons.refresh, size: 17),
                      label: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (items.isEmpty &&
                    !state.isLoading &&
                    state.loadError == null)
                  ResponderEmptyState(
                    icon: AppIcons.history,
                    title: _filter == _Filter.all
                        ? 'Your history starts here'
                        : 'No ${_filter == _Filter.completed ? 'completed' : 'invalid'} dispatches',
                    message: _filter == _Filter.all
                        ? 'Completed responses will appear here. Open a record to review its trip and patient-care details.'
                        : 'Choose All to view your other dispatch records.',
                  ),
                for (final group in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      2,
                      AppSpacing.sm,
                      2,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      group.key,
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  for (final dispatch in group.value)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _DispatchCard(dispatch: dispatch),
                    ),
                ],
                PageLoader(
                  hasMore: state.historyNext != null,
                  loading:
                      state.isLoading || state.isSaving || state.loadingHistory,
                  error: state.historyError,
                  onLoad: state.loadMoreHistory,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DispatchCard extends StatelessWidget {
  const _DispatchCard({required this.dispatch});
  final Dispatch dispatch;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final done = dispatch.status == DispatchStatus.completed;
    return ResponderPanel(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: () {
        final state = ResponderScope.of(context);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResponderScope(
              state: state,
              child: DispatchDetailsScreen(dispatch: dispatch),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              Text(
                dispatch.id,
                style: MdrrmoTypography.tabular(
                  MdrrmoTypography.labelSm.copyWith(color: palette.textMuted),
                ),
              ),
              AppStatusBadge(
                done
                    ? 'Completed'
                    : dispatch.status == DispatchStatus.invalid
                    ? 'Invalid'
                    : 'Unknown status',
                color: done ? palette.success : palette.warning,
                icon: done ? AppIcons.checkCircle : AppIcons.infoCircle,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            dispatch.emergencyType,
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.pin, size: 17, color: palette.brand),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  dispatch.pickup,
                  style: MdrrmoTypography.bodyMd.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(AppIcons.clock, size: 14, color: palette.textMuted),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${fmtTime(dispatch.time)} · ${dispatch.driver}',
                  style: MdrrmoTypography.labelSm.copyWith(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(AppIcons.chevron, size: 18, color: palette.textMuted),
            ],
          ),
        ],
      ),
    );
  }
}
