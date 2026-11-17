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

    final completedCount = state.history
        .where((d) => d.status == DispatchStatus.completed)
        .length;
    final flaggedCount = state.history
        .where((d) => d.status == DispatchStatus.invalid)
        .length;
    final formSavedCount = state.history.where((d) => d.hasDriverForm).length;

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
                ResponderHeading(
                  'Dispatch history',
                  subtitle: 'Past emergency responses and trip logs',
                  trailing: state.history.isEmpty
                      ? null
                      : AppStatusBadge(
                          '${items.length} ${items.length == 1 ? 'record' : 'records'}',
                          color: palette.brand,
                        ),
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
                if (state.history.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  _HistorySummaryStrip(
                    completedCount: completedCount,
                    flaggedCount: flaggedCount,
                    formSavedCount: formSavedCount,
                  ),
                ],
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
                      AppSpacing.xs,
                      2,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.key,
                            style: MdrrmoTypography.labelSm.copyWith(
                              color: palette.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: palette.surfaceSubtle,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(color: palette.border),
                          ),
                          child: Text(
                            '${group.value.length}',
                            style: MdrrmoTypography.tabular(
                              MdrrmoTypography.labelSm.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppSectionGroup(
                    children: [
                      for (final dispatch in group.value)
                        _DispatchCard(dispatch: dispatch),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
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

class _HistorySummaryStrip extends StatelessWidget {
  const _HistorySummaryStrip({
    required this.completedCount,
    required this.flaggedCount,
    required this.formSavedCount,
  });

  final int completedCount;
  final int flaggedCount;
  final int formSavedCount;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      tint: palette.surface,
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: 'Done',
              value: '$completedCount',
              color: palette.success,
            ),
          ),
          Container(width: 1, height: 28, color: palette.border),
          Expanded(
            child: _SummaryMetric(
              label: 'Forms saved',
              value: '$formSavedCount',
              color: palette.brand,
            ),
          ),
          Container(width: 1, height: 28, color: palette.border),
          Expanded(
            child: _SummaryMetric(
              label: 'Flagged',
              value: '$flaggedCount',
              color: flaggedCount > 0 ? palette.warning : palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: MdrrmoTypography.tabular(
            MdrrmoTypography.titleMd.copyWith(color: color),
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: MdrrmoTypography.labelSm.copyWith(
            color: palette.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    final invalid = dispatch.status == DispatchStatus.invalid;
    final statusColor = done
        ? palette.success
        : invalid
        ? palette.warning
        : palette.textMuted;
    final hasDestination =
        dispatch.destination.trim().isNotEmpty &&
        dispatch.destination != 'Destination not recorded';

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              margin: const EdgeInsets.only(top: 2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statusColor.withValues(
                  alpha: palette.isDark ? 0.18 : 0.10,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                done ? AppIcons.checkCircle : AppIcons.infoCircle,
                size: 19,
                color: statusColor,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          dispatch.emergencyType,
                          style: MdrrmoTypography.titleMd.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: palette.surfaceSubtle,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(color: palette.border),
                        ),
                        child: Text(
                          dispatch.id,
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.labelSm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          AppIcons.pin,
                          size: 13,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          dispatch.pickup,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MdrrmoTypography.bodySm.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasDestination) ...[
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            AppIcons.navigation,
                            size: 13,
                            color: palette.brand,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            dispatch.destination,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MdrrmoTypography.bodySm.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      AppStatusBadge(
                        done
                            ? 'Completed'
                            : invalid
                            ? 'Invalid'
                            : 'Unknown status',
                        color: statusColor,
                        icon: done ? AppIcons.checkCircle : AppIcons.infoCircle,
                      ),
                      AppStatusBadge(
                        priorityLabel(dispatch.priority),
                        color: Semantic.priority(dispatch.priority),
                      ),
                      if (dispatch.hasDriverForm)
                        AppStatusBadge(
                          'Form saved',
                          color: palette.brand,
                          icon: AppIcons.fileCheck,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${fmtTime(dispatch.time)} · ${dispatch.driver}',
                        style: MdrrmoTypography.labelSm.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (dispatch.durationMin != null)
                        Text(
                          '· ${dispatch.durationMin} min',
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.labelSm.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                      if (dispatch.distanceKm != null)
                        Text(
                          '· ${dispatch.distanceKm!.toStringAsFixed(1)} km',
                          style: MdrrmoTypography.tabular(
                            MdrrmoTypography.labelSm.copyWith(
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Icon(AppIcons.chevron, size: 18, color: palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
