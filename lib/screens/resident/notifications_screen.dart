import 'package:material_ui/material_ui.dart';

import '../../data/resident_models.dart';
import '../../state/resident_state.dart';
import '../../ui/kit.dart';
import '../../ui/notification_widgets.dart';
import '../../ui/page_loader.dart';
import '../record_details_screen.dart';
import 'resident_widgets.dart';

class ResidentNotificationsScreen extends StatefulWidget {
  const ResidentNotificationsScreen({super.key});
  @override
  State<ResidentNotificationsScreen> createState() =>
      _ResidentNotificationsScreenState();
}

class _ResidentNotificationsScreenState
    extends State<ResidentNotificationsScreen> {
  bool _unreadOnly = false;

  (IconData, Color) _look(NotificationKind kind, MdrrmoColors palette) =>
      switch (kind) {
        NotificationKind.resolved => (AppIcons.checkCircle, palette.success),
        NotificationKind.onTheWay => (AppIcons.truck, palette.brand),
        NotificationKind.received => (AppIcons.infoCircle, palette.brand),
        NotificationKind.submitted => (AppIcons.form, palette.textMuted),
        NotificationKind.rate => (AppIcons.star, palette.brandPressed),
      };

  Future<void> _markAll(ResidentState state) async {
    try {
      await state.markAllRead();
    } catch (error) {
      if (mounted) {
        snack(
          context,
          'Could not mark updates as read: ${apiErrorMessage(error)}',
        );
      }
    }
  }

  Future<void> _open(
    ResidentState state,
    ResidentNotification notification,
  ) async {
    try {
      await state.markRead(notification);
      if (!mounted ||
          notification.relatedId == null ||
          notification.relatedKind == null) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordDetailsScreen(
            id: notification.relatedId!,
            schedule: notification.relatedKind == 'schedule',
            onChanged: state.load,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        snack(context, 'Could not open update: ${apiErrorMessage(error)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ResidentScope.of(context);
    final palette = MdrrmoColors.of(context);
    final items = state.notifications
        .where((notification) => !_unreadOnly || notification.unread)
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
                NotificationsHeaderSection(
                  title: 'Your updates',
                  subtitle: state.unreadCount == 0
                      ? 'Report and service updates from MDRRMO.'
                      : '${state.unreadCount} unread updates from MDRRMO.',
                  unreadOnly: _unreadOnly,
                  unreadCount: state.unreadCount,
                  onFilterChanged: (value) =>
                      setState(() => _unreadOnly = value),
                  onMarkAllRead:
                      state.isUpdatingNotifications || state.isLoading
                      ? null
                      : () => _markAll(state),
                ),
                if (items.isEmpty)
                  ResidentEmptyState(
                    icon: AppIcons.bell,
                    title: state.unreadCount == 0
                        ? 'You are all caught up'
                        : 'No updates to show',
                    message: _unreadOnly && state.unreadCount > 0
                        ? 'Load more updates below or choose All updates.'
                        : 'New report and service updates will appear here.',
                  ),
                for (final notification in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Builder(
                      builder: (context) {
                        final (icon, color) = _look(
                          notification.kind,
                          palette,
                        );
                        return NotificationUpdateTile(
                          message: notification.message,
                          timestampText: timeAgo(notification.time),
                          icon: icon,
                          iconColor: color,
                          unread: notification.unread,
                          hasDetails:
                              notification.relatedId != null &&
                              notification.relatedKind != null,
                          onTap: () => _open(state, notification),
                        );
                      },
                    ),
                  ),
                PageLoader(
                  hasMore: state.hasMore('notifications'),
                  loading:
                      state.loadingPage == 'notifications' ||
                      state.isLoading ||
                      state.isSaving,
                  error: state.pageErrors['notifications'],
                  onLoad: () => state.loadMore('notifications'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
