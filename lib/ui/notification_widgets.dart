import 'package:material_ui/material_ui.dart';

import 'kit.dart';

/// Shared header, unread filter, and "Mark all read" action for notification feeds.
class NotificationsHeaderSection extends StatelessWidget {
  const NotificationsHeaderSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.unreadOnly,
    required this.unreadCount,
    required this.onFilterChanged,
    this.onMarkAllRead,
  });

  final String title;
  final String subtitle;
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
          bottomSpacing: AppSpacing.md + 2,
        ),
        Segmented<bool>(
          value: unreadOnly,
          onChanged: onFilterChanged,
          options: const [
            SegmentOption(false, 'All updates'),
            SegmentOption(true, 'Unread'),
          ],
        ),
        if (unreadCount > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
              ),
              onPressed: onMarkAllRead,
              icon: const Icon(AppIcons.check, size: 16),
              label: const Text('Mark all read'),
            ),
          ),
        ] else
          const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// Shared notification card matching the Resident Updates UI/UX.
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
      child: Surface(
        padding: const EdgeInsets.all(14),
        radius: AppRadius.md,
        tint: unread
            ? Color.alphaBlend(
                palette.brand.withValues(
                  alpha: palette.isDark ? 0.12 : 0.05,
                ),
                palette.surface,
              )
            : null,
        borderColor: unread ? palette.brand.withValues(alpha: 0.32) : null,
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
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
                        fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    timestampText,
                    style: MdrrmoTypography.labelSm.copyWith(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (hasDetails) ...[
                    const SizedBox(height: 6),
                    Text(
                      opening ? 'Opening...' : 'View details →',
                      style: MdrrmoTypography.labelSm.copyWith(
                        color: palette.brand,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (unread)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
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
          ],
        ),
      ),
    );
  }
}
