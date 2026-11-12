import 'package:material_ui/material_ui.dart';

import '../../ui/kit.dart';

const responderBlue = AppColors.primary;

class ResponderPanel extends StatelessWidget {
  const ResponderPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.accent,
    this.onTap,
  });
  final Widget child;
  final EdgeInsets padding;
  final Color? accent;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Surface(
      padding: padding,
      onTap: onTap,
      radius: AppRadius.md,
      borderColor: accent?.withValues(alpha: palette.isDark ? 0.40 : 0.32),
      tint: accent != null
          ? Color.alphaBlend(
              accent!.withValues(alpha: palette.isDark ? 0.08 : 0.04),
              palette.surface,
            )
          : null,
      child: child,
    );
  }
}

class ResponderHeading extends StatelessWidget {
  const ResponderHeading(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => AppHeading(
    title,
    subtitle: subtitle,
    trailing: trailing,
    bottomSpacing: AppSpacing.md,
  );
}

class ResponderTag extends StatelessWidget {
  const ResponderTag(
    this.label, {
    super.key,
    this.color = responderBlue,
    this.icon,
  });
  final String label;
  final Color color;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => AppStatusBadge(
    label,
    color: color,
    dot: icon == null,
    icon: icon,
  );
}

class ResponderEmptyState extends StatelessWidget {
  const ResponderEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title, message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => AppStateView(
    icon: icon,
    title: title,
    message: message,
    accent: MdrrmoColors.of(context).brand,
    action: action,
  );
}

class ResponderShortcut extends StatelessWidget {
  const ResponderShortcut({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = responderBlue,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final enabled = onTap != null;
    return Surface(
      padding: EdgeInsets.zero,
      tint: enabled ? palette.surface : palette.surfaceSubtle,
      child: AppRowItem(
        title: title,
        subtitle: subtitle,
        enabled: enabled,
        onTap: onTap,
        showChevron: true,
        padding: const EdgeInsets.all(AppSpacing.md + 2),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: palette.isDark ? 0.20 : 0.10),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Icon(
            icon,
            color: enabled ? color : palette.textMuted,
            size: 20,
          ),
        ),
      ),
    );
  }
}
