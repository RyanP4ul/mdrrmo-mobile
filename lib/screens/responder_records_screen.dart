import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

import '../data/api_client.dart';
import '../data/paged_records.dart';
import '../ui/data_refresh.dart';
import '../ui/kit.dart';
import '../ui/notification_widgets.dart';
import '../ui/page_loader.dart';
import '../ui/record_widgets.dart';
import 'driver-responder/responder_widgets.dart';
import 'record_details_screen.dart';

class ResponderRecordsScreen extends StatefulWidget {
  const ResponderRecordsScreen({super.key, this.inbox = false, this.onChanged});
  final bool inbox;
  final Future<void> Function()? onChanged;

  @override
  State<ResponderRecordsScreen> createState() => _ResponderRecordsScreenState();
}

class _ResponderRecordsScreenState extends State<ResponderRecordsScreen> {
  final _cancel = CancelToken();
  List<Map<String, dynamic>> _items = [];
  int? _next, _openingId;
  bool _loading = false,
      _unreadOnly = false,
      _moreError = false,
      _expanded = false,
      _markingAll = false;
  Object? _error;

  String get _path =>
      '/driver-responder/${widget.inbox ? 'notifications' : 'authored-reports'}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted || _loading || (more && _next == null)) return;
    final cursor = more ? _next : null;
    setState(() {
      _loading = true;
      _error = null;
      _moreError = false;
    });
    try {
      final response = await dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: more ? {'before': cursor} : null,
        cancelToken: _cancel,
      );
      final result = RecordPage.fromJson(response.data);
      final page = result.items;
      final next = result.nextBefore;
      if (next != null && (next <= 0 || (cursor != null && next >= cursor))) {
        throw const FormatException('Invalid page cursor.');
      }
      if (!mounted) return;
      setState(() {
        _items = more || _expanded
            ? mergeRecords(page, _items, (item) => item['id'])
            : page;
        if (more || !_expanded) _next = next;
        if (more) _expanded = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _moreError = more;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (_openingId != null) return;
    final id = item['id'] as int;
    final scheduleId = widget.inbox ? item['schedule_id'] as int? : null;
    final recordId = widget.inbox
        ? (scheduleId ?? item['report_id']) as int?
        : id;
    setState(() => _openingId = id);
    try {
      if (widget.inbox && item['read_at'] == null) {
        try {
          await dio.patch(
            '/driver-responder/notifications/$id/read',
            cancelToken: _cancel,
          );
          if (!mounted) return;
          setState(() => item['read_at'] = DateTime.now().toIso8601String());
          await widget.onChanged?.call();
        } catch (error) {
          if (mounted) {
            snack(
              context,
              'Could not mark this update as read. ${apiErrorMessage(error)}',
            );
          }
        }
      }
      if (!mounted) return;
      if (recordId == null) {
        snack(context, 'This update has no linked record.');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordDetailsScreen(
            id: recordId,
            driver: true,
            schedule: scheduleId != null,
            onChanged: widget.onChanged,
          ),
        ),
      );
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  Future<void> _markAllRead() async {
    final unread = _items.where((item) => item['read_at'] == null).toList();
    if (_markingAll || _loading || unread.isEmpty) return;
    setState(() => _markingAll = true);
    try {
      for (final item in unread) {
        final id = item['id'] as int;
        await dio.patch(
          '/driver-responder/notifications/$id/read',
          cancelToken: _cancel,
        );
        if (!mounted) return;
        setState(() => item['read_at'] = DateTime.now().toIso8601String());
      }
      await widget.onChanged?.call();
    } catch (error) {
      if (mounted) {
        snack(
          context,
          'Could not mark updates as read: ${apiErrorMessage(error)}',
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  (IconData, Color) _inboxLook(
    Map<String, dynamic> item,
    MdrrmoColors palette,
  ) {
    final kind = '${item['kind'] ?? ''}'.toLowerCase();
    final schedule =
        item['schedule_id'] != null || kind.startsWith('schedule_');
    if (kind.contains('cancelled') || kind.contains('invalid')) {
      return (AppIcons.infoCircle, palette.danger);
    }
    if (kind.contains('completed') || kind.contains('resolved')) {
      return (AppIcons.checkCircle, palette.success);
    }
    if (schedule) {
      return (AppIcons.calendar, palette.brand);
    }
    if (kind.contains('en_route') ||
        kind.contains('on_the_way') ||
        kind.contains('dispatched')) {
      return (AppIcons.truck, palette.brand);
    }
    return (AppIcons.bell, palette.brand);
  }

  String _inboxTimestamp(dynamic raw) {
    final parsed = DateTime.tryParse('${raw ?? ''}')?.toLocal();
    return parsed == null ? recordTimestamp(raw) : timeAgo(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final visible = _items
        .where(
          (item) => !widget.inbox || !_unreadOnly || item['read_at'] == null,
        )
        .toList();
    final unreadCount = widget.inbox
        ? _items.where((item) => item['read_at'] == null).length
        : 0;
    final groups = <String, List<Map<String, dynamic>>>{};
    if (!widget.inbox) {
      for (final item in visible) {
        final time = DateTime.tryParse('${item['reported_at']}');
        groups
            .putIfAbsent(
              time == null ? 'Earlier updates' : fmtDay(time),
              () => [],
            )
            .add(item);
      }
    }

    return DataRefresh(
      onRefresh: _load,
      child: AppScaffold(
        childPad: false,
        header: pushedHeader(
          context,
          widget.inbox ? 'Responder notifications' : 'Reports I submitted',
        ),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              widget.inbox ? AppSpacing.xxl : AppSpacing.xxxl,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              ContentFrame(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.inbox)
                      NotificationsHeaderSection(
                        title: 'Notifications',
                        subtitle: unreadCount == 0
                            ? null
                            : '$unreadCount unread',
                        unreadOnly: _unreadOnly,
                        unreadCount: unreadCount,
                        onFilterChanged: (value) =>
                            setState(() => _unreadOnly = value),
                        onMarkAllRead: _markingAll || _loading
                            ? null
                            : _markAllRead,
                      )
                    else
                      const ResponderHeading('Your submitted reports'),
                    if (_loading && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.md),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_error != null && !_moreError)
                      RecordMessage(
                        title:
                            'Could not refresh ${widget.inbox ? 'notifications' : 'reports'}',
                        message: apiErrorMessage(_error!),
                        icon: AppIcons.wifiOff,
                        onRetry:
                            _loading ? null : () => _load(more: _moreError),
                      ),
                    if (!_loading && _error == null && visible.isEmpty)
                      ResponderEmptyState(
                        icon: widget.inbox ? AppIcons.bell : AppIcons.form,
                        title: widget.inbox
                            ? (_unreadOnly
                                  ? 'No unread updates here'
                                  : 'You are all caught up')
                            : 'No submitted reports yet',
                        message: _unreadOnly && _next != null
                            ? 'Load more updates below or choose All updates.'
                            : widget.inbox
                            ? 'New assignments and service updates will appear here.'
                            : 'Your reports and their progress will appear here once submitted.',
                      ),
                  ],
                ),
              ),
              if (widget.inbox && visible.isNotEmpty)
                ContentFrame(
                  child: AppSectionGroup(
                    children: [
                      for (final item in visible)
                        Builder(
                          builder: (context) {
                            final (icon, color) = _inboxLook(item, palette);
                            final hasDetails =
                                (item['schedule_id'] ?? item['report_id']) !=
                                null;
                            return NotificationUpdateTile(
                              title: '${item['title'] ?? 'Assignment update'}',
                              message:
                                  '${item['message'] ?? 'No additional details.'}',
                              timestampText: _inboxTimestamp(
                                item['created_at'],
                              ),
                              icon: icon,
                              iconColor: color,
                              unread: item['read_at'] == null,
                              hasDetails: hasDetails,
                              opening: _openingId == item['id'],
                              onTap: _openingId == null && !_markingAll
                                  ? () => _open(item)
                                  : null,
                            );
                          },
                        ),
                    ],
                  ),
                )
              else if (!widget.inbox)
                for (final group in groups.entries) ...[
                  ContentFrame(
                    child: Padding(
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
                  ),
                  for (final item in group.value)
                    ContentFrame(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _UpdateCard(
                          item: item,
                          inbox: widget.inbox,
                          opening: _openingId == item['id'],
                          onTap: _openingId == null ? () => _open(item) : null,
                        ),
                      ),
                    ),
                ],
              if (_error != null && _moreError)
                ContentFrame(
                  child: RecordMessage(
                    title:
                        'Could not refresh ${widget.inbox ? 'notifications' : 'reports'}',
                    message: apiErrorMessage(_error!),
                    icon: AppIcons.wifiOff,
                    onRetry: _loading ? null : () => _load(more: _moreError),
                  ),
                ),
              ContentFrame(
                child: PageLoader(
                  hasMore: _next != null && _error == null,
                  loading: _loading || _markingAll,
                  onLoad: () => _load(more: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateCard extends StatelessWidget {
  const _UpdateCard({
    required this.item,
    required this.inbox,
    required this.opening,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final bool inbox, opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final unread = inbox && item['read_at'] == null;
    final kind = '${item['kind'] ?? ''}';
    final schedule =
        inbox && (item['schedule_id'] != null || kind.startsWith('schedule_'));
    final finished = kind.contains('completed') || kind.contains('resolved');
    final cancelled = kind.contains('cancelled') || kind.contains('invalid');
    final accent = cancelled
        ? palette.danger
        : finished
        ? palette.success
        : palette.brand;
    final related = schedule
        ? item['schedule_id']
        : inbox
        ? item['report_id']
        : item['id'];

    return Surface(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.lg),
      radius: AppRadius.md,
      borderColor: unread ? accent.withValues(alpha: 0.45) : null,
      tint: unread
          ? Color.alphaBlend(accent.withValues(alpha: 0.06), palette.surface)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  schedule
                      ? AppIcons.calendar
                      : inbox
                      ? AppIcons.bell
                      : AppIcons.form,
                  color: accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inbox
                          ? (schedule
                                ? 'Scheduled service'
                                : 'Response update')
                          : '${item['reference'] ?? 'Report #${item['id']}'}',
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${inbox ? item['title'] ?? 'Assignment update' : item['type'] ?? 'Emergency report'}',
                      style: MdrrmoTypography.titleMd.copyWith(
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (unread)
                Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
                  child: Semantics(
                    label: 'Unread notification',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (inbox)
                RecordBadge(
                  unread ? 'Unread' : 'Read',
                  color: unread ? accent : palette.textMuted,
                  icon: unread ? AppIcons.mail : AppIcons.checkCircle,
                ),
              if (!inbox) RecordBadge('${item['status'] ?? 'Unknown'}'),
              if (related != null)
                RecordBadge(
                  '${schedule ? 'Service' : 'Report'} #$related',
                  color: palette.textMuted,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${inbox ? item['message'] ?? 'No additional details.' : item['location'] ?? 'Location not recorded'}',
            style: MdrrmoTypography.bodyMd.copyWith(
              height: 1.5,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: palette.border),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                recordTimestamp(item[inbox ? 'created_at' : 'reported_at']),
                style: MdrrmoTypography.tabular(
                  MdrrmoTypography.labelSm.copyWith(color: palette.textMuted),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (opening)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      related == null ? AppIcons.check : AppIcons.chevron,
                      size: 16,
                      color: accent,
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    opening
                        ? 'Opening...'
                        : related == null
                        ? 'Mark as read'
                        : schedule
                        ? 'View service'
                        : 'View report',
                    style: MdrrmoTypography.labelSm.copyWith(color: accent),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
