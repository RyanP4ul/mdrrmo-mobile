import 'package:forui/forui.dart';
import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// Responsive width constraint so tablets/foldables don't stretch forms edge-to-edge.
class ContentFrame extends StatelessWidget {
  const ContentFrame({
    super.key,
    required this.child,
    this.maxWidth = 640,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// Consistent page section heading replacing duplicated Resident/Responder headings.
class AppHeading extends StatelessWidget {
  const AppHeading(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.bottomSpacing = AppSpacing.md,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final titleWidget = Text(
      title,
      style: MdrrmoTypography.displaySm.copyWith(color: palette.textPrimary),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null)
            titleWidget
          else
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [titleWidget, trailing!],
            ),
          if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              style: MdrrmoTypography.bodySm.copyWith(
                color: palette.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum AppBannerTone { info, warning, danger, success }

/// Brightness-aware inline alert banner (replaces light-only *Surface hacks).
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = AppBannerTone.info,
    this.icon,
    this.action,
    this.onTap,
  });

  final String? title;
  final String message;
  final AppBannerTone tone;
  final IconData? icon;
  final Widget? action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final (bg, fg, borderColor) = switch (tone) {
      AppBannerTone.info => (
        palette.brandTint,
        palette.brand,
        palette.brand.withValues(alpha: 0.28),
      ),
      AppBannerTone.warning => (
        palette.warningTint,
        palette.warning,
        palette.warning.withValues(alpha: 0.30),
      ),
      AppBannerTone.danger => (
        palette.dangerTint,
        palette.danger,
        palette.danger.withValues(alpha: 0.30),
      ),
      AppBannerTone.success => (
        palette.successTint,
        palette.success,
        palette.success.withValues(alpha: 0.30),
      ),
    };

    final radius = BorderRadius.circular(AppRadius.md);
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon ??
                      switch (tone) {
                        AppBannerTone.info => FLucideIcons.info,
                        AppBannerTone.warning => FLucideIcons.triangleAlert,
                        AppBannerTone.danger => FLucideIcons.circleAlert,
                        AppBannerTone.success => FLucideIcons.circleCheck,
                      },
                  size: 18,
                  color: tone == AppBannerTone.warning
                      ? palette.warningIcon
                      : fg,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title!.trim().isNotEmpty) ...[
                      Text(
                        title!,
                        style: MdrrmoTypography.bodyMd.copyWith(
                          fontWeight: FontWeight.w700,
                          color: fg,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: MdrrmoTypography.bodySm.copyWith(
                        color: palette.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (action != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      action!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Restrained grouped surface container with 1px border and internal hairlines.
class AppSectionGroup extends StatelessWidget {
  const AppSectionGroup({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.padding = EdgeInsets.zero,
    this.dividers = true,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: MdrrmoTypography.titleMd.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: MdrrmoTypography.bodySm.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
        Container(
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0 && dividers)
                    Divider(height: 1, thickness: 1, color: palette.border),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Accessible `>= 52dp` row inside an [AppSectionGroup] or standalone list.
class AppRowItem extends StatelessWidget {
  const AppRowItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.showChevron = false,
    this.destructive = false,
    this.enabled = true,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final bool destructive;
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final effectiveTap = enabled ? onTap : null;
    final titleColor = !enabled
        ? palette.textMuted
        : destructive
        ? palette.danger
        : palette.textPrimary;

    return Semantics(
      button: effectiveTap != null,
      enabled: enabled,
      child: InkWell(
        onTap: effectiveTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: padding,
            child: Opacity(
              opacity: enabled ? 1.0 : 0.6,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: MdrrmoTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: MdrrmoTypography.bodySm.copyWith(
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    trailing!,
                  ] else if (showChevron && effectiveTap != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      FLucideIcons.chevronRight,
                      size: 18,
                      color: palette.textMuted,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Restrained semantic status badge with optional leading status dot.
class AppStatusBadge extends StatelessWidget {
  const AppStatusBadge(
    this.label, {
    super.key,
    required this.color,
    this.dot = true,
    this.icon,
  });

  final String label;
  final Color color;
  final bool dot;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: palette.isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: color.withValues(alpha: palette.isDark ? 0.40 : 0.26),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 5),
          ] else if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: MdrrmoTypography.labelSm.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean empty/error/loading state without unnecessary decorative clutter.
class AppStateView extends StatelessWidget {
  const AppStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.accent,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? accent;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final effectiveAccent = accent ?? palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: effectiveAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 22, color: effectiveAccent),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: MdrrmoTypography.titleMd.copyWith(
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: MdrrmoTypography.bodySm.copyWith(
              color: palette.textSecondary,
              height: 1.45,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Clean switch row meeting `>= 48dp` target sizing inside forms/settings.
class AppSwitchRow extends StatelessWidget {
  const AppSwitchRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MdrrmoTypography.bodyMd.copyWith(
                        fontWeight: FontWeight.w600,
                        color: onChanged == null
                            ? palette.textMuted
                            : palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: MdrrmoTypography.bodySm.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Standardized neutral modal bottom sheet with drag handle & safe-area padding.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  final palette = MdrrmoColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: palette.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: ContentFrame(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: MdrrmoTypography.titleLg.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: MdrrmoTypography.bodySm.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: palette.border),
              Flexible(child: builder(ctx)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Standardized 48dp read-only date selector wrapping [showDatePicker].
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.valueText,
    required this.onPick,
    this.placeholder = 'Select date',
    this.enabled = true,
  });

  final String label;
  final String? valueText;
  final VoidCallback? onPick;
  final String placeholder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final palette = MdrrmoColors.of(context);
    final hasValue = valueText != null && valueText!.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MdrrmoTypography.bodySm.copyWith(
            fontWeight: FontWeight.w600,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: '$label, ${hasValue ? valueText! : placeholder}',
          child: InkWell(
            onTap: enabled ? onPick : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: hasValue
                      ? palette.brand.withValues(alpha: 0.45)
                      : palette.border,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    FLucideIcons.calendar,
                    size: 18,
                    color: hasValue ? palette.brand : palette.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      hasValue ? valueText! : placeholder,
                      style: MdrrmoTypography.tabular(
                        MdrrmoTypography.bodyMd.copyWith(
                          color: hasValue
                              ? palette.textPrimary
                              : palette.textMuted,
                          fontWeight: hasValue
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    FLucideIcons.chevronRight,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
