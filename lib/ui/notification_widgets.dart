import 'package:material_ui/material_ui.dart';

import 'kit.dart';

/// Shared header, unread filter, and "Mark all read" action for notification feeds.
class NotificationsHeaderSection extends StatelessWidget {
  const NotificationsHeaderSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.unreadOnly,
    required this.unreadCount,
    required this.onFilterChanged,
    this.onMarkAllRead,
  });

  final String title;
  final String? subtitle;
  final bool unreadOnly;
  final int unreadCount;
  final ValueChanged<bool> onFilterChanged;
  final VoidCallback? onMarkAllRead;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppHeading(
          title,
          subtitle: subtitle,
          bottomSpacing: AppSpacing.md,
          trailing: unreadCount > 0
              ? TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: onMarkAllRead,
                  icon: const Icon(AppIcons.check, size: 16),
                  label: const Text('Mark all read'),
                )
              : null,
        ),
        Segmented<bool>(
          value: unreadOnly,
          onChanged: onFilterChanged,
          options: const [
            SegmentOption(false, 'All updates'),
            SegmentOption(true, 'Unread'),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Clean notification list row designed for placement inside [AppSectionGroup].
class NotificationUpdateTile extends StatelessWidget {
  const NotificationUpdateTile({
    super.key,
    this.title,
    required this.message,
    required this.timestampText,
    required this.icon,
    required this.iconColor,
    required this.unread,
    required this.hasDetails,
    this.opening = false,
    this.onTap,
  });

  final String? title;
  final String message;
  final String timestampText;
  final IconData icon;
  final Color iconColor;
  final bool unread;
  final bool hasDetails;
  final bool opening;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final hasTitle = title != null && title!.trim().isNotEmpty;
    final semanticsTitle = hasTitle ? '${title!.trim()}. ' : '';

    return Semantics(
      label: '${unread ? 'Unread. ' : ''}$semanticsTitle$message',
      button: onTap != null,
      child: Material(
        color: unread
            ? Color.alphaBlend(
                palette.brand.withValues(alpha: palette.isDark ? 0.10 : 0.04),
                palette.surface,
              )
            : palette.surface,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md + 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasTitle) ...[
                        Text(
                          title!,
                          style: MdrrmoTypography.bodyMd.copyWith(
                            color: palette.textPrimary,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                        if (message.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            message,
                            style: MdrrmoTypography.bodySm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ] else
                        Text(
                          message,
                          style: MdrrmoTypography.bodyMd.copyWith(
                            color: palette.textPrimary,
                            fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        timestampText,
                        style: MdrrmoTypography.labelSm.copyWith(
                          color: palette.textMuted,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (unread)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 6),
                        child: Semantics(
                          label: 'Unread notification',
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.brand,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                    if (opening)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (hasDetails)
                      Icon(
                        AppIcons.chevron,
                        size: 18,
                        color: palette.textMuted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
